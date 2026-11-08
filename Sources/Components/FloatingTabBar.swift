import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home, library, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .library: return "square.stack.3d.up.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Floating glass tab bar with a sliding selection pill and per-tab badges.
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    var badges: [AppTab: Int] = [:]

    @Environment(\.themeAccent) private var accent
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                item(tab)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
        .padding(.horizontal, 28)
        .padding(.bottom, 6)
    }

    private func item(_ tab: AppTab) -> some View {
        let selected = tab == selection
        let badge = badges[tab] ?? 0
        return Button {
            guard tab != selection else { return }
            Haptics.selection()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { selection = tab }
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 19, weight: .semibold))
                        .scaleEffect(selected ? 1.08 : 1)
                        .frame(width: 30, height: 24)
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(Capsule().fill(Theme.danger))
                            .offset(x: 10, y: -6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(tab.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundColor(selected ? accent : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                if selected {
                    Capsule()
                        .fill(accent.opacity(0.16))
                        .matchedGeometryEffect(id: "selection", in: namespace)
                }
            }
            .contentShape(Capsule())
            .animation(Theme.bouncy, value: badge)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.92))
        .accessibilityLabel(badge > 0 ? "\(tab.title), \(badge) need attention" : tab.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

extension View {
    /// Keeps scrolling content clear of the floating tab bar.
    func floatingTabBarInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 76)
        }
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

/// Soft accent glow behind dashboard-style screens.
struct AmbientBackground: View {
    @Environment(\.themeAccent) private var accent

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            LinearGradient(colors: [accent.opacity(0.18), accent.opacity(0.04), .clear],
                           startPoint: .top, endPoint: .center)
                .frame(height: 420)
        }
        .ignoresSafeArea()
    }
}
