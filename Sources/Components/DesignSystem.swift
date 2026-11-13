import SwiftUI
import QuartzCore

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
            // Concentric with the container (the screen / sheet), so a panel near the device's
            // edge follows its corner curve instead of using a fixed radius.
            if interactive {
                self.glassEffect(.regular.interactive(), in: ConcentricRectangle())
            } else {
                self.glassEffect(.regular, in: ConcentricRectangle())
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

/// Cheap animated aurora: a few large radial gradients drifting slowly over the base colour,
/// drawn by ONE Canvas (Metal-backed via drawingGroup) instead of a view per light: no blur
/// filters, no per-frame view diffing. Capped at 30 fps (the drift is slow, so 30 looks the same).
/// Holds still with Reduce Motion, Low Power Mode, the setting off, on hidden tabs, while
/// scrolling and while a sheet is up. Accent changes and light ↔ dark switches redraw for their
/// 0.35 s fade even while the drift is held. All numbers per appearance live in `AuroraStyle`.
struct AuroraBackground: View {
    var intensity: Double = 1

    @Environment(\.themeGradient) private var gradient
    @Environment(\.themeFade) private var fade
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.auroraActive) private var active
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKeys.backgroundAnimation) private var animationEnabled = true
    @AppStorage(SettingsKeys.glowIntensityLight) private var lightLevel: GlowLevel = .normal
    @AppStorage(SettingsKeys.glowIntensityDark) private var darkLevel: GlowLevel = .normal
    @ObservedObject private var power = PowerMonitor.shared
    @ObservedObject private var activity = BackgroundActivity.shared
    @State private var schemeFade: SchemeFade?

    static let frameRate: Double = 30
    private static let lightTraits = UITraitCollection(userInterfaceStyle: .light)

    /// Drifting only on the visible screen, app active, setting on, Reduce Motion and Low Power
    /// off, not scrolling and no sheet up. Otherwise the timeline pauses (the static version).
    private var drifting: Bool {
        active && scenePhase == .active && animationEnabled && !reduceMotion && !power.lowPower && !activity.paused
    }

    var body: some View {
        let dark = scheme == .dark
        let colors = gradient.isEmpty ? Theme.signature : gradient
        // Light mode works on resolved, saturation-boosted colours; dark mode uses the colours as they are.
        let lightColors = colors.map { AuroraStyle.light.boosted(RGBA($0, traits: Self.lightTraits)) }
        // Dimmer screens (intensity < 1) still keep most of the glow.
        let darkGain = AuroraStyle.dark.gain(intensity: intensity, level: darkLevel)
        let lightGain = AuroraStyle.light.gain(intensity: intensity, level: lightLevel)
        let fade = self.fade
        let schemeFade = self.schemeFade
        let transitioning = fade != nil || schemeFade != nil
        TimelineView(.animation(minimumInterval: 1 / Self.frameRate, paused: !(drifting || (transitioning && active)))) { context in
            let time = AuroraClock.shared.time(at: context.date)
            let now = CACurrentMediaTime()
            let stops = fade?.stops(at: now)
            let darkPalette = stops.map { $0.map(\.color) } ?? colors
            let lightPalette = stops.map { $0.map { AuroraStyle.light.boosted($0) } } ?? lightColors
            Canvas { ctx, size in
                if let schemeFade, schemeFade.isRunning(at: now) {
                    // Old appearance underneath, the new one fading in on top (0.35 s theme curve).
                    Self.draw(ctx, dark: schemeFade.fromDark, size: size, time: time,
                              darkPalette: darkPalette, darkGain: darkGain, lightPalette: lightPalette, lightGain: lightGain)
                    var top = ctx
                    top.opacity = schemeFade.progress(at: now)
                    top.drawLayer { layer in
                        Self.draw(layer, dark: !schemeFade.fromDark, size: size, time: time,
                                  darkPalette: darkPalette, darkGain: darkGain, lightPalette: lightPalette, lightGain: lightGain)
                    }
                } else if dark {
                    Self.drawDark(ctx, size: size, time: time, palette: darkPalette, gain: darkGain, base: Theme.background)
                } else {
                    Self.drawLight(ctx, frame: AuroraStyle.light.lightFrame(
                        time: time, size: size, palette: lightPalette, gain: lightGain))
                }
            }
            .drawingGroup()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { BackgroundActivity.shared.installIfNeeded() }
        .onChange(of: scheme) { newScheme in
            let next = SchemeFade(fromDark: newScheme != .dark, start: CACurrentMediaTime(),
                                  duration: reduceMotion ? 0.2 : Motion.themeCrossfade)
            self.schemeFade = next
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64((next.duration + 0.05) * 1_000_000_000))
                if self.schemeFade == next { self.schemeFade = nil }
            }
        }
    }

    /// One whole frame of either appearance (used while switching between them).
    private static func draw(_ ctx: GraphicsContext, dark: Bool, size: CGSize, time: Double,
                             darkPalette: [Color], darkGain: Double, lightPalette: [RGBA], lightGain: Double) {
        if dark {
            drawDark(ctx, size: size, time: time, palette: darkPalette, gain: darkGain, base: AuroraStyle.darkBase.color)
        } else {
            drawLight(ctx, frame: AuroraStyle.light.lightFrame(time: time, size: size, palette: lightPalette, gain: lightGain))
        }
    }

    /// Dark mode, as before: the lights add up and glow where they meet (plusLighter), drawn
    /// straight onto the near-black base (no extra transparency layer: it cost more than it saved).
    private static func drawDark(_ context: GraphicsContext, size: CGSize, time: Double, palette: [Color],
                                 gain: Double, base: Color) {
        let style = AuroraStyle.dark
        var ctx = context
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
        ctx.blendMode = .plusLighter
        for (index, blob) in AuroraGeometry.blobs.enumerated() {
            let placed = AuroraGeometry.place(blob, time: time, size: size, sizeScale: style.sizeScale)
            let opacity = min(1, gain * style.blobOpacities[index] * placed.pulse)
            let color = palette[AuroraGeometry.index(at: blob.colorPosition, count: palette.count)]
            fillGlow(ctx, center: placed.center, diameter: placed.diameter, color: color, opacity: opacity)
        }
    }

    /// Light mode: accent-tinted off-white base, saturated accent glows with normal blending (they
    /// tint the surface instead of vanishing like a lightening blend would), then a soft vignette.
    private static func drawLight(_ ctx: GraphicsContext, frame: AuroraStyle.LightFrame) {
        let rect = CGRect(origin: .zero, size: frame.size)
        ctx.fill(Path(rect), with: .color(frame.base.color))
        for glow in frame.glows {
            fillGlow(ctx, center: glow.center, diameter: glow.diameter, color: glow.color.color, opacity: glow.alpha)
        }
        if frame.vignette > 0 {
            let edge = AuroraStyle.vignetteColor.color
            ctx.fill(Path(rect), with: .radialGradient(
                Gradient(stops: [.init(color: edge.opacity(0), location: 0.55),
                                 .init(color: edge.opacity(frame.vignette), location: 1)]),
                center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0, endRadius: frame.vignetteRadius))
        }
    }

    /// One light: full at the centre, 55 % halfway, gone at the edge.
    private static func fillGlow(_ ctx: GraphicsContext, center: CGPoint, diameter: CGFloat, color: Color, opacity: Double) {
        let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [color.opacity(opacity), color.opacity(opacity * 0.55), color.opacity(0)]),
            center: center, startRadius: 0, endRadius: diameter / 2))
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
    /// Consistent sheet look: SF Rounded and a visible grabber.
    /// iOS 26+: the sheet container is left completely to the system (no corner radius, background
    /// or clip override), so it gets native Liquid Glass whose corners follow the screen's curve.
    /// iOS 16.4–25: large continuous corners as before.
    func sheetChrome() -> some View {
        sheetChromeStyle()
            // The background behind a sheet holds still while it's up.
            .onAppear { BackgroundActivity.shared.sheetAppeared() }
            .onDisappear { BackgroundActivity.shared.sheetDisappeared() }
    }

    @ViewBuilder
    private func sheetChromeStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.roundedDesign()
                .presentationDragIndicator(.visible)
        } else if #available(iOS 16.4, *) {
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

// MARK: - Delete motion (shared by every delete in the app)

/// Where a row is in the delete sequence. `nil` = resting.
enum DeletePhase: Equatable {
    /// Quick confirmation: scaled down to 0.96.
    case pressed
    /// Sliding out toward the swipe direction while fading (opacity only, no blur).
    case leaving
}

enum DeleteMotion {
    static let press = Animation.spring(response: 0.18, dampingFraction: 0.8)
    static let leave = Animation.easeIn(duration: 0.22)
    /// The removed row's height collapses and the rows below move up.
    static let collapse = Animation.spring(response: 0.4, dampingFraction: 0.85)
    static let pressNanoseconds: UInt64 = 110_000_000
    static let leaveNanoseconds: UInt64 = 220_000_000
    /// How long a pushed detail screen takes to pop before its row is removed in the list.
    static let popNanoseconds: UInt64 = 420_000_000
    /// How far the row slides while fading.
    static let slideDistance: CGFloat = 140

    /// Press → slide/fade → remove (with the collapse spring) ≈ 0.45 s in total, then reset.
    /// `setPhase` drives `.deleteExit(_:)`; `remove` must take the item out of the data source.
    /// Reduce Motion: fades only.
    @MainActor
    static func run(reduceMotion: Bool, setPhase: @escaping (DeletePhase?) -> Void, remove: @escaping () -> Void) {
        Haptics.impact(.light)
        if !reduceMotion {
            withAnimation(press) { setPhase(.pressed) }
        }
        Task { @MainActor in
            if !reduceMotion { try? await Task.sleep(nanoseconds: pressNanoseconds) }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : leave) { setPhase(.leaving) }
            try? await Task.sleep(nanoseconds: leaveNanoseconds)
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : collapse) { remove() }
            // Keep the removed row invisible until its collapse has finished (a List keeps drawing
            // the old cell during its delete animation), then forget the phase.
            try? await Task.sleep(nanoseconds: 650_000_000)
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { setPhase(nil) }
        }
    }
}

extension View {
    /// The shared delete look: keeps its rounded corners the whole way, scales to 0.96, then slides
    /// toward `edge` while fading. Apply the same phase to a List row's content AND its row background.
    func deleteExit(_ phase: DeletePhase?, edge: HorizontalEdge = .leading,
                    cornerRadius: CGFloat = Radius.md, clip: Bool = true) -> some View {
        modifier(DeleteExit(phase: phase, edge: edge, cornerRadius: cornerRadius, clip: clip))
    }
}

private struct DeleteExit: ViewModifier {
    let phase: DeletePhase?
    let edge: HorizontalEdge
    let cornerRadius: CGFloat
    let clip: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let moving = phase != nil && !reduceMotion
        let direction: CGFloat = edge == .leading ? -1 : 1
        content
            .clipShape(DeleteClipShape(active: clip && phase != nil, cornerRadius: cornerRadius))
            .scaleEffect(moving ? 0.96 : 1)
            .offset(x: moving && phase == .leaving ? direction * DeleteMotion.slideDistance : 0)
            .opacity(phase == .leaving ? 0 : 1)
            .allowsHitTesting(phase == nil)
    }
}

extension View {
    /// Empty states appear after a deleted last item is gone: fade in and scale 0.96 → 1 after 0.15 s,
    /// so the two never overlap. Fade only with Reduce Motion.
    func emptyStateEntrance() -> some View {
        modifier(EmptyStateEntrance())
    }
}

private struct EmptyStateEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.96)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3).delay(0.15)) { shown = true }
            }
    }
}

/// Rounded clip while a delete plays; effectively no clip at rest (shadows and glows stay intact).
private struct DeleteClipShape: Shape {
    let active: Bool
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        active
            ? RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
            : Rectangle().path(in: rect.insetBy(dx: -2000, dy: -2000))
    }
}

/// Lets a detail screen pop back first and then have its row removed, with the row animation,
/// by whichever list shows that item. Falls back to a plain removal if no list claims it.
@MainActor
final class RowDeleteRequests: ObservableObject {
    static let shared = RowDeleteRequests()
    @Published private(set) var requested: Set<UUID> = []

    func request(_ id: UUID, fallback: @escaping () -> Void) {
        requested.insert(id)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: DeleteMotion.popNanoseconds + 600_000_000)
            if self.requested.remove(id) != nil { fallback() }
        }
    }

    /// The list showing the item takes the request (returns false if someone else already did).
    func claim(_ id: UUID) -> Bool {
        requested.remove(id) != nil
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
            .animation(Motion.adaptive(Motion.smooth, reduceMotion: reduceMotion)
                           .delay(min(Double(index) * Motion.stagger, Motion.maxStaggerDelay)),
                       value: active)
    }
}
