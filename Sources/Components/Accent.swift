import SwiftUI
import UIKit

/// An accent: an id, a name and 1 to 3 colours. The original accents (`AccentOption`) keep their
/// exact colours; blended presets and the user's custom blends are gradients.
///
/// - `colors`: the raw stops, shown on the swatch.
/// - `gradient`: what big accent surfaces fill with (buttons, selected segment, rings, glows).
///   For blends, any stop that would leave the label under 4.5:1 is nudged just far enough.
/// - `tint`: one colour for small elements (text, icons, thin strokes): the gradient's mid-point,
///   adjusted per appearance so it stays visible on light and dark backgrounds.
/// - `onAccent`: black or white, whichever reads better on the gradient.
struct Accent: Identifiable, Equatable {
    enum Group: String, CaseIterable, Identifiable {
        case solid, blended
        var id: String { rawValue }
        var title: String { self == .solid ? "Solid" : "Blended" }
    }

    let id: String
    let name: String
    let colors: [Color]
    let gradient: [Color]
    let tint: Color
    let onAccent: Color
    let group: Group
    let isCustom: Bool
    /// Resolved values kept for tests and the contrast check.
    let surfaceStops: [RGBA]
    let onAccentIsWhite: Bool

    static let defaultID = AccentOption.aurora.rawValue
    static let minimumContrast = 4.5

    /// An original accent, unchanged: same tint, same gradient, white labels.
    init(_ option: AccentOption) {
        id = option.rawValue
        name = option.title
        colors = option.gradient
        gradient = option.gradient
        tint = option.color
        onAccent = .white
        group = .solid
        isCustom = false
        surfaceStops = []
        onAccentIsWhite = true
    }

    /// A blend from 1 to 3 hex colours.
    init(id: String, name: String, hex: [String], isCustom: Bool = false) {
        let stops = Array(hex.compactMap(RGBA.init(hex:)).prefix(3))
        let raw = stops.isEmpty ? [RGBA(r: 0.58, g: 0.34, b: 1, a: 1)] : stops
        self.id = id
        self.name = name
        self.isCustom = isCustom
        group = .blended
        colors = raw.count == 1 ? [raw[0].color, raw[0].color] : raw.map(\.color)

        // Label colour: whichever of white / black has the better worst-case contrast.
        let white = RGBA(r: 1, g: 1, b: 1, a: 1), black = RGBA(r: 0, g: 0, b: 0, a: 1)
        let worstWhite = raw.map { $0.contrast(with: white) }.min() ?? 1
        let worstBlack = raw.map { $0.contrast(with: black) }.min() ?? 1
        let useWhite = worstWhite >= worstBlack
        let label = useWhite ? white : black
        // Nudge only the stops that fall short, only as far as needed.
        let surface = raw.map { stop -> RGBA in
            var c = stop
            var steps = 0
            while c.contrast(with: label) < Accent.minimumContrast && steps < 40 {
                c = c.mixed(with: useWhite ? black : white, 0.04)
                steps += 1
            }
            return c
        }
        surfaceStops = surface
        onAccentIsWhite = useWhite
        onAccent = useWhite ? .white : .black
        gradient = surface.count == 1 ? [surface[0].color, surface[0].color] : surface.map(\.color)
        tint = Accent.readableTint(Accent.midpoint(raw))
    }

    static func midpoint(_ stops: [RGBA]) -> RGBA {
        switch stops.count {
        case 0: return .clear
        case 1: return stops[0]
        case 2: return stops[0].mixed(with: stops[1], 0.5)
        default: return stops[stops.count / 2]
        }
    }

    /// The mid-point colour, moved toward black (light mode) or white (dark mode) until it has
    /// at least 3:1 against the screen background, so text, icons and strokes stay visible.
    static func readableTint(_ mid: RGBA) -> Color {
        Color(UIColor { traits in
            let c = adjustedTint(mid, dark: traits.userInterfaceStyle == .dark)
            return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        })
    }

    static func adjustedTint(_ mid: RGBA, dark: Bool) -> RGBA {
        let background = dark ? RGBA(r: 0.06, g: 0.06, b: 0.08, a: 1) : RGBA(r: 1, g: 1, b: 1, a: 1)
        let toward = dark ? RGBA(r: 1, g: 1, b: 1, a: 1) : RGBA(r: 0, g: 0, b: 0, a: 1)
        var c = mid
        var steps = 0
        while c.contrast(with: background) < 3 && steps < 40 {
            c = c.mixed(with: toward, 0.04)
            steps += 1
        }
        return c
    }

    // MARK: Catalogue

    static let solids: [Accent] = AccentOption.allCases.map { Accent($0) }

    static let blends: [Accent] = [
        Accent(id: "blend.aurora", name: "Aurora", hex: ["#00F5A0", "#7C3AED"]),
        Accent(id: "blend.sunsetBlaze", name: "Sunset Blaze", hex: ["#FF512F", "#F09819"]),
        Accent(id: "blend.cottonCandy", name: "Cotton Candy", hex: ["#FF9A9E", "#A18CD1"]),
        Accent(id: "blend.deepOcean", name: "Deep Ocean", hex: ["#2193B0", "#6DD5ED"]),
        Accent(id: "blend.cherryBlossom", name: "Cherry Blossom", hex: ["#FF6B9D", "#C44CFF"]),
        Accent(id: "blend.mojito", name: "Mojito", hex: ["#1D976C", "#93F9B9"]),
        Accent(id: "blend.ember", name: "Ember", hex: ["#F12711", "#F5AF19"]),
        Accent(id: "blend.twilight", name: "Twilight", hex: ["#4776E6", "#8E54E9"]),
        Accent(id: "blend.peachFizz", name: "Peach Fizz", hex: ["#FF7E5F", "#FEB47B"]),
        Accent(id: "blend.neonLime", name: "Neon Lime", hex: ["#A8FF78", "#00C9FF"]),
        Accent(id: "blend.royalGold", name: "Royal Gold", hex: ["#B79891", "#F7D794"]),
        Accent(id: "blend.roseQuartz", name: "Rose Quartz", hex: ["#F857A6", "#FF5858"]),
        Accent(id: "blend.arctic", name: "Arctic", hex: ["#74EBD5", "#9FACE6"]),
        Accent(id: "blend.galaxy", name: "Galaxy", hex: ["#0F2027", "#7B2FF7", "#F107A3"]),
        Accent(id: "blend.lagoon", name: "Lagoon", hex: ["#00B4DB", "#0083B0"]),
        Accent(id: "blend.berryCrush", name: "Berry Crush", hex: ["#8E2DE2", "#FF0080"])
    ]

    // MARK: Stored selection and custom blends

    struct Stored: Codable, Equatable {
        var id: String
        var name: String
        var hex: [String]
    }

    static let customKey = "ui.customAccents"

    static func storedCustoms(_ defaults: UserDefaults = .standard) -> [Stored] {
        guard let data = defaults.data(forKey: customKey) else { return [] }
        return (try? JSONDecoder().decode([Stored].self, from: data)) ?? []
    }

    /// The accent for a stored id. Old installs stored the `AccentOption` raw value, which is
    /// the same id the original accents still use, so the previous selection carries over.
    /// Unknown or deleted ids fall back to the default.
    static func resolve(id: String?, defaults: UserDefaults = .standard) -> Accent {
        guard let id else { return solids[0] }
        if let match = (solids + blends).first(where: { $0.id == id }) { return match }
        if let custom = storedCustoms(defaults).first(where: { $0.id == id }) {
            return Accent(id: custom.id, name: custom.name, hex: custom.hex, isCustom: true)
        }
        return solids[0]
    }
}

/// The user's saved custom blends.
@MainActor
final class AccentLibrary: ObservableObject {
    static let shared = AccentLibrary(defaults: .standard)

    @Published private(set) var customs: [Accent] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        customs = Accent.storedCustoms(defaults).map { Accent(id: $0.id, name: $0.name, hex: $0.hex, isCustom: true) }
    }

    @discardableResult
    func add(name: String, hex: [String]) -> Accent {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = Accent.Stored(id: "custom.\(UUID().uuidString.lowercased())",
                                   name: trimmed.isEmpty ? "My Blend" : trimmed, hex: hex)
        save(Accent.storedCustoms(defaults) + [stored])
        return Accent(id: stored.id, name: stored.name, hex: stored.hex, isCustom: true)
    }

    func delete(_ id: String) {
        save(Accent.storedCustoms(defaults).filter { $0.id != id })
    }

    private func save(_ list: [Accent.Stored]) {
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: Accent.customKey) }
        customs = list.map { Accent(id: $0.id, name: $0.name, hex: $0.hex, isCustom: true) }
    }
}

extension RGBA {
    init?(hex: String) {
        let text = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespacesAndNewlines))
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(r: Double((value >> 16) & 0xFF) / 255, g: Double((value >> 8) & 0xFF) / 255,
                  b: Double(value & 0xFF) / 255, a: 1)
    }

    var hex: String {
        func part(_ x: Double) -> Int { Int((min(1, max(0, x)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", part(r), part(g), part(b))
    }

    /// WCAG relative luminance.
    var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// WCAG contrast ratio (1 to 21).
    func contrast(with other: RGBA) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

private struct ThemeOnAccentKey: EnvironmentKey {
    static let defaultValue: Color = .white
}

extension EnvironmentValues {
    /// Label colour (black or white) for content drawn on the accent gradient.
    var themeOnAccent: Color {
        get { self[ThemeOnAccentKey.self] }
        set { self[ThemeOnAccentKey.self] = newValue }
    }
}
