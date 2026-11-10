import XCTest
import SwiftUI
@testable import CertSigner

/// Accent model: old selections migrate, presets are complete, labels on every gradient reach
/// 4.5:1, small-element tints stay visible in light and dark, custom blends save and delete.
@MainActor
final class AccentTests: XCTestCase {
    func testOldStoredValuesStillSelectTheSameAccent() {
        for option in AccentOption.allCases {
            let accent = Accent.resolve(id: option.rawValue)
            XCTAssertEqual(accent.id, option.rawValue)
            XCTAssertEqual(accent.tint, option.color, "original accents are unchanged")
            XCTAssertEqual(accent.gradient, option.gradient)
        }
        XCTAssertEqual(Accent.resolve(id: nil).id, "aurora")
        XCTAssertEqual(Accent.resolve(id: "custom.deleted").id, "aurora", "unknown ids fall back")
    }

    func testPresetsAndContrast() {
        XCTAssertEqual(Accent.blends.count, 16)
        XCTAssertEqual(Set((Accent.solids + Accent.blends).map(\.id)).count, Accent.solids.count + 16, "unique ids")
        XCTAssertEqual(Accent.resolve(id: "blend.galaxy").colors.count, 3)
        let white = RGBA(r: 1, g: 1, b: 1, a: 1), black = RGBA(r: 0, g: 0, b: 0, a: 1)
        for accent in Accent.blends {
            let label = accent.onAccentIsWhite ? white : black
            let worst = accent.surfaceStops.map { $0.contrast(with: label) }.min() ?? 0
            let mid = Accent.midpoint(accent.surfaceStops)
            let light = Accent.adjustedTint(mid, dark: false).contrast(with: white)
            let dark = Accent.adjustedTint(mid, dark: true).contrast(with: RGBA(r: 0.06, g: 0.06, b: 0.08, a: 1))
            print(String(format: "ACCENT %@: %@ label %.2f:1, tint %.2f:1 light / %.2f:1 dark",
                         accent.name, accent.onAccentIsWhite ? "white" : "black", worst, light, dark))
            XCTAssertGreaterThanOrEqual(worst, 4.5, "\(accent.name) label contrast")
            XCTAssertGreaterThanOrEqual(light, 3, "\(accent.name) tint on light")
            XCTAssertGreaterThanOrEqual(dark, 3, "\(accent.name) tint on dark")
        }
    }

    func testCustomBlendSaveResolveDelete() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "accent-test-\(UUID().uuidString)"))
        let library = AccentLibrary(defaults: defaults)
        let saved = library.add(name: "  ", hex: ["#112233", "#AABBCC"])
        XCTAssertEqual(saved.name, "My Blend")
        XCTAssertTrue(saved.isCustom)
        XCTAssertEqual(library.customs.map(\.id), [saved.id])
        XCTAssertEqual(Accent.resolve(id: saved.id, defaults: defaults).id, saved.id)
        XCTAssertEqual(AccentLibrary(defaults: defaults).customs.count, 1, "persists")
        library.delete(saved.id)
        XCTAssertTrue(library.customs.isEmpty)
        XCTAssertEqual(Accent.resolve(id: saved.id, defaults: defaults).id, "aurora")
        XCTAssertEqual(RGBA(hex: "#FF0080")?.hex, "#FF0080")
    }

    func testThemeStoreUsesBlendColours() {
        let store = ThemeStore(option: .blue)
        let neon = Accent.resolve(id: "blend.neonLime")
        store.apply(neon, animated: false)
        XCTAssertEqual(store.gradient, neon.gradient)
        XCTAssertEqual(store.onAccent, .black, "light gradients get black labels")
        store.apply(Accent.resolve(id: "blend.galaxy"), animated: false)
        XCTAssertEqual(store.onAccent, .white)
    }
}
