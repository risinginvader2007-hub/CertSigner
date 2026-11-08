import Foundation

/// Thin Swift wrapper over the vendored zsign (Vendor/ZSignBridge).
enum ZSignService {
    /// Signs an extracted .app in place. Blocking; call off the main thread.
    /// `log` is called on the signing thread for every zsign log line.
    static func sign(
        appURL: URL,
        p12URL: URL,
        password: String,
        profileURL: URL,
        entitlementsURL: URL? = nil,
        log: @escaping (String, Bool) -> Void
    ) throws {
        try ZSignBridge.sign(
            appPath: appURL.path,
            p12Path: p12URL.path,
            password: password,
            provisionPath: profileURL.path,
            entitlementsPath: entitlementsURL?.path,
            log: { line, isError in log(line, isError) }
        )
    }
}
