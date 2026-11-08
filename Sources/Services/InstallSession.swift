import Foundation
import UIKit

enum InstallPhase: Equatable {
    case idle
    case preparing
    case waitingForPrompt
    case manifestSent
    case downloading(Double)
    case installing
    case failed(String)

    var isActive: Bool {
        switch self {
        case .preparing, .waitingForPrompt, .manifestSent, .downloading: return true
        default: return false
        }
    }
}

enum InstallError: LocalizedError {
    case noServerCertificate(String)
    case openFailed
    case timedOut
    case missingFile

    var errorDescription: String? {
        switch self {
        case .noServerCertificate(let reason):
            return "Fully Local needs a valid server certificate. \(reason)"
        case .openFailed:
            return "iOS refused to open the install link."
        case .timedOut:
            return "iOS never asked for the app. If you tapped Cancel on the prompt, try again. Otherwise switch the install method in Settings → Install."
        case .missingFile:
            return "The signed IPA is missing. Sign the app again."
        }
    }
}

/// Runs one itms-services install: local server → manifest → iOS prompt → payload → done.
@MainActor
final class InstallSession: ObservableObject {
    static let shared = InstallSession()

    @Published private(set) var phase: InstallPhase = .idle
    @Published private(set) var methodDescription = ""
    @Published private(set) var log: [LogLine] = []

    private var server: LocalHTTPServer?
    private var watchdog: Task<Void, Never>?
    private var shutdownTask: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var manifestPath = ""
    private var payloadPath = ""
    private var lastProgress = 0.0
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var startedAt = Date()
    /// The signed app this session is installing.
    private(set) var appID: UUID?

    /// Re-check backloop.dev at most this often when its last certificate was expired or unreachable.
    static let backloopRecheckInterval: TimeInterval = 12 * 60 * 60

    func isRunning(for id: UUID) -> Bool {
        appID == id && phase.isActive
    }

    /// User cancelled / closed: stop and forget, so the next Install starts fresh.
    func cancel() {
        stop()
        phase = .idle
        appID = nil
    }

    static let promptTimeout: UInt64 = 180 // seconds

    func start(app: SignedApp, ipaURL: URL, iconURL: URL?, method: InstallMethod, certificates: ServerCertificateStore) async {
        stop()
        log = []
        lastProgress = 0
        startedAt = Date()
        appID = app.id
        phase = .preparing
        beginBackgroundTask()
        observeLifecycle()
        AppLog.info("install: start \(app.name) \(app.bundleID) v\(app.version) (\(ipaURL.lastPathComponent)), method \(method.rawValue)")

        do {
            guard FileManager.default.fileExists(atPath: ipaURL.path) else { throw InstallError.missingFile }

            // 1. Pick the method and (for HTTPS) the server certificate.
            var certificate: ServerCertificate?
            if method != .semiLocal {
                certificate = certificates.preferred
                let recheckDue = certificates.lastBackloopAttempt
                    .map { Date().timeIntervalSince($0) > InstallSession.backloopRecheckInterval } ?? true
                if certificate == nil && method == .automatic && !recheckDue {
                    // The last check found no usable backloop.dev certificate: don't wait on the network again.
                    note("No valid server certificate (backloop.dev checked recently); using Semi-Local")
                } else if certificate == nil {
                    note("No valid server certificate stored; fetching backloop.dev…")
                    do {
                        certificate = try await certificates.refreshBackloop(timeout: method == .automatic ? 8 : 20)
                    } catch {
                        note(error.localizedDescription, error: method == .localHTTPS)
                    }
                    certificate = certificates.preferred
                }
                if certificate == nil && method == .localHTTPS {
                    throw InstallError.noServerCertificate("Add your own certificate in Settings → Install, or switch to Semi-Local.")
                }
            }

            var identity: sec_identity_t?
            if let certificate, let pem = certificates.pem(for: certificate.source) {
                identity = try TLSIdentityFactory.makeIdentity(certificatePEM: pem.certificate, privateKeyPEM: pem.key)
            }

            // 2. Start the loopback server.
            let server = LocalHTTPServer(identity: identity) { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
            self.server = server
            let port = try await server.start()

            let token = UUID().uuidString.lowercased()
            manifestPath = "/\(token)/manifest.plist"
            payloadPath = "/\(token)/app.ipa"
            let iconPath = "/\(token)/icon.png"
            server.setRoute(payloadPath, .file(ipaURL, contentType: "application/octet-stream"))
            if let iconURL, let data = try? Data(contentsOf: iconURL) {
                server.setRoute(iconPath, .data(data, contentType: "image/png"))
            }

            let manifestURL: URL
            if let certificate, identity != nil {
                let base = "https://\(certificate.hostname):\(port)"
                guard let packageURL = URL(string: base + payloadPath), let localManifest = URL(string: base + manifestPath) else {
                    throw InstallError.openFailed
                }
                let iconURLRemote = iconURL == nil ? nil : URL(string: base + iconPath)
                let manifest = InstallManifest.data(packageURL: packageURL, bundleID: app.bundleID, version: app.version,
                                                    title: app.name, displayImageURL: iconURLRemote, fullSizeImageURL: iconURLRemote)
                server.setRoute(manifestPath, .data(manifest, contentType: "text/xml"))
                manifestURL = localManifest
                methodDescription = "Fully Local · \(certificate.hostname)"
            } else {
                guard let packageURL = URL(string: "http://127.0.0.1:\(port)\(payloadPath)"),
                      let remote = InstallManifest.paleraManifestURL(packageURL: packageURL, bundleID: app.bundleID,
                                                                     version: app.version, title: app.name) else {
                    throw InstallError.openFailed
                }
                manifestURL = remote
                methodDescription = "Semi-Local · manifest from api.palera.in"
            }
            note("Server listening on port \(port) (\(identity == nil ? "HTTP" : "HTTPS"))")
            note("Manifest: \(manifestURL.absoluteString)")

            // 3. Hand off to iOS.
            guard let itms = InstallManifest.itmsURL(manifestURL: manifestURL) else { throw InstallError.openFailed }
            phase = .waitingForPrompt
            let opened = await UIApplication.shared.open(itms)
            guard opened else { throw InstallError.openFailed }
            note("Opened itms-services link; waiting for iOS…")
            startWatchdog()
        } catch {
            fail(error.localizedDescription)
        }
    }

    func stop() {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        lifecycleObservers = []
        watchdog?.cancel()
        watchdog = nil
        shutdownTask?.cancel()
        shutdownTask = nil
        server?.stop()
        server = nil
        endBackgroundTask()
    }

    // MARK: Events

    private func handle(_ event: LocalHTTPServer.Event) {
        switch event {
        case .request(let method, let path):
            if path == manifestPath {
                note("iOS fetched the manifest")
                if case .waitingForPrompt = phase { phase = .manifestSent }
            } else if path == payloadPath {
                note("iOS requested the app (\(method))")
                if method == "GET", phase != .installing { phase = .downloading(lastProgress) }
            } else {
                note("\(method) \(path)")
            }
        case .payloadProgress(let value):
            guard phase != .installing, value - lastProgress >= 0.01 || value >= 1 else { return }
            lastProgress = value
            if case .failed = phase { return }
            phase = .downloading(value)
        case .payloadCompleted:
            note("App sent to iOS; installing…")
            phase = .installing
            Haptics.success()
            watchdog?.cancel()
            // Keep the server briefly in case iOS retries, then shut down cleanly.
            shutdownTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if Task.isCancelled { return }
                self?.stop()
                self?.note("Server stopped")
            }
        case .payloadFailed(let reason):
            fail("Sending the app failed: \(reason)")
        case .requestDetail(let text):
            AppLog.info("install: request \(text)")
        }
    }

    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: InstallSession.promptTimeout * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            switch self.phase {
            case .waitingForPrompt, .manifestSent:
                self.fail(InstallError.timedOut.localizedDescription)
            default:
                break
            }
        }
    }

    private func fail(_ message: String) {
        note(message, error: true)
        phase = .failed(message)
        Haptics.error()
        stop()
    }

    private func note(_ text: String, error: Bool = false) {
        let elapsed = String(format: "+%.2fs", Date().timeIntervalSince(startedAt))
        let text = "[\(elapsed)] \(text)"
        log.append(LogLine(text: text, isError: error))
        if error { AppLog.error("install: \(text)") } else { AppLog.info("install: \(text)") }
    }

    /// Records when CertSigner leaves / returns to the foreground mid-install (a suspended app can't serve the IPA).
    private func observeLifecycle() {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        let center = NotificationCenter.default
        let events: [(Notification.Name, String)] = [
            (UIApplication.willResignActiveNotification, "CertSigner inactive (system prompt shown?)"),
            (UIApplication.didBecomeActiveNotification, "CertSigner active again"),
            (UIApplication.didEnterBackgroundNotification, "CertSigner went to the background"),
            (UIApplication.willEnterForegroundNotification, "CertSigner back in the foreground")
        ]
        lifecycleObservers = events.map { name, text in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.phase.isActive else { return }
                    self.note("\(text) · phase \(self.phase)")
                }
            }
        }
    }

    // MARK: Background time (keeps the server alive if the app is briefly backgrounded)

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "CertSigner Install") { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
