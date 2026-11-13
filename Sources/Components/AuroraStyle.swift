import SwiftUI
import UIKit

/// How strong the background glows are (Settings → Appearance → Glow intensity), stored
/// separately for light and dark mode. Normal is exactly the original strength.
enum GlowLevel: String, CaseIterable, Identifiable {
    case low, normal, high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }

    var multiplier: Double {
        switch self {
        case .low: return 0.6
        case .normal: return 1
        case .high: return 1.3
        }
    }

    static func storageKey(dark: Bool) -> String {
        dark ? SettingsKeys.glowIntensityDark : SettingsKeys.glowIntensityLight
    }

    static func stored(dark: Bool, defaults: UserDefaults = .standard) -> GlowLevel {
        defaults.string(forKey: storageKey(dark: dark)).flatMap(GlowLevel.init(rawValue:)) ?? .normal
    }
}

/// Every number the animated background uses, per appearance, in one place.
///
/// - Dark: the original values, unchanged: additive (plusLighter) lights on the near-black base.
/// - Light: a lightening blend vanishes on a light base, so the accent colours are drawn with
///   normal blending, 25 % more saturated, more opaque and 1.2× larger, over an off-white base
///   tinted with the accent, with a soft vignette at the edges. Each light blob is capped so the
///   background behind it keeps a relative luminance of at least `minLuminance` (black text
///   ≥ 7.6:1 behind one blob; the test checks ≥ 4.5:1 everywhere, overlaps and vignette included).
struct AuroraStyle {
    let dark: Bool
    /// Overall strength at screen intensity 1 and glow level Normal.
    let strength: Double
    /// Peak opacity of each blob (same order as `AuroraGeometry.blobs`), times `strength`.
    let blobOpacities: [Double]
    let sizeScale: Double
    /// Multiplies each accent colour's saturation (HSB).
    let saturation: Double
    /// plusLighter blending (dark only).
    let additive: Bool
    /// How far the base moves toward the accent (0 = plain base).
    let baseTint: Double
    /// Opacity of the edge vignette.
    let vignette: Double
    /// Lowest background luminance a single blob may leave (light only).
    let minLuminance: Double?

    static let dark = AuroraStyle(dark: true, strength: 0.85, blobOpacities: [1, 0.85, 0.6, 0.35],
                                  sizeScale: 1, saturation: 1, additive: true, baseTint: 0,
                                  vignette: 0, minLuminance: nil)

    static let light = AuroraStyle(dark: false, strength: 1, blobOpacities: [0.65, 0.6, 0.52, 0.45],
                                   sizeScale: 1.2, saturation: 1.25, additive: false, baseTint: 0.06,
                                   vignette: 0.07, minLuminance: 0.33)

    static func forScheme(_ scheme: ColorScheme) -> AuroraStyle { scheme == .dark ? .dark : .light }

    /// `Theme.background` in each appearance.
    static let darkBase = RGBA(r: 0.027, g: 0.031, b: 0.055, a: 1)
    static let lightBase = RGBA(r: 0.953, g: 0.957, b: 0.976, a: 1)
    /// Cool slate for the light vignette.
    static let vignetteColor = RGBA(r: 0.16, g: 0.17, b: 0.26, a: 1)

    /// Screen intensity (0.45 – 1.4) and the user's glow level → one factor for every blob.
    func gain(intensity: Double, level: GlowLevel) -> Double {
        strength * (0.55 + 0.45 * intensity) * level.multiplier
    }

    func boosted(_ color: RGBA) -> RGBA {
        saturation == 1 ? color : color.saturated(by: saturation)
    }

    /// The base under the glows: plain in dark mode, off-white with a hint of the accent in light.
    func base(palette: [RGBA]) -> RGBA {
        let plain = dark ? Self.darkBase : Self.lightBase
        guard baseTint > 0, !palette.isEmpty else { return plain }
        var mid = Accent.midpoint(palette)
        mid.a = 1
        return plain.mixed(with: mid, baseTint)
    }

    /// The largest opacity up to `alpha` that keeps `color` drawn over `base` at or above
    /// `minLuminance`.
    func cappedOpacity(_ alpha: Double, color: RGBA, over base: RGBA) -> Double {
        let wanted = min(1, max(0, alpha))
        guard let floor = minLuminance, wanted > 0 else { return wanted }
        if base.mixed(with: color, wanted).luminance >= floor { return wanted }
        var low = 0.0, high = wanted
        for _ in 0..<14 {
            let mid = (low + high) / 2
            if base.mixed(with: color, mid).luminance >= floor { low = mid } else { high = mid }
        }
        return low
    }

    // MARK: Light frame

    /// Everything the light background draws at one moment. The Canvas draws exactly this, and
    /// the tests read colours from it.
    struct LightFrame {
        struct Glow {
            let center: CGPoint
            let diameter: CGFloat
            let color: RGBA
            let alpha: Double
        }

        let size: CGSize
        let base: RGBA
        let glows: [Glow]
        let vignette: Double

        /// Radial profile of one glow: full at the centre, 55 % halfway, 0 at the edge.
        static func profile(_ distance: Double) -> Double {
            if distance >= 1 { return 0 }
            if distance <= 0.5 { return 1 - 0.9 * distance }
            return 0.55 * (1 - (distance - 0.5) / 0.5)
        }

        /// Vignette strength from the centre (0) to the corners (1).
        static func vignetteProfile(_ distance: Double) -> Double {
            distance <= 0.55 ? 0 : min(1, (distance - 0.55) / 0.45)
        }

        var vignetteRadius: CGFloat { hypot(size.width, size.height) / 2 }

        /// The colour on screen at `point` (sRGB compositing, like the Canvas).
        func color(at point: CGPoint) -> RGBA {
            var result = base
            for glow in glows {
                let distance = Double(hypot(point.x - glow.center.x, point.y - glow.center.y) / (glow.diameter / 2))
                let alpha = glow.alpha * Self.profile(distance)
                if alpha > 0 { result = result.mixed(with: glow.color, alpha) }
            }
            if vignette > 0 {
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let distance = Double(hypot(point.x - center.x, point.y - center.y) / vignetteRadius)
                let alpha = vignette * Self.vignetteProfile(distance)
                if alpha > 0 { result = result.mixed(with: AuroraStyle.vignetteColor, alpha) }
            }
            return result
        }
    }

    /// The light background at `time`. `palette` is already boosted (`boosted(_:)`).
    func lightFrame(time: Double, size: CGSize, palette: [RGBA], gain: Double) -> LightFrame {
        let colors = palette.isEmpty ? [Self.lightBase] : palette
        let background = self.base(palette: colors)
        let glows = AuroraGeometry.blobs.enumerated().map { (index, blob) -> LightFrame.Glow in
            let placed = AuroraGeometry.place(blob, time: time, size: size, sizeScale: sizeScale)
            var color = colors[AuroraGeometry.index(at: blob.colorPosition, count: colors.count)]
            color.a = 1
            let alpha = cappedOpacity(gain * blobOpacities[index] * placed.pulse, color: color, over: background)
            return LightFrame.Glow(center: placed.center, diameter: placed.diameter, color: color, alpha: alpha)
        }
        return LightFrame(size: size, base: background, glows: glows, vignette: vignette)
    }
}

/// Where each background light is at a moment: a slow figure-eight per blob, with its own speed,
/// size breathing (±12 %) and brightness pulse (≈ 65 – 100 %). Shared by both appearances.
enum AuroraGeometry {
    struct Blob {
        let colorPosition: Double   // where on the theme gradient its colour comes from
        let size: CGFloat           // × screen width
        let base: CGPoint           // centre, as a fraction of the screen
        let amplitude: CGSize       // travel, as a fraction of the screen
        let period: Double          // seconds per loop (20 – 40 s)
        let phase: Double
    }

    static let blobs: [Blob] = [
        Blob(colorPosition: 0, size: 1.25, base: CGPoint(x: 0.12, y: 0.10), amplitude: CGSize(width: 0.20, height: 0.08), period: 26, phase: 0),
        Blob(colorPosition: 0.5, size: 1.10, base: CGPoint(x: 0.88, y: 0.16), amplitude: CGSize(width: 0.18, height: 0.10), period: 34, phase: 1.7),
        Blob(colorPosition: 1, size: 0.95, base: CGPoint(x: 0.55, y: 0.36), amplitude: CGSize(width: 0.24, height: 0.11), period: 21, phase: 3.1),
        Blob(colorPosition: 0.25, size: 1.05, base: CGPoint(x: 0.30, y: 0.78), amplitude: CGSize(width: 0.22, height: 0.07), period: 39, phase: 4.4)
    ]

    struct Placed {
        let center: CGPoint
        let diameter: CGFloat
        let pulse: Double
    }

    static func place(_ blob: Blob, time: Double, size: CGSize, sizeScale: Double) -> Placed {
        let angle = 2 * Double.pi * time / blob.period + blob.phase
        let diameter = size.width * blob.size * CGFloat(sizeScale) * CGFloat(1 + 0.12 * sin(angle + 1.1))
        let pulse = 0.825 + 0.175 * sin(angle * 2 + 2.3)
        let center = CGPoint(x: size.width * (blob.base.x + blob.amplitude.width * CGFloat(sin(angle))),
                             y: size.height * (blob.base.y + blob.amplitude.height * CGFloat(sin(2 * angle + blob.phase))))
        return Placed(center: center, diameter: diameter, pulse: pulse)
    }

    /// Nearest gradient stop for a position on the gradient.
    static func index(at position: Double, count: Int) -> Int {
        let index = Int((position * Double(count - 1)).rounded())
        return min(max(index, 0), count - 1)
    }
}

/// A light ↔ dark switch of the background (the app's setting or the system changing it): the
/// old appearance's glows fade into the new ones with the shared 0.35 s theme curve.
struct SchemeFade: Equatable {
    let fromDark: Bool
    let start: CFTimeInterval
    let duration: Double

    func progress(at time: CFTimeInterval) -> Double {
        let p = min(1, max(0, (time - start) / duration))
        return p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
    }

    func isRunning(at time: CFTimeInterval) -> Bool { time - start < duration }
}

extension RGBA {
    /// HSB saturation (0 – 1).
    var saturation: Double {
        let top = max(r, g, b), bottom = min(r, g, b)
        return top > 0 ? (top - bottom) / top : 0
    }

    /// The same hue and brightness with saturation multiplied by `factor` (capped at 1).
    func saturated(by factor: Double) -> RGBA {
        let top = max(r, g, b)
        let current = saturation
        guard current > 0 else { return self }
        let scale = min(1, current * factor) / current
        func channel(_ c: Double) -> Double { min(1, max(0, top - (top - c) * scale)) }
        return RGBA(r: channel(r), g: channel(g), b: channel(b), a: a)
    }
}
