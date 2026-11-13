import Foundation
import CryptoKit
import SwiftUI

// MARK: - Release metadata

/// `update.json`, published by CI next to `CertSigner.ipa` on the `latest` release.
struct ReleaseManifest: Codable, Equatable {
    struct Asset: Codable, Equatable {
        let name: String
        let size: Int64
        let sha256: String
    }

    let schema: Int
    let build: Int
    let version: String
    let commit: String
    let bundleID: String
    let minimumOS: String
    let ipa: Asset
    let published: String
    let notes: [String]

    var publishedDate: Date? { ISO8601DateFormatter().date(from: published) }
}

/// The parts of GitHub's "latest release" answer the updater reads.
struct GitHubRelease: Decodable, Equatable {
    struct Asset: Decodable, Equatable {
        let name: String
        let size: Int64
        let downloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name, size
            case downloadURL = "browser_download_url"
        }
    }

    let name: String?
    let pageURL: URL?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case name, draft, prerelease, assets
        case pageURL = "html_url"
    }
}

/// A newer CertSigner build, checked and ready to offer.
struct AvailableUpdate: Equatable {
    let manifest: ReleaseManifest
    let ipaURL: URL
    let pageURL: URL?
    var build: Int { manifest.build }
}

enum UpdateError: LocalizedError, Equatable {
    case network(String)
    case invalidRelease(String)
    case download(String)
    case verification(String)
    case signing(String)
    case notReady(String)

    var errorDescription: String? {
        switch self {
        case .network(let reason): return "Couldn't check for updates. \(reason)"
        case .invalidRelease(let reason): return "The latest release doesn't look like a CertSigner update (\(reason))."
        case .download(let reason): return "The download didn't finish. \(reason)"
        case .verification(let reason): return "The download didn't match the release (\(reason)). Nothing was installed."
        case .signing(let reason): return "Signing the update failed: \(reason)"
        case .notReady(let reason): return reason
        }
    }
}

// MARK: - Rules (pure, tested)

enum UpdateRules {
    /// The only repository updates come from.
    static let repository = "risinginvader2007-hub/CertSigner"
    static let releaseAPI = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    /// The bundle ID CI builds with (the installed copy may use another one; that one is kept).
    static let bundleID = "com.certsigner.app"
    static let assetName = "CertSigner.ipa"
    static let manifestName = "update.json"
    static let maxIPASize: Int64 = 200 * 1024 * 1024
    static let checkInterval: TimeInterval = 12 * 60 * 60

    /// This copy's build number (CFBundleVersion). Builds before the updater all say "1".
    static var installedBuild: Int { build(from: Bundle.main.infoDictionary?["CFBundleVersion"] as? String) }

    static func build(from text: String?) -> Int { Int((text ?? "").trimmingCharacters(in: .whitespaces)) ?? 0 }

    /// Downloads must come from this repository's releases on github.com, over HTTPS.
    static func isTrustedDownload(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com"
            && url.path.hasPrefix("/\(repository)/releases/download/")
    }

    static func isSHA256(_ text: String) -> Bool {
        text.count == 64 && text.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// iOS version check: "16.0" ≤ "17.4.1".
    static func osSatisfies(_ minimum: String, current: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Bool {
        let parts = minimum.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return true }
        let wanted = [parts[0], parts.count > 1 ? parts[1] : 0, parts.count > 2 ? parts[2] : 0]
        let have = [current.majorVersion, current.minorVersion, current.patchVersion]
        return have.lexicographicallyPrecedes(wanted) == false
    }

    /// Checks the release and its update.json against each other; returns the update if it is newer.
    static func update(release: GitHubRelease, manifest: ReleaseManifest, installedBuild: Int) throws -> AvailableUpdate? {
        guard !release.draft, !release.prerelease else { throw UpdateError.invalidRelease("not a published release") }
        guard manifest.schema == 1 else { throw UpdateError.invalidRelease("unknown update.json format \(manifest.schema)") }
        guard manifest.bundleID == bundleID else { throw UpdateError.invalidRelease("bundle ID \(manifest.bundleID)") }
        guard manifest.build > 0 else { throw UpdateError.invalidRelease("no build number") }
        guard manifest.ipa.name == assetName else { throw UpdateError.invalidRelease("asset \(manifest.ipa.name)") }
        guard isSHA256(manifest.ipa.sha256) else { throw UpdateError.invalidRelease("no checksum") }
        guard manifest.ipa.size > 0, manifest.ipa.size <= maxIPASize else { throw UpdateError.invalidRelease("size \(manifest.ipa.size)") }
        guard let asset = release.assets.first(where: { $0.name == assetName }) else {
            throw UpdateError.invalidRelease("no \(assetName)")
        }
        guard asset.size == manifest.ipa.size else { throw UpdateError.invalidRelease("asset size differs from update.json") }
        guard isTrustedDownload(asset.downloadURL) else { throw UpdateError.invalidRelease("unexpected download address") }
        guard manifest.build > installedBuild else { return nil }
        return AvailableUpdate(manifest: manifest, ipaURL: asset.downloadURL, pageURL: release.pageURL)
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The downloaded IPA is exactly the release's: size, SHA-256, CertSigner's bundle ID and the build number.
    static func verify(ipa url: URL, against manifest: ReleaseManifest) throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? -1
        guard size == manifest.ipa.size else { throw UpdateError.verification("size \(size) instead of \(manifest.ipa.size)") }
        guard try sha256(of: url) == manifest.ipa.sha256 else { throw UpdateError.verification("checksum") }
        let meta: IPAMetadata
        do { meta = try IPAInspector.inspect(url) } catch { throw UpdateError.verification("unreadable IPA") }
        guard meta.bundleID == bundleID else { throw UpdateError.verification("bundle ID \(meta.bundleID)") }
        guard build(from: meta.build) == manifest.build else { throw UpdateError.verification("build \(meta.build)") }
    }
}

// MARK: - Which certificate signs the update

/// How this installed copy was signed (its own embedded profile).
struct RunningSignature: Equatable {
    var bundleID: String
    var displayName: String
    var teamID: String?
    var teamName: String?
    var certificates: [Data]

    static func current(bundle: Bundle = .main) -> RunningSignature {
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? "CertSigner"
        let profile = bundle.url(forResource: "embedded", withExtension: "mobileprovision")
            .flatMap { try? ProfileParser.parse(url: $0) }
        return RunningSignature(bundleID: bundle.bundleIdentifier ?? UpdateRules.bundleID, displayName: name,
                                teamID: profile?.teamID, teamName: profile?.teamName,
                                certificates: profile?.developerCertificates ?? [])
    }
}

enum UpdateCertificateMatcher {
    struct Candidate: Equatable {
        let id: UUID
        let teamID: String?
        /// Its .p12 is one of the certificates in the installed copy's profile.
        let signedThisCopy: Bool
        let usable: Bool
        let isActive: Bool
        let expires: Date?
    }

    /// The certificate to sign the update with: same team as the installed copy (iOS refuses an
    /// update from another team, and the saved passwords in the Keychain belong to that team).
    /// Prefers the certificate that signed this copy, then one that passes every check, then the
    /// active one, then the latest expiry.
    static func pick(_ candidates: [Candidate], runningTeam: String?) -> Candidate? {
        candidates
            .filter { runningTeam == nil || $0.teamID == runningTeam }
            .sorted { a, b in
                if a.signedThisCopy != b.signedThisCopy { return a.signedThisCopy }
                if a.usable != b.usable { return a.usable }
                if a.isActive != b.isActive { return a.isActive }
                return (a.expires ?? .distantPast) > (b.expires ?? .distantPast)
            }
            .first
    }
}

/// What the update will do, and whether it can.
struct UpdatePlan {
    struct Check: Identifiable {
        let id: String
        let title: String
        let detail: String
        /// nil = couldn't be checked.
        let passed: Bool?
    }

    let certificate: Certificate?
    let running: RunningSignature
    let checks: [Check]

    var blockingIssue: String? { checks.first { $0.passed == false }?.detail }
    var canUpdate: Bool { certificate != nil && blockingIssue == nil }
}

// MARK: - Service

/// Checks GitHub for a newer CertSigner, then downloads it, verifies it, signs it with the
/// user's own certificate (the same SigningWorker as every other app) and installs it through
/// the same InstallSession. iOS asks the user to confirm and closes CertSigner while it installs;
/// the next launch confirms the update. Files live in Caches/Updates only.
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    enum CheckState: Equatable {
        case idle, checking
        case upToDate(Date)
        case available(AvailableUpdate)
        case failed(String)
    }

    enum Stage: Int, CaseIterable, Identifiable {
        case download, verify, sign, install
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .download: return "Download"
            case .verify: return "Verify"
            case .sign: return "Sign with your certificate"
            case .install: return "Install"
            }
        }
    }

    enum RunState: Equatable {
        case idle
        case running(Stage, Double)
        /// Signed and handed to InstallSession (its phase shows the rest).
        case installing
        case failed(Stage, String)
    }

    enum Keys {
        static let autoCheck = "updates.autoCheck"
        static let lastCheck = "updates.lastCheck"
        static let skippedBuild = "updates.skippedBuild"
        static let pendingBuild = "updates.pendingBuild"
        static let etag = "updates.etag"
    }

    @Published private(set) var checkState: CheckState = .idle
    @Published private(set) var runState: RunState = .idle
    @Published private(set) var log: [LogLine] = []
    @Published private(set) var skippedBuild: Int
    /// The update sheet (RootView presents it; Home and Settings open it).
    @Published var sheetShown = false

    private let defaults: UserDefaults
    private var runTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        skippedBuild = defaults.integer(forKey: Keys.skippedBuild)
    }

    var available: AvailableUpdate? {
        if case .available(let update) = checkState { return update }
        return nil
    }

    /// An update to point out (Home card, Settings badge): available and not skipped.
    var highlighted: AvailableUpdate? {
        guard let update = available, update.build != skippedBuild else { return nil }
        return update
    }

    var isRunning: Bool {
        if case .running = runState { return true }
        return false
    }

    static var folder: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Updates", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Launch

    /// On launch: confirm a finished update once, clean up, and check if due.
    /// Returns true when it showed "Updated to build N".
    @discardableResult
    func launch(toasts: ToastCenter) -> Bool {
        let pending = defaults.integer(forKey: Keys.pendingBuild)
        let installed = UpdateRules.installedBuild
        var updated = false
        if pending > 0, installed >= pending {
            defaults.removeObject(forKey: Keys.pendingBuild)
            try? FileManager.default.removeItem(at: Self.folder)
            toasts.show("Updated to build \(installed)", kind: .success)
            AppLog.info("update: now running build \(installed)")
            updated = true
        }
        Task { await checkIfDue() }
        return updated
    }

    func checkIfDue() async {
        guard SettingsKeys.bool(Keys.autoCheck, default: true) else { return }
        let last = defaults.double(forKey: Keys.lastCheck)
        guard Date().timeIntervalSince1970 - last >= UpdateRules.checkInterval else { return }
        await check()
    }

    // MARK: Check

    func check() async {
        guard checkState != .checking else { return }
        checkState = .checking
        do {
            let release = try await fetchRelease()
            guard let manifestAsset = release.assets.first(where: { $0.name == UpdateRules.manifestName }),
                  UpdateRules.isTrustedDownload(manifestAsset.downloadURL) else {
                // Releases from before the updater have no update.json: nothing to offer.
                finishCheck(.upToDate(Date()))
                return
            }
            let manifest = try await fetchManifest(manifestAsset.downloadURL)
            if let update = try UpdateRules.update(release: release, manifest: manifest, installedBuild: UpdateRules.installedBuild) {
                guard UpdateRules.osSatisfies(manifest.minimumOS) else {
                    finishCheck(.failed("Build \(update.build) needs iOS \(manifest.minimumOS) or later."))
                    return
                }
                finishCheck(.available(update))
                AppLog.info("update: build \(update.build) available (installed \(UpdateRules.installedBuild))")
            } else {
                finishCheck(.upToDate(Date()))
            }
        } catch {
            let message = (error as? UpdateError)?.localizedDescription ?? UpdateError.network(error.localizedDescription).localizedDescription
            AppLog.error("update: check failed: \(message)")
            finishCheck(.failed(message))
        }
    }

    private func finishCheck(_ state: CheckState) {
        checkState = state
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastCheck)
    }

    private var cachedReleaseURL: URL { Self.folder.appendingPathComponent("latest-release.json") }

    private func fetchRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: UpdateRules.releaseAPI, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CertSigner-Updater", forHTTPHeaderField: "User-Agent")
        let cached = try? Data(contentsOf: cachedReleaseURL)
        if cached != nil, let etag = defaults.string(forKey: Keys.etag) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body: Data
        switch status {
        case 200:
            body = data
            try? data.write(to: cachedReleaseURL, options: .atomic)
            if let etag = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag") { defaults.set(etag, forKey: Keys.etag) }
        case 304:
            guard let cached else { throw UpdateError.network("GitHub sent no data.") }
            body = cached
        case 403, 429:
            throw UpdateError.network("GitHub is limiting requests right now. Try again later.")
        case 404:
            throw UpdateError.network("No release is published yet.")
        default:
            throw UpdateError.network("GitHub answered \(status).")
        }
        do {
            return try JSONDecoder().decode(GitHubRelease.self, from: body)
        } catch {
            throw UpdateError.invalidRelease("unreadable release information")
        }
    }

    private func fetchManifest(_ url: URL) async throws -> ReleaseManifest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("CertSigner-Updater", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 256 * 1024 else {
            throw UpdateError.invalidRelease("update.json couldn't be downloaded")
        }
        do {
            return try JSONDecoder().decode(ReleaseManifest.self, from: data)
        } catch {
            throw UpdateError.invalidRelease("unreadable update.json")
        }
    }

    // MARK: Skip

    func skip(_ update: AvailableUpdate) {
        skippedBuild = update.build
        defaults.set(update.build, forKey: Keys.skippedBuild)
    }

    // MARK: Plan

    /// Picks the certificate and runs the pre-update checks.
    func plan(certificates: CertificateStore, udid: String) async -> UpdatePlan {
        let running = RunningSignature.current()
        var candidates: [UpdateCertificateMatcher.Candidate] = []
        for certificate in certificates.certificates {
            let der = await certificateDER(certificate, store: certificates)
            let signedThisCopy = der.map { running.certificates.contains($0) } ?? false
            candidates.append(.init(id: certificate.id, teamID: certificate.profile?.teamID,
                                    signedThisCopy: signedThisCopy,
                                    usable: Self.checks(for: certificate, running: running, udid: udid).allSatisfy { $0.passed != false },
                                    isActive: certificate.id == certificates.activeID,
                                    expires: certificate.expirationDate))
        }
        let picked = UpdateCertificateMatcher.pick(candidates, runningTeam: running.teamID)
            .flatMap { pick in certificates.certificates.first { $0.id == pick.id } }

        guard let picked else {
            let team = running.teamName.map { "\($0) (\(running.teamID ?? ""))" } ?? running.teamID
            let detail = certificates.certificates.isEmpty
                ? "Add your certificate in Settings → Certificates first."
                : "None of your certificates is from \(team ?? "the team that signed CertSigner"). iOS only updates an app with a certificate from the same team. Import that certificate in Settings → Certificates."
            return UpdatePlan(certificate: nil, running: running,
                              checks: [.init(id: "certificate", title: "Certificate from the same team", detail: detail, passed: false)])
        }
        var checks = Self.checks(for: picked, running: running, udid: udid)
        if running.teamID == nil {
            checks.insert(.init(id: "team", title: "Same team as this copy",
                                detail: "Couldn't read how this copy of CertSigner was signed.", passed: nil), at: 0)
        }
        return UpdatePlan(certificate: picked, running: running, checks: checks)
    }

    private func certificateDER(_ certificate: Certificate, store: CertificateStore) async -> Data? {
        guard let data = try? Data(contentsOf: store.p12URL(for: certificate.id)),
              let password = store.password(for: certificate.id) else { return nil }
        let outcome = await Task.detached(priority: .userInitiated) { P12Inspector.inspect(data: data, password: password) }.value
        if case .valid(let der, _) = outcome { return der }
        return nil
    }

    static func checks(for certificate: Certificate, running: RunningSignature, udid: String, now: Date = Date()) -> [UpdatePlan.Check] {
        var checks: [UpdatePlan.Check] = []
        let profile = certificate.profile
        if let team = running.teamID {
            let same = profile?.teamID == team
            checks.append(.init(id: "team", title: "Same team as this copy",
                                detail: same ? "Team \(team): iOS updates CertSigner in place and keeps its data."
                                             : "This copy is from team \(team); the certificate is from \(profile?.teamID ?? "an unknown team"). iOS would refuse the update.",
                                passed: same))
        }
        let certificateExpiry = certificate.record.signingCertificate?.notAfter
        let certificateOK = certificateExpiry.map { $0 > now }
        checks.append(.init(id: "certificate", title: "Certificate valid",
                            detail: certificateExpiry.map { certificateOK == true ? "Expires \($0.formatted(date: .abbreviated, time: .omitted))." : "Expired on \($0.formatted(date: .abbreviated, time: .omitted)). Import a renewed certificate." }
                                ?? "Its expiry couldn't be read.",
                            passed: certificateOK))
        let profileExpired = profile?.isExpired(now: now)
        checks.append(.init(id: "profile", title: "Provisioning profile valid",
                            detail: profile?.expirationDate.map { profileExpired == true ? "Expired on \($0.formatted(date: .abbreviated, time: .omitted)). Import a renewed profile." : "Expires \($0.formatted(date: .abbreviated, time: .omitted))." }
                                ?? "The profile couldn't be read.",
                            passed: profile == nil ? Optional(false) : profileExpired.map { !$0 }))
        checks.append(.init(id: "pair", title: "Certificate is in the profile",
                            detail: certificate.record.matchesProfile == false ? "This .p12 isn't listed in its profile, so iOS would reject the update." : "The .p12 and profile belong together.",
                            passed: certificate.record.matchesProfile.map { $0 }))
        let pattern = profile?.bundleIDPattern ?? "*"
        let allowed = SigningValidator.bundleID(running.bundleID, matches: pattern)
        checks.append(.init(id: "bundle", title: "Keeps bundle ID \(running.bundleID)",
                            detail: allowed ? "The profile's App ID (\(pattern)) allows it, so iOS treats this as an update."
                                            : "The profile's App ID is \(pattern), which doesn't allow \(running.bundleID). Use the profile CertSigner was installed with.",
                            passed: allowed))
        checks.append(.init(id: "password", title: "Password saved",
                            detail: certificate.hasPassword ? "Stored in the Keychain." : "Enter the .p12 password in the certificate's details.",
                            passed: certificate.hasPassword))
        if !udid.isEmpty, let profile {
            let listed = profile.containsDevice(udid)
            checks.append(.init(id: "device", title: "This iPhone is in the profile",
                                detail: listed == false ? "Your UDID isn't in this profile, so iOS would refuse to install." : "Your UDID is listed (or the profile covers all devices).",
                                passed: listed))
        }
        return checks
    }

    // MARK: Run

    func start(_ update: AvailableUpdate, plan: UpdatePlan, certificates: CertificateStore,
               serverCertificates: ServerCertificateStore, method: InstallMethod, paleraFallback: Bool) {
        guard !isRunning, plan.canUpdate, let certificate = plan.certificate else { return }
        runTask = Task { [weak self] in
            await self?.run(update, plan: plan, certificate: certificate, certificates: certificates,
                            serverCertificates: serverCertificates, method: method, paleraFallback: paleraFallback)
        }
    }

    func cancel() {
        runTask?.cancel()
        runTask = nil
        if isRunning { runState = .idle }
    }

    /// Back to the start after a failure or a finished hand-off (not while running).
    func resetRun() {
        guard !isRunning else { return }
        runState = .idle
    }

    private func note(_ text: String, error: Bool = false) {
        log.append(LogLine(text: text, isError: error))
        if error { AppLog.error("update: \(text)") } else { AppLog.info("update: \(text)") }
    }

    private func run(_ update: AvailableUpdate, plan: UpdatePlan, certificate: Certificate, certificates: CertificateStore,
                     serverCertificates: ServerCertificateStore, method: InstallMethod, paleraFallback: Bool) async {
        log = []
        let folder = Self.folder.appendingPathComponent("\(update.build)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let downloaded = folder.appendingPathComponent(UpdateRules.assetName)
        let signedName = "CertSigner-\(update.build)-\(certificate.id.uuidString.prefix(8)).ipa"
        let signed = folder.appendingPathComponent(signedName)
        var stage = Stage.download
        note("Updating build \(UpdateRules.installedBuild) → \(update.build) with \(certificate.nickname)")

        do {
            // 1. Download (reused when an earlier attempt already verified it).
            if (try? UpdateRules.verify(ipa: downloaded, against: update.manifest)) != nil {
                note("Using the build \(update.build) download from the last attempt")
            } else {
                runState = .running(.download, 0)
                note("Downloading \(update.ipaURL.absoluteString)")
                let downloader = FileDownloader(log: { line in Task { @MainActor in UpdateService.shared.note(line) } }) { received, expected in
                    let total = Double(expected ?? update.manifest.ipa.size)
                    let fraction = total > 0 ? min(1, Double(received) / total) : 0
                    Task { @MainActor in
                        if case .running(.download, _) = UpdateService.shared.runState {
                            UpdateService.shared.runState = .running(.download, fraction)
                        }
                    }
                }
                let temp: URL
                do {
                    temp = try await withTaskCancellationHandler {
                        try await downloader.start(update.ipaURL)
                    } onCancel: {
                        downloader.cancel()
                    }
                } catch is CancellationError {
                    return
                } catch {
                    throw UpdateError.download(error.localizedDescription)
                }
                try? FileManager.default.removeItem(at: downloaded)
                try FileManager.default.moveItem(at: temp, to: downloaded)

                // 2. Verify.
                stage = .verify
                runState = .running(.verify, 0)
                try UpdateRules.verify(ipa: downloaded, against: update.manifest)
                note("Verified: \(update.manifest.ipa.size) bytes, SHA-256 \(update.manifest.ipa.sha256.prefix(12))…, build \(update.build)")
            }
            try Task.checkCancellation()

            // 3. Sign with the same pipeline as every app, keeping this copy's bundle ID and name.
            stage = .sign
            if FileManager.default.fileExists(atPath: signed.path) {
                note("Using the signed copy from the last attempt")
            } else {
                runState = .running(.sign, 0)
                let options = SigningOptions(displayName: plan.running.displayName, bundleID: plan.running.bundleID,
                                             mode: .strict)
                let input = SigningInput(
                    ipaURL: downloaded,
                    p12URL: certificates.p12URL(for: certificate.id),
                    profileURL: certificates.profileURL(for: certificate.id),
                    password: certificates.password(for: certificate.id) ?? "",
                    options: options,
                    appIDPattern: certificate.profile?.bundleIDPattern ?? "*",
                    outputURL: signed.appendingPathExtension("partial"),
                    certificateName: certificate.record.signingCertificate?.commonName.map { "\($0) (\(certificate.nickname))" } ?? certificate.nickname,
                    certificateExpiry: certificate.record.signingCertificate?.notAfter ?? certificate.expirationDate
                )
                let output: SigningOutput
                do {
                    output = try await Task.detached(priority: .userInitiated) {
                        try SigningWorker.run(input) { event in
                            Task { @MainActor in UpdateService.shared.handle(event) }
                        }
                    }.value
                } catch {
                    throw UpdateError.signing(error.localizedDescription)
                }
                guard output.bundleID == plan.running.bundleID else {
                    throw UpdateError.signing("bundle ID came out as \(output.bundleID)")
                }
                try FileManager.default.moveItem(at: signed.appendingPathExtension("partial"), to: signed)
                note("Signed as \(output.bundleID)")
            }
            try Task.checkCancellation()

            // 4. Install through the shared install session (the user confirms the iOS prompt).
            stage = .install
            defaults.set(update.build, forKey: Keys.pendingBuild)
            runState = .installing
            let size = (try? FileManager.default.attributesOfItem(atPath: signed.path)[.size] as? NSNumber)?.int64Value ?? 0
            let app = SignedApp(id: UUID(), name: plan.running.displayName, bundleID: plan.running.bundleID,
                                version: "\(update.manifest.version) (\(update.build))", signedAt: Date(),
                                certificateID: certificate.id, certificateName: certificate.nickname,
                                expiresAt: certificate.expirationDate, fileName: signed.lastPathComponent,
                                iconFileName: nil, size: size, sourceAppID: nil)
            await InstallSession.shared.start(app: app, ipaURL: signed, iconURL: nil, method: method,
                                              certificates: serverCertificates,
                                              signingTeamID: certificate.profile?.teamID, paleraFallback: paleraFallback)
        } catch is CancellationError {
            runState = .idle
        } catch {
            let message = (error as? UpdateError)?.localizedDescription ?? error.localizedDescription
            note(message, error: true)
            if stage == .verify { try? FileManager.default.removeItem(at: downloaded) }
            runState = .failed(stage, message)
            Haptics.error()
        }
    }

    private func handle(_ event: SigningEvent) {
        switch event {
        case .step: break
        case .progress(let value): if case .running(.sign, _) = runState { runState = .running(.sign, value) }
        case .log(let text, let isError): log.append(LogLine(text: text, isError: isError))
        }
    }
}
