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
    /// Files at least this big are fetched over several connections at once.
    static let parallelThreshold: Int64 = 8 * 1024 * 1024
    static let maxConnections = 8
    /// UI updates at most this often (fast, jumpy numbers are hard to read).
    static let progressInterval: TimeInterval = 0.25

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
    private var parallel: ParallelDownload?

    init(log: @escaping (String) -> Void = { _ in }, onProgress: @escaping ProgressHandler) {
        self.log = log
        self.onProgress = onProgress
    }

    /// Large files on servers that support byte ranges are split into up to `maxConnections` parts
    /// downloaded in parallel (one connection each); everything else uses a single connection.
    func start(_ url: URL) async throws -> URL {
        started = Date()
        if let probe = await probeRanges(url), probe.total >= Self.parallelThreshold {
            try Task.checkCancellation()
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("source-\(UUID().uuidString).ipa")
            let count = Int(min(Int64(Self.maxConnections), max(2, probe.total / (4 * 1024 * 1024))))
            let download = ParallelDownload(url: probe.url, total: probe.total, destination: destination, connections: count,
                                            log: log) { [weak self] received in
                self?.report(received, expected: probe.total)
            }
            lock.lock()
            let alreadyCancelled = cancelled
            if !alreadyCancelled { parallel = download }
            lock.unlock()
            if alreadyCancelled { throw CancellationError() }
            log("download: \(probe.total) bytes from \(probe.url.host ?? "?") over \(count) connections")
            do {
                try await withTaskCancellationHandler {
                    try await download.run()
                } onCancel: {
                    download.cancel()
                }
                report(probe.total, expected: probe.total, force: true)
                log(String(format: "download: finished %lld bytes in %.1fs (%.1f MB/s)", probe.total,
                           Date().timeIntervalSince(started),
                           Double(probe.total) / 1_048_576 / max(0.001, Date().timeIntervalSince(started))))
                return destination
            } catch {
                try? FileManager.default.removeItem(at: destination)
                lock.lock()
                parallel = nil
                let stop = cancelled
                lock.unlock()
                if stop || error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                log("download: parallel download failed (\(error.localizedDescription)), retrying over one connection")
            }
        }
        try Task.checkCancellation()
        return try await single(url)
    }

    /// Asks for the first byte. A 206 with a total size means the server supports ranges;
    /// the redirected URL is reused so every part skips the redirect.
    private func probeRanges(_ url: URL) async -> (url: URL, total: Int64)? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        guard let result = try? await URLSession.shared.data(for: request),
              let http = result.1 as? HTTPURLResponse else {
            log("download: range probe failed, using one connection")
            return nil
        }
        let range = http.value(forHTTPHeaderField: "Content-Range") ?? ""
        guard http.statusCode == 206, let slash = range.lastIndex(of: "/"),
              let total = Int64(range[range.index(after: slash)...].trimmingCharacters(in: .whitespaces)), total > 0,
              let finalURL = http.url else {
            log("download: server doesn't support ranges (HTTP \(http.statusCode)), using one connection")
            return nil
        }
        return (finalURL, total)
    }

    private func report(_ received: Int64, expected: Int64?, force: Bool = false) {
        lock.lock()
        let now = Date()
        let due = force || now.timeIntervalSince(lastReport) >= Self.progressInterval
        if due { lastReport = now }
        lock.unlock()
        if due { onProgress(received, expected) }
    }

    private func single(_ url: URL) async throws -> URL {
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
        let parallel = self.parallel
        lock.unlock()
        task?.cancel()
        parallel?.cancel()
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
        report(totalBytesWritten, expected: totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil,
               force: totalBytesWritten == totalBytesExpectedToWrite)
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

// MARK: - Parallel (multi-connection) download

/// Downloads `total` bytes as `connections` byte ranges at once into a preallocated file.
/// Each range has its own URLSession, so each gets its own TCP connection (one HTTP/2 session
/// would multiplex all ranges over a single connection and gain nothing).
private final class ParallelDownload: @unchecked Sendable {
    let url: URL
    let total: Int64
    let destination: URL
    let connections: Int
    let log: (String) -> Void
    private let onProgress: (Int64) -> Void

    private let lock = NSLock()
    private var segments: [Segment] = []
    private var remaining = 0
    private var received: Int64 = 0
    private var continuation: CheckedContinuation<Void, Error>?
    private var done = false

    init(url: URL, total: Int64, destination: URL, connections: Int, log: @escaping (String) -> Void,
         onProgress: @escaping (Int64) -> Void) {
        self.url = url
        self.total = total
        self.destination = destination
        self.connections = connections
        self.log = log
        self.onProgress = onProgress
    }

    func run() async throws {
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: destination)
        try handle.truncate(atOffset: UInt64(total))
        try handle.close()

        let chunk = total / Int64(connections)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            if done {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            for index in 0..<connections {
                let start = Int64(index) * chunk
                let end = index == connections - 1 ? total - 1 : start + chunk - 1
                segments.append(Segment(index: index, start: start, end: end, url: url, file: destination, owner: self))
            }
            remaining = segments.count
            let all = segments
            lock.unlock()
            all.forEach { $0.begin() }
        }
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    fileprivate func segmentReceived(_ bytes: Int64) {
        lock.lock()
        received += bytes
        let total = received
        lock.unlock()
        onProgress(total)
    }

    fileprivate func segmentFinished(_ segment: Segment) {
        lock.lock()
        remaining -= 1
        let last = remaining == 0
        lock.unlock()
        if last { finish(.success(())) }
    }

    fileprivate func segmentFailed(_ segment: Segment, _ error: Error) {
        log("download: part \(segment.index + 1) failed: \(error.localizedDescription)")
        finish(.failure(error))
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true
        let continuation = self.continuation
        self.continuation = nil
        let all = segments
        lock.unlock()
        all.forEach { $0.close() }
        continuation?.resume(with: result)
    }
}

/// One byte range: streams straight into its slice of the file, resumes up to 3 times on errors.
private final class Segment: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let index: Int
    let start: Int64
    let end: Int64
    let url: URL
    let file: URL
    private weak var owner: ParallelDownload?

    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var handle: FileHandle?
    private var written: Int64 = 0
    private var retries = 0
    private var closed = false
    private var failure: Error?

    private static let maxRetries = 3

    init(index: Int, start: Int64, end: Int64, url: URL, file: URL, owner: ParallelDownload) {
        self.index = index
        self.start = start
        self.end = end
        self.url = url
        self.file = file
        self.owner = owner
    }

    private var length: Int64 { end - start + 1 }

    func begin() {
        do {
            let handle = try FileHandle(forWritingTo: file)
            lock.lock()
            self.handle = handle
            lock.unlock()
        } catch {
            owner?.segmentFailed(self, error)
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = FileDownloader.idleTimeout
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        lock.lock()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        lock.unlock()
        request()
    }

    private func request() {
        lock.lock()
        guard !closed, let session, let handle else { lock.unlock(); return }
        let from = start + written
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: FileDownloader.idleTimeout)
        request.setValue("bytes=\(from)-\(end)", forHTTPHeaderField: "Range")
        failure = nil
        do {
            try handle.seek(toOffset: UInt64(from))
        } catch {
            lock.unlock()
            owner?.segmentFailed(self, error)
            return
        }
        let task = session.dataTask(with: request)
        self.task = task
        lock.unlock()
        task.resume()
    }

    func close() {
        lock.lock()
        closed = true
        let task = self.task
        let session = self.session
        try? handle?.close()
        handle = nil
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 206 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            lock.lock()
            failure = RepositoryError.http(code)
            retries = Self.maxRetries // a server that ignores ranges won't start honouring them
            lock.unlock()
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !closed, let handle, failure == nil else { lock.unlock(); return }
        let room = length - written
        let slice = Int64(data.count) > room ? data.prefix(Int(max(0, room))) : data
        do {
            try handle.write(contentsOf: slice)
            written += Int64(slice.count)
        } catch {
            failure = error
            retries = Self.maxRetries
        }
        let wrote = Int64(slice.count)
        let failed = failure != nil
        lock.unlock()
        if failed {
            dataTask.cancel()
        } else if wrote > 0 {
            owner?.segmentReceived(wrote)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        if closed { lock.unlock(); return }
        let complete = written >= length
        let problem: Error? = failure ?? error ?? (complete ? nil : URLError(.networkConnectionLost))
        let canRetry = problem != nil && retries < Self.maxRetries
        if canRetry { retries += 1 }
        let attempt = retries
        let doneBytes = written
        lock.unlock()

        guard let problem else {
            owner?.segmentFinished(self)
            return
        }
        if canRetry {
            owner?.log("download: part \(index + 1) interrupted at \(doneBytes)/\(length) bytes (\(problem.localizedDescription)), resuming (try \(attempt))")
            request()
        } else {
            owner?.segmentFailed(self, problem)
        }
    }
}
