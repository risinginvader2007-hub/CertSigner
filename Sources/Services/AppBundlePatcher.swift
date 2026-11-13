import Foundation

/// Edits an extracted .app before signing (Info.plist values, nested bundle IDs,
/// removing extensions / watch app). Plain Foundation, unit-testable.
enum AppBundlePatcher {
    enum PatchError: LocalizedError {
        case noPayload
        case noApp
        case unreadablePlist(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .noPayload: return "The IPA has no Payload folder."
            case .noApp: return "No .app found in Payload."
            case .unreadablePlist(let path): return "Couldn't read \(path)."
            case .writeFailed(let reason): return "Couldn't write Info.plist: \(reason)"
            }
        }
    }

    struct Summary {
        var bundleID: String
        var displayName: String
        var version: String
    }

    static let extensionFolders = ["PlugIns", "Extensions"]
    static let watchFolders = ["Watch", "WatchKit", "com.apple.WatchPlaceholder"]

    /// Gives the owner write permission on every file and folder under `root` that lacks it
    /// (keeping the other permission bits, e.g. executable). Symbolic links are left alone.
    /// Returns how many items were changed.
    @discardableResult
    static func makeWritable(_ root: URL) -> Int {
        let fm = FileManager.default
        var changed = 0
        func unlock(_ path: String) {
            guard let attributes = try? fm.attributesOfItem(atPath: path),
                  (attributes[.type] as? FileAttributeType) != .typeSymbolicLink,
                  let mode = (attributes[.posixPermissions] as? NSNumber)?.int16Value,
                  mode & 0o200 == 0 else { return }
            if (try? fm.setAttributes([.posixPermissions: NSNumber(value: mode | 0o200)], ofItemAtPath: path)) != nil {
                changed += 1
            }
        }
        unlock(root.path)
        if let items = fm.enumerator(atPath: root.path) {
            for case let relative as String in items {
                unlock(root.appendingPathComponent(relative).path)
            }
        }
        return changed
    }

    /// Finds Payload/<X>.app inside an extracted IPA folder.
    static func findApp(in extracted: URL) throws -> URL {
        let payload = extracted.appendingPathComponent("Payload", isDirectory: true)
        guard FileManager.default.fileExists(atPath: payload.path) else { throw PatchError.noPayload }
        let items = (try? FileManager.default.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)) ?? []
        guard let app = items.first(where: { $0.pathExtension == "app" }) else { throw PatchError.noApp }
        return app
    }

    /// New ID for a nested bundle when the main bundle ID changes.
    /// com.old.app.widget → com.new.app.widget; unrelated IDs keep their last component.
    static func nestedBundleID(_ original: String, oldMain: String, newMain: String) -> String {
        if original == oldMain { return newMain }
        if original.hasPrefix(oldMain + ".") {
            return newMain + original.dropFirst(oldMain.count)
        }
        let last = original.split(separator: ".").last.map(String.init) ?? original
        return newMain + "." + last
    }

    @discardableResult
    static func apply(_ options: SigningOptions, to appURL: URL, log: (String) -> Void) throws -> Summary {
        let fm = FileManager.default
        let infoURL = appURL.appendingPathComponent("Info.plist")
        var (info, format) = try readPlist(infoURL)

        if options.removeExtensions {
            for folder in extensionFolders {
                let url = appURL.appendingPathComponent(folder)
                if fm.fileExists(atPath: url.path) {
                    try? fm.removeItem(at: url)
                    log("Removed \(folder)/")
                }
            }
        }
        if options.removeWatchApp {
            for folder in watchFolders {
                let url = appURL.appendingPathComponent(folder)
                if fm.fileExists(atPath: url.path) {
                    try? fm.removeItem(at: url)
                    log("Removed \(folder)/")
                }
            }
        }

        if !options.trimmedDisplayName.isEmpty {
            info["CFBundleDisplayName"] = options.trimmedDisplayName
            log("Display name → \(options.trimmedDisplayName)")
        }
        if !options.trimmedVersion.isEmpty {
            info["CFBundleShortVersionString"] = options.trimmedVersion
            log("Version → \(options.trimmedVersion)")
        }

        let oldID = info["CFBundleIdentifier"] as? String ?? ""
        let newID = options.trimmedBundleID.isEmpty ? oldID : options.trimmedBundleID
        if newID != oldID {
            info["CFBundleIdentifier"] = newID
            log("Bundle ID → \(newID)")
            for nested in nestedBundles(in: appURL) {
                try rewriteNested(nested, oldMain: oldID, newMain: newID, log: log)
            }
        }

        try writePlist(info, format: format, to: infoURL)

        let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? appURL.deletingPathExtension().lastPathComponent
        return Summary(bundleID: newID, displayName: name, version: info["CFBundleShortVersionString"] as? String ?? "")
    }

    /// Bundle IDs of every nested .appex / .app (after patching).
    static func nestedBundleIDs(in appURL: URL) -> [String] {
        nestedBundles(in: appURL).compactMap { url in
            (try? readPlist(url.appendingPathComponent("Info.plist")))?.0["CFBundleIdentifier"] as? String
        }
    }

    /// Something zsign signs: the main app, extensions, nested apps, frameworks, dylibs.
    struct SignableItem {
        enum Kind: String { case app, appex, framework, dylib }
        let kind: Kind
        /// Path relative to Payload/ (e.g. "Husk.app/PlugIns/Share.appex").
        let path: String
        let bundleID: String?

        var description: String {
            "\(kind.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) \(path)" + (bundleID.map { "  [\($0)]" } ?? "")
        }
    }

    /// Every item in the bundle that gets signed, main app first, in path order.
    static func signableItems(in appURL: URL) -> [SignableItem] {
        func bundleID(_ url: URL) -> String? {
            (try? readPlist(url.appendingPathComponent("Info.plist")))?.0["CFBundleIdentifier"] as? String
        }
        let base = appURL.deletingLastPathComponent().path + "/"
        func relative(_ url: URL) -> String {
            url.path.hasPrefix(base) ? String(url.path.dropFirst(base.count)) : url.lastPathComponent
        }
        var items = [SignableItem(kind: .app, path: appURL.lastPathComponent, bundleID: bundleID(appURL))]
        guard let enumerator = FileManager.default.enumerator(at: appURL, includingPropertiesForKeys: nil) else { return items }
        var found: [SignableItem] = []
        for case let url as URL in enumerator {
            switch url.pathExtension {
            case "appex": found.append(SignableItem(kind: .appex, path: relative(url), bundleID: bundleID(url)))
            case "app": found.append(SignableItem(kind: .app, path: relative(url), bundleID: bundleID(url)))
            case "framework": found.append(SignableItem(kind: .framework, path: relative(url), bundleID: bundleID(url)))
            case "dylib": found.append(SignableItem(kind: .dylib, path: relative(url), bundleID: nil))
            default: break
            }
        }
        items += found.sorted { $0.path < $1.path }
        return items
    }

    // MARK: Private

    private static func nestedBundles(in appURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: appURL, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            let ext = url.pathExtension
            guard ext == "appex" || ext == "app" else { continue }
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Info.plist").path) {
                result.append(url)
            }
        }
        return result
    }

    private static func rewriteNested(_ bundle: URL, oldMain: String, newMain: String, log: (String) -> Void) throws {
        let url = bundle.appendingPathComponent("Info.plist")
        var (plist, format) = try readPlist(url)
        if let id = plist["CFBundleIdentifier"] as? String {
            let updated = nestedBundleID(id, oldMain: oldMain, newMain: newMain)
            plist["CFBundleIdentifier"] = updated
            log("  \(bundle.lastPathComponent): \(id) → \(updated)")
        }
        if let companion = plist["WKCompanionAppBundleIdentifier"] as? String, companion == oldMain {
            plist["WKCompanionAppBundleIdentifier"] = newMain
        }
        if var ext = plist["NSExtension"] as? [String: Any],
           var attributes = ext["NSExtensionAttributes"] as? [String: Any],
           let watchID = attributes["WKAppBundleIdentifier"] as? String {
            attributes["WKAppBundleIdentifier"] = nestedBundleID(watchID, oldMain: oldMain, newMain: newMain)
            ext["NSExtensionAttributes"] = attributes
            plist["NSExtension"] = ext
        }
        try writePlist(plist, format: format, to: url)
    }

    static func readPlist(_ url: URL) throws -> ([String: Any], PropertyListSerialization.PropertyListFormat) {
        guard let data = try? Data(contentsOf: url) else { throw PatchError.unreadablePlist(url.lastPathComponent) }
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: &format)) as? [String: Any] else {
            throw PatchError.unreadablePlist(url.lastPathComponent)
        }
        return (dict, format)
    }

    static func writePlist(_ dict: [String: Any], format: PropertyListSerialization.PropertyListFormat, to url: URL) throws {
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: format == .openStep ? .xml : format, options: 0)
            try data.write(to: url, options: .atomic)
        } catch {
            throw PatchError.writeFailed(error.localizedDescription)
        }
    }
}
