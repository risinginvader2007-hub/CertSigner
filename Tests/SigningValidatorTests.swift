import XCTest
@testable import CertSigner

/// Bundle ID rules around explicit profiles: Strict never targets CertSigner's own bundle ID, and
/// Compatibility only warns (never blocks) when the app will share another App ID's identity.
final class SigningValidatorTests: XCTestCase {
    private let own = "app.serval455.apricot580"

    private func profile(_ appID: String) -> ProvisioningProfile {
        ProvisioningProfile(name: "Test", uuid: "u", teamID: "A2V52T4RD8", teamName: "Team", appIDName: "",
                            applicationIdentifier: appID, creationDate: nil,
                            expirationDate: Date().addingTimeInterval(86_400 * 30), devices: [],
                            provisionsAllDevices: true, entitlements: [:], developerCertificates: [], platforms: ["iOS"])
    }

    private func certificate(_ appID: String) -> Certificate {
        Certificate(record: CertificateRecord(id: UUID(), nickname: "Test", dateAdded: Date(), signingCertificate: nil,
                                              matchesProfile: true),
                    profile: profile(appID), hasPassword: true)
    }

    private func issues(_ mode: SigningMode, appID: String, bundleID: String, original: String = "streaming.octave.dev") -> [SigningIssue] {
        SigningValidator.validate(certificate: certificate(appID), bundleID: bundleID, originalBundleID: original,
                                  extensionIDs: [], removeExtensions: false, udid: "", mode: mode, ownBundleID: own)
    }

    func testStrictRefusesCertSignersOwnBundleID() {
        let errors = issues(.strict, appID: "A2V52T4RD8.\(own)", bundleID: own).filter { $0.severity == .error }
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].message.contains("would replace CertSigner"), errors[0].message)

        // With the app's own ID, the explicit profile owned by CertSigner explains to use Compatibility.
        let other = issues(.strict, appID: "A2V52T4RD8.\(own)", bundleID: "streaming.octave.dev").filter { $0.severity == .error }
        XCTAssertTrue(other.contains { $0.message.contains("Use Compatibility mode") }, "\(other)")

        let checks = SigningValidator.checks(certificate: certificate("A2V52T4RD8.\(own)"), bundleID: own,
                                             originalBundleID: "streaming.octave.dev", extensionIDs: [], removeExtensions: false,
                                             udid: "", mode: .strict, ownBundleID: own)
        XCTAssertEqual(checks.first { $0.id == "bundle" }?.state, .fail)
    }

    func testReSigningCertSignerItselfIsStillAllowed() {
        XCTAssertFalse(SigningValidator.wouldReplaceCertSigner(bundleID: own, originalBundleID: own, ownBundleID: own))
        XCTAssertFalse(SigningValidator.wouldReplaceCertSigner(bundleID: own, originalBundleID: UpdateRules.bundleID, ownBundleID: own))
        XCTAssertTrue(SigningValidator.wouldReplaceCertSigner(bundleID: own, originalBundleID: "streaming.octave.dev", ownBundleID: own))
        XCTAssertFalse(SigningValidator.wouldReplaceCertSigner(bundleID: "com.other", originalBundleID: "streaming.octave.dev", ownBundleID: own))
    }

    func testSuggestedBundleIDNeverProposesCertSignersOwnID() {
        XCTAssertEqual(SigningValidator.suggestedBundleID(appBundleID: "streaming.octave.dev", profile: profile("A2V52T4RD8.\(own)"), ownBundleID: own),
                       "streaming.octave.dev")
        XCTAssertEqual(SigningValidator.suggestedBundleID(appBundleID: "streaming.octave.dev", profile: profile("A2V52T4RD8.com.music.app"), ownBundleID: own),
                       "com.music.app", "an explicit profile for another app is still proposed")
        XCTAssertEqual(SigningValidator.suggestedBundleID(appBundleID: "streaming.octave.dev", profile: profile("A2V52T4RD8.*"), ownBundleID: own),
                       "streaming.octave.dev")
    }

    func testCompatibilityWarnsAboutSharedIdentityButNeverBlocks() {
        let result = issues(.compatibility, appID: "A2V52T4RD8.\(own)", bundleID: "streaming.octave.dev")
        XCTAssertTrue(result.allSatisfy { $0.severity == .warning }, "\(result)")
        let warning = result.first { $0.message.contains("share the identity") }
        XCTAssertNotNil(warning)
        XCTAssertTrue(warning?.message.contains("A2V52T4RD8.\(own) (CertSigner)") == true, warning?.message ?? "")
        XCTAssertTrue(warning?.message.contains("Now Playing") == true)

        // No warning when the profile matches the app, or is a wildcard.
        XCTAssertFalse(issues(.compatibility, appID: "A2V52T4RD8.streaming.octave.dev", bundleID: "streaming.octave.dev")
            .contains { $0.message.contains("share the identity") })
        XCTAssertFalse(issues(.compatibility, appID: "A2V52T4RD8.*", bundleID: "streaming.octave.dev")
            .contains { $0.message.contains("share the identity") })
    }

    func testSignedIdentityMismatchDetection() {
        XCTAssertTrue(SignedIdentity.appIDMismatch(appID: "A2V52T4RD8.\(own)", bundleID: "streaming.octave.dev"))
        XCTAssertFalse(SignedIdentity.appIDMismatch(appID: "A2V52T4RD8.streaming.octave.dev", bundleID: "streaming.octave.dev"))
        XCTAssertFalse(SignedIdentity.appIDMismatch(appID: "A2V52T4RD8.*", bundleID: "streaming.octave.dev"))
        let line = SignedIdentity.summary(["application-identifier": "A2V52T4RD8.\(own)",
                                           "com.apple.developer.team-identifier": "A2V52T4RD8",
                                           "keychain-access-groups": ["A2V52T4RD8.*"],
                                           "get-task-allow": true], bundleID: "streaming.octave.dev")
        XCTAssertTrue(line.contains("(differs from the bundle ID: shared identity)"))
        XCTAssertTrue(line.contains("keychain: A2V52T4RD8.*"))
        XCTAssertTrue(line.contains("app groups: none"))
        XCTAssertTrue(line.contains("4 entitlements"))
    }
}
