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
}
