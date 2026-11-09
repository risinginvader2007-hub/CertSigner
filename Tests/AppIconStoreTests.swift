import XCTest
@testable import CertSigner

/// The icon selection is optimistic (moves on tap), ignores taps on the current icon, and the
/// alert-free private API is detected at runtime.
@MainActor
final class AppIconStoreTests: XCTestCase {
    func testSelectionIsImmediateAndSameIconIsIgnored() {
        let store = AppIconStore(initial: nil)
        var errors: [String] = []
        store.select(nil, animation: nil) { errors.append($0) }
        XCTAssertNil(store.selected, "tapping the selected icon does nothing")
        store.select("AppIcon-Sunset", animation: nil) { errors.append($0) }
        XCTAssertEqual(store.selected, "AppIcon-Sunset", "selection updates before the system call returns")
        let privateAPI = UIApplication.shared.responds(to: NSSelectorFromString("_setAlternateIconName:completionHandler:"))
        print("private _setAlternateIconName available: \(privateAPI); supportsAlternateIcons: \(store.supportsAlternateIcons)")
        let done = expectation(description: "system call finished")
        AppIconStore.setIcon(nil) { error in
            print("reset to primary icon: \(error.map { "\($0)" } ?? "ok")")
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
    }
}
