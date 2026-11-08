import Foundation

struct SigningIssue: Identifiable, Hashable {
    enum Severity { case error, warning }

    let severity: Severity
    let message: String
    var id: String { message }
}

/// Pre-flight checks before signing. Plain Swift, unit-testable.
enum SigningValidator {
    /// Matches a bundle ID against a profile App ID pattern ("*", "com.foo.*", or exact).
    static func bundleID(_ bundleID: String, matches pattern: String) -> Bool {
        if pattern == "*" { return true }
        if pattern.hasSuffix("*") {
            let prefix = String(pattern.dropLast())
            return bundleID.hasPrefix(prefix) && bundleID.count > prefix.count
        }
        return bundleID == pattern
    }

    static func isValidBundleID(_ id: String) -> Bool {
        guard !id.isEmpty, !id.hasPrefix("."), !id.hasSuffix("."), !id.contains("..") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        return id.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// The bundle ID to pre-fill: the profile's exact ID for explicit profiles, else the app's own.
    static func suggestedBundleID(appBundleID: String, profile: ProvisioningProfile?) -> String {
        guard let profile, !profile.isWildcard, !profile.bundleIDPattern.isEmpty else { return appBundleID }
        return profile.bundleIDPattern
    }

    static func validate(
        certificate: Certificate?,
        bundleID: String,
        originalBundleID: String,
        extensionIDs: [String],
        removeExtensions: Bool,
        udid: String,
        now: Date = Date()
    ) -> [SigningIssue] {
        var issues: [SigningIssue] = []

        guard let certificate else {
            return [SigningIssue(severity: .error, message: "Choose a certificate first.")]
        }
        guard let profile = certificate.profile else {
            return [SigningIssue(severity: .error, message: "This certificate's provisioning profile can't be read. Re-import it.")]
        }

        if case .expired = certificate.status(now: now) {
            issues.append(SigningIssue(severity: .error, message: "\(certificate.nickname) has expired. Import a valid certificate."))
        }
        if certificate.record.matchesProfile == false {
            issues.append(SigningIssue(severity: .error, message: "The .p12 isn't one of the certificates in this profile. Use the matching pair."))
        }
        if !certificate.hasPassword {
            issues.append(SigningIssue(severity: .warning, message: "No saved password: signing will try an empty password."))
        }

        let pattern = profile.bundleIDPattern
        if !isValidBundleID(bundleID) {
            issues.append(SigningIssue(severity: .error, message: "“\(bundleID)” isn't a valid bundle ID (letters, digits, dots and hyphens only)."))
        } else if !self.bundleID(bundleID, matches: pattern) {
            issues.append(SigningIssue(severity: .error, message: "Bundle ID \(bundleID) isn't allowed by this profile (App ID: \(pattern)). Set the bundle ID to \(profile.isWildcard ? "something matching \(pattern)" : pattern)."))
        }

        if !removeExtensions && !extensionIDs.isEmpty && isValidBundleID(bundleID) {
            let finalIDs = extensionIDs.map { AppBundlePatcher.nestedBundleID($0, oldMain: originalBundleID, newMain: bundleID) }
            let rejected = finalIDs.filter { !self.bundleID($0, matches: pattern) }
            if !rejected.isEmpty {
                issues.append(SigningIssue(
                    severity: .error,
                    message: "\(rejected.count) app extension\(rejected.count == 1 ? "" : "s") (e.g. \(rejected[0])) won't match App ID \(pattern). Turn on “Remove app extensions”, or use a wildcard profile."
                ))
            }
        }

        let trimmedUDID = udid.trimmingCharacters(in: .whitespaces)
        if trimmedUDID.isEmpty {
            issues.append(SigningIssue(severity: .warning, message: "Device not checked: add your UDID in Settings to verify this iPhone is in the profile."))
        } else if profile.containsDevice(trimmedUDID) == false {
            issues.append(SigningIssue(severity: .error, message: "This iPhone's UDID isn't in the profile, so the signed app won't install. Register the device and re-import the profile."))
        }

        return issues
    }
}
