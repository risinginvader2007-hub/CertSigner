import Foundation
import ZIPFoundation

struct IPAInfo {
    var fileName: String
    var appName: String
    var bundleID: String
    var version: String
}

@MainActor
final class CertStore: ObservableObject {
    @Published var p12Name: String?
    @Published var p12Password: String = ""
    @Published var profile: ProvisioningProfile?
    @Published var profileName: String?
    @Published var ipa: IPAInfo?
    @Published var message: String = ""

    private let fm = FileManager.default

    private var certsDir: URL {
        let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Certs")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var ipaDir: URL {
        let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("IPAs")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        p12Password = Keychain.load(account: "p12password") ?? ""
        let p12 = certsDir.appendingPathComponent("cert.p12")
        if fm.fileExists(atPath: p12.path) { p12Name = "cert.p12" }
        let prov = certsDir.appendingPathComponent("profile.mobileprovision")
        if fm.fileExists(atPath: prov.path) {
            profile = ProvisioningProfile.parse(url: prov)
            profileName = profile?.name
        }
    }

    /// Copies a picked file into the app's folder.
    private func copyIn(_ url: URL, to dest: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try? fm.removeItem(at: dest)
        try fm.copyItem(at: url, to: dest)
    }

    func importP12(_ url: URL) {
        do {
            try copyIn(url, to: certsDir.appendingPathComponent("cert.p12"))
            p12Name = url.lastPathComponent
            message = "Certificate imported."
        } catch {
            message = "Could not import certificate: \(error.localizedDescription)"
        }
    }

    func savePassword() {
        Keychain.save(p12Password, account: "p12password")
        message = "Password saved."
    }

    func importProfile(_ url: URL) {
        do {
            let dest = certsDir.appendingPathComponent("profile.mobileprovision")
            try copyIn(url, to: dest)
            profile = ProvisioningProfile.parse(url: dest)
            profileName = profile?.name
            message = profile == nil ? "Could not read the profile." : "Profile imported."
        } catch {
            message = "Could not import profile: \(error.localizedDescription)"
        }
    }

    func importIPA(_ url: URL) {
        do {
            let dest = ipaDir.appendingPathComponent(url.lastPathComponent)
            try copyIn(url, to: dest)

            let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tmp) }
            try fm.unzipItem(at: dest, to: tmp)

            let payload = tmp.appendingPathComponent("Payload")
            let apps = try fm.contentsOfDirectory(atPath: payload.path).filter { $0.hasSuffix(".app") }
            guard let appDir = apps.first else {
                message = "No .app found inside that IPA."
                return
            }
            let infoURL = payload.appendingPathComponent(appDir).appendingPathComponent("Info.plist")
            let data = try Data(contentsOf: infoURL)
            let info = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] ?? [:]
            ipa = IPAInfo(
                fileName: url.lastPathComponent,
                appName: (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? appDir,
                bundleID: info["CFBundleIdentifier"] as? String ?? "?",
                version: info["CFBundleShortVersionString"] as? String ?? "?"
            )
            message = "IPA imported."
        } catch {
            message = "Could not read IPA: \(error.localizedDescription)"
        }
    }
}
