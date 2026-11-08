import Foundation

/// Stage 2: in-memory sample data so the UI can be exercised.
/// Stage 3 replaces this with real IPA import and on-disk persistence.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var apps: [LibraryApp] = []
    @Published private(set) var isLoading = true

    init() {
        Task { await initialLoad() }
    }

    private func initialLoad() async {
        try? await Task.sleep(nanoseconds: 900_000_000) // lets the shimmer placeholders show
        apps = LibraryStore.samples
        isLoading = false
    }

    func refresh() async {
        try? await Task.sleep(nanoseconds: 700_000_000)
        if apps.isEmpty { apps = LibraryStore.samples }
    }

    func delete(_ app: LibraryApp) {
        apps.removeAll { $0.id == app.id }
    }

    func filtered(search: String, sort: LibrarySort) -> [LibraryApp] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let matches = query.isEmpty ? apps : apps.filter {
            $0.name.lowercased().contains(query) || $0.bundleID.lowercased().contains(query)
        }
        switch sort {
        case .name: return matches.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .dateAdded: return matches.sorted { $0.dateAdded > $1.dateAdded }
        case .size: return matches.sorted { $0.size > $1.size }
        }
    }

    static let samples: [LibraryApp] = {
        let now = Date()
        func sample(_ name: String, _ bundle: String, _ version: String, _ mb: Double, _ daysAgo: Double, _ minOS: String) -> LibraryApp {
            LibraryApp(
                id: UUID(), name: name, bundleID: bundle, version: version, build: "1",
                size: Int64(mb * 1_048_576), dateAdded: now.addingTimeInterval(-daysAgo * 86_400),
                minimumOS: minOS, fileName: "\(name).ipa", iconFileName: nil, isSample: true
            )
        }
        return [
            sample("Nebula Player", "com.example.nebula", "3.2.1", 48.6, 1, "15.0"),
            sample("Pixel Forge", "com.example.pixelforge", "1.8", 112.3, 3, "16.0"),
            sample("Terminal Pro", "com.example.terminal", "5.0.4", 22.1, 6, "14.0"),
            sample("Orbit Notes", "com.example.orbit", "2.4", 31.9, 9, "16.0"),
            sample("Lumen Camera", "com.example.lumen", "4.1.2", 76.4, 14, "17.0"),
            sample("Wavelength", "com.example.wavelength", "1.0.3", 18.7, 21, "15.0")
        ]
    }()
}
