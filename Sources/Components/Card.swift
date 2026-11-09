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
    /// Layered surface: depth fill, soft inner top highlight, gradient hairline border, gentle shadow.
    func cardBackground(cornerRadius: CGFloat = Theme.corner) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }
}

struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat
    var glow: Color? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let dark = scheme == .dark
        let strong = contrast == .increased
        return content
            .background(
                ZStack {
                    // The shadow belongs to the single base shape (cheap path shadow) rather than
                    // to the layered group, which needed an offscreen pass per card.
                    shape.fill(Theme.surface)
                        .shadow(color: (glow ?? .black).opacity(glow == nil ? (dark ? 0.35 : 0.07) : 0.28),
                                radius: glow == nil ? 14 : 18, x: 0, y: glow == nil ? 6 : 8)
                    // Inner highlight: light catching the top edge.
                    shape.fill(
                        LinearGradient(colors: [Color.white.opacity(dark ? 0.055 : 0.5), .clear],
                                       startPoint: .top, endPoint: .center)
                    )
                }
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: strong
                            ? [Color.primary.opacity(0.35), Color.primary.opacity(0.25)]
                            : [Color.white.opacity(dark ? 0.14 : 0.9), Color.primary.opacity(dark ? 0.04 : 0.07)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
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
        VStack(alignment: .leading, spacing: Space.x2) {
            SectionHeader(title, systemImage: systemImage)

            Card { VStack(alignment: .leading, spacing: Space.x3) { content } }
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
        HStack(alignment: .firstTextBaseline, spacing: Space.x3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundColor(.secondary)
                    .frame(width: 20)
            }
            Text(label)
                .foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(monospaced ? .system(.subheadline, design: .rounded) : .subheadline)
                .multilineTextAlignment(.trailing)
                // Values here are names / IDs: one line, shrink a little, truncate in the middle.
                .identifierText(minimumScale: 0.7)
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
