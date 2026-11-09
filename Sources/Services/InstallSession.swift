import Foundation
import UIKit

/// Why an install is waiting longer than it should. The server keeps listening; the sheet shows a
/// readable message with Retry and Reopen Prompt.
enum InstallStall: Equatable {
    /// iOS hasn't asked our server for the manifest (Fully Local) 15 s after the link opened.
    case noManifest
    /// iOS has the manifest (or Semi-Local's service served it) but hasn't asked for the app.
    case noPayload
}

enum InstallPhase: Equatable {
    case idle
    case preparing
    case waitingForPrompt
    case manifestSent
    case stalled(InstallStall)
    case downloading(Double)
    /// iOS has the whole app and is installing it.
    case installing
    /// iOS reports the app as installed (LaunchServices), when that can be checked.
    case installed
    case failed(String)

    var isActive: Bool {
        switch self {
        case .preparing, .waitingForPrompt, .manifestSent, .stalled, .downloading: return true
        default: return false
        }
    }

    /// The transfer finished (installing or confirmed installed).
    var isSuccess: Bool { self == .installing || self == .installed }
}

enum InstallError: LocalizedError {
    case noServerCertificate(String)
    case openFailed
    case timedOut
    case missingFile
    case manifestServiceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noServerCertificate(let reason):
            return "Fully Local needs a valid server certificate. \(reason)"
        case .openFailed:
            return "iOS refused to open the install link."
        case .timedOut:
            return "iOS never asked for the app within 3 minutes. If you tapped Cancel on the prompt, try again; otherwise switch the install method in Settings → Install."
        case .missingFile:
            return "The signed IPA is missing. Sign the app again."
        case .manifestServiceUnavailable(let reason):
            return "Semi-Local needs api.palera.in to create the install manifest, and it didn't respond (\(reason)). Check your connection, or add a server certificate in Settings → Install to install without it."
        }
    }
}

/// Runs one itms-services install: local server → manifest → iOS prompt → payload → done.
///
/// Phases advance on what the server actually sees (manifest request, IPA request, bytes sent),
/// never on app lifecycle events. Every `start` is a completely fresh session: the previous
/// server is stopped, a new port and one-time path token are used, timers are cancelled, and
/// events from an older server are ignored.
@MainActor
final class InstallSession: ObservableObject {
    static let shared = InstallSession()

    @Published private(set) var phase: InstallPhase = .idle
    @Published private(set) var methodDescription = ""
    @Published private(set) var log: [LogLine] = []
    /// "Already installed" / team-mismatch explanation, shown under the status.
    @Published private(set) var installHint: String?
    @Published private(set) var installHintIsWarning = false

    private var server: LocalHTTPServer?
    private var generation = 0
    private var timers: [Task<Void, Never>] = []
    private var shutdownTask: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var manifestPath = ""
    private var payloadPath = ""
    private var itmsURL: URL?
    private var usesLocalManifest = false
    private var lastPort: UInt16?
    private var lastProgress = 0.0
    private var lastProgressAt = Date()
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var startedAt = Date()
    private var bundleID = ""
    private var appName = ""
    private var previouslyInstalled: InstalledApps.Info?
    /// The signed app this session is installing.
    private(set) var appID: UUID?

    /// Re-check backloop.dev at most this often when its last certificate was expired or unreachable.
    static let backloopRecheckInterval: TimeInterval = 12 * 60 * 60
    static let manifestStallSeconds: UInt64 = 15
    static let payloadStallSeconds: UInt64 = 30
    static let promptTimeoutSeconds: UInt64 = 180
    static let transferStallSeconds: TimeInterval = 30

    func isRunning(for id: UUID) -> Bool {
        appID == id && phase.isActive
    }

    /// User cancelled / closed: stop and forget, so the next Install starts fresh.
    func cancel() {
        stop()
        phase = .idle
        appID = nil
    }

    func start(app: SignedApp, ipaURL: URL, iconURL: URL?, method: InstallMethod, certificates: ServerCertificateStore,
               signingTeamID: String? = nil, paleraFallback: Bool = true) async {
        // A completely fresh session.
        stop()
        generation += 1
        let session = generation
        log = []
        lastProgress = 0
        startedAt = Date()
        appID = app.id
        bundleID = app.bundleID
        appName = app.name
        manifestPath = ""
        payloadPath = ""
        itmsURL = nil
        methodDescription = ""
        installHint = nil
        installHintIsWarning = false
        phase = .preparing
        beginBackgroundTask()
        observeLifecycle()
        AppLog.info("install: start \(app.name) \(app.bundleID) v\(app.version) (\(ipaURL.lastPathComponent)), method \(method.rawValue)")

        do {
            guard FileManager.default.fileExists(atPath: ipaURL.path) else { throw InstallError.missingFile }
            checkAlreadyInstalled(app: app, signingTeamID: signingTeamID)

            // 1. Pick the method and (for HTTPS) the server certificate.
            var certificate: ServerCertificate?
            if method != .semiLocal {
                certificate = await serverCertificate(method: method, certificates: certificates)
                if certificate == nil && method == .localHTTPS {
                    throw InstallError.noServerCertificate("Add your own certificate in Settings → Install, or switch to Semi-Local.")
                }
            }
            if certificate == nil {
                // Semi-Local depends on api.palera.in: check it answers before relying on it.
                if let problem = await InstallManifest.checkManifestService() {
                    note("api.palera.in didn't respond: \(problem)", error: true)
                    if paleraFallback, let local = await serverCertificate(method: .automatic, certificates: certificates, forceRefresh: true) {
                        note("Falling back to Fully Local (\(local.hostname)) so the install doesn't depend on api.palera.in")
                        certificate = local
                    } else {
                        throw InstallError.manifestServiceUnavailable(problem)
                    }
                } else {
                    note("api.palera.in is reachable")
                }
            }
            guard session == generation else { return }

            var identity: sec_identity_t?
            if let certificate, let pem = certificates.pem(for: certificate.source) {
                identity = try TLSIdentityFactory.makeIdentity(certificatePEM: pem.certificate, privateKeyPEM: pem.key)
            }

            // 2. Start a new loopback server on a new port with a new one-time token.
            let server = LocalHTTPServer(identity: identity) { [weak self] event in
                Task { @MainActor in
                    guard let self, session == self.generation else { return } // an older session's server
                    self.handle(event)
                }
            }
            self.server = server
            let port = try await server.start(avoiding: lastPort)
            lastPort = port
            guard session == generation else { server.stop(); return }

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
                usesLocalManifest = true
                methodDescription = "Fully Local · manifest and app from this iPhone (\(certificate.hostname))"
            } else {
                guard let packageURL = URL(string: "http://127.0.0.1:\(port)\(payloadPath)"),
                      let remote = InstallManifest.paleraManifestURL(packageURL: packageURL, bundleID: app.bundleID,
                                                                     version: app.version, title: app.name) else {
                    throw InstallError.openFailed
                }
                manifestURL = remote
                usesLocalManifest = false
                methodDescription = "Semi-Local · manifest from api.palera.in, app from this iPhone"
            }
            note("Server listening on port \(port) (\(identity == nil ? "HTTP" : "HTTPS")), new one-time path")
            note("Method: \(methodDescription)")

            // 3. Hand off to iOS.
            guard let itms = InstallManifest.itmsURL(manifestURL: manifestURL) else { throw InstallError.openFailed }
            itmsURL = itms
            try await openPrompt(itms)
        } catch {
            guard session == generation else { return }
            fail(error.localizedDescription)
        }
    }

    /// Opens the same itms-services link again (the server is still listening).
    func reopenPrompt() {
        guard let itmsURL, server != nil else { return }
        note("Reopening the install prompt")
        Task { @MainActor in
            do { try await openPrompt(itmsURL) } catch { fail(error.localizedDescription) }
        }
    }

    private func openPrompt(_ itms: URL) async throws {
        phase = .waitingForPrompt
        let opened = await UIApplication.shared.open(itms)
        guard opened else { throw InstallError.openFailed }
        note("Opened the install link; waiting for iOS to ask for the \(usesLocalManifest ? "manifest" : "app")…")
        startPromptTimers()
    }

    func stop() {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        lifecycleObservers = []
        cancelTimers()
        shutdownTask?.cancel()
        shutdownTask = nil
        server?.stop()
        server = nil
        endBackgroundTask()
    }

    /// The session log as a shareable text file.
    func logFileURL() -> URL? {
        let name = "CertSigner-install-\(appName.isEmpty ? "log" : appName).txt"
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        var text = "CertSigner install log\nApp: \(appName) (\(bundleID))\nMethod: \(methodDescription)\n\n"
        text += log.map { ($0.isError ? "[error] " : "") + $0.text }.joined(separator: "\n") + "\n"
        return (try? Data(text.utf8).write(to: url, options: .atomic)) != nil ? url : nil
    }

    // MARK: Certificates

    private func serverCertificate(method: InstallMethod, certificates: ServerCertificateStore,
                                   forceRefresh: Bool = false) async -> ServerCertificate? {
        if let preferred = certificates.preferred { return preferred }
        let recheckDue = certificates.lastBackloopAttempt
            .map { Date().timeIntervalSince($0) > InstallSession.backloopRecheckInterval } ?? true
        if method == .automatic && !recheckDue && !forceRefresh {
            note("No valid server certificate (backloop.dev checked recently)")
            return nil
        }
        note("No valid server certificate stored; fetching backloop.dev…")
        do {
            _ = try await certificates.refreshBackloop(timeout: method == .automatic ? 8 : 20)
        } catch {
            note(error.localizedDescription, error: method == .localHTTPS)
        }
        return certificates.preferred
    }

    // MARK: Already installed

    private func checkAlreadyInstalled(app: SignedApp, signingTeamID: String?) {
        guard let info = InstalledApps.info(bundleID: app.bundleID) else {
            note("Couldn't check whether \(app.bundleID) is already installed (not available on this iOS)")
            return
        }
        previouslyInstalled = info
        guard info.isInstalled else {
            note("\(app.bundleID) isn't installed yet")
            return
        }
        let version = info.version.map { " v\($0)" } ?? ""
        note("Already installed:\(version), team \(info.teamID ?? "unknown")")
        if let installedTeam = info.teamID, let signingTeamID, !installedTeam.isEmpty {
            if installedTeam == signingTeamID {
                installHint = "\(app.name)\(version) is already installed from the same team. iOS will update it in place and keep its data."
                installHintIsWarning = false
            } else {
                installHint = "\(app.name) is already installed from a different team (\(installedTeam)). iOS won't replace it: delete the existing app first, then install."
                installHintIsWarning = true
            }
        } else {
            installHint = "\(app.name)\(version) is already installed. It updates in place if it was signed by the same team; if it came from another source or certificate, iOS refuses, so delete it first."
            installHintIsWarning = false
        }
    }

    // MARK: Events

    private func handle(_ event: LocalHTTPServer.Event) {
        switch event {
        case .request(let method, let path):
            if path == manifestPath {
                note("iOS requested the manifest (\(method))")
                if phase == .waitingForPrompt || phase == .stalled(.noManifest) {
                    phase = .manifestSent
                    startPayloadTimer()
                }
            } else if path == payloadPath {
                note("iOS requested the app (\(method))")
                if method == "GET", !phase.isSuccess {
                    cancelTimers()
                    lastProgressAt = Date()
                    phase = .downloading(lastProgress)
                    startTransferWatch()
                }
            }
        case .payloadProgress(let value):
            guard !phase.isSuccess else { return }
            if case .failed = phase { return }
            lastProgressAt = Date()
            guard value - lastProgress >= 0.01 || value >= 1 else { return }
            lastProgress = value
            phase = .downloading(value)
        case .payloadCompleted:
            note("App sent to iOS; iOS is installing it")
            phase = .installing
            Haptics.success()
            cancelTimers()
            confirmInstalled()
            // Keep the server briefly in case iOS retries, then shut down cleanly.
            shutdownTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if Task.isCancelled { return }
                self?.server?.stop()
                self?.server = nil
                self?.note("Server stopped")
            }
        case .payloadFailed(let reason):
            fail("Sending the app failed: \(reason)")
        case .requestDetail(let text):
            AppLog.info("install: request \(text)")
        case .served(let text):
            note(text)
        }
    }

    // MARK: Timers (each one checks the phase it was started for)

    private func cancelTimers() {
        timers.forEach { $0.cancel() }
        timers = []
    }

    private func schedule(after seconds: UInt64, _ body: @escaping @MainActor (InstallSession) -> Void) {
        let session = generation
        timers.append(Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard let self, !Task.isCancelled, session == self.generation else { return }
            body(self)
        })
    }

    private func startPromptTimers() {
        cancelTimers()
        if usesLocalManifest {
            schedule(after: Self.manifestStallSeconds) { session in
                guard session.phase == .waitingForPrompt else { return }
                session.note("iOS hasn't asked for the manifest after \(Self.manifestStallSeconds) s", error: true)
                session.phase = .stalled(.noManifest)
            }
        } else {
            schedule(after: Self.payloadStallSeconds) { session in
                guard session.phase == .waitingForPrompt else { return }
                session.note("iOS hasn't asked for the app after \(Self.payloadStallSeconds) s", error: true)
                session.phase = .stalled(.noPayload)
            }
        }
        schedule(after: Self.promptTimeoutSeconds) { session in
            switch session.phase {
            case .waitingForPrompt, .manifestSent, .stalled:
                session.fail(InstallError.timedOut.localizedDescription)
            default:
                break
            }
        }
    }

    private func startPayloadTimer() {
        schedule(after: Self.payloadStallSeconds) { session in
            guard session.phase == .manifestSent else { return }
            session.note("iOS read the manifest but hasn't asked for the app after \(Self.payloadStallSeconds) s", error: true)
            session.phase = .stalled(.noPayload)
        }
    }

    /// Fails a transfer that stops moving for 30 s.
    private func startTransferWatch() {
        let session = generation
        timers.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, session == self.generation, case .downloading = self.phase else { return }
                if Date().timeIntervalSince(self.lastProgressAt) > Self.transferStallSeconds {
                    self.fail("The transfer stopped: iOS stopped receiving the app for \(Int(Self.transferStallSeconds)) s. Keep CertSigner open and try again.")
                    return
                }
            }
        })
    }

    /// After the transfer, poll LaunchServices until the app shows as installed (up to 2 minutes).
    private func confirmInstalled() {
        let session = generation
        let bundleID = self.bundleID
        let before = previouslyInstalled
        timers.append(Task { [weak self] in
            for _ in 0..<120 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled, session == self.generation, self.phase == .installing else { return }
                guard let info = InstalledApps.info(bundleID: bundleID) else {
                    self.note("Install can't be confirmed on this iOS; check your Home Screen")
                    return
                }
                if info.isInstalled && !info.isPlaceholder && (before?.isInstalled != true || info != before) {
                    self.note("iOS reports \(bundleID) installed\(info.version.map { " (v\($0))" } ?? "")")
                    self.phase = .installed
                    return
                }
            }
            guard let self, session == self.generation, self.phase == .installing else { return }
            if before?.isInstalled == true {
                self.installHint = "iOS took the app but the installed copy didn't change. If it was installed from another team or certificate, iOS refuses to replace it: delete the existing app and install again."
                self.installHintIsWarning = true
            }
            self.note("No install confirmation from iOS after 2 minutes", error: before?.isInstalled == true)
        })
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

    /// Records when CertSigner leaves / returns to the foreground mid-install (diagnostics only;
    /// phases never depend on these).
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
