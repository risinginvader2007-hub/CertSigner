import XCTest
import SwiftUI
import UIKit
@testable import CertSigner

/// The background glow parameters per appearance (`AuroraStyle`): dark mode unchanged, light mode
/// boosted, and text on the light background still readable.
final class AuroraStyleTests: XCTestCase {
    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let black = RGBA(r: 0, g: 0, b: 0, a: 1)

    /// Every accent the app offers, as the light background receives it (resolved + boosted).
    private func lightPalettes() -> [(String, [RGBA])] {
        let accents = Accent.solids + Accent.blends
        let all = accents.map { ($0.name, $0.gradient) } + [("Signature", Theme.signature)]
        return all.map { name, colors in
            (name, colors.map { AuroraStyle.light.boosted(RGBA($0, traits: light)) })
        }
    }

    func testDarkModeValuesAreUnchanged() {
        let dark = AuroraStyle.dark
        XCTAssertEqual(dark.strength, 0.85)
        XCTAssertEqual(dark.blobOpacities, [1, 0.85, 0.6, 0.35])
        XCTAssertEqual(dark.sizeScale, 1)
        XCTAssertEqual(dark.saturation, 1)
        XCTAssertTrue(dark.additive)
        XCTAssertEqual(dark.baseTint, 0)
        XCTAssertEqual(dark.vignette, 0)
        XCTAssertNil(dark.minLuminance)
        XCTAssertEqual(GlowLevel.normal.multiplier, 1)
        // Same strength formula as before, for every screen intensity in use.
        for intensity in [0.45, 0.5, 0.55, 0.6, 0.7, 1, 1.4] {
            XCTAssertEqual(dark.gain(intensity: intensity, level: .normal), 0.85 * (0.55 + 0.45 * intensity))
        }
        // Colours are not touched in dark mode.
        let color = RGBA(r: 0.31, g: 0.27, b: 0.98, a: 1)
        XCTAssertEqual(dark.boosted(color), color)
    }

    func testLightModeValues() {
        let style = AuroraStyle.light
        XCTAssertFalse(style.additive, "a lightening blend vanishes on a light base")
        XCTAssertEqual(style.sizeScale, 1.2, accuracy: 0.0001)
        XCTAssertTrue((1.2...1.3).contains(style.saturation))
        for opacity in style.blobOpacities {
            XCTAssertTrue((0.45...0.65).contains(opacity * style.strength), "peak opacity \(opacity)")
        }
        let base = style.base(palette: [RGBA(r: 0.58, g: 0.34, b: 1, a: 1)])
        XCTAssertNotEqual(base, AuroraStyle.lightBase, "the light base carries a hint of the accent")
        XCTAssertGreaterThan(base.luminance, 0.8, "the light base stays an off-white")
    }

    func testSaturationBoostKeepsHueAndBrightness() {
        let indigo = RGBA(r: 0.31, g: 0.27, b: 0.98, a: 1)
        let boosted = indigo.saturated(by: 1.25)
        XCTAssertEqual(boosted.saturation, min(1, indigo.saturation * 1.25), accuracy: 0.0001)
        XCTAssertEqual(max(boosted.r, boosted.g, boosted.b), 0.98, accuracy: 0.0001)
        XCTAssertGreaterThan(boosted.r, boosted.g, "hue order kept")
        let gray = RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1)
        XCTAssertEqual(gray.saturated(by: 1.25), gray)
    }

    func testLightGlowsAreClearlyVisibleForTheDefaultAccent() {
        let palette = Theme.signature.map { AuroraStyle.light.boosted(RGBA($0, traits: light)) }
        let gain = AuroraStyle.light.gain(intensity: 1, level: .normal)
        let frame = AuroraStyle.light.lightFrame(time: 0, size: CGSize(width: 440, height: 956), palette: palette, gain: gain)
        // The strongest light tints its centre well away from the base.
        let strongest = frame.glows.map(\.alpha).max() ?? 0
        print("PERF light glow peak opacities (default accent, intensity 1, Normal): "
              + frame.glows.map { String(format: "%.2f", $0.alpha) }.joined(separator: ", "))
        XCTAssertGreaterThan(strongest, 0.4)
    }

    /// Black text on the light background keeps at least 4.5:1 everywhere on screen, at any
    /// moment of the drift, for every accent, at Normal and High, up to the intro's intensity.
    func testBlackTextStaysReadableOnTheLightBackground() {
        let style = AuroraStyle.light
        let size = CGSize(width: 440, height: 956)
        var worst = (contrast: Double.infinity, name: "")
        var worstSecondaryRatio = Double.infinity
        let secondary = RGBA(r: 0.235, g: 0.235, b: 0.263, a: 1)   // .secondaryLabel at 60 %
        for (name, palette) in lightPalettes() {
            for level in [GlowLevel.normal, .high] {
                for intensity in [1.0, 1.4] {
                    let gain = style.gain(intensity: intensity, level: level)
                    for time in stride(from: 0.0, to: 240, by: 4) {
                        let frame = style.lightFrame(time: time, size: size, palette: palette, gain: gain)
                        for gx in 0...10 {
                            for gy in 0...20 {
                                let point = CGPoint(x: size.width * CGFloat(gx) / 10, y: size.height * CGFloat(gy) / 20)
                                let background = frame.color(at: point)
                                let contrast = black.contrast(with: background)
                                if contrast < worst.contrast { worst = (contrast, "\(name) \(level.title) ×\(intensity) t=\(time)") }
                                // How much the glow lowers secondary text against the plain base.
                                let text = background.mixed(with: secondary, 0.6)
                                let plain = frame.base.mixed(with: secondary, 0.6)
                                worstSecondaryRatio = min(worstSecondaryRatio,
                                                          text.contrast(with: background) / plain.contrast(with: frame.base))
                            }
                        }
                    }
                }
            }
        }
        print(String(format: "PERF light glow worst black-text contrast %.2f:1 (%@); secondary text keeps %.0f%% of its contrast",
                     worst.contrast, worst.name, worstSecondaryRatio * 100))
        XCTAssertGreaterThanOrEqual(worst.contrast, 4.5, worst.name)
    }

    /// Cards and list rows are opaque in light mode, so the stronger glows never show through them.
    func testCardsAndRowsAreOpaqueInLightMode() {
        XCTAssertEqual(RGBA(Theme.surface, traits: light).a, 1)
        XCTAssertEqual(RGBA(Theme.surfaceRaised, traits: light).a, 1)
    }

    func testGlowLevelIsStoredPerAppearance() {
        let defaults = UserDefaults(suiteName: "AuroraStyleTests-\(UUID().uuidString)")!
        XCTAssertNotEqual(GlowLevel.storageKey(dark: true), GlowLevel.storageKey(dark: false))
        XCTAssertEqual(GlowLevel.stored(dark: false, defaults: defaults), .normal)
        defaults.set(GlowLevel.high.rawValue, forKey: GlowLevel.storageKey(dark: false))
        XCTAssertEqual(GlowLevel.stored(dark: false, defaults: defaults), .high)
        XCTAssertEqual(GlowLevel.stored(dark: true, defaults: defaults), .normal)
        XCTAssertLessThan(GlowLevel.low.multiplier, 1)
        XCTAssertGreaterThan(GlowLevel.high.multiplier, 1)
    }

    func testSchemeFadeUsesTheThemeCurve() {
        let fade = SchemeFade(fromDark: true, start: 10, duration: Motion.themeCrossfade)
        XCTAssertEqual(fade.duration, 0.35, accuracy: 0.0001)
        XCTAssertEqual(fade.progress(at: 10), 0)
        XCTAssertEqual(fade.progress(at: 10 + fade.duration / 2), 0.5, accuracy: 0.0001)
        XCTAssertEqual(fade.progress(at: 10 + fade.duration), 1)
        XCTAssertTrue(fade.isRunning(at: 10.2))
        XCTAssertFalse(fade.isRunning(at: 10.4))
        // Same curve as accent changes.
        let accent = ThemeFade(from: [], to: [], start: 10, duration: fade.duration)
        for t in stride(from: 10.0, through: 10.35, by: 0.05) {
            XCTAssertEqual(fade.progress(at: t), accent.progress(at: t), accuracy: 0.0001)
        }
    }
}
