import Foundation

/// How a job treats the bundle ID and the profile's App ID.
enum SigningMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Keep the original bundle ID and every extension / framework / dylib; never block on an
    /// App ID mismatch (how FlareStore's signer behaves).
    case compatibility
    /// Rewrite the bundle ID to fit the profile and enforce the App ID checks.
    case strict

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compatibility: return "Compatibility"
        case .strict: return "Strict"
        }
    }

    var detail: String {
        switch self {
        case .compatibility: return "Keeps the original bundle ID and all extensions; signs everything with your certificate."
        case .strict: return "Rewrites the bundle ID to match the profile and blocks App ID mismatches."
        }
    }

    /// The mode chosen in Settings (Compatibility unless changed).
    static var defaultMode: SigningMode {
        UserDefaults.standard.string(forKey: SettingsKeys.signingMode).flatMap(SigningMode.init(rawValue:)) ?? .compatibility
    }
}

/// Optional edits applied before signing. Empty strings mean "keep the original".
struct SigningOptions: Equatable, Sendable, Codable {
    var displayName: String = ""
    var bundleID: String = ""
    var version: String = ""
    var removeExtensions: Bool = false
    var removeWatchApp: Bool = false
    /// nil = jobs saved before signing modes existed (they ran Strict).
    var mode: SigningMode? = nil

    var effectiveMode: SigningMode { mode ?? .strict }

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

    func status(now: Date = Date()) -> CertificateStatus {
        CertificateStatus.evaluate(expiration: expiresAt, now: now)
    }

    func needsAttention(now: Date = Date()) -> Bool {
        switch status(now: now) {
        case .expired, .expiringSoon: return true
        case .valid, .unknown: return false
        }
    }
}

extension Certificate {
    /// Fraction of the profile lifetime left (1 = brand new, 0 = expired).
    var lifetimeRemaining: Double? {
        guard let start = profile?.creationDate, let end = expirationDate, end > start else { return nil }
        return min(max(end.timeIntervalSinceNow / end.timeIntervalSince(start), 0), 1)
    }

    var daysLeft: Int? {
        guard let end = expirationDate else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0)
    }

    var needsAttention: Bool {
        switch status() {
        case .expired, .expiringSoon: return true
        case .valid, .unknown: return false
        }
    }
}
