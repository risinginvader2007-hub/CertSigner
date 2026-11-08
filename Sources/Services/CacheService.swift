import Foundation

enum CacheService {
    static var directories: [URL] {
        let fm = FileManager.default
        return [fm.temporaryDirectory, fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]]
    }

    static func size() -> Int64 {
        var total: Int64 = 0
        for directory in directories {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
            ) else { continue }
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if values?.isRegularFile == true {
                    total += Int64(values?.fileSize ?? 0)
                }
            }
        }
        return total
    }

    static func clear() {
        let fm = FileManager.default
        for directory in directories {
            let items = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for item in items {
                try? fm.removeItem(at: item)
            }
        }
    }
}
