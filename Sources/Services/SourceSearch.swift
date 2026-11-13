import Foundation
import SwiftUI

/// Search over source apps for one list (a source, All Apps, the Search tab): the query is
/// debounced (250 ms while typing), filtering and sorting run off the main thread, and the
/// results never repeat an entry (one row per app per source).
@MainActor
final class SourceSearch: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { schedule(debounce: true) } }
    }
    @Published private(set) var results: [SourceEntry] = []
    /// True until the first results for the current entries are in.
    @Published private(set) var isLoading = true

    /// Sort by app name (All Apps, Search) or keep the source's own order (one source).
    let sortByName: Bool
    /// An empty query shows nothing (the Search tab) instead of everything.
    let emptyQueryShowsAll: Bool

    private var entries: [SourceEntry] = []
    private var task: Task<Void, Never>?

    static let debounceNanoseconds: UInt64 = 250_000_000

    init(sortByName: Bool, emptyQueryShowsAll: Bool = true) {
        self.sortByName = sortByName
        self.emptyQueryShowsAll = emptyQueryShowsAll
    }

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// New data (a refresh finished, a source was added or removed): searched again right away.
    func update(_ entries: [SourceEntry]) {
        self.entries = entries
        schedule(debounce: false)
    }

    private func schedule(debounce: Bool) {
        task?.cancel()
        let query = trimmedQuery
        let entries = self.entries
        let sortByName = self.sortByName
        let showAll = emptyQueryShowsAll
        task = Task { [weak self] in
            if debounce && !query.isEmpty {
                try? await Task.sleep(nanoseconds: Self.debounceNanoseconds)
                guard !Task.isCancelled else { return }
            }
            let found = await Task.detached(priority: .userInitiated) {
                SourceSearch.filter(entries, query: query, sortByName: sortByName, emptyQueryShowsAll: showAll)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.results = found
            self.isLoading = false
        }
    }

    /// Matches name, bundle ID, developer or source name; drops any repeated entry id; sorts.
    nonisolated static func filter(_ entries: [SourceEntry], query: String, sortByName: Bool,
                                   emptyQueryShowsAll: Bool = true) -> [SourceEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty && !emptyQueryShowsAll { return [] }
        var seen = Set<String>()
        var found = entries.filter { entry in
            guard seen.insert(entry.id).inserted else { return false }
            guard !q.isEmpty else { return true }
            return entry.app.name.lowercased().contains(q) || entry.app.bundleID.lowercased().contains(q)
                || (entry.app.developer?.lowercased().contains(q) ?? false)
                || (sortByName && entry.repo.name.lowercased().contains(q))   // across sources only
        }
        if sortByName {
            found.sort {
                let order = $0.app.name.localizedCaseInsensitiveCompare($1.app.name)
                return order == .orderedSame ? $0.repo.name < $1.repo.name : order == .orderedAscending
            }
        }
        return found
    }
}
