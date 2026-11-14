import Foundation

/// Append-only text log in Documents/Logs/certsigner.log, exportable from Settings.
enum AppLog {
    private static let queue = DispatchQueue(label: "com.certsigner.log")
    private static let maxBytes = 2 * 1024 * 1024

    static var fileURL: URL {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("certsigner.log")
    }

    static func info(_ message: String) { write("INFO", message) }
    static func error(_ message: String) { write("ERROR", message) }

    /// Writes before returning, for lines that must survive the process being killed right after.
    static func infoNow(_ message: String) {
        let line = format("INFO", message)
        queue.sync { append(line) }
    }

    private static func format(_ level: String, _ message: String) -> String {
        "\(ISO8601DateFormatter().string(from: Date())) [\(level)] \(message)\n"
    }

    private static func write(_ level: String, _ message: String) {
        let line = format(level, message)
        queue.async { append(line) }
    }

    /// Runs on `queue`.
    private static func append(_ line: String) {
        let url = fileURL
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber, size.intValue > maxBytes {
            try? fm.removeItem(at: url) // keep the log small
        }
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        }
    }

    static func size() -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    static func clear() {
        queue.async { try? FileManager.default.removeItem(at: fileURL) }
    }

    /// A copy with a friendly, dated name for sharing.
    static func exportCopy() -> URL? {
        queue.sync {
            let name = "CertSigner-log-\(Date().formatted(.iso8601.year().month().day())).txt"
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: destination)
            let source = fileURL
            if !FileManager.default.fileExists(atPath: source.path) {
                FileManager.default.createFile(atPath: source.path, contents: Data("No log entries yet.\n".utf8))
            }
            return (try? FileManager.default.copyItem(at: source, to: destination)) != nil ? destination : nil
        }
    }
}
