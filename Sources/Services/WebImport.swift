import Foundation

/// Certificate hand-off from the Get CertSigner web page.
///
/// After installing, the page opens `certsigner://import#<payload>` on the same iPhone. The
/// payload is base64url JSON `{"v":1,"name":…,"p12":…,"profile":…,"password":…}`. It sits in the
/// URL fragment and goes from Safari to the app locally: it is never sent over the network.
enum WebImport {
    struct Payload: Equatable {
        var name: String
        var p12: Data
        var profile: Data
        var password: String
    }

    enum Failure: LocalizedError, Equatable {
        case notAnImportLink
        case damaged

        var errorDescription: String? {
            switch self {
            case .notAnImportLink: return "This link isn't a certificate import."
            case .damaged: return "The certificate link is incomplete. Tap Import again on the Get CertSigner page."
            }
        }
    }

    static let scheme = "certsigner"

    static func isImportLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme && url.host?.lowercased() == "import"
    }

    static func parse(_ url: URL) throws -> Payload {
        guard isImportLink(url) else { throw Failure.notAnImportLink }
        guard let fragment = url.fragment, let json = base64URLDecode(fragment),
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              (object["v"] as? Int) == 1,
              let p12 = (object["p12"] as? String).flatMap({ Data(base64Encoded: $0) }), !p12.isEmpty,
              let profile = (object["profile"] as? String).flatMap({ Data(base64Encoded: $0) }), !profile.isEmpty,
              let password = object["password"] as? String else { throw Failure.damaged }
        let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Payload(name: name.isEmpty ? "Web Certificate" : String(name.prefix(120)), p12: p12, profile: profile, password: password)
    }

    static func base64URLDecode(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        return Data(base64Encoded: base64)
    }
}
