import Foundation
import ZIPFoundation

enum SigningError: LocalizedError {
    case unzip(String)
    case extensionMismatch([String], String)
    case sign(String)
    case package(String)

    var errorDescription: String? {
        switch self {
        case .unzip(let reason): return "Couldn't unpack the IPA: \(reason)"
        case .extensionMismatch(let ids, let pattern):
            return "\(ids.count) nested bundle\(ids.count == 1 ? "" : "s") (e.g. \(ids.first ?? "")) don't match App ID \(pattern). Enable “Remove app extensions” or use a wildcard profile."
        case .sign(let reason): return reason
        case .package(let reason): return "Couldn't create the signed IPA: \(reason)"
        }
    }
}

enum SigningEvent: Sendable {
    case step(SigningStep)
    case progress(Double)
    case log(String, isError: Bool)
}

struct SigningInput: Sendable {
    let ipaURL: URL
    let p12URL: URL
    let profileURL: URL
    let password: String
    let options: SigningOptions
    let appIDPattern: String
    let outputURL: URL
    /// For the signing log.
    var certificateName: String = ""
    var certificateExpiry: Date? = nil
}

extension SigningInput {
    /// The one way to build a signing input from a stored certificate: normal jobs and the in-app
    /// updater both use it, so their certificate, profile, App ID and log details can't diverge.
    static func make(certificate: Certificate, p12URL: URL, profileURL: URL, password: String,
                     ipa: URL, options: SigningOptions, output: URL) -> SigningInput {
        SigningInput(
            ipaURL: ipa,
            p12URL: p12URL,
            profileURL: profileURL,
            password: password,
            options: options,
            appIDPattern: certificate.profile?.bundleIDPattern ?? "*",
            outputURL: output,
            certificateName: certificate.record.signingCertificate?.commonName.map { "\($0) (\(certificate.nickname))" } ?? certificate.nickname,
            certificateExpiry: certificate.record.signingCertificate?.notAfter ?? certificate.expirationDate
        )
    }
}

/// Persisted signing logs: Documents/Logs/Signing/<signed app id>.log (failures: failed-<date>.log).
enum SigningLogStore {
    static var folder: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Signing", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(forSignedApp id: UUID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).log")
    }

    /// A shareable copy with a readable name, e.g. "Husk-signing-log.txt".
    static func shareableCopy(of url: URL, appName: String) -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let safe = appName.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safe.isEmpty ? "App" : safe)-signing-log.txt")
        try? FileManager.default.removeItem(at: destination)
        return (try? FileManager.default.copyItem(at: url, to: destination)) != nil ? destination : nil
    }
}

struct SigningOutput: Sendable {
    let bundleID: String
    let displayName: String
    let version: String
    let size: Int64
}

/// Thread-safe "only report meaningful changes" helper for progress callbacks.
private final class ProgressThrottle: @unchecked Sendable {
    private var last = -1.0
    private let lock = NSLock()
    private let emit: (Double) -> Void

    init(_ emit: @escaping (Double) -> Void) { self.emit = emit }

    func report(_ value: Double) {
        lock.lock()
        defer { lock.unlock() }
        guard value - last >= 0.01 || value >= 1 else { return }
        last = value
        emit(value)
    }
}

/// The blocking pipeline. Runs on a background thread; reports via `emit`.
enum SigningWorker {
    static func run(_ input: SigningInput, emit: @escaping (SigningEvent) -> Void) throws -> SigningOutput {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("Signing-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: work) }
        let throttle = ProgressThrottle { emit(.progress($0)) }
        func log(_ text: String, error: Bool = false) { emit(.log(text, isError: error)) }

        // 1. Unpacking (0 – 30%)
        emit(.step(.unpacking))
        log("Unpacking \(input.ipaURL.lastPathComponent)…")
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let progress = Progress()
            let observation = progress.observe(\.fractionCompleted) { p, _ in throttle.report(0.30 * p.fractionCompleted) }
            defer { observation.invalidate() }
            try fm.unzipItem(at: input.ipaURL, to: work, progress: progress)
        } catch {
            throw SigningError.unzip(error.localizedDescription)
        }
        let appURL = try AppBundlePatcher.findApp(in: work)
        log("Found Payload/\(appURL.lastPathComponent)")
        // zsign writes each signature into the file itself, so it must be able to open every file
        // for writing. IPAs can carry read-only binaries (CertSigner's own OpenSSL.framework is
        // 0555); zsign then skips them as "non-Mach-O" and fails the whole app.
        let unlocked = AppBundlePatcher.makeWritable(work)
        if unlocked > 0 { log("Made \(unlocked) read-only item\(unlocked == 1 ? "" : "s") writable for signing") }
        throttle.report(0.30)

        // 2. Patching (30 – 40%)
        emit(.step(.patching))
        let mode = input.options.effectiveMode
        var options = input.options
        if mode == .compatibility {
            // Compatibility: original bundle ID (no override reaches zsign or Info.plist), keep every extension.
            options.bundleID = ""
            options.removeExtensions = false
        }
        log("Signing mode: \(mode.title)")
        let originalID = (try? AppBundlePatcher.readPlist(appURL.appendingPathComponent("Info.plist")))?.0["CFBundleIdentifier"] as? String ?? ""
        let ownID = Bundle.main.bundleIdentifier ?? ""
        if SigningValidator.wouldReplaceCertSigner(bundleID: options.trimmedBundleID, originalBundleID: originalID, ownBundleID: ownID) {
            throw SigningError.sign("\(options.trimmedBundleID) is CertSigner's own bundle ID: installing this app would replace CertSigner. Use Compatibility mode, or give the app a bundle ID of its own.")
        }
        let summary = try AppBundlePatcher.apply(options, to: appURL) { log($0) }
        if mode == .strict {
            let nested = AppBundlePatcher.nestedBundleIDs(in: appURL)
            let mismatched = nested.filter { !SigningValidator.bundleID($0, matches: input.appIDPattern) }
            if !mismatched.isEmpty {
                throw SigningError.extensionMismatch(mismatched, input.appIDPattern)
            }
        }
        let embedded = appURL.appendingPathComponent("embedded.mobileprovision")
        try? fm.removeItem(at: embedded)
        try? fm.copyItem(at: input.profileURL, to: embedded)
        log("Replaced embedded.mobileprovision")
        log("Entitlements: taken from the provisioning profile")

        // Signing summary for the log.
        func dateText(_ date: Date?) -> String { date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "unknown" }
        log("— Signing summary —")
        log("Certificate: \(input.certificateName.isEmpty ? "unknown" : input.certificateName), expires \(dateText(input.certificateExpiry))")
        if let profile = try? ProfileParser.parse(url: input.profileURL) {
            log("Profile: \(profile.name), expires \(dateText(profile.expirationDate))")
            if profile.provisionsAllDevices {
                log("Devices: not device-limited (all devices)")
            } else {
                log("Devices: device-limited, \(profile.devices.count) UDID\(profile.devices.count == 1 ? "" : "s") listed")
            }
            log("Profile App ID: \(profile.applicationIdentifier.isEmpty ? "(missing)" : profile.applicationIdentifier)")
            if let value = profile.entitlements["get-task-allow"] {
                log("get-task-allow: present (\(ProfileParser.describe(value)))")
            } else {
                log("get-task-allow: not present")
            }
        } else {
            log("Profile: couldn't be read for the summary", error: true)
        }
        log("Bundle ID used: \(summary.bundleID)")
        let items = AppBundlePatcher.signableItems(in: appURL)
        log("Items to sign (\(items.count)):")
        for item in items { log("  \(item.description)") }
        throttle.report(0.40)

        // 3. Signing (40 – 85%): zsign signs nested frameworks/dylibs/appex first, main binary last.
        emit(.step(.signing))
        log("Signing \(summary.bundleID) with zsign…")
        var lines = 0.0
        let counterLock = NSLock()
        do {
            try ZSignService.sign(
                appURL: appURL,
                p12URL: input.p12URL,
                password: input.password,
                profileURL: input.profileURL
            ) { line, isError in
                let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                log(text, error: isError)
                counterLock.lock()
                lines += 1
                let value = 0.40 + 0.45 * (1 - exp(-lines / 25))
                counterLock.unlock()
                throttle.report(min(value, 0.84))
            }
        } catch {
            throw SigningError.sign(error.localizedDescription)
        }
        log("Signed \(items.count) item\(items.count == 1 ? "" : "s"):")
        for item in items { log("  ✓ \(item.description)") }
        // What each bundle was actually signed as, read back from its executable's signature.
        log("Signed identity per bundle:")
        for line in SignedIdentity.summaryLines(appURL: appURL) { log("  \(line)") }
        throttle.report(0.85)

        // 4. Packaging (85 – 100%)
        emit(.step(.packaging))
        log("Compressing Payload…")
        do {
            try? fm.removeItem(at: input.outputURL)
            let progress = Progress()
            let observation = progress.observe(\.fractionCompleted) { p, _ in throttle.report(0.85 + 0.15 * p.fractionCompleted) }
            defer { observation.invalidate() }
            try fm.zipItem(
                at: work.appendingPathComponent("Payload", isDirectory: true),
                to: input.outputURL,
                shouldKeepParent: true,
                compressionMethod: .deflate,
                progress: progress
            )
        } catch {
            throw SigningError.package(error.localizedDescription)
        }
        let size = (try? fm.attributesOfItem(atPath: input.outputURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        log("Wrote \(input.outputURL.lastPathComponent) (\(size.byteString))")
        throttle.report(1)

        return SigningOutput(bundleID: summary.bundleID, displayName: summary.displayName, version: summary.version, size: size)
    }
}

/// Observable state for one signing run, driven by `SigningWorker`.
@MainActor
final class SigningJob: ObservableObject {
    @Published private(set) var step: SigningStep?
    @Published private(set) var progress: Double = 0
    @Published private(set) var log: [LogLine] = []
    @Published private(set) var result: AnimatedResultIcon.Result?
    @Published private(set) var errorMessage: String?
    @Published private(set) var signedApp: SignedApp?
    @Published private(set) var isRunning = false
    /// The saved signing log once the job finished (success or failure).
    @Published private(set) var logFileURL: URL?

    func reset() {
        step = nil
        progress = 0
        log = []
        result = nil
        errorMessage = nil
        signedApp = nil
        logFileURL = nil
    }

    func run(
        app: LibraryApp,
        ipaURL: URL,
        iconURL: URL?,
        certificate: Certificate,
        p12URL: URL,
        profileURL: URL,
        password: String,
        options: SigningOptions,
        store: SignedAppsStore
    ) async {
        guard !isRunning else { return }
        reset()
        isRunning = true
        defer { isRunning = false }

        let (signedID, folder) = store.reserve()
        let safeName = app.name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        let fileName = "\(safeName.isEmpty ? "App" : safeName)-signed.ipa"
        let input = SigningInput.make(certificate: certificate, p12URL: p12URL, profileURL: profileURL, password: password,
                                      ipa: ipaURL, options: options, output: folder.appendingPathComponent(fileName))

        var continuation: AsyncStream<SigningEvent>.Continuation?
        let events = AsyncStream<SigningEvent> { continuation = $0 }
        let sink = continuation

        let worker = Task.detached(priority: .userInitiated) { () throws -> SigningOutput in
            defer { sink?.finish() }
            return try SigningWorker.run(input) { event in _ = sink?.yield(event) }
        }

        for await event in events {
            switch event {
            case .step(let newStep): step = newStep
            case .progress(let value): progress = value
            case .log(let text, isError: let isError): log.append(LogLine(text: text, isError: isError))
            }
        }

        do {
            let output = try await worker.value
            let record = SignedApp(
                id: signedID,
                name: output.displayName,
                bundleID: output.bundleID,
                version: output.version.isEmpty ? app.version : output.version,
                signedAt: Date(),
                certificateID: certificate.id,
                certificateName: certificate.nickname,
                expiresAt: certificate.expirationDate,
                fileName: fileName,
                iconFileName: nil,
                size: output.size,
                sourceAppID: app.id
            )
            store.add(record, iconSource: iconURL)
            signedApp = record
            progress = 1
            result = .success
            Haptics.success()
            saveLog(app: app, to: SigningLogStore.url(forSignedApp: signedID))
        } catch {
            store.discard(signedID)
            let message = error.localizedDescription
            log.append(LogLine(text: "error: \(message)", isError: true))
            errorMessage = message
            result = .failure
            Haptics.error()
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            saveLog(app: app, to: SigningLogStore.folder.appendingPathComponent("failed-\(stamp).log"))
        }
    }

    private func saveLog(app: LibraryApp, to url: URL) {
        var text = "CertSigner signing log\nApp: \(app.name) (\(app.bundleID)) v\(app.version)\n"
        text += "Date: \(Date().formatted(date: .abbreviated, time: .standard))\n"
        text += "Result: \(result == .success ? "success" : "failed")\n\n"
        text += log.map { ($0.isError ? "[error] " : "") + $0.text }.joined(separator: "\n") + "\n"
        if (try? Data(text.utf8).write(to: url, options: .atomic)) != nil {
            logFileURL = url
        }
    }
}
