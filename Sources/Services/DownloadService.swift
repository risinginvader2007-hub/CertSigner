import Foundation

enum DownloadError: LocalizedError {
    case badStatus(Int)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "The server replied with HTTP \(code)."
        case .cancelled: return "The download was cancelled."
        }
    }
}

/// One-shot file download with progress. Create a new instance per download.
final class DownloadService: NSObject, URLSessionDownloadDelegate {
    struct Result {
        let fileURL: URL
        let suggestedFileName: String
    }

    private var continuation: CheckedContinuation<Result, Error>?
    private var onProgress: ((Double) -> Void)?
    private var session: URLSession?
    private let lock = NSLock()

    func download(_ url: URL, progress: @escaping (Double) -> Void) async throws -> Result {
        onProgress = progress
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: url).resume()
        }
    }

    private func finish(_ result: Swift.Result<Result, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
        session?.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(DownloadError.badStatus(http.statusCode)))
            return
        }
        let name = downloadTask.response?.suggestedFilename ?? downloadTask.originalRequest?.url?.lastPathComponent ?? "download.ipa"
        // The temp file is deleted when this method returns, so move it now.
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("download-\(UUID().uuidString).ipa")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(Result(fileURL: destination, suggestedFileName: name)))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        }
    }
}
