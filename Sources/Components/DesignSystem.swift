import SwiftUI

// Design system: typography, glass, glow, symbol effects, aurora background and shared controls.
// Tokens (colours, spacing, radii, motion) live in Theme.swift.

// MARK: - Typography

extension Font {
    /// Big hero numbers and titles.
    static let csDisplay = Font.system(size: 34, weight: .bold, design: .rounded)
    static let csTitle = Font.system(.title2, design: .rounded).weight(.bold)
    static let csHeadline = Font.system(.headline, design: .rounded)
    static let csBody = Font.system(.body, design: .rounded)
    static let csCaption = Font.system(.caption, design: .rounded).weight(.medium)
    /// Overlines ("ACTIVE CERTIFICATE").
    static let csOverline = Font.system(.caption2, design: .rounded).weight(.bold)
}

extension View {
    /// Tight tracking for large titles.
    func displayTracking() -> some View { tracking(-0.4) }

    /// Tabular digits so counters don't jiggle.
    func tabularDigits() -> some View { monospacedDigit() }
}

// MARK: - Gradients

extension LinearGradient {
    static func accent(_ colors: [Color], angle: UnitPoint = .topLeading, to end: UnitPoint = .bottomTrailing) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: angle, endPoint: end)
    }
}

extension View {
    /// Fills text / symbols with the accent gradient.
    func accentGradientForeground(_ colors: [Color]) -> some View {
        foregroundStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    /// Soft coloured glow behind a key element (shadow-based, cheap; off with Reduce Transparency).
    func ambientGlow(_ color: Color, radius: CGFloat = 18, opacity: Double = 0.45) -> some View {
        modifier(AmbientGlow(color: color, radius: radius, opacity: opacity))
    }
}

private struct AmbientGlow: ViewModifier {
    let color: Color
    let radius: CGFloat
    let opacity: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.shadow(color: color.opacity(reduceTransparency ? 0 : opacity), radius: radius, x: 0, y: radius / 3)
    }
}

// MARK: - Glass surfaces

extension View {
    /// Liquid Glass on iOS 26+, layered material with highlight + hairline before.
    /// With Reduce Transparency the fallback becomes an opaque surface.
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = Theme.corner, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            self.modifier(MaterialGlass(cornerRadius: cornerRadius))
        }
        #else
        self.modifier(MaterialGlass(cornerRadius: cornerRadius))
        #endif
    }
}

private struct MaterialGlass: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                if reduceTransparency {
                    shape.fill(Theme.surfaceRaised)
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
            .overlay(
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.12), .clear], startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false)
            )
            .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1).allowsHitTesting(false))
    }
}

// MARK: - Symbol effects (iOS 17+, no-ops before; respect Reduce Motion)

extension View {
    /// Bounces an SF Symbol whenever `value` changes.
    func symbolBounce<V: Equatable>(value: V) -> some View {
        modifier(SymbolBounce(value: value))
    }

    /// Gentle repeating pulse while `active`.
    func symbolPulse(_ active: Bool = true) -> some View {
        modifier(SymbolPulse(active: active))
    }

    /// Iterative variable-colour animation while `active` (e.g. "working" symbols).
    func symbolVariableColor(_ active: Bool = true) -> some View {
        modifier(SymbolVariableColor(active: active))
    }

    /// Animated symbol swap when the image name changes.
    @ViewBuilder
    func symbolReplace() -> some View {
        if #available(iOS 17.0, *) {
            self.contentTransition(.symbolEffect(.replace))
        } else {
            self
        }
    }
}

private struct SymbolBounce<V: Equatable>: ViewModifier {
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            if reduceMotion {
                content
            } else {
                content.symbolEffect(.bounce, value: value)
            }
        } else {
            content
        }
    }
}

private struct SymbolPulse: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.symbolEffect(.pulse, isActive: active && !reduceMotion)
        } else {
            content
        }
    }
}

private struct SymbolVariableColor: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.symbolEffect(.variableColor.iterative, isActive: active && !reduceMotion)
        } else {
            content
        }
    }
}

// MARK: - Aurora background

/// Cheap animated aurora: a few large radial gradients drifting slowly over the base colour.
/// No blur filters (radial gradients are already soft). Static with Reduce Motion.
struct AuroraBackground: View {
    var intensity: Double = 1

    @Environment(\.themeGradient) private var gradient
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.auroraActive) private var active
    @State private var drift = false

    private var colors: [Color] {
        let base = gradient.isEmpty ? Theme.signature : gradient
        return [base[0], base[min(1, base.count - 1)], base[base.count - 1]]
    }

    var body: some View {
        let strength = (scheme == .dark ? 0.30 : 0.16) * intensity
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                Theme.background
                blob(colors[0], opacity: strength, size: w * 1.25)
                    .offset(x: drift ? -w * 0.28 : -w * 0.42, y: drift ? -w * 0.42 : -w * 0.55)
                blob(colors[1], opacity: strength * 0.85, size: w * 1.1)
                    .offset(x: drift ? w * 0.38 : w * 0.24, y: drift ? -w * 0.30 : -w * 0.48)
                blob(colors[2], opacity: strength * 0.6, size: w * 0.95)
                    .offset(x: drift ? w * 0.05 : w * 0.18, y: drift ? -w * 0.05 : -w * 0.18)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { updateDrift() }
        .onChange(of: active) { _ in updateDrift() }
    }

    /// Drifts only while visible (hidden tabs pause, so off-screen auroras cost nothing).
    private func updateDrift() {
        if active && !reduceMotion {
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) { drift = true }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { drift = false }
        }
    }

    private func blob(_ color: Color, opacity: Double, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), color.opacity(0)], center: .center,
                                 startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct AuroraActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False for screens that are alive but hidden (inactive tabs): the aurora stops animating.
    var auroraActive: Bool {
        get { self[AuroraActiveKey.self] }
        set { self[AuroraActiveKey.self] = newValue }
    }
}

// MARK: - Focus glow for text fields

extension View {
    /// Accent ring + glow while focused (wrap the field's container).
    func focusGlow(_ focused: Bool, cornerRadius: CGFloat = Radius.sm) -> some View {
        modifier(FocusGlow(focused: focused, cornerRadius: cornerRadius))
    }
}

private struct FocusGlow: ViewModifier {
    let focused: Bool
    let cornerRadius: CGFloat
    @Environment(\.themeAccent) private var accent

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(.horizontal, Space.x3)
            .padding(.vertical, Space.x2 + 2)
            .background(shape.fill(Color.primary.opacity(0.045)))
            .overlay(shape.strokeBorder(focused ? accent.opacity(0.9) : Theme.hairline, lineWidth: focused ? 1.5 : 1))
            .shadow(color: accent.opacity(focused ? 0.28 : 0), radius: 10)
            .animation(Motion.snappy, value: focused)
    }
}

/// Plain text field with the focus glow (no autocapitalisation / autocorrect, for IDs and versions).
struct GlowTextField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused)
            .frame(minHeight: 24)
            .focusGlow(focused)
    }
}

// MARK: - Segmented control with a sliding glass indicator

struct GlassSegmentedControl<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        var systemImage: String? = nil
        var id: Value { value }
    }

    @Binding var selection: Value
    let options: [Option]

    @Environment(\.themeAccent) private var accent
    @Environment(\.themeGradient) private var gradient
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: Space.x1) {
            ForEach(options) { option in
                let selected = option.value == selection
                Button {
                    guard !selected else { return }
                    Haptics.selection()
                    withAnimation(Motion.snappy) { selection = option.value }
                } label: {
                    HStack(spacing: 6) {
                        if let image = option.systemImage {
                            Image(systemName: image).symbolBounce(value: selected)
                        }
                        Text(option.title).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(selected ? .white : .primary.opacity(0.75))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background {
                        if selected {
                            Capsule()
                                .fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                                .shadow(color: accent.opacity(0.35), radius: 8, y: 3)
                                .matchedGeometryEffect(id: "segment", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle(scale: 0.95))
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(Space.x1)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - Scroll-driven tilt (hero cards)

extension View {
    /// Subtle 3D tilt + parallax as the view scrolls (iOS 17+, GPU-only via `visualEffect`; none with Reduce Motion).
    func scrollTilt(maxDegrees: Double = 5) -> some View {
        modifier(ScrollTilt(maxDegrees: maxDegrees))
    }
}

private struct ScrollTilt: ViewModifier {
    let maxDegrees: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            if reduceMotion {
                content
            } else {
                let screen = max(UIScreen.main.bounds.height, 1)
                content.visualEffect { effect, proxy in
                    let frame = proxy.frame(in: .global)
                    let t = max(-1, min(1, (frame.midY - screen * 0.55) / (screen * 0.5)))
                    return effect
                        .rotation3DEffect(.degrees(-t * maxDegrees), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                        .offset(x: 0, y: t * -6)
                }
            }
        } else {
            content
        }
    }
}

// MARK: - List rows and rings

/// Background for List rows sitting on the aurora: depth surface with a faint top highlight.
struct RowSurface: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Theme.surface
            LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.04 : 0.35), .clear],
                           startPoint: .top, endPoint: .center)
        }
    }
}

/// Small ring showing how much signing lifetime is left, with days in the middle.
struct ExpiryRing: View {
    /// 0…1 lifetime remaining, nil when unknown.
    let remaining: Double?
    let days: Int?
    let color: Color
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.02, min(1, remaining ?? 0))))
                .stroke(AngularGradient(colors: [color.opacity(0.6), color], center: .center),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(days.map { $0 > 99 ? "99+" : "\($0)" } ?? "–")
                .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .foregroundColor(color)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(days.map { "\($0) days left" } ?? "Expiry unknown")
    }
}

// MARK: - Sheet chrome

extension View {
    /// Consistent sheet look: SF Rounded, visible grabber, large continuous corners (iOS 16.4+).
    @ViewBuilder
    func sheetChrome() -> some View {
        if #available(iOS 16.4, *) {
            self.roundedDesign()
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Radius.xl)
        } else {
            self.roundedDesign()
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Staggered entrance

extension View {
    /// Fades/rises in with a per-index delay on first appearance (fade only with Reduce Motion).
    func staggeredEntrance(_ index: Int, active: Bool) -> some View {
        modifier(StaggeredEntrance(index: index, active: active))
    }
}

private struct StaggeredEntrance: ViewModifier {
    let index: Int
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(active ? 1 : 0)
            .offset(y: active || reduceMotion ? 0 : 16)
            .scaleEffect(active || reduceMotion ? 1 : 0.98)
            .animation(Motion.adaptive(Motion.smooth, reduceMotion: reduceMotion).delay(Double(index) * Motion.stagger),
                       value: active)
    }
}
