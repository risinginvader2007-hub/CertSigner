import Foundation

/// One downloadable build of a source app.
struct RepoVersion: Codable, Hashable, Identifiable {
    var version: String
    var buildVersion: String?
    var date: Date?
    var downloadURL: URL
    var size: Int64?
    var minOSVersion: String?
    var notes: String?

    var id: String { "\(version)|\(buildVersion ?? "")|\(downloadURL.absoluteString)" }
}

/// An app listed by a source (AltStore-style "apps" entry).
struct RepoApp: Codable, Hashable, Identifiable {
    var name: String
    var bundleID: String
    var developer: String?
    var subtitle: String?
    var appDescription: String?
    var iconURL: URL?
    var category: String?
    var screenshotURLs: [URL]
    /// Newest first, never empty.
    var versions: [RepoVersion]

    /// Unique within one source.
    var id: String { "\(bundleID)|\(name)" }
    var latest: RepoVersion { versions[0] }
}

/// A source the user added: its URL plus the last successfully parsed contents.
struct Repository: Codable, Hashable, Identifiable {
    var id: UUID
    var url: URL
    var name: String
    var subtitle: String?
    var iconURL: URL?
    var website: URL?
    var apps: [RepoApp]
    var lastUpdated: Date?
    /// Set when the last refresh failed (the previous app list is kept).
    var lastError: String?
    var dateAdded: Date
    /// HTTP validators from the last good response, sent back as If-None-Match / If-Modified-Since.
    var etag: String? = nil
    var lastModified: String? = nil
}

enum RepositoryError: LocalizedError {
    case invalidURL
    case insecureURL
    case http(Int)
    case notJSON
    case noApps
    case duplicate(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "That doesn't look like a source URL."
        case .insecureURL: return "iOS blocks plain http:// links. Use an https:// source URL."
        case .http(let code): return "The server answered with HTTP \(code)."
        case .notJSON: return "The URL didn't return a source file (JSON)."
        case .noApps: return "The source has no installable apps."
        case .duplicate(let name): return "\(name) is already in your sources."
        }
    }
}

/// Reads source JSON. Tolerates the common layouts:
/// - AltStore / SideStore / Feather: `{ name, iconURL, apps: [{ ..., versions: [...] }] }`
/// - Legacy AltStore / ESign: apps carry `version`, `versionDate`, `downloadURL`, `size` directly
/// - Scarlet-style: `{ META: { repoName, repoIcon }, <Category>: [apps…] }`
/// - A bare top-level array of apps
enum RepositoryParser {
    struct Parsed {
        var name: String
        var subtitle: String?
        var iconURL: URL?
        var website: URL?
        var apps: [RepoApp]
    }

    static func parse(_ data: Data, sourceURL: URL) throws -> Parsed {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw RepositoryError.notJSON
        }
        let fallbackName = sourceURL.host ?? "Source"

        var parsed = Parsed(name: fallbackName, apps: [])
        if let list = root as? [Any] {
            parsed.apps = list.compactMap { ($0 as? [String: Any]).flatMap { app($0, category: nil, base: sourceURL) } }
        } else if let dict = root as? [String: Any] {
            let meta = dict["META"] as? [String: Any] ?? dict["meta"] as? [String: Any] ?? [:]
            parsed.name = string(dict["name"]) ?? string(meta["repoName"]) ?? string(meta["name"]) ?? fallbackName
            parsed.subtitle = string(dict["subtitle"]) ?? string(dict["description"]) ?? string(meta["repoDescription"])
            parsed.iconURL = url(dict["iconURL"] ?? dict["icon"] ?? meta["repoIcon"], base: sourceURL)
            parsed.website = url(dict["website"] ?? meta["website"], base: sourceURL)

            if let apps = dict["apps"] as? [Any] {
                parsed.apps = apps.compactMap { ($0 as? [String: Any]).flatMap { app($0, category: nil, base: sourceURL) } }
            } else {
                // Scarlet-style: every other top-level array is a category of apps.
                for key in dict.keys.sorted() where key != "META" && key != "meta" {
                    guard let list = dict[key] as? [Any] else { continue }
                    parsed.apps += list.compactMap { ($0 as? [String: Any]).flatMap { app($0, category: key, base: sourceURL) } }
                }
            }
        } else {
            throw RepositoryError.notJSON
        }
        return parsed
    }

    private static func app(_ d: [String: Any], category: String?, base: URL) -> RepoApp? {
        guard let name = string(d["name"]) else { return nil }

        var versions: [RepoVersion] = []
        if let list = d["versions"] as? [Any] {
            for case let v as [String: Any] in list {
                if let parsedVersion = version(v, base: base) { versions.append(parsedVersion) }
            }
        }
        if versions.isEmpty, let legacy = version(d, base: base) {
            versions = [legacy]
        }
        guard !versions.isEmpty else { return nil }

        var screenshots: [URL] = []
        for key in ["screenshots", "screenshotURLs"] where screenshots.isEmpty {
            if let list = d[key] as? [Any] {
                screenshots += list.compactMap { (item: Any) -> URL? in
                    if let dict = item as? [String: Any] { return url(dict["imageURL"] ?? dict["url"], base: base) }
                    return url(item, base: base)
                }
            } else if let dict = d[key] as? [String: Any], let iphone = dict["iphone"] as? [Any] {
                screenshots += iphone.compactMap { (item: Any) -> URL? in
                    if let dict = item as? [String: Any] { return url(dict["imageURL"], base: base) }
                    return url(item, base: base)
                }
            }
        }

        return RepoApp(
            name: name,
            bundleID: string(d["bundleIdentifier"]) ?? string(d["bundleID"]) ?? string(d["bundleId"]) ?? "",
            developer: string(d["developerName"]) ?? string(d["developer"]) ?? string(d["dev"]),
            subtitle: string(d["subtitle"]),
            appDescription: string(d["localizedDescription"]) ?? string(d["description"]),
            iconURL: url(d["iconURL"] ?? d["icon"], base: base),
            category: string(d["category"]) ?? category,
            screenshotURLs: screenshots,
            versions: versions
        )
    }

    private static func version(_ d: [String: Any], base: URL) -> RepoVersion? {
        guard let download = url(d["downloadURL"] ?? d["down"] ?? d["download"] ?? d["url"], base: base) else { return nil }
        return RepoVersion(
            version: string(d["version"]) ?? "–",
            buildVersion: string(d["buildVersion"]),
            date: date(d["date"] ?? d["versionDate"]),
            downloadURL: download,
            size: int64(d["size"]),
            minOSVersion: string(d["minOSVersion"]),
            notes: string(d["localizedDescription"]) ?? string(d["versionDescription"])
        )
    }

    // MARK: Loose value readers

    private static func string(_ value: Any?) -> String? {
        if let s = value as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private static func url(_ value: Any?, base: URL) -> URL? {
        guard let s = string(value) else { return nil }
        let encoded = s.replacingOccurrences(of: " ", with: "%20")
        guard let resolved = URL(string: s, relativeTo: base) ?? URL(string: encoded, relativeTo: base) else { return nil }
        let absolute = resolved.absoluteURL
        guard let scheme = absolute.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return absolute
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let n = value as? NSNumber { return n.int64Value > 0 ? n.int64Value : nil }
        if let s = value as? String, let n = Int64(s.trimmingCharacters(in: .whitespaces)) { return n > 0 ? n : nil }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        guard let s = string(value) else { return nil }
        let full = ISO8601DateFormatter()
        if let d = full.date(from: s) { return d }
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: s) { return d }
        let plain = DateFormatter()
        plain.locale = Locale(identifier: "en_US_POSIX")
        plain.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss"] {
            plain.dateFormat = format
            if let d = plain.date(from: s) { return d }
        }
        return nil
    }
}
