import Foundation
import Security

/// What this copy of CertSigner was signed with, read from its own embedded profile. Shown once
/// per signature on launch ("Signed with …, expires …"), e.g. right after installing from the
/// Get CertSigner web page; after that the in-app signer takes over.
enum LaunchSignature {
    struct Info: Equatable {
        var certificateName: String
        var expires: Date?
        /// Identifies this signature (profile + certificate), so the confirmation shows once for it.
        var key: String
    }

    static let shownKey = "launch.signatureConfirmed"

    static func current(bundle: Bundle = .main) -> Info? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return info(profileData: data)
    }

    static func info(profileData: Data) -> Info? {
        guard let profile = try? ProfileParser.parse(data: profileData) else { return nil }
        let certificateName = profile.developerCertificates.first
            .flatMap { SecCertificateCreateWithData(nil, $0 as CFData) }
            .flatMap { SecCertificateCopySubjectSummary($0) as String? }
        let name = certificateName ?? (profile.teamName.isEmpty ? profile.name : profile.teamName)
        return Info(certificateName: name, expires: profile.expirationDate, key: "\(profile.uuid)|\(name)")
    }

    static func message(_ info: Info) -> String {
        guard let expires = info.expires else { return "Signed with \(info.certificateName)" }
        return "Signed with \(info.certificateName), expires \(expires.formatted(date: .abbreviated, time: .omitted))"
    }

    /// The confirmation to show now, or nil when this signature was already confirmed (or the
    /// app has no embedded profile, as in the simulator).
    static func confirmationIfNew(_ info: Info?, defaults: UserDefaults = .standard) -> String? {
        guard let info, defaults.string(forKey: shownKey) != info.key else { return nil }
        defaults.set(info.key, forKey: shownKey)
        return message(info)
    }
}
