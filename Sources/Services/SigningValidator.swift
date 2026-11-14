import Foundation

struct SigningIssue: Identifiable, Hashable {
    enum Severity { case error, warning }

    let severity: Severity
    let message: String
    var id: String { message }
}

/// One row of the review sheet's checklist.
struct PreSignCheck: Identifiable, Hashable {
    enum State { case pass, fail, unknown }

    let id: String
    let title: String
    let detail: String
    let state: State
}

/// Pre-flight checks before signing. Plain Swift, unit-testable.
enum SigningValidator {
    /// The four checks shown in the review sheet (independent of the blocking issues list).
    static func checks(
        certificate: Certificate?,
        bundleID: String,
        originalBundleID: String,
        extensionIDs: [String],
        removeExtensions: Bool,
        udid: String,
        mode: SigningMode = .strict,
        now: Date = Date(),
        ownBundleID: String = Bundle.main.bundleIdentifier ?? ""
    ) -> [PreSignCheck] {
        guard let certificate, let profile = certificate.profile else {
            return [PreSignCheck(id: "cert", title: "Certificate", detail: "No usable certificate selected.", state: .fail)]
        }
        var result: [PreSignCheck] = []

        switch certificate.status(now: now) {
        case .expired:
            result.append(PreSignCheck(id: "expiry", title: "Not expired", detail: "Expired \(certificate.expirationDate?.shortDate ?? "")", state: .fail))
        case .expiringSoon(let days):
            result.append(PreSignCheck(id: "expiry", title: "Not expired", detail: "Expires in \(days) day\(days == 1 ? "" : "s")", state: .pass))
        case .valid(let days):
            result.append(PreSignCheck(id: "expiry", title: "Not expired", detail: "\(days) days left", state: .pass))
        case .unknown:
            result.append(PreSignCheck(id: "expiry", title: "Not expired", detail: "Expiry date unknown", state: .unknown))
        }

        switch certificate.record.matchesProfile {
        case .some(true):
            result.append(PreSignCheck(id: "pair", title: ".p12 matches profile", detail: "The certificate is listed in the profile", state: .pass))
        case .some(false):
            result.append(PreSignCheck(id: "pair", title: ".p12 matches profile", detail: "This .p12 isn't in the profile", state: .fail))
        case .none:
            result.append(PreSignCheck(id: "pair", title: ".p12 matches profile", detail: "Couldn't verify (password or format)", state: .unknown))
        }

        let pattern = profile.bundleIDPattern
        if mode == .compatibility {
            // No App ID matching in Compatibility: just a neutral note.
            result.append(PreSignCheck(id: "bundle", title: "Bundle ID", detail: "Keeps the original bundle ID (\(originalBundleID))", state: .pass))
            appendDeviceCheck(to: &result, profile: profile, udid: udid)
            return result
        }
        let replacesSelf = wouldReplaceCertSigner(bundleID: bundleID, originalBundleID: originalBundleID, ownBundleID: ownBundleID)
        var bundleOK = !replacesSelf && isValidBundleID(bundleID) && self.bundleID(bundleID, matches: pattern)
        var bundleDetail = replacesSelf ? "\(bundleID) is CertSigner's own bundle ID"
            : bundleOK ? "\(bundleID) fits \(pattern)" : "\(bundleID) doesn't fit \(pattern)"
        if bundleOK && !removeExtensions && !extensionIDs.isEmpty {
            let finals = extensionIDs.map { AppBundlePatcher.nestedBundleID($0, oldMain: originalBundleID, newMain: bundleID) }
            if finals.contains(where: { !self.bundleID($0, matches: pattern) }) {
                bundleOK = false
                bundleDetail = "App extensions don't fit \(pattern)"
            }
        }
        result.append(PreSignCheck(id: "bundle", title: "Bundle ID allowed", detail: bundleDetail, state: bundleOK ? .pass : .fail))
        appendDeviceCheck(to: &result, profile: profile, udid: udid)
        return result
    }

    private static func appendDeviceCheck(to result: inout [PreSignCheck], profile: ProvisioningProfile, udid: String) {
        let trimmed = udid.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            result.append(PreSignCheck(id: "device", title: "This iPhone in profile", detail: "Add your UDID in Settings to check", state: .unknown))
        } else if profile.containsDevice(trimmed) == true {
            result.append(PreSignCheck(id: "device", title: "This iPhone in profile",
                                       detail: profile.provisionsAllDevices ? "Enterprise profile: all devices" : "UDID found",
                                       state: .pass))
        } else {
            result.append(PreSignCheck(id: "device", title: "This iPhone in profile", detail: "UDID not in the profile", state: .fail))
        }
    }

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
    /// Never CertSigner's own bundle ID for another app (installing it would replace CertSigner).
    static func suggestedBundleID(appBundleID: String, profile: ProvisioningProfile?,
                                  ownBundleID: String = Bundle.main.bundleIdentifier ?? "") -> String {
        guard let profile, !profile.isWildcard, !profile.bundleIDPattern.isEmpty else { return appBundleID }
        if wouldReplaceCertSigner(bundleID: profile.bundleIDPattern, originalBundleID: appBundleID, ownBundleID: ownBundleID) {
            return appBundleID
        }
        return profile.bundleIDPattern
    }

    /// True when signing `originalBundleID` as `bundleID` would install over CertSigner itself.
    /// Re-signing CertSigner's own IPA (its release ID or this copy's ID) is allowed.
    static func wouldReplaceCertSigner(bundleID: String, originalBundleID: String, ownBundleID: String) -> Bool {
        guard !ownBundleID.isEmpty, bundleID == ownBundleID else { return false }
        return originalBundleID != ownBundleID && originalBundleID != UpdateRules.bundleID
    }

    /// Compatibility with an explicit profile for another App ID: the app keeps its bundle ID but is
    /// signed with the profile's application-identifier, so it shares that app's identity.
    static func sharedIdentityWarning(profile: ProvisioningProfile, originalBundleID: String, ownBundleID: String) -> String? {
        let pattern = profile.bundleIDPattern
        guard !profile.isWildcard, !pattern.isEmpty, pattern != originalBundleID else { return nil }
        let appID = profile.applicationIdentifier.isEmpty ? pattern : profile.applicationIdentifier
        let owner = pattern == ownBundleID ? " (CertSigner)" : ""
        return "This app will share the identity of \(appID)\(owner): Keychain, App Groups and system UI such as Now Playing may resolve to that app. Signing still works."
    }

    static func validate(
        certificate: Certificate?,
        bundleID: String,
        originalBundleID: String,
        extensionIDs: [String],
        removeExtensions: Bool,
        udid: String,
        mode: SigningMode = .strict,
        now: Date = Date(),
        ownBundleID: String = Bundle.main.bundleIdentifier ?? ""
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
        // Compatibility keeps the original bundle ID: no App ID matching and nothing blocks; with an
        // explicit profile for another App ID it only warns that the identity is shared.
        let strict = mode == .strict
        if !strict {
            if let warning = sharedIdentityWarning(profile: profile, originalBundleID: originalBundleID, ownBundleID: ownBundleID) {
                issues.append(SigningIssue(severity: .warning, message: warning))
            }
        } else if wouldReplaceCertSigner(bundleID: bundleID, originalBundleID: originalBundleID, ownBundleID: ownBundleID) {
            issues.append(SigningIssue(severity: .error, message: "\(bundleID) is CertSigner's own bundle ID: installing this app would replace CertSigner. Use Compatibility mode, or give the app a bundle ID of its own."))
        } else if !isValidBundleID(bundleID) {
            issues.append(SigningIssue(severity: .error, message: "“\(bundleID)” isn't a valid bundle ID (letters, digits, dots and hyphens only)."))
        } else if !self.bundleID(bundleID, matches: pattern) {
            if !profile.isWildcard && wouldReplaceCertSigner(bundleID: pattern, originalBundleID: originalBundleID, ownBundleID: ownBundleID) {
                issues.append(SigningIssue(severity: .error, message: "This profile's App ID (\(pattern)) is CertSigner's own, so Strict mode can't sign other apps with it. Use Compatibility mode."))
            } else {
                issues.append(SigningIssue(severity: .error, message: "Bundle ID \(bundleID) isn't allowed by this profile (App ID: \(pattern)). Set the bundle ID to \(profile.isWildcard ? "something matching \(pattern)" : pattern)."))
            }
        }

        if strict && !removeExtensions && !extensionIDs.isEmpty && isValidBundleID(bundleID) {
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
