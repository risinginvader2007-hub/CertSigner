import SwiftUI

// CertSigner design tokens: the one place for spacing, radii, type, elevation, borders,
// semantic colours and motion. Screens and components use these, never raw numbers.
// Documented in DESIGN.md.

// MARK: - Motion

/// Shared motion spec. Springs for interactions; ease-in-out for colour and opacity; 0.2 – 0.45 s.
enum Motion {
    /// Taps, toggles, selection pills: quick and crisp.
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.82)
    /// Layout changes, cards appearing, sheets' inner content.
    static let smooth = Animation.spring(response: 0.45, dampingFraction: 0.86)
    /// Playful confirmations: checkmarks, badges, icons popping in.
    static let bouncy = Animation.spring(response: 0.42, dampingFraction: 0.68)
    /// Sliding selection highlights (segmented controls, swatch rings, tab bar).
    static let selection = Animation.spring(response: 0.35, dampingFraction: 0.82)
    /// Opacity changes.
    static let fade = Animation.easeInOut(duration: 0.25)
    /// Colour changes (theme / accent cross-fade).
    static let color = Animation.easeInOut(duration: 0.35)
    /// Ambient loops only (glows, breathing). Not for interactions.
    static let gentle = Animation.easeInOut(duration: 0.6)

    /// Durations (seconds) for non-spring timing.
    static let quick: Double = 0.2
    static let standard: Double = 0.3
    static let slow: Double = 0.45
    /// Theme / accent / appearance cross-fade.
    static let themeCrossfade: Double = 0.35
    /// Delay between items in staggered entrances (capped so a whole list is in by 0.3 s).
    static let stagger: Double = 0.04
    static let maxStaggerDelay: Double = 0.16

    /// With Reduce Motion on, movement becomes a short cross-fade.
    static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : animation
    }
}

// MARK: - Spacing

/// 4/8 pt spacing grid. Named scale: xs 4 · s 8 · m 12 · l 16 · xl 24 · xxl 32.
enum Space {
    /// 2 pt: only for tight line gaps inside one text block (title / subtitle).
    static let hair: CGFloat = 2
    static let x1: CGFloat = 4
    static let x2: CGFloat = 8
    static let x3: CGFloat = 12
    static let x4: CGFloat = 16
    /// 20 pt: gap between top-level sections on a screen.
    static let x5: CGFloat = 20
    static let x6: CGFloat = 24
    static let x8: CGFloat = 32

    static let xs = x1
    static let s = x2
    static let m = x3
    static let l = x4
    static let xl = x6
    static let xxl = x8
}

// MARK: - Corner radii

/// One corner-radius scale; always used with `style: .continuous`.
enum Radius {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
    static let xl: CGFloat = 28
    /// Fully rounded ends (use `Capsule()` where possible).
    static let pill: CGFloat = 999
    /// Icon tiles: the same squircle proportion as an app icon (radius = 28% of the side).
    static func tile(_ side: CGFloat) -> CGFloat { (side * 0.28).rounded() }

    static let small = sm
    static let medium = md
    static let large = lg

    /// Nested shapes: inner radius = outer radius − padding (never below 4).
    static func inner(_ outer: CGFloat, padding: CGFloat) -> CGFloat {
        max(4, outer - padding)
    }
}

// MARK: - Type scale

/// Fixed type scale (SF Rounded comes from `.roundedDesign()` at the root). All sizes scale with
/// Dynamic Type.
enum TypeScale {
    static let largeTitle = Font.largeTitle.weight(.bold)
    static let title = Font.title2.weight(.bold)
    static let headline = Font.headline
    static let body = Font.body
    static let callout = Font.callout
    static let subheadline = Font.subheadline
    static let caption = Font.caption.weight(.medium)
    static let captionStrong = Font.caption.weight(.semibold)
    /// Section titles above cards / list sections.
    static let sectionTitle = Font.caption.weight(.semibold)
    /// Big numbers (stats, storage totals).
    static let number = Font.system(.title, design: .rounded).weight(.bold)
}

// MARK: - Semantic colours

/// Semantic colours. All are dynamic (light / dark); the accent follows the active theme via
/// `@Environment(\.themeAccent)`.
enum SemanticColor {
    static let surface = Theme.surface
    static let elevatedSurface = Theme.surfaceRaised
    static let background = Theme.background
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let success = Theme.success
    static let warning = Theme.warning
    static let danger = Theme.danger
    static let hairline = Theme.hairline
}

// MARK: - Borders & elevation

enum Border {
    static let width: CGFloat = 1
    static let hairlineWidth: CGFloat = 0.75
}

enum Elevation {
    /// Flat rows inside a card.
    case flat
    /// Cards on the screen background.
    case raised
    /// Things floating above content (toasts, tab bar, sheets' hero).
    case floating
}

extension View {
    /// Shared shadow styles.
    func elevation(_ level: Elevation) -> some View {
        modifier(ElevationShadow(level: level))
    }
}

private struct ElevationShadow: ViewModifier {
    let level: Elevation
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        switch level {
        case .flat:
            content
        case .raised:
            content.shadow(color: .black.opacity(dark ? 0.35 : 0.07), radius: 14, x: 0, y: 6)
        case .floating:
            content.shadow(color: .black.opacity(dark ? 0.4 : 0.12), radius: 18, x: 0, y: 8)
        }
    }
}
