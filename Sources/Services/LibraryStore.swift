import Foundation
import UIKit

struct TransferState: Equatable {
    var title: String
    var progress: Double? // nil = indeterminate
}

/// IPAs live in Documents/Library/<uuid>/ (app.ipa + icon.png) with an index.json.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var apps: [LibraryApp] = []
    @Published private(set) var icons: [UUID: UIImage] = [:]
    @Published private(set) var isLoading = true
    @Published private(set) var transfer: TransferState?

    private let fm = FileManager.default
    private let root: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = documents.appendingPathComponent("Library", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        Task { await load() }
    }

    // MARK: Paths

    func folder(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func ipaURL(for app: LibraryApp) -> URL { folder(for: app.id).appendingPathComponent(app.fileName) }
    func iconURL(for app: LibraryApp) -> URL? {
        app.iconFileName.map { folder(for: app.id).appendingPathComponent($0) }
    }
    private var indexURL: URL { root.appendingPathComponent("index.json") }

    // MARK: Loading

    func load() async {
        let records = loadIndex().filter { fm.fileExists(atPath: ipaURL(for: $0).path) }
        var loadedIcons: [UUID: UIImage] = [:]
        for app in records {
            if let url = iconURL(for: app), let image = UIImage(contentsOfFile: url.path) {
                loadedIcons[app.id] = image
            }
        }
        apps = records
        icons = loadedIcons
        isLoading = false
    }

    func refresh() async {
        await load()
    }

    private func loadIndex() -> [LibraryApp] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([LibraryApp].self, from: data)) ?? []
    }

    private func saveIndex() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(apps) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    // MARK: Import

    /// Imports an IPA. `moveSource` = true moves the file instead of copying (for temp files).
    @discardableResult
    func importIPA(from source: URL, originalName: String? = nil, moveSource: Bool) async throws -> LibraryApp {
        let displayName = originalName ?? source.lastPathComponent
        transfer = TransferState(title: "Importing \(displayName)…", progress: nil)
        defer { transfer = nil }

        let id = UUID()
        let folder = folder(for: id)
        let fileName = "app.ipa"

        let prepared: (LibraryApp, UIImage?) = try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(fileName)
            do {
                if moveSource {
                    try fm.moveItem(at: source, to: destination)
                } else {
                    let scoped = source.startAccessingSecurityScopedResource()
                    defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                    try fm.copyItem(at: source, to: destination)
                }
                let meta = try IPAInspector.inspect(destination)
                let size = (try? fm.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0

                // Normalise the (often CgBI-crushed) icon into a standard PNG.
                var iconFileName: String?
                var image: UIImage?
                if let data = meta.iconData, let decoded = UIImage(data: data),
                   let png = LibraryStore.downsampled(decoded, to: 180).pngData() {
                    try? png.write(to: folder.appendingPathComponent("icon.png"))
                    iconFileName = "icon.png"
                    image = UIImage(data: png)
                }

                let app = LibraryApp(
                    id: id, name: meta.name, bundleID: meta.bundleID, version: meta.version, build: meta.build,
                    size: size, dateAdded: Date(), minimumOS: meta.minimumOS, fileName: fileName,
                    iconFileName: iconFileName, originalFileName: displayName,
                    extensionBundleIDs: meta.extensionBundleIDs, hasWatchApp: meta.hasWatchApp
                )
                return (app, image)
            } catch {
                try? fm.removeItem(at: folder)
                throw error
            }
        }.value

        let (app, image) = prepared
        apps.append(app)
        if let image { icons[app.id] = image }
        saveIndex()
        return app
    }

    /// Shrinks large icons so long lists stay light on memory.
    nonisolated static func downsampled(_ image: UIImage, to side: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > side || size.height > side, size.width > 0, size.height > 0 else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    // MARK: Mutations

    func delete(_ app: LibraryApp) {
        try? fm.removeItem(at: folder(for: app.id))
        apps.removeAll { $0.id == app.id }
        icons[app.id] = nil
        saveIndex()
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
}
