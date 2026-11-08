import Foundation
import SwiftUI

/// Live state of an IPA being downloaded from a source.
struct RepoDownload: Equatable {
    var received: Int64 = 0
    var expected: Int64?
    /// True once the file is on disk and being imported into the library.
    var importing = false

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
    private var lastAutoRefresh: Date?
    private let indexURL: URL

    init() {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sources", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        indexURL = folder.appendingPathComponent("sources.json")
        repositories = load()
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

    func refresh(_ id: UUID) async {
        guard let repo = repository(id), !refreshing.contains(id) else { return }
        refreshing.insert(id)
        defer { refreshing.remove(id) }
        do {
            let parsed = try await fetch(repo.url)
            guard let index = repositories.firstIndex(where: { $0.id == id }) else { return }
            var updated = repositories[index]
            updated.name = parsed.name
            updated.subtitle = parsed.subtitle
            updated.iconURL = parsed.iconURL
            updated.website = parsed.website
            if !parsed.apps.isEmpty { updated.apps = parsed.apps }
            updated.lastUpdated = Date()
            updated.lastError = parsed.apps.isEmpty ? RepositoryError.noApps.localizedDescription : nil
            repositories[index] = updated
        } catch {
            if let index = repositories.firstIndex(where: { $0.id == id }) {
                repositories[index].lastError = error.localizedDescription
            }
            AppLog.error("Refreshing source \(repo.name) failed: \(error.localizedDescription)")
        }
        save()
    }

    func refreshAll() async {
        lastAutoRefresh = Date()
        await withTaskGroup(of: Void.self) { group in
            for repo in repositories {
                group.addTask { await self.refresh(repo.id) }
            }
        }
    }

    /// Refreshes on first appearance and then at most every 30 minutes.
    func refreshIfStale() async {
        if let last = lastAutoRefresh, Date().timeIntervalSince(last) < 30 * 60 { return }
        await refreshAll()
    }

    private func fetch(_ url: URL) async throws -> RepositoryParser.Parsed {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RepositoryError.http(http.statusCode)
        }
        let base = response.url ?? url
        return try await Task.detached(priority: .userInitiated) {
            try RepositoryParser.parse(data, sourceURL: base)
        }.value
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

        downloads[key] = RepoDownload(received: 0, expected: build.size)
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
