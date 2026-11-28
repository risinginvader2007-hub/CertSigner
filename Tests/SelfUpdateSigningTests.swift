import XCTest
@testable import CertSigner

/// Signs the real, unsigned CertSigner release IPA (CI downloads it as certsigner.ipa into the
/// fixtures) the way the in-app updater does and the way a normal signing job does, with the test
/// certificate. Each run's full log (zsign output included) is saved next to the fixtures and
/// printed by the workflow, so the two can be compared line by line.
final class SelfUpdateSigningTests: XCTestCase {
    private var fixtures: URL!
    private var ipa: URL!

    override func setUpWithError() throws {
        // CI sets CS_SELF_UPDATE_REQUIRED when it downloaded the release IPA: then any missing
        // input is a failure, never a silent skip (checked before either skip below).
        let environment = ProcessInfo.processInfo.environment
        let required = environment["CS_SELF_UPDATE_REQUIRED"] == "1"
        guard let path = environment["CS_FIXTURES"] else {
            if required { throw MissingFixture(what: "CS_FIXTURES is not set") }
            throw XCTSkip("CS_FIXTURES not set")
        }
        fixtures = URL(fileURLWithPath: path)
        ipa = fixtures.appendingPathComponent("certsigner.ipa")
        guard FileManager.default.fileExists(atPath: ipa.path) else {
            if required { throw MissingFixture(what: "certsigner.ipa is missing from \(path)") }
            throw XCTSkip("no certsigner.ipa fixture (this repository has never published a release)")
        }
    }

    private struct MissingFixture: Error, CustomStringConvertible {
        let what: String
        var description: String { "CI supplied the release IPA, but \(what)" }
    }

    private final class Lines: @unchecked Sendable {
        let lock = NSLock()
        var items: [String] = []
        func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    }

    private func sign(_ options: SigningOptions, output: String) throws -> (SigningOutput, [String]) {
        let profileURL = fixtures.appendingPathComponent("profile.mobileprovision")
        let profile = try ProfileParser.parse(url: profileURL)
        let input = SigningInput(ipaURL: ipa, p12URL: fixtures.appendingPathComponent("cert.p12"),
                                 profileURL: profileURL, password: "test", options: options,
                                 appIDPattern: profile.bundleIDPattern,
                                 outputURL: fixtures.appendingPathComponent(output),
                                 certificateName: "CertSigner Test Cert", certificateExpiry: nil)
        let lines = Lines()
        defer {
            try? lines.items.joined(separator: "\n")
                .write(to: fixtures.appendingPathComponent(output + ".log"), atomically: true, encoding: .utf8)
        }
        let result = try SigningWorker.run(input) { event in
            if case .log(let text, let isError) = event { lines.add((isError ? "[error] " : "") + text) }
        }
        return (result, lines.items)
    }

    /// A normal Compatibility job on the same IPA (the comparison).
    func testNormalJobSignsTheReleaseIPA() throws {
        var options = SigningOptions()
        options.mode = .compatibility
        let (output, _) = try sign(options, output: "self-normal.ipa")
        XCTAssertEqual(output.bundleID, "com.certsigner.app")
    }

    /// The release IPA ships OpenSSL.framework/OpenSSL read-only (0555); signing must still sign it.
    func testReadOnlyFrameworkBinaryIsSigned() throws {
        var options = SigningOptions()
        options.mode = .compatibility
        let (_, lines) = try sign(options, output: "self-readonly.ipa")
        XCTAssertTrue(lines.contains { $0.hasPrefix("Made ") && $0.contains("writable") })
        XCTAssertFalse(lines.contains { $0.contains("non-Mach-O") }, "zsign must not skip a program file")
        XCTAssertTrue(lines.contains { $0.contains("✓ framework") && $0.contains("OpenSSL.framework") })
    }

    /// A copy installed with the IPA's own bundle ID: Compatibility, nothing rewritten.
    func testUpdateKeepsTheIPABundleIDInCompatibilityMode() throws {
        let running = RunningSignature(bundleID: "com.certsigner.app", displayName: "CertSigner", teamID: "ABCDE12345",
                                       teamName: nil, certificates: [])
        let options = UpdateService.signingOptions(for: running)
        XCTAssertEqual(options.effectiveMode, .compatibility)
        let (output, _) = try sign(options, output: "self-update-compat.ipa")
        XCTAssertEqual(output.bundleID, "com.certsigner.app")
    }

    /// The updater's exact options, for a copy installed under the profile's explicit App ID.
    func testUpdatePathSignsTheReleaseIPA() throws {
        let running = RunningSignature(bundleID: "com.other.app", displayName: "CertSigner", teamID: "ABCDE12345",
                                       teamName: nil, certificates: [])
        let (output, lines) = try sign(UpdateService.signingOptions(for: running), output: "self-update.ipa")
        XCTAssertEqual(output.bundleID, "com.other.app")
        XCTAssertTrue(lines.contains { $0.hasPrefix("Signed ") })
    }
}
