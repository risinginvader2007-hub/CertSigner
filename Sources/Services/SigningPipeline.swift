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
        throttle.report(0.30)

        // 2. Patching (30 – 40%)
        emit(.step(.patching))
        let summary = try AppBundlePatcher.apply(input.options, to: appURL) { log($0) }
        let nested = AppBundlePatcher.nestedBundleIDs(in: appURL)
        let mismatched = nested.filter { !SigningValidator.bundleID($0, matches: input.appIDPattern) }
        if !mismatched.isEmpty {
            throw SigningError.extensionMismatch(mismatched, input.appIDPattern)
        }
        let embedded = appURL.appendingPathComponent("embedded.mobileprovision")
        try? fm.removeItem(at: embedded)
        try? fm.copyItem(at: input.profileURL, to: embedded)
        log("Replaced embedded.mobileprovision")
        log("Entitlements: taken from the provisioning profile")
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

    func reset() {
        step = nil
        progress = 0
        log = []
        result = nil
        errorMessage = nil
        signedApp = nil
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
        let input = SigningInput(
            ipaURL: ipaURL,
            p12URL: p12URL,
            profileURL: profileURL,
            password: password,
            options: options,
            appIDPattern: certificate.profile?.bundleIDPattern ?? "*",
            outputURL: folder.appendingPathComponent(fileName)
        )

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
        } catch {
            store.discard(signedID)
            let message = error.localizedDescription
            log.append(LogLine(text: "error: \(message)", isError: true))
            errorMessage = message
            result = .failure
            Haptics.error()
        }
    }
}
