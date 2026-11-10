import XCTest
@testable import CertSigner

/// The first-launch "Signed with …, expires …" confirmation: read from a profile, shown once per signature.
final class LaunchSignatureTests: XCTestCase {
    func testConfirmationShowsOncePerSignature() throws {
        guard let path = ProcessInfo.processInfo.environment["CS_FIXTURES"] else { throw XCTSkip("CS_FIXTURES not set") }
        let data = try Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("profile.mobileprovision"))
        let info = try XCTUnwrap(LaunchSignature.info(profileData: data))
        print("launch signature: \(LaunchSignature.message(info))")
        XCTAssertEqual(info.certificateName, "iPhone Distribution: CertSigner Test (ABCDE12345)")
        XCTAssertTrue(LaunchSignature.message(info).hasPrefix("Signed with iPhone Distribution: CertSigner Test (ABCDE12345), expires "))
        XCTAssertTrue(LaunchSignature.message(info).contains("2030"))

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "launch-signature-\(UUID().uuidString)"))
        XCTAssertNotNil(LaunchSignature.confirmationIfNew(info, defaults: defaults), "shown on first launch")
        XCTAssertNil(LaunchSignature.confirmationIfNew(info, defaults: defaults), "not shown again")
        var resigned = info
        resigned.key = "another-profile|another certificate"
        XCTAssertNotNil(LaunchSignature.confirmationIfNew(resigned, defaults: defaults), "shown again after re-signing with something else")
        XCTAssertNil(LaunchSignature.confirmationIfNew(nil, defaults: defaults), "no embedded profile: nothing to show")
        XCTAssertNil(LaunchSignature.info(profileData: Data("not a profile".utf8)))
    }
}
