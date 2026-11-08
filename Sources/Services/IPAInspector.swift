import Foundation
import ZIPFoundation

struct IPAMetadata {
    var name: String
    var bundleID: String
    var version: String
    var build: String
    var minimumOS: String?
    var extensionBundleIDs: [String]
    var hasWatchApp: Bool
    /// Raw icon PNG (may be Apple's CgBI format; UIImage can decode it).
    var iconData: Data?
}

/// Reads metadata straight out of an .ipa without extracting it. No UI dependency.
enum IPAInspector {
    enum InspectError: LocalizedError {
        case notAnArchive
        case noApp
        case badInfoPlist

        var errorDescription: String? {
            switch self {
            case .notAnArchive: return "This file isn't a valid IPA (not a zip archive)."
            case .noApp: return "No Payload/*.app found inside this IPA."
            case .badInfoPlist: return "The app's Info.plist couldn't be read."
            }
        }
    }

    static func inspect(_ url: URL) throws -> IPAMetadata {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read, pathEncoding: nil)
        } catch {
            throw InspectError.notAnArchive
        }

        var entries: [String: Entry] = [:]
        for entry in archive {
            entries[entry.path] = entry
        }

        guard let infoPath = entries.keys.sorted().first(where: isMainInfoPlist) else { throw InspectError.noApp }
        let root = String(infoPath.dropLast("Info.plist".count)) // "Payload/Name.app/"
        guard let info = plist(at: infoPath, in: archive, entries: entries) else { throw InspectError.badInfoPlist }

        let bundleID = info["CFBundleIdentifier"] as? String ?? ""
        let appFolderName = String(root.dropFirst("Payload/".count).dropLast(5)) // strip ".app/"
        let name = (info["CFBundleDisplayName"] as? String).nonEmpty
            ?? (info["CFBundleName"] as? String).nonEmpty
            ?? appFolderName

        var extensionIDs: [String] = []
        for path in entries.keys.sorted() where isExtensionInfoPlist(path, root: root) {
            if let id = plist(at: path, in: archive, entries: entries)?["CFBundleIdentifier"] as? String {
                extensionIDs.append(id)
            }
        }

        let hasWatch = entries.keys.contains { $0.hasPrefix(root + "Watch/") || $0.hasPrefix(root + "WatchKit/") }

        return IPAMetadata(
            name: name,
            bundleID: bundleID,
            version: info["CFBundleShortVersionString"] as? String ?? "1.0",
            build: info["CFBundleVersion"] as? String ?? "1",
            minimumOS: info["MinimumOSVersion"] as? String,
            extensionBundleIDs: extensionIDs,
            hasWatchApp: hasWatch,
            iconData: iconData(info: info, root: root, archive: archive, entries: entries)
        )
    }

    // MARK: Helpers

    /// "Payload/<X>.app/Info.plist"
    static func isMainInfoPlist(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0] == "Payload" && parts[1].hasSuffix(".app") && parts[2] == "Info.plist"
    }

    /// "<root>PlugIns/<Y>.appex/Info.plist" or "<root>Extensions/<Y>.appex/Info.plist"
    static func isExtensionInfoPlist(_ path: String, root: String) -> Bool {
        guard path.hasPrefix(root) else { return false }
        let rest = path.dropFirst(root.count).split(separator: "/", omittingEmptySubsequences: false)
        return rest.count == 3 && (rest[0] == "PlugIns" || rest[0] == "Extensions")
            && rest[1].hasSuffix(".appex") && rest[2] == "Info.plist"
    }

    private static func read(_ entry: Entry, in archive: Archive) -> Data? {
        var data = Data()
        do {
            _ = try archive.extract(entry, skipCRC32: true) { chunk in data.append(chunk) }
        } catch {
            return nil
        }
        return data
    }

    private static func plist(at path: String, in archive: Archive, entries: [String: Entry]) -> [String: Any]? {
        guard let entry = entries[path], let data = read(entry, in: archive) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    /// Icon base names from CFBundleIcons / CFBundleIconFiles / CFBundleIconName.
    static func iconNames(info: [String: Any]) -> [String] {
        var names: [String] = []
        for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
            if let icons = info[key] as? [String: Any],
               let primary = icons["CFBundlePrimaryIcon"] as? [String: Any] {
                names += primary["CFBundleIconFiles"] as? [String] ?? []
                if let name = primary["CFBundleIconName"] as? String { names.append(name) }
            }
        }
        names += info["CFBundleIconFiles"] as? [String] ?? []
        if let file = info["CFBundleIconFile"] as? String { names.append(file) }
        return names.map { $0.hasSuffix(".png") ? String($0.dropLast(4)) : $0 }
    }

    private static func iconData(info: [String: Any], root: String, archive: Archive, entries: [String: Entry]) -> Data? {
        // PNGs directly inside the .app folder.
        let pngs = entries.filter { path, entry in
            guard entry.type == .file, path.hasPrefix(root), path.lowercased().hasSuffix(".png") else { return false }
            return !path.dropFirst(root.count).contains("/")
        }
        func fileName(_ path: String) -> String { String(path.dropFirst(root.count)) }

        let names = iconNames(info: info)
        var candidates = pngs.filter { path, _ in names.contains { fileName(path).hasPrefix($0) } }
        if candidates.isEmpty {
            candidates = pngs.filter { path, _ in
                let lower = fileName(path).lowercased()
                return lower.hasPrefix("appicon") || lower.hasPrefix("icon")
            }
        }
        guard let best = candidates.max(by: { Int64($0.value.uncompressedSize) < Int64($1.value.uncompressedSize) }) else { return nil }
        return read(best.value, in: archive)
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }
}
