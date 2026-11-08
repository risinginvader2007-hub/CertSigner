import SwiftUI

struct PrimaryButton: View {
    enum Style { case filled, tinted, destructive }

    let title: String
    var systemImage: String? = nil
    var style: Style = .filled
    var isLoading: Bool = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.themeAccent) private var accent

    var body: some View {
        Button {
            Haptics.impact(.medium)
            action()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(foreground)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title).fontWeight(.semibold)
            }
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: 22)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .foregroundColor(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .opacity(isEnabled ? 1 : 0.45)
        .allowsHitTesting(!isLoading)
        .animation(Theme.spring, value: isLoading)
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
            LinearGradient(colors: [accent.opacity(0.85), accent], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .tinted:
            accent.opacity(0.14)
        case .destructive:
            LinearGradient(colors: [Theme.danger.opacity(0.85), Theme.danger], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
