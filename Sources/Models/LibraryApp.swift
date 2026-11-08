import Foundation

struct LibraryApp: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var bundleID: String
    var version: String
    var build: String
    var size: Int64
    var dateAdded: Date
    var minimumOS: String?
    /// File name of the IPA inside the app's library folder.
    var fileName: String
    /// File name of the extracted icon PNG, if any.
    var iconFileName: String?
    /// Original file name the user imported.
    var originalFileName: String?
    /// CFBundleIdentifiers of PlugIns/Extensions (.appex).
    var extensionBundleIDs: [String]?
    var hasWatchApp: Bool?

    var extensions: [String] { extensionBundleIDs ?? [] }
    var containsWatchApp: Bool { hasWatchApp ?? false }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case dateAdded, name, size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateAdded: return "Date Added"
        case .name: return "Name"
        case .size: return "Size"
        }
    }

    var systemImage: String {
        switch self {
        case .dateAdded: return "calendar"
        case .name: return "textformat"
        case .size: return "internaldrive"
        }
    }
}

enum LibraryLayout: String {
    case grid, list
}
