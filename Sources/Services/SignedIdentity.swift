import Foundation

/// Reads the entitlements embedded in a signed Mach-O (the code signature's entitlements blob), so
/// the signing log shows what each bundle was really signed as, not what we meant to sign.
enum SignedIdentity {
    /// One line per app / extension bundle, main app first, e.g.
    /// "Octave.app [streaming.octave.dev]: application-identifier A2V52T4RD8.app.x (differs from the
    /// bundle ID: shared identity), team A2V52T4RD8, app groups: none, keychain: A2V52T4RD8.*,
    /// get-task-allow: true, 9 entitlements".
    static func summaryLines(appURL: URL) -> [String] {
        let base = appURL.deletingLastPathComponent().path + "/"
        return bundles(in: appURL).map { bundle in
            let name = bundle.path.hasPrefix(base) ? String(bundle.path.dropFirst(base.count)) : bundle.lastPathComponent
            let info = (try? AppBundlePatcher.readPlist(bundle.appendingPathComponent("Info.plist")))?.0 ?? [:]
            let bundleID = info["CFBundleIdentifier"] as? String ?? "?"
            guard let executable = info["CFBundleExecutable"] as? String else {
                return "\(name) [\(bundleID)]: no CFBundleExecutable"
            }
            guard let entitlements = entitlements(ofExecutable: bundle.appendingPathComponent(executable)) else {
                return "\(name) [\(bundleID)]: no entitlements in the signature"
            }
            return "\(name) [\(bundleID)]: " + summary(entitlements, bundleID: bundleID)
        }
    }

    /// The one-line summary of a bundle's signed entitlements.
    static func summary(_ entitlements: [String: Any], bundleID: String) -> String {
        let appID = entitlements["application-identifier"] as? String ?? "(none)"
        let team = entitlements["com.apple.developer.team-identifier"] as? String ?? "(none)"
        func list(_ key: String) -> String {
            let values = entitlements[key] as? [String] ?? []
            return values.isEmpty ? "none" : values.joined(separator: ", ")
        }
        let getTaskAllow = (entitlements["get-task-allow"] as? Bool).map { $0 ? "true" : "false" } ?? "absent"
        var appIDText = "application-identifier \(appID)"
        if appIDMismatch(appID: appID, bundleID: bundleID) {
            appIDText += " (differs from the bundle ID: shared identity)"
        }
        return "\(appIDText), team \(team), app groups: \(list("com.apple.security.application-groups")), "
            + "keychain: \(list("keychain-access-groups")), get-task-allow: \(getTaskAllow), \(entitlements.count) entitlements"
    }

    /// True when the signed App ID doesn't name this bundle ("TEAM.bundle.id"); wildcards don't count.
    static func appIDMismatch(appID: String, bundleID: String) -> Bool {
        guard let dot = appID.firstIndex(of: ".") else { return false }
        let suffix = String(appID[appID.index(after: dot)...])
        if suffix == "*" || suffix.hasSuffix(".*") { return false }
        return suffix != bundleID
    }

    /// The main app and every nested .appex / .app.
    static func bundles(in appURL: URL) -> [URL] {
        var nested: [URL] = []
        if let enumerator = FileManager.default.enumerator(at: appURL, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.pathExtension == "appex" || url.pathExtension == "app" {
                if FileManager.default.fileExists(atPath: url.appendingPathComponent("Info.plist").path) {
                    nested.append(url)
                }
            }
        }
        return [appURL] + nested.sorted { $0.path < $1.path }
    }

    // MARK: Mach-O

    /// The entitlements plist from the executable's code signature (first slice of a fat binary).
    static func entitlements(ofExecutable url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return entitlements(inMachO: data)
    }

    static func entitlements(inMachO data: Data) -> [String: Any]? {
        guard let magic = data.u32BE(at: 0) else { return nil }
        var slice = 0
        if magic == 0xCAFE_BABE || magic == 0xCAFE_BABF { // fat: use the first architecture
            guard let count = data.u32BE(at: 4), count > 0 else { return nil }
            let entryOffset = 8
            slice = Int(magic == 0xCAFE_BABE ? data.u32BE(at: entryOffset + 8) ?? 0
                                             : UInt32(truncatingIfNeeded: data.u64BE(at: entryOffset + 8) ?? 0))
        }
        guard let header = data.u32LE(at: slice) else { return nil }
        let headerSize: Int
        switch header {
        case 0xFEED_FACF: headerSize = 32 // MH_MAGIC_64
        case 0xFEED_FACE: headerSize = 28 // MH_MAGIC
        default: return nil
        }
        guard let commands = data.u32LE(at: slice + 16) else { return nil }
        var offset = slice + headerSize
        for _ in 0..<commands {
            guard let cmd = data.u32LE(at: offset), let size = data.u32LE(at: offset + 4), size >= 8 else { return nil }
            if cmd == 0x1D { // LC_CODE_SIGNATURE
                guard let dataOffset = data.u32LE(at: offset + 8) else { return nil }
                return entitlements(inSuperBlobAt: slice + Int(dataOffset), data: data)
            }
            offset += Int(size)
        }
        return nil
    }

    private static func entitlements(inSuperBlobAt start: Int, data: Data) -> [String: Any]? {
        guard data.u32BE(at: start) == 0xFADE_0CC0, let count = data.u32BE(at: start + 8) else { return nil }
        for index in 0..<Int(count) {
            guard let blobOffset = data.u32BE(at: start + 12 + index * 8 + 4) else { return nil }
            let blob = start + Int(blobOffset)
            guard data.u32BE(at: blob) == 0xFADE_7171, let length = data.u32BE(at: blob + 4),
                  length > 8, blob + Int(length) <= data.count else { continue }
            let plistData = data.subdata(in: (data.startIndex + blob + 8)..<(data.startIndex + blob + Int(length)))
            return (try? PropertyListSerialization.propertyList(from: plistData, format: nil)) as? [String: Any]
        }
        return nil
    }
}

private extension Data {
    func bytes(at offset: Int, count: Int) -> [UInt8]? {
        guard offset >= 0, offset + count <= self.count else { return nil }
        let start = startIndex + offset
        return [UInt8](self[start..<(start + count)])
    }

    func u32BE(at offset: Int) -> UInt32? {
        guard let raw = self.bytes(at: offset, count: 4) else { return nil }
        var value: UInt32 = 0
        for byte in raw { value = value << 8 | UInt32(byte) }
        return value
    }

    func u32LE(at offset: Int) -> UInt32? {
        guard let raw = self.bytes(at: offset, count: 4) else { return nil }
        var value: UInt32 = 0
        for byte in raw.reversed() { value = value << 8 | UInt32(byte) }
        return value
    }

    func u64BE(at offset: Int) -> UInt64? {
        guard let raw = self.bytes(at: offset, count: 8) else { return nil }
        var value: UInt64 = 0
        for byte in raw { value = value << 8 | UInt64(byte) }
        return value
    }
}
