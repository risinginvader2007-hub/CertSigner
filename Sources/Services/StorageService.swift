import Foundation
import SwiftUI

/// The five storage areas, each with one fixed colour used identically in the ring, legend and cards.
enum StorageCategory: String, CaseIterable, Identifiable, Sendable {
    case signed, imports, certificates, logs, cache

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signed: return "Signed apps"
        case .imports: return "Imported IPAs"
        case .certificates: return "Certificates & profiles"
        case .logs: return "Logs"
        case .cache: return "Cache"
        }
    }

    var systemImage: String {
        switch self {
        case .signed: return "signature"
        case .imports: return "square.and.arrow.down.fill"
        case .certificates: return "checkmark.seal.fill"
        case .logs: return "doc.text.fill"
        case .cache: return "internaldrive.fill"
        }
    }

    /// Five clearly distinct hues, readable on light and dark, independent of the accent theme.
    var color: Color {
        switch self {
        case .signed: return Color(red: 0.31, green: 0.49, blue: 1.0)       // blue
        case .imports: return Color(red: 0.07, green: 0.72, blue: 0.78)     // teal
        case .certificates: return Color(red: 1.0, green: 0.62, blue: 0.04) // amber
        case .logs: return Color(red: 0.93, green: 0.30, blue: 0.62)        // pink
        case .cache: return Color(red: 0.45, green: 0.36, blue: 0.95)       // violet
        }
    }

    func countText(_ count: Int) -> String {
        switch self {
        case .signed: return count == 1 ? "1 app" : "\(count) apps"
        case .imports: return count == 1 ? "1 IPA" : "\(count) IPAs"
        case .certificates: return count == 1 ? "1 item" : "\(count) items"
        case .logs, .cache: return count == 1 ? "1 file" : "\(count) files"
        }
    }
}

/// One measurable thing on disk (an app's folder, a certificate pair, a log file, a cache item).
struct StorageEntry: Identifiable, Sendable, Hashable {
    let category: StorageCategory
    /// UUID string for store items, a path for files.
    let key: String
    let name: String
    var detail: String? = nil
    let date: Date?
    let urls: [URL]
    var bytes: Int64 = 0
    /// Can be deleted from the storage screen.
    var deletable = true

    var id: String { "\(category.rawValue)|\(key)" }
}

struct StorageReport: Sendable {
    var entries: [StorageCategory: [StorageEntry]]
    var calculatedAt: Date
    var deviceAvailable: Int64?
    var deviceTotal: Int64?

    func entries(_ category: StorageCategory) -> [StorageEntry] { entries[category] ?? [] }
    func bytes(_ category: StorageCategory) -> Int64 { entries(category).reduce(0) { $0 + $1.bytes } }
    var total: Int64 { StorageCategory.allCases.reduce(0) { $0 + bytes($1) } }

    func share(_ category: StorageCategory) -> Double {
        let total = self.total
        return total > 0 ? Double(bytes(category)) / Double(total) : 0
    }

    var largestItem: StorageEntry? {
        entries.values.flatMap { $0 }.filter { $0.bytes > 0 }.max { $0.bytes < $1.bytes }
    }

    var oldestSignedApp: StorageEntry? {
        entries(.signed).compactMap { entry in entry.date.map { (entry, $0) } }.min { $0.1 < $1.1 }?.0
    }

    /// Log files not touched for 30 days.
    var oldLogs: [StorageEntry] {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        return entries(.logs).filter { ($0.date ?? Date()) < cutoff }
    }
}

/// Disk usage. Every size is the real on-disk total of every file inside (recursively, including
/// nested folders and .app bundles), measured off the main thread.
enum StorageService {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static let sizeKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey
    ]

    private static func fileBytes(_ values: URLResourceValues?) -> Int64 {
        Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
    }

    /// Recursive on-disk size of a file or folder (adds up every file inside, at any depth).
    static func size(of url: URL) -> Int64 {
        let rootValues = try? url.resourceValues(forKeys: sizeKeys)
        if rootValues?.isDirectory != true {
            return rootValues?.isRegularFile == true ? fileBytes(rootValues) : 0
        }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(sizeKeys)) else {
            return 0
        }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: sizeKeys)
            if values?.isRegularFile == true { total += fileBytes(values) }
        }
        return total
    }

    static func measure(_ entries: [StorageEntry]) -> [StorageEntry] {
        entries.map { entry in
            var measured = entry
            measured.bytes = entry.urls.reduce(0) { $0 + size(of: $1) }
            return measured
        }
    }

    /// Top-level items of the temporary and Caches folders.
    static func cacheEntries() -> [StorageEntry] {
        let fm = FileManager.default
        return CacheService.directories.flatMap { directory -> [StorageEntry] in
            let items = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            return items.map { url in
                StorageEntry(category: .cache, key: url.path, name: url.lastPathComponent,
                             date: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                             urls: [url])
            }
        }
    }

    /// Every file under Documents/Logs (the app log and per-job signing logs).
    static func logEntries() -> [StorageEntry] {
        let folder = documents.appendingPathComponent("Logs", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey]
        ) else { return [] }
        var entries: [StorageEntry] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { continue }
            let isAppLog = url.lastPathComponent == AppLog.fileURL.lastPathComponent
            let inSigning = url.deletingLastPathComponent().lastPathComponent == "Signing"
            entries.append(StorageEntry(
                category: .logs, key: url.path,
                name: isAppLog ? "App log" : url.deletingPathExtension().lastPathComponent,
                detail: isAppLog ? "Imports, signing and install events" : (inSigning ? "Signing log" : nil),
                date: values?.contentModificationDate, urls: [url]
            ))
        }
        return entries
    }

    /// Device free space (as iOS reports it for important data) and capacity.
    static func deviceCapacity() -> (available: Int64?, total: Int64?) {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return (values?.volumeAvailableCapacityForImportantUsage, values?.volumeTotalCapacity.map(Int64.init))
    }

    /// "Empty" instead of "Zero KB"; otherwise the locale-aware file-size string.
    static func format(_ bytes: Int64) -> String {
        bytes <= 0 ? "Empty" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
