import Foundation

enum CertificateImportError: LocalizedError {
    case missingNickname
    case wrongPassword
    case fileWrite(String)

    var errorDescription: String? {
        switch self {
        case .missingNickname: return "Give this certificate a nickname."
        case .wrongPassword: return "That password doesn't open the .p12."
        case .fileWrite(let reason): return "Couldn't save the files: \(reason)"
        }
    }
}

struct CertificateImportResult {
    let certificate: Certificate
    /// Non-fatal note to show the user (e.g. password couldn't be verified).
    let warning: String?
}

/// Stores certificate pairs in Documents/Certificates/<uuid>/ with an index.json.
/// p12 passwords live in the Keychain under "p12-<uuid>".
@MainActor
final class CertificateStore: ObservableObject {
    @Published private(set) var certificates: [Certificate] = []
    @Published private(set) var activeID: UUID?

    private let fm = FileManager.default
    private let root: URL
    private let activeKey = "certificates.activeID"

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = documents.appendingPathComponent("Certificates", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        if let raw = UserDefaults.standard.string(forKey: activeKey) {
            activeID = UUID(uuidString: raw)
        }
        migrateLegacyIfNeeded(documents: documents)
        reload()
    }

    var active: Certificate? {
        certificates.first { $0.id == activeID }
    }

    // MARK: Paths

    func folder(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func p12URL(for id: UUID) -> URL { folder(for: id).appendingPathComponent("certificate.p12") }
    func profileURL(for id: UUID) -> URL { folder(for: id).appendingPathComponent("embedded.mobileprovision") }
    private var indexURL: URL { root.appendingPathComponent("index.json") }
    private func keychainAccount(_ id: UUID) -> String { "p12-\(id.uuidString)" }

    func password(for id: UUID) -> String? { Keychain.load(account: keychainAccount(id)) }

    // MARK: Loading

    func reload() {
        let records = loadIndex()
        certificates = records.map(makeCertificate)
        if activeID == nil || !certificates.contains(where: { $0.id == activeID }) {
            setActive(certificates.first?.id)
        }
    }

    private func makeCertificate(_ record: CertificateRecord) -> Certificate {
        Certificate(
            record: record,
            profile: try? ProfileParser.parse(url: profileURL(for: record.id)),
            hasPassword: password(for: record.id) != nil
        )
    }

    private func loadIndex() -> [CertificateRecord] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([CertificateRecord].self, from: data)) ?? []
    }

    private func saveIndex() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(certificates.map(\.record)) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    // MARK: Mutations

    func setActive(_ id: UUID?) {
        activeID = id
        UserDefaults.standard.set(id?.uuidString, forKey: activeKey)
    }

    func importCertificate(nickname: String, p12Data: Data, profileData: Data, password: String) async throws -> CertificateImportResult {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CertificateImportError.missingNickname }
        let profile = try ProfileParser.parse(data: profileData)

        let outcome = await Task.detached(priority: .userInitiated) {
            P12Inspector.inspect(data: p12Data, password: password)
        }.value

        var record = CertificateRecord(id: UUID(), nickname: trimmed, dateAdded: Date(), signingCertificate: nil, matchesProfile: nil)
        var warning: String?
        switch outcome {
        case .wrongPassword:
            throw CertificateImportError.wrongPassword
        case .unverifiable(let reason):
            warning = "Saved, but iOS couldn't verify the .p12 (\(reason))."
        case .valid(let der, let summary):
            record.signingCertificate = summary
            record.matchesProfile = profile.developerCertificates.isEmpty ? nil : profile.containsCertificate(der)
            if record.matchesProfile == false {
                warning = "Saved, but this .p12 isn't listed in the profile. Signing will likely fail."
            }
        }

        do {
            try fm.createDirectory(at: folder(for: record.id), withIntermediateDirectories: true)
            try p12Data.write(to: p12URL(for: record.id), options: .atomic)
            try profileData.write(to: profileURL(for: record.id), options: .atomic)
        } catch {
            try? fm.removeItem(at: folder(for: record.id))
            throw CertificateImportError.fileWrite(error.localizedDescription)
        }

        if !Keychain.save(password, account: keychainAccount(record.id)) {
            warning = "Saved, but the password couldn't be stored in the Keychain."
        }

        let certificate = makeCertificate(record)
        certificates.append(certificate)
        saveIndex()
        if activeID == nil || certificates.count == 1 { setActive(record.id) }
        return CertificateImportResult(certificate: certificate, warning: warning)
    }

    /// Verifies and stores a new password for an existing certificate.
    func updatePassword(_ password: String, for id: UUID) async throws {
        guard let index = certificates.firstIndex(where: { $0.id == id }) else { return }
        let data = (try? Data(contentsOf: p12URL(for: id))) ?? Data()
        let outcome = await Task.detached(priority: .userInitiated) {
            P12Inspector.inspect(data: data, password: password)
        }.value
        if case .wrongPassword = outcome { throw CertificateImportError.wrongPassword }
        if case .valid(let der, let summary) = outcome {
            certificates[index].record.signingCertificate = summary
            if let profile = certificates[index].profile, !profile.developerCertificates.isEmpty {
                certificates[index].record.matchesProfile = profile.containsCertificate(der)
            }
        }
        Keychain.save(password, account: keychainAccount(id))
        certificates[index].hasPassword = true
        saveIndex()
    }

    func rename(_ id: UUID, to nickname: String) {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = certificates.firstIndex(where: { $0.id == id }) else { return }
        certificates[index].record.nickname = trimmed
        saveIndex()
    }

    func delete(_ id: UUID) {
        try? fm.removeItem(at: folder(for: id))
        Keychain.delete(account: keychainAccount(id))
        certificates.removeAll { $0.id == id }
        saveIndex()
        if activeID == id { setActive(certificates.first?.id) }
    }

    // MARK: Stage 1 migration

    /// Stage 1 stored a single pair in Documents/Certs. Move it into the new layout once.
    private func migrateLegacyIfNeeded(documents: URL) {
        let legacy = documents.appendingPathComponent("Certs", isDirectory: true)
        let p12 = legacy.appendingPathComponent("cert.p12")
        let prov = legacy.appendingPathComponent("profile.mobileprovision")
        guard !fm.fileExists(atPath: indexURL.path),
              let p12Data = try? Data(contentsOf: p12),
              let profileData = try? Data(contentsOf: prov) else { return }

        let id = UUID()
        let profile = try? ProfileParser.parse(data: profileData)
        let password = Keychain.load(account: "p12password") ?? ""
        var record = CertificateRecord(id: id, nickname: profile?.name ?? "My certificate", dateAdded: Date(), signingCertificate: nil, matchesProfile: nil)
        if case .valid(let der, let summary) = P12Inspector.inspect(data: p12Data, password: password) {
            record.signingCertificate = summary
            record.matchesProfile = profile.map { $0.containsCertificate(der) }
        }
        do {
            try fm.createDirectory(at: folder(for: id), withIntermediateDirectories: true)
            try p12Data.write(to: p12URL(for: id))
            try profileData.write(to: profileURL(for: id))
        } catch { return }
        if !password.isEmpty { Keychain.save(password, account: keychainAccount(id)) }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode([record]) {
            try? data.write(to: indexURL, options: .atomic)
        }
        try? fm.removeItem(at: legacy)
        Keychain.delete(account: "p12password")
        setActive(id)
    }
}
