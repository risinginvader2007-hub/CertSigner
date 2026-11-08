import SwiftUI

struct PrimaryButton: View {
    enum Style { case filled, tinted, destructive }
    /// Brief morph after an action: green check or red cross.
    enum Feedback: Equatable { case success, error }

    let title: String
    var systemImage: String? = nil
    var style: Style = .filled
    var isLoading: Bool = false
    var feedback: Feedback? = nil
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.themeAccent) private var accent
    @Environment(\.themeGradient) private var themeGradient
    @Environment(\.colorSchemeContrast) private var contrast

    /// The accent gradient, unless a screen overrode the accent (e.g. red for destructive actions).
    private var fillColors: [Color] {
        if let feedback { return feedback == .success ? [Theme.success.opacity(0.85), Theme.success]
                                                      : [Theme.danger.opacity(0.85), Theme.danger] }
        return accent == Theme.danger ? [Theme.danger.opacity(0.85), Theme.danger] : themeGradient
    }

    var body: some View {
        Button {
            Haptics.impact(.medium)
            action()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(foreground)
                } else if let feedback {
                    Image(systemName: feedback == .success ? "checkmark" : "xmark")
                        .fontWeight(.bold)
                        .symbolBounce(value: feedback)
                        .transition(.scale.combined(with: .opacity))
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .transition(.scale.combined(with: .opacity))
                }
                Text(title).fontWeight(.semibold)
            }
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: 22)
            .padding(.vertical, 15)
            .padding(.horizontal, Space.x4)
            .foregroundColor(foreground)
            .background(background)
            .overlay(
                // Inner highlight + hairline: the "lit edge" of the button.
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(style == .tinted ? 0.12 : 0.38),
                                                Color.white.opacity(contrast == .increased ? 0.3 : 0.04)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .ambientGlow(style == .tinted ? .clear : (style == .destructive ? Theme.danger : accent),
                         radius: 14, opacity: isEnabled ? 0.38 : 0)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
        .opacity(isEnabled ? 1 : 0.45)
        .allowsHitTesting(!isLoading)
        .animation(Theme.spring, value: isLoading)
        .animation(Motion.bouncy, value: feedback)
        .accessibilityLabel(title)
    }

    private var foreground: Color {
        switch style {
        case .filled, .destructive: return .white
        case .tinted: return accent
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .filled:
            LinearGradient(colors: fillColors, startPoint: .topLeading, endPoint: .bottomTrailing)
        case .tinted:
            accent.opacity(0.14)
        case .destructive:
            LinearGradient(colors: [Theme.danger.opacity(0.85), Theme.danger], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
