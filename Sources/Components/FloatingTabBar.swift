import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home, library, sources, settings
    /// iOS 26+ only: the native Liquid Glass search tab.
    case search

    var id: String { rawValue }

    /// Tabs shown in the custom bar on iOS 16–25 (no search tab there).
    static let barTabs: [AppTab] = [.home, .library, .sources, .settings]

    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .sources: return "Sources"
        case .settings: return "Settings"
        case .search: return "Search"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .library: return "square.stack.3d.up.fill"
        case .sources: return "shippingbox.fill"
        case .settings: return "gearshape.fill"
        case .search: return "magnifyingglass"
        }
    }
}

/// Custom floating bar for iOS 16–25 (iOS 26+ uses the native Liquid Glass TabView).
/// Place it with `.safeAreaInset(edge: .bottom)` so content always sits above it.
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    var badges: [AppTab: Int] = [:]
    /// Tabs that show a red dot without a number (when they have no count badge).
    var dots: Set<AppTab> = []

    @Environment(\.themeAccent) private var accent
    @Environment(\.themeGradient) private var gradient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: Space.x1) {
            ForEach(AppTab.barTabs) { tab in
                item(tab)
            }
        }
        .background {
            // ONE pill that slides from tab to tab (gradient-tinted glass, lit edge, soft glow).
            Capsule()
                .fill(LinearGradient(colors: gradient.map { $0.opacity(0.22) },
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Capsule().strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.35), accent.opacity(0.25)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: Border.width))
                .shadow(color: accent.opacity(0.3), radius: 10, y: 2)
                .matchedGeometryEffect(id: selection, in: namespace, properties: .frame, isSource: false)
        }
        .animation(reduceMotion ? Motion.fade : Motion.selection, value: selection)
        .padding(Space.x2)
        .glassCapsule()
        .padding(.horizontal, Space.x8)
        .padding(.bottom, Space.x1)
    }

    private func item(_ tab: AppTab) -> some View {
        let selected = tab == selection
        let badge = badges[tab] ?? 0
        let dot = dots.contains(tab)
        return Button {
            guard tab != selection else { return }
            Haptics.selection()
            withAnimation(Motion.snappy) { selection = tab }
        } label: {
            VStack(spacing: Space.x1) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 19, weight: .semibold))
                        .symbolBounce(value: selected)
                        .scaleEffect(selected ? 1.08 : 1)
                        .frame(width: 30, height: 24)
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, Space.x1)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(Capsule().fill(Theme.danger))
                            .offset(x: 10, y: -6)
                            .transition(.scale.combined(with: .opacity))
                    }
                    NotificationDot(visible: badge == 0 && dot)
                        .offset(x: 3, y: -1)
                }
                Text(tab.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundColor(selected ? accent : .secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, Space.hair)
            .background(
                // Where the single sliding selection pill sits for this tab.
                Color.clear.matchedGeometryEffect(id: tab, in: namespace, properties: .frame, isSource: true)
            )
            .contentShape(Capsule())
            .animation(Theme.bouncy, value: badge)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.92))
        .accessibilityLabel(badge > 0 ? "\(tab.title), \(badge) need attention"
                            : dot ? "\(tab.title), update available" : tab.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Glass styling

/// Pre-iOS 26 stand-in for Liquid Glass: material, faint white stroke, top highlight, soft shadow.
private struct LegacyGlass<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(
                shape.fill(
                    LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0)],
                                   startPoint: .top, endPoint: .center)
                )
                .allowsHitTesting(false)
            )
            .overlay(shape.strokeBorder(Color.white.opacity(0.15), lineWidth: 1).allowsHitTesting(false))
            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
    }
}

extension View {
    /// Liquid Glass capsule on iOS 26+, material capsule before.
    @ViewBuilder
    func glassCapsule() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self.modifier(LegacyGlass(shape: Capsule()))
        }
        #else
        self.modifier(LegacyGlass(shape: Capsule()))
        #endif
    }

    /// Round glass background for small floating icon buttons (toolbar items get native glass on iOS 26).
    @ViewBuilder
    func glassIconButton() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self
        } else {
            self.frame(width: 34, height: 34).modifier(LegacyGlass(shape: Circle()))
        }
        #else
        self.frame(width: 34, height: 34).modifier(LegacyGlass(shape: Circle()))
        #endif
    }

    /// Library search: inline on iOS 16–25; on iOS 26+ the native Search tab handles it.
    @ViewBuilder
    func librarySearchable(text: Binding<String>) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self
        } else {
            self.searchable(text: text, prompt: "Search signed apps")
        }
        #else
        self.searchable(text: text, prompt: "Search signed apps")
        #endif
    }

    /// SF Rounded everywhere (fontDesign needs iOS 16.1).
    @ViewBuilder
    func roundedDesign() -> some View {
        if #available(iOS 16.1, *) {
            self.fontDesign(.rounded)
        } else {
            self
        }
    }
}

/// Background for dashboard-style screens and sheets: the animated aurora (see DesignSystem.swift).
struct AmbientBackground: View {
    var body: some View {
        AuroraBackground()
    }
}
