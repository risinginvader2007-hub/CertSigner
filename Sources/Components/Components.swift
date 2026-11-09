import SwiftUI

// Reusable building blocks. Screens are assembled from these (plus Card / CardSection in Card.swift,
// PrimaryButton, ToastView, EmptyStateView). See DESIGN.md.

// MARK: - Section header

/// Small uppercase title above a card or list section, with an optional trailing accessory
/// (a count, "Last updated", a button).
struct SectionHeader<Accessory: View>: View {
    let title: String
    var systemImage: String? = nil
    private let accessory: Accessory

    init(_ title: String, systemImage: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: Space.x2) {
            HStack(spacing: Space.x2) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title.uppercased())
                    .lineLimit(1)
            }
            .font(TypeScale.sectionTitle)
            .tracking(0.6)
            .foregroundColor(SemanticColor.textSecondary)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.x2)
            accessory
                .font(TypeScale.caption)
                .foregroundColor(SemanticColor.textSecondary)
        }
        .padding(.horizontal, Space.x1)
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(_ title: String, systemImage: String? = nil) {
        self.init(title, systemImage: systemImage) { EmptyView() }
    }
}

// MARK: - Icon tile

/// Rounded, coloured square holding an SF Symbol (settings rows, storage categories, stats).
struct IconTile: View {
    let systemImage: String
    var color: Color
    var size: CGFloat = 32
    /// Solid fill with a white glyph (true) or a soft tint with a coloured glyph (false).
    var filled = true

    var body: some View {
        let radius = Radius.inner(size * 0.36 + 4, padding: 4)
        Image(systemName: systemImage)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundColor(filled ? .white : color)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(filled
                          ? AnyShapeStyle(LinearGradient(colors: [color.opacity(0.85), color],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(color.opacity(0.16)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(filled ? 0.22 : 0), lineWidth: Border.hairlineWidth)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - List row

/// Standard row: icon tile, title, optional subtitle, trailing content. 44 pt minimum height.
struct ListRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var tint: Color = .accentColor
    private let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, systemImage: String? = nil, tint: Color = .accentColor,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Space.x3) {
            if let systemImage {
                IconTile(systemImage: systemImage, color: tint, size: 30)
            }
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(title)
                    .font(TypeScale.body)
                    .foregroundColor(SemanticColor.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(TypeScale.caption)
                        .foregroundColor(SemanticColor.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Space.x2)
            trailing
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension ListRow where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, systemImage: String? = nil, tint: Color = .accentColor) {
        self.init(title, subtitle: subtitle, systemImage: systemImage, tint: tint) { EmptyView() }
    }
}

// MARK: - Pill / badge

/// The shared badge (kinds: success, warning, danger, info, neutral).
typealias Pill = StatusBadge

// MARK: - Stat tile

/// Number + label + icon, used on Home and the storage dashboard. Numbers roll with a numeric
/// transition (iOS 17+).
struct StatTile: View {
    let value: String
    let label: String
    let systemImage: String
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Shown value: counts up once from 0 when the tile first appears, then follows `value`.
    @State private var shown: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2 + 2) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundColor(tint)
                .symbolBounce(value: value)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs + 2, style: .continuous)
                        .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.10)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .overlay(RoundedRectangle(cornerRadius: Radius.xs + 2, style: .continuous)
                    .strokeBorder(tint.opacity(0.3), lineWidth: Border.hairlineWidth))
                .ambientGlow(tint, radius: 8, opacity: 0.35)
            Text(shown ?? value)
                .font(TypeScale.number)
                .monospacedDigit()
                .displayTracking()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .numericTransition()
            Text(label)
                .font(TypeScale.caption)
                .foregroundColor(SemanticColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(Space.x3 + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .glassShine(cornerRadius: Theme.corner)
        .onAppear {
            guard shown == nil else { return }
            guard !reduceMotion, Int(value) != nil else { shown = value; return }
            shown = "0"
            withAnimation(.easeOut(duration: 0.45).delay(0.1)) { shown = value }
        }
        .onChange(of: value) { newValue in
            withAnimation(Motion.smooth) { shown = newValue }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Error state

/// Something failed: icon, short title, one plain-language sentence, Retry, and the technical
/// detail tucked into a "Details" disclosure.
struct ErrorState: View {
    var systemImage = "exclamationmark.triangle.fill"
    let title: String
    let message: String
    var details: String? = nil
    var retryTitle = "Try Again"
    var onRetry: (() -> Void)? = nil
    /// Compact inline version (inside a card or row) instead of a full-screen state.
    var compact = false

    @State private var showDetails = false

    var body: some View {
        VStack(alignment: compact ? .leading : .center, spacing: compact ? Space.x2 : Space.x3) {
            if compact {
                Label(title, systemImage: systemImage)
                    .font(TypeScale.subheadline.weight(.semibold))
                    .foregroundColor(SemanticColor.warning)
            } else {
                IconTile(systemImage: systemImage, color: SemanticColor.warning, size: 56, filled: false)
                Text(title)
                    .font(TypeScale.headline)
                    .multilineTextAlignment(.center)
            }
            Text(message)
                .font(compact ? TypeScale.caption : TypeScale.subheadline)
                .foregroundColor(SemanticColor.textSecondary)
                .multilineTextAlignment(compact ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
            if let details, !details.isEmpty {
                DisclosureGroup(isExpanded: $showDetails) {
                    Text(details)
                        .font(.caption2.monospaced())
                        .foregroundColor(SemanticColor.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Space.x1)
                } label: {
                    Text("Details").font(TypeScale.caption)
                }
                .frame(maxWidth: compact ? .infinity : 320)
            }
            if let onRetry {
                if compact {
                    Button(retryTitle, action: onRetry)
                        .font(TypeScale.captionStrong)
                        .buttonStyle(.borderless)
                } else {
                    PrimaryButton(title: retryTitle, systemImage: "arrow.clockwise", style: .tinted, action: onRetry)
                        .frame(maxWidth: 240)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: compact ? .leading : .center)
        .padding(compact ? 0 : Space.x6)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Loading skeleton

/// Shimmering placeholder rows while content loads.
struct LoadingSkeleton: View {
    var rows = 3
    var showsIcon = true

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            ForEach(0..<rows, id: \.self) { index in
                HStack(spacing: Space.x3) {
                    if showsIcon {
                        SkeletonBlock(width: 36, height: 36, cornerRadius: Radius.xs)
                    }
                    VStack(alignment: .leading, spacing: Space.x2) {
                        SkeletonBlock(width: index.isMultiple(of: 2) ? 150 : 120, height: 12)
                        SkeletonBlock(width: index.isMultiple(of: 2) ? 90 : 110, height: 10)
                    }
                    Spacer()
                    SkeletonBlock(width: 44, height: 12)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

/// The shared empty state (icon, title, one-line explanation, one action).
typealias EmptyState = EmptyStateView
