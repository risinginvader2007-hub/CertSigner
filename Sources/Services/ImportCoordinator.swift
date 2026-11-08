import Foundation

/// A file the user picked or shared into the app, already read into memory.
struct PickedFile: Equatable {
    let name: String
    let data: Data

    var pathExtension: String { (name as NSString).pathExtension.lowercased() }
}

/// Routes files arriving via "Open in" / Share → CertSigner to the right screen.
@MainActor
final class ImportCoordinator: ObservableObject {
    @Published var showCertificateImport = false
    @Published private(set) var pendingCertificateFiles: [PickedFile] = []

    static let certificateExtensions: Set<String> = ["p12", "pfx", "mobileprovision"]

    enum IncomingResult {
        case certificateFile(String)
        /// A temp copy of the IPA, ready to be moved into the library.
        case ipa(URL, String)
        case unsupported(String)
        case unreadable(String, String)
    }

    func handleIncoming(_ url: URL) -> IncomingResult {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
            // With LSSupportsOpeningDocumentsInPlace = NO, iOS copies into Documents/Inbox.
            if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
        }

        if ext == "ipa" {
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("incoming-\(UUID().uuidString).ipa")
            do {
                try FileManager.default.copyItem(at: url, to: temp)
                return .ipa(temp, name)
            } catch {
                return .unreadable(name, error.localizedDescription)
            }
        }
        guard ImportCoordinator.certificateExtensions.contains(ext) else { return .unsupported(name) }

        do {
            let data = try Data(contentsOf: url)
            pendingCertificateFiles.append(PickedFile(name: name, data: data))
            showCertificateImport = true
            return .certificateFile(name)
        } catch {
            return .unreadable(name, error.localizedDescription)
        }
    }

    func takePendingCertificateFiles() -> [PickedFile] {
        let files = pendingCertificateFiles
        pendingCertificateFiles = []
        return files
    }
}
