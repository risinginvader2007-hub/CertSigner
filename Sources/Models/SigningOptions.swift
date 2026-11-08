import Foundation

/// Optional edits applied before signing. Empty strings mean "keep the original".
struct SigningOptions: Equatable, Sendable {
    var displayName: String = ""
    var bundleID: String = ""
    var version: String = ""
    var removeExtensions: Bool = false
    var removeWatchApp: Bool = false

    var trimmedDisplayName: String { displayName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedBundleID: String { bundleID.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedVersion: String { version.trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct SignedApp: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var bundleID: String
    var version: String
    var signedAt: Date
    var certificateID: UUID
    var certificateName: String
    /// Earliest of certificate / profile expiry at signing time.
    var expiresAt: Date?
    var fileName: String
    var iconFileName: String?
    var size: Int64
    var sourceAppID: UUID?
}
