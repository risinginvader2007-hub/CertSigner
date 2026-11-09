import XCTest
import SwiftUI
@testable import CertSigner

/// The shared accent fade: not instant, passes through in-between colours, ends exactly on the target.
@MainActor
final class ThemeStoreTests: XCTestCase {
    private func distance(_ a: RGBA, _ b: RGBA) -> Double {
        abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
    }

    func testAccentChangeFadesOverSixTenthsOfASecond() {
        let traits = ThemeStore.currentTraits
        let store = ThemeStore(option: .purple)
        let from = RGBA(AccentOption.purple.color, traits: traits)
        let to = RGBA(AccentOption.orange.color, traits: traits)
        let start = Date()
        store.apply(.orange)
        XCTAssertEqual(store.accent, AccentOption.purple.color, "colour must not jump instantly")

        var samples: [(Double, Double)] = []   // (seconds, fraction of the way to orange)
        while Date().timeIntervalSince(start) < 0.9 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            let now = RGBA(store.accent, traits: traits)
            let fraction = distance(from, now) / distance(from, to)
            samples.append((Date().timeIntervalSince(start), fraction))
        }
        for (t, f) in samples { print(String(format: "theme fade t=%.2fs  %.0f%%", t, f * 100)) }

        let middle = samples.filter { $0.0 > 0.2 && $0.0 < 0.45 }
        XCTAssertFalse(middle.isEmpty)
        XCTAssertTrue(middle.allSatisfy { $0.1 > 0.05 && $0.1 < 0.97 }, "mid-fade colours should be in between")
        for (earlier, later) in zip(samples, samples.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later.1, earlier.1 - 0.001, "fade should move steadily toward the new colour (no flicker)")
        }
        XCTAssertLessThan(samples.first!.1, 0.1, "starts from the old colour")
        XCTAssertEqual(store.accent, AccentOption.orange.color, "ends exactly on the new accent")
        XCTAssertEqual(store.gradient, AccentOption.orange.gradient)
    }

    func testRetargetMidFadeStartsFromCurrentColour() {
        let traits = ThemeStore.currentTraits
        let store = ThemeStore(option: .blue)
        store.apply(.red)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let mid = RGBA(store.accent, traits: traits)
        store.apply(.green)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        let after = RGBA(store.accent, traits: traits)
        XCTAssertLessThan(distance(mid, after), 0.25, "switching again mid-fade continues from the current colour")
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        XCTAssertEqual(store.accent, AccentOption.green.color)
    }
}
