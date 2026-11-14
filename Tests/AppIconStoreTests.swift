import XCTest
@testable import CertSigner

/// The icon selection is optimistic (moves on tap), reverts only when the system call fails, and
/// ignores taps on the current icon. Uses an injected setter so the test never changes the real icon.
@MainActor
final class AppIconStoreTests: XCTestCase {
    func testOptimisticSelectRevertOnErrorAndSameIconIgnored() async throws {
        var calls: [String?] = []
        var pending: [(Error?) -> Void] = []
        let store = AppIconStore(initial: nil) { name, done in
            calls.append(name)
            pending.append(done)
        }
        var errors: [String] = []

        store.select(nil, animation: nil) { errors.append($0) }
        XCTAssertTrue(calls.isEmpty, "tapping the selected icon does nothing")

        store.select("AppIcon-Sunset", animation: nil) { errors.append($0) }
        XCTAssertEqual(store.selected, "AppIcon-Sunset", "selection moves before the system call returns")
        pending.removeFirst()(nil)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(store.selected, "AppIcon-Sunset")

        store.select("AppIcon-Mint", animation: nil) { errors.append($0) }
        XCTAssertEqual(store.selected, "AppIcon-Mint")
        pending.removeFirst()(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not allowed"]))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(store.selected, "AppIcon-Sunset", "reverts to the previous icon on error")
        XCTAssertEqual(errors, ["Not allowed"])
        XCTAssertEqual(calls, ["AppIcon-Sunset", "AppIcon-Mint"])

        let privateAPI = UIApplication.shared.responds(to: NSSelectorFromString("_setAlternateIconName:completionHandler:"))
        print("private _setAlternateIconName available: \(privateAPI)")
    }

    /// iOS 27 calls the private API's completion off the main thread; that used to trap (SIGTRAP)
    /// because the store's closure was main-actor isolated. It must revert and report on main.
    func testCompletionFromBackgroundQueueRevertsOnMain() {
        let store = AppIconStore(initial: nil) { _, done in
            DispatchQueue.global().async {
                done(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not allowed"]))
            }
        }
        let reported = expectation(description: "error reported")
        var message: String?
        store.select("AppIcon-Mint", animation: nil) { text in
            XCTAssertTrue(Thread.isMainThread)
            message = text
            reported.fulfill()
        }
        XCTAssertEqual(store.selected, "AppIcon-Mint")
        wait(for: [reported], timeout: 5)
        XCTAssertEqual(message, "Not allowed")
        XCTAssertNil(store.selected, "reverted to the primary icon")
    }

    /// The block handed to UIKit can fire on any queue and always delivers the result on main.
    func testCompletionBlockDeliversOnMain() {
        let delivered = expectation(description: "delivered on main")
        let block = AppIconStore.completionBlock(path: "test") { error in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual((error as NSError?)?.code, 7)
            delivered.fulfill()
        }
        DispatchQueue.global().async {
            block(NSError(domain: "test", code: 7))
        }
        wait(for: [delivered], timeout: 5)
    }

    /// How a run that died during an icon change is classified from its marker.
    func testIconChangeVerdict() {
        let header = "icon change to AppIcon-Mint at 2026-11-14T10:00:00Z on iOS 18.1\n"
        XCTAssertTrue(IconChangeDiagnostics.verdict(for: header + "event +0.10 s: willResignActive\nevent: crash signal 05\n").hasPrefix("CRASHED"))
        XCTAssertTrue(IconChangeDiagnostics.verdict(for: header + "event +0.30 s: didEnterBackground\nevent +0.31 s: willTerminate\n").hasPrefix("TERMINATED"))
        XCTAssertTrue(IconChangeDiagnostics.verdict(for: header + "event +0.10 s: willResignActive\nevent +0.30 s: didEnterBackground\n").hasPrefix("KILLED WITHOUT NOTICE"))
        XCTAssertTrue(IconChangeDiagnostics.verdict(for: header).hasPrefix("ENDED WITHOUT"))
    }
}
