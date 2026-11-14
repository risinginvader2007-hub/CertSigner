import Darwin
import UIKit

/// Diagnostics for the app icon change (Settings → App Icon), written to the app log.
///
/// Logs the environment, which API is called and with what, the completion result, and the app
/// lifecycle events for `window` seconds after the call. A marker file records the same events as
/// they happen; if the process dies inside the window, the next launch finds the marker and logs
/// how the previous run ended (crash signal, terminated with notice, or killed without notice).
enum IconChangeDiagnostics {
    /// How long after a change lifecycle events are recorded.
    static let window: TimeInterval = 20

    static var markerURL: URL {
        AppLog.fileURL.deletingLastPathComponent().appendingPathComponent("icon-change.marker")
    }

    private static var observers: [NSObjectProtocol] = []
    private static var generation = 0
    private static var started = Date()
    private static var previousHandlers: [Int32: (@convention(c) (Int32) -> Void)?] = [:]
    private static let crashSignals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGTRAP, SIGILL, SIGFPE]

    static func log(_ message: String) { AppLog.infoNow(message) }

    /// Main thread, right before the system call.
    static func begin(name: String?, privateAvailable: Bool) {
        let app = UIApplication.shared
        let device = UIDevice.current
        let alternates = (Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])?["CFBundleAlternateIcons"] as? [String: Any]
        log("Icon change requested: \(describe(name)) (current: \(describe(app.alternateIconName)))")
        log("Icon change environment: \(device.systemName) \(device.systemVersion), \(modelIdentifier()), "
            + "supportsAlternateIcons \(app.supportsAlternateIcons), state \(stateName(app.applicationState)), "
            + "declared alternate icons: \(alternates?.keys.sorted().joined(separator: ", ") ?? "none")")
        log("Icon change: private _setAlternateIconName:completionHandler: \(privateAvailable ? "available" : "MISSING")")

        stop()
        generation += 1
        started = Date()
        let header = "icon change to \(describe(name)) at \(ISO8601DateFormatter().string(from: started)) "
            + "on \(device.systemName) \(device.systemVersion)\n"
        FileManager.default.createFile(atPath: markerURL.path, contents: Data(header.utf8))
        installCrashHandlers()

        let events: [(Notification.Name, String)] = [
            (UIApplication.willResignActiveNotification, "willResignActive"),
            (UIApplication.didEnterBackgroundNotification, "didEnterBackground"),
            (UIApplication.willEnterForegroundNotification, "willEnterForeground"),
            (UIApplication.didBecomeActiveNotification, "didBecomeActive"),
            (UIApplication.willTerminateNotification, "willTerminate"),
            (UIApplication.didReceiveMemoryWarningNotification, "didReceiveMemoryWarning"),
        ]
        observers = events.map { notification, label in
            NotificationCenter.default.addObserver(forName: notification, object: nil, queue: .main) { _ in
                record(label)
            }
        }
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + window) {
            guard current == generation else { return }
            record("still running; diagnostics stopped")
            stop()
            try? FileManager.default.removeItem(at: markerURL)
        }
    }

    /// The system call's completion handler fired (any thread).
    static func completion(path: String, error: Error?) {
        let result: String
        if let error = error as NSError? {
            result = "error \(error.domain) \(error.code): \(error.localizedDescription)"
        } else {
            result = "success"
        }
        record("completion (\(path) API): \(result)")
    }

    /// Records one event in the log and in the marker.
    static func record(_ event: String) {
        let elapsed = String(format: "+%.2f s", Date().timeIntervalSince(started))
        log("Icon change \(elapsed): \(event)")
        if let handle = try? FileHandle(forWritingTo: markerURL) {
            handle.seekToEndOfFile()
            handle.write(Data("event \(elapsed): \(event)\n".utf8))
            try? handle.close()
        }
    }

    /// At launch: if the previous run died during an icon change, log how.
    static func reportPreviousRun() {
        guard let text = try? String(contentsOf: markerURL, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: markerURL)
        log("Previous run ended during an icon change. Verdict: \(verdict(for: text))\nMarker:\n\(text)")
    }

    /// How the previous run ended, from the marker's events.
    static func verdict(for marker: String) -> String {
        if let line = marker.split(separator: "\n").first(where: { $0.contains("crash signal") }) {
            return "CRASHED (\(line.trimmingCharacters(in: .whitespaces))). Look for a CertSigner .ips in "
                + "Settings → Privacy & Security → Analytics & Improvements → Analytics Data."
        }
        if marker.contains("willTerminate") {
            return "TERMINATED by the system with notice (willTerminate)."
        }
        if marker.contains("didEnterBackground") {
            return "KILLED WITHOUT NOTICE after going to the background (SIGKILL from the system, no crash)."
        }
        return "ENDED WITHOUT ANY LIFECYCLE EVENT OR CATCHABLE CRASH (SIGKILL while in the foreground)."
    }

    private static func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        for (signalNumber, handler) in previousHandlers {
            signal(signalNumber, handler)
        }
        previousHandlers = [:]
        if iconCrashFD >= 0 {
            close(iconCrashFD)
            iconCrashFD = -1
        }
    }

    private static func installCrashHandlers() {
        iconCrashFD = open(markerURL.path, O_WRONLY | O_APPEND)
        for signalNumber in crashSignals {
            let previous: (@convention(c) (Int32) -> Void)? = signal(signalNumber, iconCrashSignalHandler)
            previousHandlers.updateValue(previous, forKey: signalNumber)
        }
    }

    private static func describe(_ name: String?) -> String { name ?? "nil (primary)" }

    private static func stateName(_ state: UIApplication.State) -> String {
        switch state {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }

    private static func modelIdentifier() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// File descriptor of the marker while a change is being watched (-1 otherwise). Global so the
/// signal handler can reach it without capturing anything.
private var iconCrashFD: Int32 = -1

/// Appends "crash signal N" to the marker using only async-signal-safe calls, then lets the
/// default action run (so iOS still writes its crash report).
private func iconCrashSignalHandler(_ signalNumber: Int32) {
    if iconCrashFD >= 0 {
        let prefix: StaticString = "event: crash signal "
        _ = write(iconCrashFD, prefix.utf8Start, prefix.utf8CodeUnitCount)
        var digits: (UInt8, UInt8, UInt8) = (
            0x30 + UInt8(truncatingIfNeeded: signalNumber / 10),
            0x30 + UInt8(truncatingIfNeeded: signalNumber % 10),
            0x0A
        )
        withUnsafeBytes(of: &digits) { bytes in
            _ = write(iconCrashFD, bytes.baseAddress, bytes.count)
        }
    }
    signal(signalNumber, SIG_DFL)
    raise(signalNumber)
}
