import Foundation

struct ProvisioningProfile {
    var name: String
    var teamID: String
    var appID: String
    var expiration: Date?
    var deviceCount: Int

    var isExpired: Bool {
        guard let expiration else { return false }
        return expiration < Date()
    }

    /// A .mobileprovision file is a signed blob that contains an XML plist.
    /// We find the plist inside it and read it.
    static func parse(url: URL) -> ProvisioningProfile? {
        guard let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8)) else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
        else { return nil }

        let name = plist["Name"] as? String ?? "Unknown"
        let teamID = (plist["TeamIdentifier"] as? [String])?.first ?? "Unknown"
        let ents = plist["Entitlements"] as? [String: Any]
        let appID = ents?["application-identifier"] as? String ?? "Unknown"
        let exp = plist["ExpirationDate"] as? Date
        let devices = (plist["ProvisionedDevices"] as? [String])?.count ?? 0
        return ProvisioningProfile(name: name, teamID: teamID, appID: appID, expiration: exp, deviceCount: devices)
    }
}
