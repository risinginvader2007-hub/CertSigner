import Foundation

/// Fields we read out of an X.509 certificate.
struct CertificateSummary: Codable, Equatable, Sendable {
    var commonName: String?
    var organization: String?
    var organizationalUnit: String?
    var notBefore: Date?
    var notAfter: Date?
}

/// Minimal DER walker for X.509 certificates. Only reads what we display.
enum DERCertificateParser {
    private struct Node {
        let tag: UInt8
        let start: Int // first byte of value
        let end: Int   // one past last byte of value
    }

    private static let oidCommonName: [UInt8] = [0x55, 0x04, 0x03]
    private static let oidOrganization: [UInt8] = [0x55, 0x04, 0x0A]
    private static let oidOrgUnit: [UInt8] = [0x55, 0x04, 0x0B]

    static func parse(_ der: Data) -> CertificateSummary? {
        let bytes = [UInt8](der)
        guard let cert = node(in: bytes, at: 0), cert.tag == 0x30 else { return nil }
        let certChildren = children(in: bytes, of: cert)
        guard let tbs = certChildren.first, tbs.tag == 0x30 else { return nil }

        var fields = children(in: bytes, of: tbs)
        if let first = fields.first, first.tag == 0xA0 { fields.removeFirst() } // explicit version
        // serial, signature algorithm, issuer, validity, subject
        guard fields.count >= 5 else { return nil }
        let validity = fields[3]
        let subject = fields[4]

        var summary = CertificateSummary()
        let times = children(in: bytes, of: validity)
        if times.count >= 2 {
            summary.notBefore = parseTime(bytes, times[0])
            summary.notAfter = parseTime(bytes, times[1])
        }

        for set in children(in: bytes, of: subject) {
            for attribute in children(in: bytes, of: set) {
                let parts = children(in: bytes, of: attribute)
                guard parts.count >= 2, parts[0].tag == 0x06 else { continue }
                let oid = Array(bytes[parts[0].start..<parts[0].end])
                let value = String(decoding: bytes[parts[1].start..<parts[1].end], as: UTF8.self)
                if oid == oidCommonName { summary.commonName = value }
                else if oid == oidOrganization { summary.organization = value }
                else if oid == oidOrgUnit { summary.organizationalUnit = value }
            }
        }
        return summary
    }

    private static func node(in bytes: [UInt8], at offset: Int) -> Node? {
        guard offset + 1 < bytes.count else { return nil }
        let tag = bytes[offset]
        var index = offset + 1
        var length = Int(bytes[index])
        index += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count > 0, count <= 4, index + count <= bytes.count else { return nil }
            length = 0
            for _ in 0..<count {
                length = (length << 8) | Int(bytes[index])
                index += 1
            }
        }
        guard length >= 0, index + length <= bytes.count else { return nil }
        return Node(tag: tag, start: index, end: index + length)
    }

    private static func children(in bytes: [UInt8], of parent: Node) -> [Node] {
        var result: [Node] = []
        var offset = parent.start
        while offset < parent.end, let child = node(in: bytes, at: offset), child.end <= parent.end {
            result.append(child)
            offset = child.end
        }
        return result
    }

    private static func parseTime(_ bytes: [UInt8], _ node: Node) -> Date? {
        let text = String(decoding: bytes[node.start..<node.end], as: UTF8.self)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        switch node.tag {
        case 0x17: formatter.dateFormat = "yyMMddHHmmss'Z'"   // UTCTime
        case 0x18: formatter.dateFormat = "yyyyMMddHHmmss'Z'" // GeneralizedTime
        default: return nil
        }
        return formatter.date(from: text)
    }
}
