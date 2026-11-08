import SwiftUI

struct Card<Content: View>: View {
    var padding: CGFloat
    private let content: Content

    init(padding: CGFloat = Theme.padding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
    }
}

extension View {
    func cardBackground(cornerRadius: CGFloat = Theme.corner) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }
}

/// A titled group: small uppercase header above a Card.
struct CardSection<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    private let content: Content

    init(_ title: String, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title.uppercased())
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)

            Card { VStack(alignment: .leading, spacing: 12) { content } }
        }
    }
}

/// A label / value row used inside cards.
struct InfoRow: View {
    let label: String
    let value: String
    var systemImage: String? = nil
    var monospaced: Bool = false
    var copyable: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundColor(.secondary)
                    .frame(width: 20)
            }
            Text(label)
                .foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(monospaced ? .system(.subheadline, design: .monospaced) : .subheadline)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
        .contextMenu {
            if copyable {
                Button {
                    UIPasteboard.general.string = value
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
