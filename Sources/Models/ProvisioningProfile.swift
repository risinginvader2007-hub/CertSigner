import Foundation

enum ProfileType: String {
    case development = "Development"
    case adHoc = "Ad Hoc"
    case enterprise = "Enterprise"
    case appStore = "App Store"
}

struct KeyValue: Identifiable, Hashable {
    let key: String
    let value: String
    var id: String { key }
}

/// Parsed contents of a .mobileprovision file. Pure data, no UI.
struct ProvisioningProfile {
    var name: String
    var uuid: String
    var teamID: String
    var teamName: String
    var appIDName: String
    /// e.g. "ABCDE12345.com.example.*"
    var applicationIdentifier: String
    var creationDate: Date?
    var expirationDate: Date?
    var devices: [String]
    var provisionsAllDevices: Bool
    var entitlements: [String: Any]
    /// DER-encoded certificates this profile is valid for.
    var developerCertificates: [Data]
    var platforms: [String]

    /// Bundle ID part of the application identifier (team prefix removed).
    var bundleIDPattern: String {
        let prefix = teamID + "."
        if applicationIdentifier.hasPrefix(prefix) {
            return String(applicationIdentifier.dropFirst(prefix.count))
        }
        if let dot = applicationIdentifier.firstIndex(of: ".") {
            return String(applicationIdentifier[applicationIdentifier.index(after: dot)...])
        }
        return applicationIdentifier
    }

    var isWildcard: Bool { bundleIDPattern.hasSuffix("*") }

    var getTaskAllow: Bool { entitlements["get-task-allow"] as? Bool ?? false }

    var type: ProfileType {
        if provisionsAllDevices { return .enterprise }
        if getTaskAllow { return .development }
        if !devices.isEmpty { return .adHoc }
        return .appStore
    }

    func isExpired(now: Date = Date()) -> Bool {
        guard let expirationDate else { return false }
        return expirationDate < now
    }

    /// nil when the UDID is empty; true for enterprise profiles.
    func containsDevice(_ udid: String) -> Bool? {
        let wanted = ProvisioningProfile.normalize(udid)
        guard !wanted.isEmpty else { return nil }
        if provisionsAllDevices { return true }
        return devices.contains { ProvisioningProfile.normalize($0) == wanted }
    }

    func containsCertificate(_ der: Data) -> Bool {
        developerCertificates.contains(der)
    }

    var sortedEntitlements: [KeyValue] {
        entitlements.keys.sorted().map { key in
            KeyValue(key: key, value: ProfileParser.describe(entitlements[key] ?? ""))
        }
    }

    static func normalize(_ udid: String) -> String {
        udid.uppercased().filter { $0.isHexDigit }
    }
}

enum ProfileParser {
    enum ParseError: LocalizedError {
        case unreadable
        case noPlist
        case invalidPlist

        var errorDescription: String? {
            switch self {
            case .unreadable: return "The provisioning profile could not be read."
            case .noPlist: return "This file doesn't look like a .mobileprovision."
            case .invalidPlist: return "The provisioning profile is damaged."
            }
        }
    }

    static func parse(url: URL) throws -> ProvisioningProfile {
        guard let data = try? Data(contentsOf: url) else { throw ParseError.unreadable }
        return try parse(data: data)
    }

    /// A .mobileprovision is a CMS-signed blob with an XML plist inside.
    /// iOS has no public CMS decoder, so we locate the plist bytes directly.
    static func extractPlist(from data: Data) -> Data? {
        let start = data.range(of: Data("<?xml".utf8)) ?? data.range(of: Data("<plist".utf8))
        guard let start,
              let end = data.range(of: Data("</plist>".utf8), options: .backwards),
              start.lowerBound < end.upperBound else { return nil }
        return data.subdata(in: start.lowerBound..<end.upperBound)
    }

    static func parse(data: Data) throws -> ProvisioningProfile {
        guard let plistData = extractPlist(from: data) else { throw ParseError.noPlist }
        guard let plist = (try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)) as? [String: Any]
        else { throw ParseError.invalidPlist }

        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        return ProvisioningProfile(
            name: plist["Name"] as? String ?? "Unnamed profile",
            uuid: plist["UUID"] as? String ?? "",
            teamID: (plist["TeamIdentifier"] as? [String])?.first ?? (entitlements["com.apple.developer.team-identifier"] as? String ?? "Unknown"),
            teamName: plist["TeamName"] as? String ?? "Unknown team",
            appIDName: plist["AppIDName"] as? String ?? "",
            applicationIdentifier: entitlements["application-identifier"] as? String ?? "",
            creationDate: plist["CreationDate"] as? Date,
            expirationDate: plist["ExpirationDate"] as? Date,
            devices: plist["ProvisionedDevices"] as? [String] ?? [],
            provisionsAllDevices: plist["ProvisionsAllDevices"] as? Bool ?? false,
            entitlements: entitlements,
            developerCertificates: plist["DeveloperCertificates"] as? [Data] ?? [],
            platforms: plist["Platform"] as? [String] ?? []
        )
    }

    /// Short human-readable description of a plist value.
    static func describe(_ value: Any) -> String {
        switch value {
        case let bool as Bool:
            return bool ? "true" : "false"
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let array as [Any]:
            if array.isEmpty { return "[]" }
            return array.map { describe($0) }.joined(separator: ", ")
        case let dict as [String: Any]:
            return "{\(dict.count) keys}"
        case let date as Date:
            return date.formatted(date: .abbreviated, time: .shortened)
        case let data as Data:
            return "\(data.count) bytes"
        default:
            return String(describing: value)
        }
    }
}
