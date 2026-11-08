import Foundation
import UIKit

/// Signed IPAs live in Documents/Signed/<uuid>/ with an index.json.
@MainActor
final class SignedAppsStore: ObservableObject {
    @Published private(set) var apps: [SignedApp] = []
    @Published private(set) var icons: [UUID: UIImage] = [:]

    private let fm = FileManager.default
    private let root: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = documents.appendingPathComponent("Signed", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    func folder(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func ipaURL(for app: SignedApp) -> URL { folder(for: app.id).appendingPathComponent(app.fileName) }
    private var indexURL: URL { root.appendingPathComponent("index.json") }

    func load() {
        guard let data = try? Data(contentsOf: indexURL) else { apps = []; return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = ((try? decoder.decode([SignedApp].self, from: data)) ?? [])
            .filter { fm.fileExists(atPath: ipaURL(for: $0).path) }
        var loaded: [UUID: UIImage] = [:]
        for app in records {
            if let icon = app.iconFileName,
               let image = UIImage(contentsOfFile: folder(for: app.id).appendingPathComponent(icon).path) {
                loaded[app.id] = image
            }
        }
        apps = records.sorted { $0.signedAt > $1.signedAt }
        icons = loaded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(apps) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    /// Creates an empty folder for a signing job and returns its id + folder.
    func reserve() -> (UUID, URL) {
        let id = UUID()
        let folder = folder(for: id)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        return (id, folder)
    }

    func discard(_ id: UUID) {
        try? fm.removeItem(at: folder(for: id))
    }

    /// Registers a finished signed IPA. Copies the icon from `iconSource` if given.
    func add(_ app: SignedApp, iconSource: URL?) {
        var record = app
        if let iconSource, fm.fileExists(atPath: iconSource.path) {
            let destination = folder(for: app.id).appendingPathComponent("icon.png")
            try? fm.removeItem(at: destination)
            if (try? fm.copyItem(at: iconSource, to: destination)) != nil {
                record.iconFileName = "icon.png"
                icons[app.id] = UIImage(contentsOfFile: destination.path)
            }
        }
        apps.insert(record, at: 0)
        save()
    }

    func delete(_ app: SignedApp) {
        try? fm.removeItem(at: folder(for: app.id))
        apps.removeAll { $0.id == app.id }
        icons[app.id] = nil
        save()
    }
}
