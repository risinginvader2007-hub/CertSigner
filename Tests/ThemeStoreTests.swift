import XCTest
import SwiftUI
import Combine
@testable import CertSigner

/// The shared accent transition: published once (no per-frame re-render of the tree), the
/// per-frame fade the background draws passes through in-between colours over about 0.35 s and
/// ends exactly on the target, and switching again mid-fade continues from what is on screen.
@MainActor
final class ThemeStoreTests: XCTestCase {
    private func distance(_ a: RGBA, _ b: RGBA) -> Double {
        abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
    }

    func testAccentChangeCrossFadesOverAbout350ms() {
        let traits = ThemeStore.currentTraits
        let store = ThemeStore(option: .purple)
        var publishes = 0
        let token = store.objectWillChange.sink { _ in publishes += 1 }
        store.apply(.orange)
        XCTAssertEqual(store.accent, AccentOption.orange.color, "views get the new accent once, animated by SwiftUI")
        guard let fade = store.fade else { return XCTFail("a fade should be running") }
        let from = ThemeStore.samples(AccentOption.purple.gradient, traits: traits)[0]
        let to = ThemeStore.samples(AccentOption.orange.gradient, traits: traits)[0]

        var samples: [(Double, Double)] = []
        for step in 0...12 {
            let t = Double(step) * 0.05
            let now = fade.stops(at: fade.start + t)[0]
            samples.append((t, distance(from, now) / distance(from, to)))
        }
        for (t, f) in samples { print(String(format: "theme fade t=%.2fs  %.0f%%", t, f * 100)) }
        XCTAssertLessThan(samples[0].1, 0.01, "starts from the old colour")
        XCTAssertTrue(samples.filter { $0.0 > 0.1 && $0.0 < 0.25 }.allSatisfy { $0.1 > 0.02 && $0.1 < 0.98 },
                      "mid-fade colours are in between")
        XCTAssertGreaterThan(samples.first { $0.0 >= 0.35 }!.1, 0.999, "done by 0.35 s")
        for (earlier, later) in zip(samples, samples.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later.1, earlier.1 - 0.001, "moves steadily (no flicker)")
        }

        // Wait for the clean-up publish itself (not a fixed time: slow CI runners missed 0.6 s).
        let deadline = Date().addingTimeInterval(5)
        while store.fade != nil && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        token.cancel()
        XCTAssertNil(store.fade, "the fade is cleared when it ends")
        XCTAssertEqual(store.gradient, AccentOption.orange.gradient)
        print("theme publishes per accent change: \(publishes)")
        XCTAssertLessThanOrEqual(publishes, 2, "one publish to start, one to finish: never per frame")
    }

    func testRetargetMidFadeStartsFromCurrentColour() {
        let store = ThemeStore(option: .blue)
        store.apply(.red)
        guard let first = store.fade else { return XCTFail() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.17))
        let mid = first.stops(at: CACurrentMediaTime())[0]
        store.apply(.green)
        guard let second = store.fade else { return XCTFail() }
        let start = second.stops(at: second.start)[0]
        XCTAssertLessThan(distance(mid, start), 0.25, "switching again mid-fade continues from the current colour")
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        XCTAssertEqual(store.accent, AccentOption.green.color)
        XCTAssertNil(store.fade)
    }
}
