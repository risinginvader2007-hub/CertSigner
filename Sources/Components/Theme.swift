import SwiftUI

// MARK: - Motion language (define once, use everywhere)

/// Named motion tokens. Every animation in the app should come from here.
enum Motion {
    /// Taps, toggles, selection pills: quick and crisp.
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.82)
    /// Layout changes, cards appearing, sheets' inner content.
    static let smooth = Animation.spring(response: 0.45, dampingFraction: 0.86)
    /// Playful confirmations: checkmarks, badges, icons popping in.
    static let bouncy = Animation.spring(response: 0.5, dampingFraction: 0.66)
    /// Ambient, slow things: glows, background drift, breathing.
    static let gentle = Animation.easeInOut(duration: 0.6)

    /// Durations (seconds) for non-spring timing.
    static let quick: Double = 0.18
    static let standard: Double = 0.3
    static let slow: Double = 0.6
    /// Delay between items in staggered entrances.
    static let stagger: Double = 0.05

    /// With Reduce Motion on, movement becomes a short cross-fade.
    static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : animation
    }
}

/// 4/8 pt spacing grid.
enum Space {
    static let x1: CGFloat = 4
    static let x2: CGFloat = 8
    static let x3: CGFloat = 12
    static let x4: CGFloat = 16
    static let x5: CGFloat = 20
    static let x6: CGFloat = 24
    static let x8: CGFloat = 32
}

/// One corner-radius scale; always used with `style: .continuous`.
enum Radius {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
    static let xl: CGFloat = 28
}

/// Central design tokens. Keep every screen pulling from here.
enum Theme {
    static let corner: CGFloat = Radius.lg
    static let smallCorner: CGFloat = Radius.sm
    static let spacing: CGFloat = Space.x4
    static let padding: CGFloat = Space.x4

    // Signature palette: deep indigo → electric violet → cyan.
    static let indigo = Color(red: 0.31, green: 0.27, blue: 0.98)
    static let violet = Color(red: 0.58, green: 0.34, blue: 1.0)
    static let cyan = Color(red: 0.16, green: 0.80, blue: 0.98)
    static let signature: [Color] = [indigo, violet, cyan]

    // Semantic colours, tuned to glow a little on dark surfaces.
    static let success = Color(red: 0.20, green: 0.84, blue: 0.52)
    static let warning = Color(red: 1.0, green: 0.64, blue: 0.16)
    static let danger = Color(red: 1.0, green: 0.30, blue: 0.36)

    /// Dark-first depth layers: near-black base, then slightly lifted surfaces. Light mode stays airy.
    static let background = dynamic(dark: UIColor(red: 0.027, green: 0.031, blue: 0.055, alpha: 1),
                                    light: UIColor(red: 0.953, green: 0.957, blue: 0.976, alpha: 1))
    static let surface = dynamic(dark: UIColor(red: 0.075, green: 0.082, blue: 0.122, alpha: 1),
                                 light: .white)
    static let surfaceRaised = dynamic(dark: UIColor(red: 0.11, green: 0.12, blue: 0.17, alpha: 1),
                                       light: UIColor(red: 0.975, green: 0.977, blue: 0.99, alpha: 1))
    static let hairline = Color.primary.opacity(0.08)

    static let spring = Motion.smooth
    static let bouncy = Motion.bouncy

    private static func dynamic(dark: UIColor, light: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    /// Deterministic two-colour palette for a string (String.hashValue is randomised per launch).
    static func palette(for seed: String) -> [Color] {
        let palettes: [[Color]] = [
            [.blue, .purple], [.pink, .orange], [.teal, .blue], [.green, .teal],
            [.indigo, .pink], [.orange, .red], [.purple, .indigo], [.mint, .green]
        ]
        var hash: UInt64 = 5381
        for scalar in seed.unicodeScalars {
            hash = (hash &* 33) &+ UInt64(scalar.value)
        }
        return palettes[Int(hash % UInt64(palettes.count))]
    }
}

enum SettingsKeys {
    static let appearance = "settings.appearance"
    static let accent = "settings.accent"
    static let deviceUDID = "settings.deviceUDID"
    static let libraryLayout = "library.layout"
    static let librarySort = "library.sort"
    static let installMethod = "install.method"
    static let autoInstall = "signing.autoInstall"
    static let deleteOriginal = "signing.deleteOriginal"
    static let defaultRemoveExtensions = "signing.defaultRemoveExtensions"
    static let defaultKeepBundleID = "signing.defaultKeepBundleID"

    static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
}

enum AppearanceOption: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AccentOption: String, CaseIterable, Identifiable {
    /// Signature indigo → violet → cyan.
    case aurora
    case blue, indigo, purple, pink, red, orange, green, teal

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Gradient for filled buttons, rings and glows: the accent plus a companion hue.
    var gradient: [Color] {
        switch self {
        case .aurora: return Theme.signature
        case .blue: return [.blue, Theme.cyan]
        case .indigo: return [.indigo, Theme.violet]
        case .purple: return [.purple, .pink]
        case .pink: return [.pink, .orange]
        case .red: return [.red, .pink]
        case .orange: return [.orange, .yellow]
        case .green: return [.green, .mint]
        case .teal: return [.teal, Theme.cyan]
        }
    }

    var color: Color {
        switch self {
        case .aurora: return Theme.violet
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .green: return .green
        case .teal: return .teal
        }
    }
}

private struct ThemeAccentKey: EnvironmentKey {
    static let defaultValue: Color = Theme.violet
}

private struct ThemeGradientKey: EnvironmentKey {
    static let defaultValue: [Color] = Theme.signature
}

extension EnvironmentValues {
    /// The accent's gradient (see `AccentOption.gradient`).
    var themeGradient: [Color] {
        get { self[ThemeGradientKey.self] }
        set { self[ThemeGradientKey.self] = newValue }
    }

    /// The user-chosen accent colour. Use this instead of `Color.accentColor`.
    var themeAccent: Color {
        get { self[ThemeAccentKey.self] }
        set { self[ThemeAccentKey.self] = newValue }
    }
}

/// Scales down slightly on press, with a spring (a fade only, with Reduce Motion).
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, scale: scale)
    }

    private struct PressableBody: View {
        let configuration: ButtonStyleConfiguration
        let scale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
                .opacity(configuration.isPressed ? 0.86 : 1)
                .animation(Motion.snappy, value: configuration.isPressed)
        }
    }
}
