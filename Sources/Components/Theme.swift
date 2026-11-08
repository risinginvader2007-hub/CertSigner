import SwiftUI

/// Central design tokens. Keep every screen pulling from here.
enum Theme {
    static let corner: CGFloat = 20
    static let smallCorner: CGFloat = 12
    static let spacing: CGFloat = 16
    static let padding: CGFloat = 16

    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red

    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let hairline = Color.primary.opacity(0.07)

    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.8)
    static let bouncy = Animation.spring(response: 0.5, dampingFraction: 0.65)

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
    case blue, indigo, purple, pink, red, orange, green, teal

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
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
    static let defaultValue: Color = .blue
}

extension EnvironmentValues {
    /// The user-chosen accent colour. Use this instead of `Color.accentColor`.
    var themeAccent: Color {
        get { self[ThemeAccentKey.self] }
        set { self[ThemeAccentKey.self] = newValue }
    }
}

/// Scales down slightly on press, with a spring.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
