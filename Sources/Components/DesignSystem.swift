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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKeys.backgroundAnimation) private var animationEnabled = true
    @ObservedObject private var power = PowerMonitor.shared

    /// One blob: its own looping path (a slow figure-eight), speed, size and opacity breathing.
    private struct Blob {
        let colorPosition: Double   // where on the theme gradient its colour comes from
        let size: CGFloat           // × screen width
        let base: CGPoint           // centre, as a fraction of the screen
        let amplitude: CGSize       // travel, as a fraction of the screen
        let period: Double          // seconds per loop (20 – 40 s)
        let phase: Double
        let opacity: Double
    }

    private static let blobs: [Blob] = [
        Blob(colorPosition: 0, size: 1.25, base: CGPoint(x: 0.12, y: 0.10), amplitude: CGSize(width: 0.20, height: 0.08), period: 26, phase: 0, opacity: 1),
        Blob(colorPosition: 0.5, size: 1.10, base: CGPoint(x: 0.88, y: 0.16), amplitude: CGSize(width: 0.18, height: 0.10), period: 34, phase: 1.7, opacity: 0.85),
        Blob(colorPosition: 1, size: 0.95, base: CGPoint(x: 0.55, y: 0.36), amplitude: CGSize(width: 0.24, height: 0.11), period: 21, phase: 3.1, opacity: 0.6),
        Blob(colorPosition: 0.25, size: 1.05, base: CGPoint(x: 0.30, y: 0.78), amplitude: CGSize(width: 0.22, height: 0.07), period: 39, phase: 4.4, opacity: 0.35)
    ]

    private var palette: [Color] { gradient.isEmpty ? Theme.signature : gradient }

    private func color(at position: Double) -> Color {
        let colors = palette
        let index = Int((position * Double(colors.count - 1)).rounded())
        return colors[min(max(index, 0), colors.count - 1)]
    }

    /// Moving only on the visible screen, with the app active, the setting on and Reduce Motion off.
    /// Otherwise the timeline pauses and the blobs hold still (the static version).
    private var animating: Bool {
        active && scenePhase == .active && animationEnabled && !reduceMotion
    }

    var body: some View {
        // Bright, glowing lights: dimmer screens (intensity < 1) still keep most of the glow.
        let strength = (scheme == .dark ? 0.62 : 0.30) * (0.55 + 0.45 * intensity)
        // Low Power Mode: same motion at 15 fps (the drift is slow, so it still looks smooth).
        TimelineView(.animation(minimumInterval: power.lowPower ? 1.0 / 15 : 1.0 / 60, paused: !animating)) { context in
            let time = AuroraClock.shared.time(at: context.date)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    Theme.background
                    ZStack {
                        ForEach(Self.blobs.indices, id: \.self) { index in
                            let blob = Self.blobs[index]
                            let angle = 2 * Double.pi * time / blob.period + blob.phase
                            let size = w * blob.size * CGFloat(1 + 0.12 * sin(angle + 1.1))
                            // Each light brightens and dims on its own rhythm (≈ 65 – 100 %).
                            let pulse = 0.825 + 0.175 * sin(angle * 2 + 2.3)
                            let opacity = min(1, strength * blob.opacity * pulse)
                            blobView(color(at: blob.colorPosition), opacity: opacity, size: size)
                                .position(x: w * (blob.base.x + blob.amplitude.width * CGFloat(sin(angle))),
                                          y: h * (blob.base.y + blob.amplitude.height * CGFloat(sin(2 * angle + blob.phase))))
                                // Overlapping lights add up and glow where they meet (dark mode).
                                .blendMode(scheme == .dark ? .plusLighter : .normal)
                        }
                    }
                    .frame(width: w, height: h)
                    .drawingGroup()
                }
                .frame(width: w, height: h)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func blobView(_ color: Color, opacity: Double, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), color.opacity(opacity * 0.55), color.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
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

// MARK: - Separators

/// Very faint separator for rows inside cards (replaces bright system `Divider()`s).
struct SoftDivider: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(contrast == .increased ? 0.18 : 0.05))
            .frame(height: 0.5)
            .padding(.vertical, 1)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Faint list-row separators (Settings, Library, Sources, Search lists).
    func softRowSeparators() -> some View {
        listRowSeparatorTint(Color.primary.opacity(0.06))
    }
}

// MARK: - Delete dissolve

enum DeleteMotion {
    /// The dissolve itself (scale down, blur, brighten, fade).
    static let dissolve = Animation.easeIn(duration: 0.28)
    static let dissolveNanoseconds: UInt64 = 280_000_000
}

extension View {
    /// Quick dissolve for an item being deleted. Fade only with Reduce Motion.
    func dissolving(_ active: Bool) -> some View {
        modifier(Dissolve(active: active))
    }
}

private struct Dissolve: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let motion = active && !reduceMotion
        content
            .scaleEffect(motion ? 0.92 : 1)
            .blur(radius: motion ? 8 : 0)
            .brightness(motion ? 0.12 : 0)
            .opacity(active ? 0 : 1)
            .allowsHitTesting(!active)
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
