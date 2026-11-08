import SwiftUI

struct StatusBadge: View {
    enum Kind { case success, warning, danger, info, neutral }

    let text: String
    var systemImage: String? = nil
    var kind: Kind = .neutral

    @Environment(\.themeAccent) private var accent

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundColor(color)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().strokeBorder(color.opacity(0.28), lineWidth: 0.75))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    private var color: Color {
        switch kind {
        case .success: return Theme.success
        case .warning: return Theme.warning
        case .danger: return Theme.danger
        case .info: return accent
        case .neutral: return .secondary
        }
    }
}
