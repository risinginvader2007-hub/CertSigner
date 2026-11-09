import Foundation
import SwiftUI

/// Live state of an IPA being downloaded from a source.
struct RepoDownload: Equatable {
    var received: Int64 = 0
    var expected: Int64?
    /// True once the file is on disk and being imported into the library.
    var importing = false
    var startedAt = Date()

    /// Average speed since the start, in bytes per second (steady, unlike an instantaneous rate).
    var bytesPerSecond: Double? {
        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed > 0.5, received > 0 else { return nil }
        return Double(received) / elapsed
    }

    var progress: Double? {
        guard let expected, expected > 0 else { return nil }
        return min(1, Double(received) / Double(expected))
    }
}

/// An app together with the source that lists it.
struct SourceEntry: Identifiable {
    let repo: Repository
    let app: RepoApp
    var id: String { "\(repo.id.uuidString)|\(app.id)" }
}

/// Sources (repositories) the user added, persisted to Documents/Sources/sources.json,
/// plus downloads of their apps into the import → review → sign → install flow.
@MainActor
final class RepositoryStore: ObservableObject {
    @Published private(set) var repositories: [Repository] = []
    @Published private(set) var refreshing: Set<UUID> = []
    /// Keyed by `downloadKey(repoID:app:)`.
    @Published private(set) var downloads: [String: RepoDownload] = [:]

    private var downloadTasks: [String: Task<Void, Never>] = [:]
    /// One running refresh per source, owned by the store (app lifetime) so leaving or redrawing
    /// a screen can never cancel it. A second request for the same source reuses the running one.
    private var refreshTasks: [UUID: Task<Void, Never>] = [:]
    private var lastAutoRefresh: Date?
    private let indexURL: URL

    init() {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sources", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        indexURL = folder.appendingPathComponent("sources.json")
        repositories = load().map { repo in
            // Older builds stored a cancelled fetch as an error; that was never a real failure.
            var repo = repo
            if let error = repo.lastError, Self.looksLikeCancellation(error) { repo.lastError = nil }
            return repo
        }
        // Refresh on launch, independent of any screen.
        Task { @MainActor [weak self] in self?.refreshIfStale() }
    }

    var allApps: [SourceEntry] {
        repositories.flatMap { repo in repo.apps.map { SourceEntry(repo: repo, app: $0) } }
    }

    func repository(_ id: UUID) -> Repository? {
        repositories.first { $0.id == id }
    }

    // MARK: Add / remove

    /// Accepts https links, bare hosts, and `altstore://source?url=…`-style links.
    static func normalizedURL(_ input: String) throws -> URL {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw RepositoryError.invalidURL }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme != "http", scheme != "https",
           let inner = URLComponents(url: url, resolvingAgainstBaseURL: false)?
               .queryItems?.first(where: { $0.name.lowercased() == "url" })?.value {
            text = inner
        }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        guard let url = URL(string: text), url.host?.isEmpty == false else { throw RepositoryError.invalidURL }
        guard url.scheme?.lowercased() == "https" else { throw RepositoryError.insecureURL }
        return url
    }

    @discardableResult
    func add(_ input: String) async throws -> Repository {
        let url = try Self.normalizedURL(input)
        if let existing = repositories.first(where: { $0.url.absoluteString.lowercased() == url.absoluteString.lowercased() }) {
            throw RepositoryError.duplicate(existing.name)
        }
        let parsed = try await fetch(url)
        guard !parsed.apps.isEmpty else { throw RepositoryError.noApps }
        let repo = Repository(
            id: UUID(), url: url, name: parsed.name, subtitle: parsed.subtitle, iconURL: parsed.iconURL,
            website: parsed.website, apps: parsed.apps, lastUpdated: Date(), lastError: nil, dateAdded: Date()
        )
        withAnimation(Theme.spring) { repositories.append(repo) }
        save()
        AppLog.info("Added source \(repo.name) (\(url.absoluteString)), \(repo.apps.count) apps")
        return repo
    }

    func remove(_ id: UUID) {
        guard let index = repositories.firstIndex(where: { $0.id == id }) else { return }
        let repo = repositories[index]
        for app in repo.apps { cancelDownload(repoID: id, app: app) }
        withAnimation(Theme.spring) { _ = repositories.remove(at: index) }
        save()
        AppLog.info("Removed source \(repo.name)")
    }

    func move(from offsets: IndexSet, to destination: Int) {
        repositories.move(fromOffsets: offsets, toOffset: destination)
        save()
    }

    // MARK: Refresh

    /// Starts (or reuses) the store-owned refresh for one source and returns its task.
    @discardableResult
    func startRefresh(_ id: UUID) -> Task<Void, Never> {
        if let running = refreshTasks[id] { return running }
        refreshing.insert(id)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh(id)
            self.refreshTasks[id] = nil
            self.refreshing.remove(id)
        }
        refreshTasks[id] = task
        return task
    }

    /// Waits for the source's refresh. Cancelling the caller (pull-to-refresh ending, view going
    /// away) only stops the waiting, never the refresh itself.
    func refresh(_ id: UUID) async {
        await startRefresh(id).value
    }

    /// Refreshes every source in parallel, each with its own status.
    func refreshAll() async {
        lastAutoRefresh = Date()
        let tasks = repositories.map { startRefresh($0.id) }
        await withTaskGroup(of: Void.self) { group in
            for task in tasks {
                group.addTask { await task.value }
            }
        }
    }

    /// Refreshes on launch / first appearance and then at most every 30 minutes. Never blocks the caller.
    func refreshIfStale() {
        if let last = lastAutoRefresh, Date().timeIntervalSince(last) < 30 * 60 { return }
        lastAutoRefresh = Date()
        for repo in repositories { startRefresh(repo.id) }
    }

    private func performRefresh(_ id: UUID) async {
        guard let repo = repository(id) else { return }
        var outcome: FetchOutcome?
        var failure: Error?
        // One try plus one retry after a short pause; a cancelled or failed first attempt retries.
        for attempt in 0..<2 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 1_500_000_000) }
            do {
                outcome = try await fetch(repo.url, etag: repo.etag, lastModified: repo.lastModified)
                failure = nil
                break
            } catch {
                failure = error
                AppLog.info("Refreshing source \(repo.name): attempt \(attempt + 1) failed: \(Self.reason(for: error))")
            }
        }
        guard let index = repositories.firstIndex(where: { $0.id == id }) else { return }
        switch outcome {
        case .notModified:
            repositories[index].lastUpdated = Date()
            repositories[index].lastError = nil
            AppLog.info("Source \(repo.name) unchanged (304)")
        case .fresh(let parsed, let etag, let lastModified):
            var updated = repositories[index]
            updated.name = parsed.name
            updated.subtitle = parsed.subtitle
            updated.iconURL = parsed.iconURL
            updated.website = parsed.website
            if !parsed.apps.isEmpty { updated.apps = parsed.apps }
            updated.lastUpdated = Date()
            updated.lastError = parsed.apps.isEmpty ? RepositoryError.noApps.localizedDescription : nil
            updated.etag = parsed.apps.isEmpty ? nil : etag
            updated.lastModified = parsed.apps.isEmpty ? nil : lastModified
            repositories[index] = updated
        case nil:
            if let failure, !Self.isCancellation(failure) {
                // Real failure: keep the last good apps, show the reason.
                repositories[index].lastError = Self.reason(for: failure)
                AppLog.error("Refreshing source \(repo.name) failed: \(Self.reason(for: failure))")
            }
            // Cancelled twice: no result. Keep the last good data and say nothing.
        }
        save()
    }

    private enum FetchOutcome {
        case notModified
        case fresh(RepositoryParser.Parsed, etag: String?, lastModified: String?)
    }

    private func fetch(_ url: URL, etag: String?, lastModified: String?) async throws -> FetchOutcome {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        if http?.statusCode == 304 { return .notModified }
        if let http, !(200..<300).contains(http.statusCode) {
            throw RepositoryError.http(http.statusCode)
        }
        let base = response.url ?? url
        let parsed = try await Task.detached(priority: .userInitiated) {
            try RepositoryParser.parse(data, sourceURL: base)
        }.value
        return .fresh(parsed, etag: http?.value(forHTTPHeaderField: "ETag"),
                      lastModified: http?.value(forHTTPHeaderField: "Last-Modified"))
    }

    private func fetch(_ url: URL) async throws -> RepositoryParser.Parsed {
        switch try await fetch(url, etag: nil, lastModified: nil) {
        case .fresh(let parsed, _, _): return parsed
        case .notModified: throw RepositoryError.http(304)
        }
    }

    nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled
    }

    nonisolated static func looksLikeCancellation(_ message: String) -> Bool {
        let text = message.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return text == "cancelled" || text == "canceled" || text.contains("cancellationerror")
    }

    /// The real reason, in plain words.
    nonisolated static func reason(for error: Error) -> String {
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return "You're offline. Check Wi-Fi or mobile data."
            case .timedOut:
                return "The source didn't respond within 20 seconds."
            case .cannotFindHost, .dnsLookupFailed:
                return "Couldn't find the source's server."
            case .cannotConnectToHost:
                return "Couldn't connect to the source's server."
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
                return "The source's secure connection failed."
            case .badServerResponse, .cannotParseResponse:
                return "The server sent a broken response."
            case .cancelled:
                return "Cancelled"
            default:
                break
            }
        }
        if let repo = error as? RepositoryError {
            if case .notJSON = repo { return "The source didn't return valid JSON." }
            return repo.localizedDescription
        }
        return error.localizedDescription
    }

    // MARK: Downloads

    nonisolated static func downloadKey(repoID: UUID, app: RepoApp) -> String {
        "\(repoID.uuidString)|\(app.id)"
    }

    func download(repoID: UUID, app: RepoApp) -> RepoDownload? {
        downloads[Self.downloadKey(repoID: repoID, app: app)]
    }

    /// Downloads the IPA, imports it into the library and opens Review & Sign.
    /// `signAndInstall` = queue signing straight away with the defaults, then show the install prompt.
    func get(_ app: RepoApp, version: RepoVersion? = nil, from repo: Repository, signAndInstall: Bool,
             importer: ImportCoordinator, library: LibraryStore, toasts: ToastCenter) {
        let key = Self.downloadKey(repoID: repo.id, app: app)
        guard downloads[key] == nil else { return }
        let build = version ?? app.latest
        guard build.downloadURL.scheme?.lowercased() == "https" else {
            toasts.show(RepositoryError.insecureURL.localizedDescription, kind: .error)
            return
        }

        downloads[key] = RepoDownload(received: 0, expected: build.size, startedAt: Date())
        AppLog.info("Downloading \(app.name) \(build.version) from \(repo.name): \(build.downloadURL.absoluteString)")

        downloadTasks[key] = Task { [weak self] in
            let downloader = FileDownloader(log: { AppLog.info($0) }) { received, expected in
                Task { @MainActor [weak self] in
                    guard var state = self?.downloads[key] else { return }
                    state.received = received
                    if let expected { state.expected = expected }
                    self?.downloads[key] = state
                }
            }
            do {
                let file = try await downloader.start(build.downloadURL)
                guard let self, !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: file)
                    return
                }
                self.downloads[key]?.importing = true
                let safeName = app.name.replacingOccurrences(of: "/", with: "-")
                await importer.importIPA(from: file, name: "\(safeName) \(build.version).ipa", moveSource: true,
                                         quickSign: signAndInstall, installWhenDone: signAndInstall,
                                         library: library, toasts: toasts)
                self.finishDownload(key)
            } catch {
                guard let self else { return }
                self.finishDownload(key)
                if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                    toasts.show("Download of \(app.name) cancelled.", kind: .info)
                } else {
                    AppLog.error("Download of \(app.name) failed: \(error.localizedDescription)")
                    toasts.show("Couldn't download \(app.name): \(error.localizedDescription)", kind: .error)
                }
            }
        }
    }

    func cancelDownload(repoID: UUID, app: RepoApp) {
        let key = Self.downloadKey(repoID: repoID, app: app)
        downloadTasks[key]?.cancel()
    }

    private func finishDownload(_ key: String) {
        downloads[key] = nil
        downloadTasks[key] = nil
    }

    // MARK: Persistence

    private func load() -> [Repository] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Repository].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(repositories) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}
