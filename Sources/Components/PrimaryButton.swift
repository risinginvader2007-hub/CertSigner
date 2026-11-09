import SwiftUI

/// The one action-button look in the app: a 52 pt capsule. Every primary, secondary and
/// destructive action (including `ShareLink`s and buttons inside sheets) uses this style, so
/// shapes, heights and press effects are identical everywhere. Navigation and information are
/// rows inside a card instead (see `Card`, `ListRow`).
struct AppButtonStyle: ButtonStyle {
    enum Kind {
        /// Accent gradient fill, white label, soft glow.
        case primary
        /// Tinted accent fill and label (follows `themeAccent`, so it can be tinted red).
        case secondary
        /// Red gradient fill, white label.
        case destructive
    }

    enum Size {
        /// Full-width, 52 pt.
        case regular
        /// Hugs its label, 36 pt: for a single action inside a row or card.
        case compact

        var height: CGFloat { self == .regular ? AppButtonStyle.height : 36 }
    }

    static let height: CGFloat = 52

    var kind: Kind = .primary
    var size: Size = .regular
    /// Brief success / error tint used by `PrimaryButton`'s feedback morph.
    var feedback: PrimaryButton.Feedback? = nil

    func makeBody(configuration: Configuration) -> some View {
        AppButtonBody(configuration: configuration, kind: kind, size: size, feedback: feedback)
    }
}

private struct AppButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: AppButtonStyle.Kind
    let size: AppButtonStyle.Size
    let feedback: PrimaryButton.Feedback?

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.themeAccent) private var accent
    @Environment(\.themeGradient) private var themeGradient
    @Environment(\.colorSchemeContrast) private var contrast

    private var fillColors: [Color] {
        if let feedback {
            return feedback == .success ? [Theme.success.opacity(0.85), Theme.success]
                                        : [Theme.danger.opacity(0.85), Theme.danger]
        }
        if kind == .destructive || accent == Theme.danger { return [Theme.danger.opacity(0.85), Theme.danger] }
        return themeGradient
    }

    private var foreground: Color {
        kind == .secondary && feedback == nil ? accent : .white
    }

    var body: some View {
        ShinePressEffect(isPressed: configuration.isPressed, shape: Capsule(), scale: 0.97) {
            configuration.label
                .font(size == .regular ? .body.weight(.semibold) : .subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundColor(foreground)
                .padding(.horizontal, size == .regular ? Space.x4 : Space.x4)
                .frame(maxWidth: size == .regular ? .infinity : nil)
                .frame(height: size.height)
                .background(background)
                .overlay(
                    // Inner highlight + hairline: the "lit edge" of the button.
                    Capsule().strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(kind == .secondary && feedback == nil ? 0.12 : 0.38),
                                                Color.white.opacity(contrast == .increased ? 0.3 : 0.04)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: Border.width
                    )
                )
                .glassShine(in: Capsule())
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        // The glow is a shadow outside the capsule, so it isn't clipped (and never forms a box).
        .ambientGlow(kind == .secondary && feedback == nil ? .clear : fillColors.last ?? accent,
                     radius: size == .regular ? 14 : 8, opacity: isEnabled ? 0.38 : 0)
        .opacity(isEnabled ? 1 : 0.45)
    }

    @ViewBuilder
    private var background: some View {
        if kind == .secondary && feedback == nil {
            Capsule().fill(accent.opacity(0.14))
        } else {
            Capsule().fill(LinearGradient(colors: fillColors, startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}

/// Press feedback for a tap row inside a card: a faint highlight, no scale (so the card's
/// clipped edge never shifts and no corner peeks out).
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(Color.primary.opacity(configuration.isPressed ? 0.06 : 0).allowsHitTesting(false))
            .animation(Motion.fade, value: configuration.isPressed)
    }
}

extension View {
    /// A button placed directly in a List/Form section: no row card behind it (so the card above
    /// keeps its rounded corners), no insets, a little vertical breathing room.
    func buttonRow() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: Space.x1, leading: 0, bottom: Space.x1, trailing: 0))
            .listRowSeparator(.hidden)
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    static func app(_ kind: AppButtonStyle.Kind = .primary, size: AppButtonStyle.Size = .regular) -> AppButtonStyle {
        AppButtonStyle(kind: kind, size: size)
    }
}

/// A full-width action button in `AppButtonStyle`, with an optional icon, loading spinner and a
/// brief success / error morph.
struct PrimaryButton: View {
    /// `filled` = primary, `tinted` = secondary, `destructive` = red fill.
    enum Style { case filled, tinted, destructive }
    /// Brief morph after an action: green check or red cross.
    enum Feedback: Equatable { case success, error }

    let title: String
    var systemImage: String? = nil
    var style: Style = .filled
    var isLoading: Bool = false
    var feedback: Feedback? = nil
    let action: () -> Void

    private var kind: AppButtonStyle.Kind {
        switch style {
        case .filled: return .primary
        case .tinted: return .secondary
        case .destructive: return .destructive
        }
    }

    var body: some View {
        Button {
            Haptics.impact(.medium)
            action()
        } label: {
            HStack(spacing: Space.x2) {
                if isLoading {
                    ProgressView().tint(kind == .secondary ? nil : .white)
                } else if let feedback {
                    Image(systemName: feedback == .success ? "checkmark" : "xmark")
                        .fontWeight(.bold)
                        .symbolBounce(value: feedback)
                        .transition(.scale.combined(with: .opacity))
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .transition(.scale.combined(with: .opacity))
                }
                Text(title)
            }
        }
        .buttonStyle(AppButtonStyle(kind: kind, feedback: feedback))
        .allowsHitTesting(!isLoading)
        .animation(Theme.spring, value: isLoading)
        .animation(Motion.bouncy, value: feedback)
        .accessibilityLabel(title)
    }
}
