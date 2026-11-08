import Foundation

/// A file the user picked or shared into the app, already read into memory.
struct PickedFile: Equatable {
    let name: String
    let data: Data

    var pathExtension: String { (name as NSString).pathExtension.lowercased() }
}

/// Routes files arriving via "Open in" / Share → CertSigner to the right screen.
/// An imported IPA waiting in the review / sign sheet.
struct ReviewRequest: Identifiable {
    let id = UUID()
    let app: LibraryApp
    /// Quick Sign: start signing with defaults as soon as the sheet opens.
    let quickSign: Bool
    /// Show the install prompt after signing even if "Install when done" is off (Sources → Sign & Install).
    var installWhenDone: Bool = false
}

@MainActor
final class ImportCoordinator: ObservableObject {
    @Published var showCertificateImport = false
    @Published var review: ReviewRequest?

    /// Reads an IPA into the staging library, then opens the review sheet.
    func importIPA(from url: URL, name: String, moveSource: Bool, quickSign: Bool, installWhenDone: Bool = false,
                   library: LibraryStore, toasts: ToastCenter) async {
        guard url.pathExtension.lowercased() == "ipa" else {
            if moveSource { try? FileManager.default.removeItem(at: url) }
            toasts.show("\(name) isn't an .ipa file.", kind: .error)
            return
        }
        do {
            let app = try await library.importIPA(from: url, originalName: name, moveSource: moveSource)
            Haptics.success()
            review = ReviewRequest(app: app, quickSign: quickSign, installWhenDone: installWhenDone)
        } catch {
            if moveSource { try? FileManager.default.removeItem(at: url) }
            toasts.show("Couldn't import \(name): \(error.localizedDescription)", kind: .error)
        }
    }
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
