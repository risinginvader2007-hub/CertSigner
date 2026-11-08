import Foundation

/// A download that stalled: the connection never delivered (more) data.
struct DownloadStalledError: LocalizedError {
    let host: String
    let received: Int64

    var errorDescription: String? {
        if received == 0 {
            return "\(host) sent no data for \(Int(FileDownloader.idleTimeout))s. That server may be blocked or unreachable on this network. Try Wi-Fi vs mobile data (or a VPN), or open the download link in Safari to check."
        }
        return "The download from \(host) stopped after \(ByteCountFormatter.string(fromByteCount: received, countStyle: .file)). Check your connection and try again."
    }
}

/// One file download with progress and cancellation, finishing into a temp `.ipa`.
/// Every hop (redirects, DNS / connect / TLS timings, protocol, status) goes to `log`, so a failure
/// on a device can be diagnosed from the exported log.
final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    typealias ProgressHandler = (_ received: Int64, _ expected: Int64?) -> Void

    /// Give up when no bytes arrive for this long.
    static let idleTimeout: TimeInterval = 30

    private let onProgress: ProgressHandler
    private let log: (String) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var finished = false
    private var cancelled = false
    private var lastReport = Date.distantPast
    private var started = Date()

    init(log: @escaping (String) -> Void = { _ in }, onProgress: @escaping ProgressHandler) {
        self.log = log
        self.onProgress = onProgress
    }

    func start(_ url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                lock.lock()
                if cancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let configuration = URLSessionConfiguration.default
                configuration.timeoutIntervalForRequest = FileDownloader.idleTimeout
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                let task = session.downloadTask(with: URLRequest(url: url))
                self.session = session
                self.task = task
                self.started = Date()
                lock.unlock()
                log("download: GET \(url.absoluteString)")
                task.resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let session = self.session
        lock.unlock()
        session?.finishTasksAndInvalidate()
        continuation?.resume(with: result)
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = Date()
        guard now.timeIntervalSince(lastReport) > 0.12 || totalBytesWritten == totalBytesExpectedToWrite else { return }
        lastReport = now
        onProgress(totalBytesWritten, totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let elapsed = Date().timeIntervalSince(started)
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            log("download: HTTP \(http.statusCode) from \(http.url?.host ?? "?")")
            finish(.failure(RepositoryError.http(http.statusCode)))
            return
        }
        // `location` is deleted when this method returns, so move it now.
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("source-\(UUID().uuidString).ipa")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            log(String(format: "download: finished %lld bytes in %.1fs", downloadTask.countOfBytesReceived, elapsed))
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let host = task.currentRequest?.url?.host ?? task.originalRequest?.url?.host ?? "the server"
        let bytes = task.countOfBytesReceived
        let nsError = error as NSError
        log("download: failed at \(host) after \(bytes) bytes: \(error.localizedDescription) [\(nsError.domain) \(nsError.code)]")
        if let urlError = error as? URLError, urlError.code == .timedOut {
            finish(.failure(DownloadStalledError(host: host, received: bytes)))
        } else {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        log("download: \(response.statusCode) redirect \(response.url?.host ?? "?") -> \(request.url?.host ?? "?")")
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        for (index, t) in metrics.transactionMetrics.enumerated() {
            let host = t.request.url?.host ?? "?"
            let status = (t.response as? HTTPURLResponse).map { "\($0.statusCode)" } ?? "no response"
            let timings = "dns=\(ms(t.domainLookupStartDate, t.domainLookupEndDate)) connect=\(ms(t.connectStartDate, t.connectEndDate))"
                + " tls=\(ms(t.secureConnectionStartDate, t.secureConnectionEndDate)) firstByte=\(ms(t.requestStartDate, t.responseStartDate))"
            log("download: hop \(index + 1) \(host) proto=\(t.networkProtocolName ?? "?") reused=\(t.isReusedConnection) "
                + timings + " status=\(status) remote=\(t.remoteAddress ?? "?")")
        }
    }

    private func ms(_ start: Date?, _ end: Date?) -> String {
        guard let start else { return "-" }
        guard let end else { return "never" }
        return "\(Int(end.timeIntervalSince(start) * 1000))ms"
    }
}
