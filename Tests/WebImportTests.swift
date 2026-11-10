import XCTest
@testable import CertSigner

/// certsigner://import#… from the Get CertSigner page: parsed exactly, rejected when damaged,
/// and the certificate it carries imports into the store without duplicating.
@MainActor
final class WebImportTests: XCTestCase {
    private func link(_ object: [String: Any]) throws -> URL {
        let data = try JSONSerialization.data(withJSONObject: object)
        let payload = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return try XCTUnwrap(URL(string: "certsigner://import#" + payload))
    }

    func testParsesAndRejects() throws {
        let p12 = Data([1, 2, 250, 251]), profile = Data("<plist/>".utf8)
        let url = try link(["v": 1, "name": " My Cert ", "p12": p12.base64EncodedString(), "profile": profile.base64EncodedString(), "password": "p+w/=d"])
        XCTAssertTrue(WebImport.isImportLink(url))
        XCTAssertEqual(try WebImport.parse(url), WebImport.Payload(name: "My Cert", p12: p12, profile: profile, password: "p+w/=d"))
        XCTAssertThrowsError(try WebImport.parse(URL(string: "certsigner://import#abc")!))
        XCTAssertThrowsError(try WebImport.parse(try link(["v": 2, "p12": "AQ==", "profile": "AQ==", "password": ""])))
        XCTAssertFalse(WebImport.isImportLink(URL(fileURLWithPath: "/tmp/a.p12")))
    }

    func testImportsTheFixtureCertificate() async throws {
        guard let path = ProcessInfo.processInfo.environment["CS_FIXTURES"] else { throw XCTSkip("CS_FIXTURES not set") }
        let folder = URL(fileURLWithPath: path)
        let p12 = try Data(contentsOf: folder.appendingPathComponent("cert.p12"))
        let profile = try Data(contentsOf: folder.appendingPathComponent("profile.mobileprovision"))
        let payload = try WebImport.parse(try link(["v": 1, "name": "Web Test", "p12": p12.base64EncodedString(),
                                                    "profile": profile.base64EncodedString(), "password": "test"]))
        let store = CertificateStore()
        let result = try await store.importCertificate(nickname: payload.name, p12Data: payload.p12, profileData: payload.profile, password: payload.password)
        print("web import: \(result.certificate.displayName), warning: \(result.warning ?? "none")")
        XCTAssertEqual(store.existing(p12Data: p12, profileData: profile)?.id, result.certificate.id, "a second tap finds it instead of duplicating")
        store.delete(result.certificate.id)
    }
}
