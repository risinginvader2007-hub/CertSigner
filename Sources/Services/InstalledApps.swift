import Foundation

/// What iOS reports about an installed app, read through the private LaunchServices classes via
/// the Objective-C runtime. Every call is guarded with `responds(to:)`; on any iOS where the class
/// or selector is missing (or the sandbox hides it) this returns nil and callers fall back to
/// "unknown", so it can never crash.
enum InstalledApps {
    struct Info: Equatable {
        var isInstalled: Bool
        var isPlaceholder: Bool
        var version: String?
        var teamID: String?
    }

    static func info(bundleID: String) -> Info? {
        guard let proxyClass = NSClassFromString("LSApplicationProxy") as? NSObject.Type else { return nil }
        let factory = NSSelectorFromString("applicationProxyForIdentifier:")
        guard proxyClass.responds(to: factory),
              let proxy = proxyClass.perform(factory, with: bundleID)?.takeUnretainedValue() as? NSObject else {
            return nil
        }
        func value(_ key: String) -> Any? {
            proxy.responds(to: NSSelectorFromString(key)) ? proxy.value(forKey: key) : nil
        }
        let installed = (value("isInstalled") as? Bool) ?? workspaceSaysInstalled(bundleID) ?? false
        return Info(
            isInstalled: installed,
            isPlaceholder: (value("isPlaceholder") as? Bool) ?? false,
            version: value("shortVersionString") as? String,
            teamID: value("teamID") as? String
        )
    }

    /// `LSApplicationWorkspace.defaultWorkspace.applicationIsInstalled:` (nil when unavailable).
    private static func workspaceSaysInstalled(_ bundleID: String) -> Bool? {
        guard let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type else { return nil }
        let defaultSelector = NSSelectorFromString("defaultWorkspace")
        let installedSelector = NSSelectorFromString("applicationIsInstalled:")
        guard workspaceClass.responds(to: defaultSelector),
              let workspace = workspaceClass.perform(defaultSelector)?.takeUnretainedValue() as? NSObject,
              workspace.responds(to: installedSelector) else { return nil }
        typealias Method = @convention(c) (NSObject, Selector, NSString) -> Bool
        let implementation = workspace.method(for: installedSelector)
        let call = unsafeBitCast(implementation, to: Method.self)
        return call(workspace, installedSelector, bundleID as NSString)
    }
}
