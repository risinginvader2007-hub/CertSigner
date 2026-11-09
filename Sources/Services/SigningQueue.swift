import Foundation
import SwiftUI

/// A queued / running / failed sign job, persisted to Documents/Signing/queue.json.
struct SigningTask: Identifiable, Codable, Equatable {
    enum Source: Codable, Equatable {
        /// A staged IPA imported from Files.
        case library(UUID)
        /// Re-sign an existing signed IPA.
        case signed(UUID)
    }

    enum Status: String, Codable {
        case queued, running, failed
    }

    var id: UUID
    var name: String
    var bundleID: String
    var version: String
    var source: Source
    var certificateID: UUID
    var options: SigningOptions
    var replacingSignedID: UUID?
    var status: Status
    var errorMessage: String?
    var createdAt: Date
    /// nil = follow the "Install when done" setting.
    var installWhenDone: Bool? = nil
}

/// Runs sign jobs one at a time in the background and feeds results into SignedAppsStore.
@MainActor
final class SigningQueue: ObservableObject {
    @Published private(set) var tasks: [SigningTask] = []
    /// Live state (step, progress, log) for tasks that ran this session.
    @Published private(set) var jobs: [UUID: SigningJob] = [:]
    /// Set when auto-install is on and a job finishes; RootView presents the install sheet.
    @Published var installRequest: SignedApp?

    private let certificates: CertificateStore
    private let library: LibraryStore
    private let signedApps: SignedAppsStore
    private let toasts: ToastCenter
    private let indexURL: URL
    private var isProcessing = false

    init(certificates: CertificateStore, library: LibraryStore, signedApps: SignedAppsStore, toasts: ToastCenter) {
        self.certificates = certificates
        self.library = library
        self.signedApps = signedApps
        self.toasts = toasts
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Signing", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        indexURL = folder.appendingPathComponent("queue.json")

        tasks = load().map { task in
            var task = task
            if task.status == .running {
                task.status = .failed
                task.errorMessage = "Interrupted because CertSigner was closed. Tap Retry."
            }
            return task
        }
        save()
        Task { await process() }
    }

    var hasWork: Bool { !tasks.isEmpty }

    // MARK: Enqueue

    @discardableResult
    func enqueue(app: LibraryApp, certificateID: UUID, options: SigningOptions, installWhenDone: Bool? = nil) -> SigningTask {
        let task = SigningTask(
            id: UUID(), name: options.trimmedDisplayName.isEmpty ? app.name : options.trimmedDisplayName,
            bundleID: options.trimmedBundleID.isEmpty ? app.bundleID : options.trimmedBundleID,
            version: options.trimmedVersion.isEmpty ? app.version : options.trimmedVersion,
            source: .library(app.id), certificateID: certificateID, options: options,
            replacingSignedID: nil, status: .queued, errorMessage: nil, createdAt: Date(),
            installWhenDone: installWhenDone
        )
        add(task)
        return task
    }

    /// Re-signs a signed IPA with the given certificate and replaces the old entry on success.
    @discardableResult
    func enqueueResign(_ signed: SignedApp, certificateID: UUID) -> SigningTask {
        let task = SigningTask(
            id: UUID(), name: signed.name, bundleID: signed.bundleID, version: signed.version,
            source: .signed(signed.id), certificateID: certificateID, options: SigningOptions(mode: SigningMode.defaultMode),
            replacingSignedID: signed.id, status: .queued, errorMessage: nil, createdAt: Date()
        )
        add(task)
        return task
    }

    private func add(_ task: SigningTask) {
        withAnimation(Theme.spring) { tasks.append(task) }
        save()
        AppLog.info("Queued signing: \(task.name) (\(task.bundleID))")
        Task { await process() }
    }

    func retry(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(Theme.spring) {
            tasks[index].status = .queued
            tasks[index].errorMessage = nil
        }
        jobs[id] = nil
        save()
        Haptics.impact(.medium)
        Task { await process() }
    }

    /// Removes a failed / queued task. Staged IPAs it owned are deleted too.
    func remove(_ id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }), task.status != .running else { return }
        if case .library(let appID) = task.source, let app = library.apps.first(where: { $0.id == appID }) {
            library.delete(app)
        }
        withAnimation(Theme.spring) { tasks.removeAll { $0.id == id } }
        jobs[id] = nil
        save()
    }

    // MARK: Processing

    private func process() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        // Staged IPAs load asynchronously at launch.
        while library.isLoading {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        while let next = tasks.first(where: { $0.status == .queued }) {
            await run(next.id)
        }
    }

    private func run(_ id: UUID) async {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        setStatus(id, .running, error: nil)

        guard let certificate = certificates.certificates.first(where: { $0.id == task.certificateID }) ?? certificates.active else {
            fail(id, "The certificate for this job was removed. Pick another and retry.")
            return
        }

        let meta: LibraryApp
        let ipaURL: URL
        let iconURL: URL?
        switch task.source {
        case .library(let appID):
            guard let app = library.apps.first(where: { $0.id == appID }) else {
                fail(id, "The imported IPA is gone. Import it again.")
                return
            }
            meta = app
            ipaURL = library.ipaURL(for: app)
            iconURL = library.iconURL(for: app)
        case .signed(let signedID):
            guard let signed = signedApps.apps.first(where: { $0.id == signedID }) else {
                fail(id, "The signed app to re-sign was deleted.")
                return
            }
            meta = LibraryApp(
                id: signed.sourceAppID ?? UUID(), name: signed.name, bundleID: signed.bundleID,
                version: signed.version, build: "", size: signed.size, dateAdded: signed.signedAt,
                minimumOS: nil, fileName: signed.fileName, iconFileName: nil, originalFileName: nil,
                extensionBundleIDs: nil, hasWatchApp: nil
            )
            ipaURL = signedApps.ipaURL(for: signed)
            iconURL = signed.iconFileName.map { signedApps.folder(for: signed.id).appendingPathComponent($0) }
        }

        let job = SigningJob()
        jobs[id] = job
        AppLog.info("Signing \(task.name) with \(certificate.nickname)")
        await job.run(
            app: meta,
            ipaURL: ipaURL,
            iconURL: iconURL,
            certificate: certificate,
            p12URL: certificates.p12URL(for: certificate.id),
            profileURL: certificates.profileURL(for: certificate.id),
            password: certificates.password(for: certificate.id) ?? "",
            options: task.options,
            store: signedApps
        )

        guard job.result == .success, let signed = job.signedApp else {
            let reason = job.errorMessage ?? "Signing failed."
            AppLog.error("Signing failed for \(task.name): \(reason)")
            fail(id, reason)
            return
        }

        AppLog.info("Signed \(signed.name) → \(signed.fileName)")
        if let replaced = task.replacingSignedID, let old = signedApps.apps.first(where: { $0.id == replaced }) {
            signedApps.delete(old)
        }
        if case .library(let appID) = task.source,
           SettingsKeys.bool(SettingsKeys.deleteOriginal, default: true),
           let app = library.apps.first(where: { $0.id == appID }) {
            library.delete(app)
        }
        withAnimation(Theme.spring) { tasks.removeAll { $0.id == id } }
        jobs[id] = nil
        save()
        toasts.show("Signed \(signed.name)", kind: .success)

        if task.installWhenDone ?? SettingsKeys.bool(SettingsKeys.autoInstall, default: false) {
            installRequest = signed
        }
    }

    private func setStatus(_ id: UUID, _ status: SigningTask.Status, error: String?) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(Theme.spring) {
            tasks[index].status = status
            tasks[index].errorMessage = error
        }
        save()
    }

    private func fail(_ id: UUID, _ message: String) {
        setStatus(id, .failed, error: message)
        toasts.show(message, kind: .error)
    }

    // MARK: Persistence

    private func load() -> [SigningTask] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SigningTask].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(tasks) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}
