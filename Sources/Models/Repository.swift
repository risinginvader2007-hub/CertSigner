import Foundation

/// One build of a source app. `downloadURL` is nil when the source lists the version without a
/// download (its GET is then disabled with a reason).
struct RepoVersion: Codable, Hashable, Identifiable {
    var version: String
    var buildVersion: String?
    var date: Date?
    var downloadURL: URL?
    var size: Int64?
    var minOSVersion: String?
    var notes: String?

    /// Unique within one app: exact duplicates (same version and download URL) are removed when parsing.
    var id: String { "\(version)|\(buildVersion ?? "")|\(downloadURL?.absoluteString ?? "-")" }
}

/// An app listed by a source: ONE entry per bundle ID, with every version the source lists for
/// it, newest first. (Sources such as AppTesters list each version as its own app entry; those
/// are merged here.)
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

    /// Unique within one source: the bundle ID (or the name when a source gives none).
    var id: String { Self.key(bundleID: bundleID, name: name) }
    var latest: RepoVersion { versions[0] }

    static func key(bundleID: String, name: String) -> String {
        bundleID.isEmpty ? "name:" + name.lowercased() : bundleID.lowercased()
    }
}

/// Orders version strings by their numbers, not as text: 10.0 > 9.0, 454.0.0 > 453.2.1,
/// 1.2.3.4 > 1.2.3, and a release beats its pre-releases (2.3 > 2.3rc > 2.3b3 > 2.3b2 > 2.3a).
enum VersionOrder {
    struct Parsed: Equatable {
        var numbers: [Int]
        /// nil = a release (no suffix).
        var preRelease: (rank: Int, number: Int, text: String)?

        static func == (a: Parsed, b: Parsed) -> Bool {
            a.numbers == b.numbers && a.preRelease?.rank == b.preRelease?.rank
                && a.preRelease?.number == b.preRelease?.number && a.preRelease?.text == b.preRelease?.text
        }
    }

    static func parse(_ raw: String) -> Parsed? {
        var text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("v") { text.removeFirst() }
        let core = text.prefix { $0.isNumber || $0 == "." }
        let numbers = core.split(separator: ".").compactMap { Int($0) }
        guard !numbers.isEmpty else { return nil }
        let suffix = text.dropFirst(core.count).trimmingCharacters(in: CharacterSet(charactersIn: "-_+. "))
        guard !suffix.isEmpty else { return Parsed(numbers: numbers, preRelease: nil) }
        let letters = String(suffix.prefix { $0.isLetter })
        let digits = Int(suffix.drop { !$0.isNumber }.prefix { $0.isNumber }) ?? 0
        let rank: Int
        switch letters {
        case "dev", "alpha", "a": rank = 0
        case "beta", "b": rank = 1
        case "pre", "rc", "c": rank = 2
        default: rank = 1
        }
        return Parsed(numbers: numbers, preRelease: (rank, digits, String(suffix)))
    }

    /// <0 when `a` is older than `b`, 0 when equal, >0 when newer. Unparseable versions are oldest.
    static func compare(_ a: String, _ b: String) -> Int {
        switch (parse(a), parse(b)) {
        case (nil, nil): return 0
        case (nil, _): return -1
        case (_, nil): return 1
        case let (x?, y?):
            for index in 0..<max(x.numbers.count, y.numbers.count) {
                let l = index < x.numbers.count ? x.numbers[index] : 0
                let r = index < y.numbers.count ? y.numbers[index] : 0
                if l != r { return l < r ? -1 : 1 }
            }
            switch (x.preRelease, y.preRelease) {
            case (nil, nil): return 0
            case (nil, _): return 1
            case (_, nil): return -1
            case let (p?, q?):
                if p.rank != q.rank { return p.rank < q.rank ? -1 : 1 }
                if p.number != q.number { return p.number < q.number ? -1 : 1 }
                return p.text == q.text ? 0 : (p.text < q.text ? -1 : 1)
            }
        }
    }

    /// Newest first; the same version number falls back to the newer date.
    static func newestFirst(_ a: RepoVersion, _ b: RepoVersion) -> Bool {
        let order = compare(a.version, b.version)
        if order != 0 { return order > 0 }
        return (a.date ?? .distantPast) > (b.date ?? .distantPast)
    }
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
    /// Technical detail of the last failure (shown under "Details").
    var lastErrorDetail: String? = nil
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
        /// App entries in the JSON, before merging (for the log).
        var rawEntries = 0
        /// Exact duplicate versions dropped while merging.
        var duplicatesRemoved = 0
    }

    /// One app per bundle ID (or name, when there is none) in first-seen order, with all its
    /// versions; exact duplicates (same version and download URL) removed; newest first.
    /// App details come from the entry with the newest version, gaps filled from the others.
    static func merge(_ entries: [RepoApp]) -> (apps: [RepoApp], duplicatesRemoved: Int) {
        var order: [String] = []
        var groups: [String: [RepoApp]] = [:]
        for entry in entries {
            let key = entry.id
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(entry)
        }
        var removed = 0
        let apps = order.compactMap { key -> RepoApp? in
            guard let group = groups[key] else { return nil }
            var seen = Set<String>()
            var versions: [RepoVersion] = []
            for version in group.flatMap(\.versions) {
                let identity = "\(version.version)|\(version.downloadURL?.absoluteString ?? "-")"
                if seen.insert(identity).inserted { versions.append(version) } else { removed += 1 }
            }
            guard !versions.isEmpty else { return nil }
            versions.sort(by: VersionOrder.newestFirst)
            let top = versions[0]
            let primary = group.first { $0.versions.contains(top) } ?? group[0]
            var app = primary
            app.versions = versions
            for other in group {
                app.developer = app.developer ?? other.developer
                app.subtitle = app.subtitle ?? other.subtitle
                app.appDescription = app.appDescription ?? other.appDescription
                app.iconURL = app.iconURL ?? other.iconURL
                app.category = app.category ?? other.category
                if app.screenshotURLs.isEmpty { app.screenshotURLs = other.screenshotURLs }
            }
            return app
        }
        return (apps, removed)
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
        parsed.rawEntries = parsed.apps.count
        let merged = merge(parsed.apps)
        parsed.apps = merged.apps
        parsed.duplicatesRemoved = merged.duplicatesRemoved
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

    /// A version from a `versions` entry, or from the app itself (legacy single-version layout).
    /// Kept without a download link when it has a version number (its GET is disabled).
    private static func version(_ d: [String: Any], base: URL) -> RepoVersion? {
        let download = url(d["downloadURL"] ?? d["down"] ?? d["download"] ?? d["url"], base: base)
        let number = string(d["version"])
        guard download != nil || number != nil else { return nil }
        return RepoVersion(
            version: number ?? "–",
            buildVersion: string(d["buildVersion"]),
            date: date(d["date"] ?? d["versionDate"]),
            downloadURL: download,
            size: int64(d["size"]),
            minOSVersion: string(d["minOSVersion"]),
            // Legacy entries keep release notes in versionDescription (localizedDescription is the app's).
            notes: string(d["versionDescription"]) ?? string(d["localizedDescription"])
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
