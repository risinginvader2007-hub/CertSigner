import Foundation

/// What we persist to disk for each certificate pair (files live in its folder).
struct CertificateRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var nickname: String
    var dateAdded: Date
    /// Read from the .p12 at import (nil if iOS couldn't open it).
    var signingCertificate: CertificateSummary?
    /// Whether the .p12 certificate is listed in the profile. nil = unknown.
    var matchesProfile: Bool?
}

enum CertificateStatus: Equatable {
    case valid(daysLeft: Int)
    case expiringSoon(daysLeft: Int)
    case expired
    case unknown

    static let warningThresholdDays = 7

    static func evaluate(expiration: Date?, now: Date = Date()) -> CertificateStatus {
        guard let expiration else { return .unknown }
        if expiration <= now { return .expired }
        let days = Calendar.current.dateComponents([.day], from: now, to: expiration).day ?? 0
        return days < warningThresholdDays ? .expiringSoon(daysLeft: days) : .valid(daysLeft: days)
    }

    var title: String {
        switch self {
        case .valid: return "Valid"
        case .expiringSoon: return "Expiring soon"
        case .expired: return "Expired"
        case .unknown: return "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .valid: return "checkmark.seal.fill"
        case .expiringSoon: return "clock.badge.exclamationmark.fill"
        case .expired: return "xmark.seal.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

/// A certificate pair as shown in the UI: record + freshly parsed profile.
struct Certificate: Identifiable {
    var record: CertificateRecord
    var profile: ProvisioningProfile?
    var hasPassword: Bool

    var id: UUID { record.id }
    var nickname: String { record.nickname }

    /// The earliest of the profile expiry and the signing certificate expiry.
    var expirationDate: Date? {
        let dates = [profile?.expirationDate, record.signingCertificate?.notAfter].compactMap { $0 }
        return dates.min()
    }

    func status(now: Date = Date()) -> CertificateStatus {
        CertificateStatus.evaluate(expiration: expirationDate, now: now)
    }
}
