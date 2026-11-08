import Foundation

struct StorageItem: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let bytes: Int64
}

/// Disk usage per area of the app. Plain Foundation.
enum StorageService {
    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func usage() -> [StorageItem] {
        [
            StorageItem(id: "signed", title: "Signed apps", systemImage: "signature",
                        bytes: size(of: documents.appendingPathComponent("Signed"))),
            StorageItem(id: "imports", title: "Imported IPAs", systemImage: "square.and.arrow.down",
                        bytes: size(of: documents.appendingPathComponent("Library"))),
            StorageItem(id: "certs", title: "Certificates", systemImage: "checkmark.seal",
                        bytes: size(of: documents.appendingPathComponent("Certificates"))
                            + size(of: documents.appendingPathComponent("Server"))),
            StorageItem(id: "logs", title: "Logs", systemImage: "doc.text",
                        bytes: size(of: documents.appendingPathComponent("Logs"))),
            StorageItem(id: "cache", title: "Cache", systemImage: "internaldrive",
                        bytes: CacheService.size())
        ]
    }

    static func size(of folder: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }
}
