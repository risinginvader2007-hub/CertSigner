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
        // Deletions whose Undo window was still open when the app quit: finish them now.
        for id in Self.pendingDeleteIDs { try? fm.removeItem(at: folder(for: id)) }
        Self.pendingDeleteIDs = []
        load()
    }

    /// Signed apps that are expiring soon or expired.
    var attentionCount: Int {
        apps.filter { $0.needsAttention() }.count
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

    // MARK: Delete with Undo

    /// An app taken out of the list whose files are kept until the Undo window closes.
    struct PendingDeletion {
        let app: SignedApp
        let index: Int
        let icon: UIImage?
    }

    /// Removes the app from the list and index right away (so a stale card can never come back),
    /// keeping its signed files until `finalizeDeletion` (or `restore` on Undo).
    @discardableResult
    func removeForUndo(_ app: SignedApp) -> PendingDeletion? {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return nil }
        let pending = PendingDeletion(app: apps[index], index: index, icon: icons[app.id])
        apps.remove(at: index)
        icons[app.id] = nil
        save()
        Self.pendingDeleteIDs.append(app.id)
        return pending
    }

    /// Undo: put the app back where it was.
    func restore(_ pending: PendingDeletion) {
        guard !apps.contains(where: { $0.id == pending.app.id }),
              fm.fileExists(atPath: ipaURL(for: pending.app).path) else { return }
        apps.insert(pending.app, at: min(pending.index, apps.count))
        icons[pending.app.id] = pending.icon
        save()
        Self.pendingDeleteIDs.removeAll { $0 == pending.app.id }
    }

    /// The Undo window closed: delete the files for good (same removal as `delete`).
    func finalizeDeletion(_ pending: PendingDeletion) {
        Self.pendingDeleteIDs.removeAll { $0 == pending.app.id }
        guard !apps.contains(where: { $0.id == pending.app.id }) else { return }
        try? fm.removeItem(at: folder(for: pending.app.id))
    }

    private static let pendingKey = "signed.pendingDeletes"
    private static var pendingDeleteIDs: [UUID] {
        get { (UserDefaults.standard.stringArray(forKey: pendingKey) ?? []).compactMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue.map(\.uuidString), forKey: pendingKey) }
    }
}
