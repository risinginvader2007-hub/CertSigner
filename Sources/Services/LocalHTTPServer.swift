import Foundation
import Network

/// Minimal HTTP/1.1 (optionally TLS) file server on the loopback interface, built on Network.framework.
/// Serves GET/HEAD for registered paths; files are streamed in chunks with Range support.
final class LocalHTTPServer: @unchecked Sendable {
    enum Resource {
        case data(Data, contentType: String)
        case file(URL, contentType: String)
    }

    enum Event {
        case request(method: String, path: String)
        /// Diagnostics: who asked for what (user agent, range).
        case requestDetail(String)
        case payloadProgress(Double)
        case payloadCompleted
        case payloadFailed(String)
    }

    enum ServerError: LocalizedError {
        case couldNotStart(String)

        var errorDescription: String? {
            switch self {
            case .couldNotStart(let reason): return "The local install server couldn't start: \(reason)"
            }
        }
    }

    private let queue = DispatchQueue(label: "com.certsigner.install-server")
    private let identity: sec_identity_t?
    private let onEvent: (Event) -> Void
    private var routes: [String: Resource] = [:]
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let chunkSize = 512 * 1024

    /// `identity` nil = plain HTTP.
    init(identity: sec_identity_t?, onEvent: @escaping (Event) -> Void) {
        self.identity = identity
        self.onEvent = onEvent
    }

    var isTLS: Bool { identity != nil }

    func setRoute(_ path: String, _ resource: Resource) {
        queue.sync { routes[path] = resource }
    }

    // MARK: Lifecycle

    /// Starts on a random port in 4000–8000 and returns it.
    func start() async throws -> UInt16 {
        var lastError = "unknown error"
        for _ in 0..<8 {
            let port = UInt16.random(in: 4000...8000)
            do {
                try await startListener(on: port)
                return port
            } catch {
                lastError = error.localizedDescription
            }
        }
        throw ServerError.couldNotStart(lastError)
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            for connection in self.connections.values { connection.cancel() }
            self.connections.removeAll()
        }
    }

    private func makeParameters() -> NWParameters {
        let parameters: NWParameters
        if let identity {
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions, identity)
            sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
            parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        } else {
            parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        }
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback // never reachable from the network
        return parameters
    }

    private func startListener(on port: UInt16) async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw ServerError.couldNotStart("bad port") }
        let listener = try NWListener(using: makeParameters(), on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !resumed { resumed = true; continuation.resume() }
                case .failed(let error):
                    listener.cancel()
                    if !resumed { resumed = true; continuation.resume(throwing: error) }
                case .cancelled:
                    if !resumed { resumed = true; continuation.resume(throwing: ServerError.couldNotStart("cancelled")) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        queue.sync { self.listener = listener }
    }

    // MARK: Connections (all on `queue`)

    private func accept(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.connections[key] = nil
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveHead(on: connection, buffer: Data())
    }

    private func receiveHead(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[buffer.startIndex..<end.lowerBound], as: UTF8.self)
                self.respond(to: head, on: connection)
            } else if isComplete || error != nil || buffer.count > 32 * 1024 {
                connection.cancel()
            } else {
                self.receiveHead(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to head: String, on connection: NWConnection) {
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ").map(String.init) ?? []
        guard requestLine.count >= 2 else {
            sendSimple(400, "Bad Request", on: connection)
            return
        }
        let method = requestLine[0].uppercased()
        var path = requestLine[1]
        if let query = path.firstIndex(of: "?") { path = String(path[..<query]) }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let agent = headers["user-agent"] ?? "-"
        onEvent(.requestDetail("\(method) \(path) range=\(headers["range"] ?? "-") agent=\(agent)"))
        onEvent(.request(method: method, path: path))

        guard method == "GET" || method == "HEAD" else {
            sendSimple(405, "Method Not Allowed", on: connection)
            return
        }
        guard let resource = routes[path] else {
            sendSimple(404, "Not Found", on: connection)
            return
        }

        let headOnly = method == "HEAD"
        switch resource {
        case .data(let data, let type):
            var response = header(status: "200 OK", contentType: type, length: Int64(data.count))
            if !headOnly { response.append(data) }
            connection.send(content: response, completion: .contentProcessed { [weak self] _ in self?.finish(connection) })
        case .file(let url, let type):
            stream(url, contentType: type, rangeHeader: headers["range"], headOnly: headOnly, on: connection)
        }
    }

    private func header(status: String, contentType: String, length: Int64, extra: [String] = []) -> Data {
        var lines = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(length)",
            "Accept-Ranges: bytes",
            "Cache-Control: no-store",
            "Connection: close"
        ]
        lines += extra
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    private func sendSimple(_ code: Int, _ reason: String, on connection: NWConnection) {
        var response = header(status: "\(code) \(reason)", contentType: "text/plain", length: Int64(reason.utf8.count))
        response.append(Data(reason.utf8))
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in self?.finish(connection) })
    }

    private func finish(_ connection: NWConnection) {
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Parses "bytes=start-end" / "bytes=start-" / "bytes=-suffix".
    static func parseRange(_ header: String?, size: Int64) -> ClosedRange<Int64>? {
        guard let header, header.hasPrefix("bytes="), size > 0 else { return nil }
        let spec = header.dropFirst("bytes=".count).split(separator: ",").first.map(String.init) ?? ""
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty, let suffix = Int64(parts[1]), suffix > 0 {
            return max(0, size - suffix)...(size - 1)
        }
        guard let start = Int64(parts[0]), start < size else { return nil }
        let end = parts[1].isEmpty ? size - 1 : min(Int64(parts[1]) ?? (size - 1), size - 1)
        return start <= end ? start...end : nil
    }

    private func stream(_ url: URL, contentType: String, rangeHeader: String?, headOnly: Bool, on connection: NWConnection) {
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0, let handle = try? FileHandle(forReadingFrom: url) else {
            sendSimple(404, "Not Found", on: connection)
            onEvent(.payloadFailed("The signed IPA file is missing."))
            return
        }

        let range = LocalHTTPServer.parseRange(rangeHeader, size: size)
        let start = range?.lowerBound ?? 0
        let end = range?.upperBound ?? size - 1
        let length = end - start + 1
        let response = range == nil
            ? header(status: "200 OK", contentType: contentType, length: length)
            : header(status: "206 Partial Content", contentType: contentType, length: length,
                     extra: ["Content-Range: bytes \(start)-\(end)/\(size)"])

        connection.send(content: response, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil || headOnly {
                try? handle.close()
                self.finish(connection)
                return
            }
            do {
                try handle.seek(toOffset: UInt64(start))
            } catch {
                try? handle.close()
                self.onEvent(.payloadFailed(error.localizedDescription))
                connection.cancel()
                return
            }
            self.sendChunk(from: handle, remaining: length, total: length, on: connection)
        })
    }

    private func sendChunk(from handle: FileHandle, remaining: Int64, total: Int64, on connection: NWConnection) {
        if remaining <= 0 {
            try? handle.close()
            onEvent(.payloadCompleted)
            finish(connection)
            return
        }
        let chunk = handle.readData(ofLength: Int(min(Int64(chunkSize), remaining)))
        if chunk.isEmpty {
            try? handle.close()
            onEvent(.payloadFailed("The IPA ended unexpectedly while sending."))
            connection.cancel()
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard let self else { try? handle.close(); return }
            if let error {
                try? handle.close()
                self.onEvent(.payloadFailed(error.localizedDescription))
                connection.cancel()
                return
            }
            let left = remaining - Int64(chunk.count)
            self.onEvent(.payloadProgress(Double(total - left) / Double(total)))
            self.sendChunk(from: handle, remaining: left, total: total, on: connection)
        })
    }
}

/// Turns a PEM certificate chain + key into a Network.framework TLS identity.
enum TLSIdentityFactory {
    enum IdentityError: LocalizedError {
        case importFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .importFailed(let status): return "iOS couldn't load the server certificate (error \(status))."
            }
        }
    }

    /// DER blocks of every "-----BEGIN CERTIFICATE-----" in a PEM string, in order.
    static func certificateBlocks(_ pem: String) -> [Data] {
        let begin = "-----BEGIN CERTIFICATE-----"
        let end = "-----END CERTIFICATE-----"
        var blocks: [Data] = []
        var remainder = Substring(pem)
        while let start = remainder.range(of: begin), let stop = remainder.range(of: end, range: start.upperBound..<remainder.endIndex) {
            let body = remainder[start.upperBound..<stop.lowerBound]
            if let der = Data(base64Encoded: String(body), options: .ignoreUnknownCharacters) {
                blocks.append(der)
            }
            remainder = remainder[stop.upperBound...]
        }
        return blocks
    }

    static func makeIdentity(certificatePEM: String, privateKeyPEM: String) throws -> sec_identity_t {
        let password = "certsigner-server"
        let p12 = try CSTLSUtil.pkcs12(certificatePEM: certificatePEM, privateKeyPEM: privateKeyPEM, password: password)
        var items: CFArray?
        let status = SecPKCS12Import(p12 as CFData, [kSecImportExportPassphrase as String: password] as CFDictionary, &items)
        guard status == errSecSuccess,
              let array = items as? [[String: Any]],
              let first = array.first,
              let rawIdentity = first[kSecImportItemIdentity as String] else {
            throw IdentityError.importFailed(status)
        }
        let identity = rawIdentity as! SecIdentity

        // Leaf first, then intermediates, so iOS clients can build the chain.
        let chain = certificateBlocks(certificatePEM).compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        if chain.count > 1, let withChain = sec_identity_create_with_certificates(identity, chain as CFArray) {
            return withChain
        }
        guard let plain = sec_identity_create(identity) else { throw IdentityError.importFailed(errSecInternalError) }
        return plain
    }
}
