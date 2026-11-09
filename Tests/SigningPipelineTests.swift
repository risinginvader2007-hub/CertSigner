import XCTest
@testable import CertSigner

/// Runs the real signing pipeline (patch → zsign → package) on a generated multi-extension IPA.
/// Fixtures come from .github/workflows/signing-test.yml (CS_FIXTURES): test.ipa, cert.p12 (password "test")
/// and a profile with an EXPLICIT App ID (ABCDE12345.com.other.app) that does not match the app (com.husk.test).
final class SigningPipelineTests: XCTestCase {
    private var fixtures: URL!

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["CS_FIXTURES"] else {
            throw XCTSkip("CS_FIXTURES not set")
        }
        fixtures = URL(fileURLWithPath: path)
    }

    private final class Lines: @unchecked Sendable {
        let lock = NSLock()
        var items: [String] = []
        func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    }

    private func sign(_ mode: SigningMode, bundleIDOverride: String = "", output: String) throws -> (SigningOutput, [String]) {
        var options = SigningOptions()
        options.mode = mode
        options.bundleID = bundleIDOverride
        let profileURL = fixtures.appendingPathComponent("profile.mobileprovision")
        let profile = try ProfileParser.parse(url: profileURL)
        let input = SigningInput(
            ipaURL: fixtures.appendingPathComponent("test.ipa"),
            p12URL: fixtures.appendingPathComponent("cert.p12"),
            profileURL: profileURL,
            password: "test",
            options: options,
            appIDPattern: profile.bundleIDPattern,
            outputURL: fixtures.appendingPathComponent(output),
            certificateName: "CertSigner Test Cert",
            certificateExpiry: nil
        )
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

    /// Compatibility: explicit, mismatching App ID must not block; bundle ID stays; both extensions signed.
    func testCompatibilityKeepsBundleIDAndSignsEveryExtension() throws {
        let (output, lines) = try sign(.compatibility, output: "compat.ipa")
        XCTAssertEqual(output.bundleID, "com.husk.test")
        XCTAssertTrue(lines.contains("Signing mode: Compatibility"))
        XCTAssertTrue(lines.contains("Bundle ID used: com.husk.test"))
        XCTAssertTrue(lines.contains { $0.contains("✓ appex") && $0.contains("PlugIns/Share.appex") })
        XCTAssertTrue(lines.contains { $0.contains("✓ appex") && $0.contains("PlugIns/Widget.appex") })
        XCTAssertTrue(lines.contains { $0.contains("✓ framework") && $0.contains("Kit.framework") })
        XCTAssertTrue(lines.contains { $0.contains("✓ dylib") && $0.contains("libextra.dylib") })
        XCTAssertTrue(lines.contains("Profile App ID: ABCDE12345.com.other.app"))
        XCTAssertTrue(lines.contains("Devices: device-limited, 1 UDID listed"))
        XCTAssertTrue(lines.contains("get-task-allow: present (true)"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtures.appendingPathComponent("compat.ipa").path))
    }

    /// Strict is unchanged: bundle ID rewritten to the explicit App ID, extensions then mismatch and block.
    func testStrictStillBlocksExtensionMismatch() throws {
        XCTAssertThrowsError(try sign(.strict, bundleIDOverride: "com.other.app", output: "strict.ipa")) { error in
            guard case SigningError.extensionMismatch(let ids, let pattern) = error else {
                return XCTFail("Expected extensionMismatch, got \(error)")
            }
            XCTAssertEqual(pattern, "com.other.app")
            XCTAssertEqual(Set(ids), ["com.other.app.share", "com.other.app.widget"])
        }
    }
}
