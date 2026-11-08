import Foundation
import Security

/// Opens a .p12 with its password using the Security framework.
enum P12Inspector {
    enum Outcome: Sendable {
        case valid(certificateDER: Data, summary: CertificateSummary?)
        case wrongPassword
        /// iOS couldn't open it (e.g. unusual encryption). zsign may still manage later.
        case unverifiable(String)
    }

    static func inspect(data: Data, password: String) -> Outcome {
        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options, &items)

        if status == errSecAuthFailed { return .wrongPassword }
        guard status == errSecSuccess else { return .unverifiable(message(for: status)) }
        guard let array = items as? [[String: Any]],
              let first = array.first,
              let rawIdentity = first[kSecImportItemIdentity as String] else {
            return .unverifiable("No signing identity inside the .p12.")
        }

        let identity = rawIdentity as! SecIdentity
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else {
            return .unverifiable("The .p12 has no certificate.")
        }
        let der = SecCertificateCopyData(certificate) as Data
        return .valid(certificateDER: der, summary: DERCertificateParser.parse(der))
    }

    private static func message(for status: OSStatus) -> String {
        if let text = SecCopyErrorMessageString(status, nil) as String? {
            return text
        }
        return "Security error \(status)."
    }
}
