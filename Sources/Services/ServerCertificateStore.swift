import Foundation

/// A TLS certificate for a hostname that resolves to 127.0.0.1, used by the local install server.
struct ServerCertificate: Codable, Equatable {
    enum Source: String, Codable {
        case backloop, custom

        var title: String {
            switch self {
            case .backloop: return "backloop.dev"
            case .custom: return "Your certificate"
            }
        }
    }

    var source: Source
    var hostname: String
    var commonName: String?
    var notAfter: Date?
    var updatedAt: Date

    func isValid(now: Date = Date()) -> Bool {
        guard let notAfter else { return false }
        return notAfter > now.addingTimeInterval(5 * 60)
    }
}

enum ServerCertificateError: LocalizedError {
    case download(String)
    case badPack
    case expired(Date, ServerCertificate.Source)
    case invalidHostname
    case unreadable

    var errorDescription: String? {
        switch self {
        case .download(let reason): return "Couldn't download the backloop.dev certificate: \(reason)"
        case .badPack: return "backloop.dev returned an unexpected certificate pack."
        case .expired(let date, let source):
            let when = date.formatted(date: .abbreviated, time: .omitted)
            return source == .backloop
                ? "backloop.dev is currently publishing an expired certificate (expired \(when)). Use Semi-Local, or add your own certificate."
                : "This certificate expired on \(when)."
        case .invalidHostname: return "Enter the hostname your certificate covers, e.g. install.example.com."
        case .unreadable: return "The certificate file couldn't be read."
        }
    }
}

/// Stores server certificates in Documents/Server/<source>/ (cert.pem, key.pem, info.json).
@MainActor
final class ServerCertificateStore: ObservableObject {
    @Published private(set) var backloop: ServerCertificate?
    @Published private(set) var custom: ServerCertificate?
    @Published private(set) var isRefreshing = false

    static let packURL = URL(string: "https://backloop.dev/pack.json")!

    private let fm = FileManager.default
    private let root: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = documents.appendingPathComponent("Server", isDirectory: true)
        backloop = loadInfo(.backloop)
        custom = loadInfo(.custom)
    }

    /// The certificate the server should use, if any is currently valid. Custom wins.
    var preferred: ServerCertificate? {
        if let custom, custom.isValid() { return custom }
        if let backloop, backloop.isValid() { return backloop }
        return nil
    }

    func pem(for source: ServerCertificate.Source) -> (certificate: String, key: String)? {
        let folder = self.folder(source)
        guard let cert = try? String(contentsOf: folder.appendingPathComponent("cert.pem"), encoding: .utf8),
              let key = try? String(contentsOf: folder.appendingPathComponent("key.pem"), encoding: .utf8) else { return nil }
        return (cert, key)
    }

    // MARK: backloop.dev

    private struct Pack: Decodable {
        struct Info: Decodable {
            struct Domains: Decodable { var commonName: String }
            var domains: Domains
        }
        var cert: String
        var ca: String
        var key1: String
        var key2: String
        var info: Info
    }

    /// Downloads the current *.backloop.dev pack (same source Feather uses).
    @discardableResult
    func refreshBackloop() async throws -> ServerCertificate {
        isRefreshing = true
        defer { isRefreshing = false }

        let data: Data
        do {
            var request = URLRequest(url: ServerCertificateStore.packURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 20
            let (body, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ServerCertificateError.download("HTTP \(http.statusCode)")
            }
            data = body
        } catch let error as ServerCertificateError {
            throw error
        } catch {
            throw ServerCertificateError.download(error.localizedDescription)
        }

        guard let pack = try? JSONDecoder().decode(Pack.self, from: data) else { throw ServerCertificateError.badPack }
        let chain = pack.cert.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + pack.ca.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        let key = pack.key1 + pack.key2
        let commonName = pack.info.domains.commonName
        let hostname = commonName.hasPrefix("*.") ? "local." + commonName.dropFirst(2) : commonName

        let info = try save(.backloop, certificatePEM: chain, keyPEM: key, hostname: hostname)
        if !info.isValid(), let notAfter = info.notAfter {
            throw ServerCertificateError.expired(notAfter, .backloop)
        }
        return info
    }

    // MARK: Custom

    /// Validates (key matches, iOS can load it) and stores your own certificate.
    @discardableResult
    func importCustom(certificatePEM: String, keyPEM: String, hostname: String) throws -> ServerCertificate {
        let host = hostname.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !host.isEmpty, host.contains("."), !host.contains("/"), !host.contains(" ") else {
            throw ServerCertificateError.invalidHostname
        }
        _ = try TLSIdentityFactory.makeIdentity(certificatePEM: certificatePEM, privateKeyPEM: keyPEM)
        let info = try save(.custom, certificatePEM: certificatePEM, keyPEM: keyPEM, hostname: host)
        if !info.isValid(), let notAfter = info.notAfter {
            throw ServerCertificateError.expired(notAfter, .custom)
        }
        return info
    }

    func removeCustom() {
        try? fm.removeItem(at: folder(.custom))
        custom = nil
    }

    // MARK: Storage

    private func folder(_ source: ServerCertificate.Source) -> URL {
        root.appendingPathComponent(source.rawValue, isDirectory: true)
    }

    private func save(_ source: ServerCertificate.Source, certificatePEM: String, keyPEM: String, hostname: String) throws -> ServerCertificate {
        guard let leaf = TLSIdentityFactory.certificateBlocks(certificatePEM).first else { throw ServerCertificateError.unreadable }
        let summary = DERCertificateParser.parse(leaf)
        let info = ServerCertificate(source: source, hostname: hostname, commonName: summary?.commonName,
                                     notAfter: summary?.notAfter, updatedAt: Date())
        let folder = self.folder(source)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(certificatePEM.utf8).write(to: folder.appendingPathComponent("cert.pem"), options: [.atomic, .completeFileProtection])
        try Data(keyPEM.utf8).write(to: folder.appendingPathComponent("key.pem"), options: [.atomic, .completeFileProtection])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(info).write(to: folder.appendingPathComponent("info.json"), options: .atomic)
        switch source {
        case .backloop: backloop = info
        case .custom: custom = info
        }
        return info
    }

    private func loadInfo(_ source: ServerCertificate.Source) -> ServerCertificate? {
        guard let data = try? Data(contentsOf: folder(source).appendingPathComponent("info.json")) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ServerCertificate.self, from: data)
    }
}
