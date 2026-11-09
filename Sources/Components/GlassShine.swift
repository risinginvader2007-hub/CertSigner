import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

// MARK: - Glass shine (reflection) modifier

extension View {
    /// Glassy reflection: a thin lighter top edge plus a soft diagonal highlight that sweeps across
    /// every few seconds. Overlay only: never changes layout, hit areas or tap handling.
    func glassShine(cornerRadius: CGFloat = Theme.corner) -> some View {
        modifier(GlassShine(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }

    func glassShine<S: InsettableShape>(in shape: S) -> some View {
        modifier(GlassShine(shape: shape))
    }
}

struct GlassShine<S: InsettableShape>: ViewModifier {
    let shape: S

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.auroraActive) private var screenActive
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var power = PowerMonitor.shared

    func body(content: Content) -> some View {
        // The sweep only runs on the visible tab, with the app active, Reduce Motion off and Low Power off.
        let sweeping = !reduceMotion && screenActive && scenePhase == .active && !power.lowPower
        let dark = scheme == .dark
        return content.overlay(
            ZStack {
                if sweeping {
                    ShineSweep(dark: dark)
                }
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(dark ? 0.30 : 0.75), Color.white.opacity(0)],
                                   startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.4)),
                    lineWidth: 1
                )
            }
            .clipShape(shape)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        )
    }
}

/// One diagonal band of light crossing the surface (1.1 s), then a ~5 s rest. Removed from the
/// hierarchy when paused, which also cancels its loop.
private struct ShineSweep: View {
    let dark: Bool
    @State private var phase: CGFloat = 0
    @State private var firstDelay = Double.random(in: 0.6...3.0)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let band = max(w * 0.32, 56)
            LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(dark ? 0.16 : 0.38), Color.white.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: band, height: (w + h) * 1.4)
                .rotationEffect(.degrees(22))
                .position(x: -band + phase * (w + band * 2), y: h / 2)
        }
        .task {
            try? await Task.sleep(nanoseconds: UInt64(firstDelay * 1_000_000_000))
            while !Task.isCancelled {
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) { phase = 0 }
                try? await Task.sleep(nanoseconds: 40_000_000)
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 1.1)) { phase = 1 }
                try? await Task.sleep(nanoseconds: 5_200_000_000)
            }
        }
    }
}

// MARK: - Press flash button style

/// Pressable style with a quick bright flash that starts where the finger touched, plus the subtle
/// scale-down spring. The tap itself is handled by the Button exactly as before.
struct ShinePressStyle<S: Shape>: ButtonStyle {
    var shape: S
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        ShinePressBody(configuration: configuration, shape: shape, scale: scale)
    }
}

private struct ShinePressBody<S: Shape>: View {
    let configuration: ButtonStyleConfiguration
    let shape: S
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flash = false
    /// Window coordinates of the touch that started this press.
    @State private var touch: CGPoint?

    var body: some View {
        configuration.label
            .overlay(
                GeometryReader { geo in
                    let size = geo.size
                    let frame = geo.frame(in: .global)
                    let local = touch.map { CGPoint(x: $0.x - frame.minX, y: $0.y - frame.minY) }
                    let inside = local.map { CGRect(origin: .zero, size: size).insetBy(dx: -12, dy: -12).contains($0) } ?? false
                    let point = inside ? local! : CGPoint(x: size.width / 2, y: size.height / 2)
                    RadialGradient(
                        colors: [Color.white.opacity(0.45), Color.white.opacity(0.12), Color.white.opacity(0)],
                        center: UnitPoint(x: point.x / max(size.width, 1), y: point.y / max(size.height, 1)),
                        startRadius: 0,
                        endRadius: max(size.width, size.height) * 0.7
                    )
                    .opacity(flash ? 1 : 0)
                }
                .clipShape(shape)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
            .onAppear { TouchTracker.shared.installIfNeeded() }
            .onChange(of: configuration.isPressed) { pressed in
                if pressed {
                    touch = TouchTracker.shared.lastTouch
                    withAnimation(.easeOut(duration: 0.12)) { flash = true }
                } else {
                    withAnimation(.easeOut(duration: 0.45)) { flash = false }
                }
            }
    }
}

/// Remembers where the last touch began (window coordinates) without taking part in any gesture:
/// the recognizer records the point and immediately fails, never cancelling or delaying touches.
@MainActor
final class TouchTracker {
    static let shared = TouchTracker()
    private(set) var lastTouch: CGPoint?
    private let windows = NSHashTable<UIWindow>.weakObjects()

    func installIfNeeded() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where !windows.contains(window) {
                window.addGestureRecognizer(TouchDownRecognizer { [weak self] point in self?.lastTouch = point })
                windows.add(window)
            }
        }
    }
}

private final class TouchDownRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let onTouch: (CGPoint) -> Void

    init(onTouch: @escaping (CGPoint) -> Void) {
        self.onTouch = onTouch
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { onTouch(touch.location(in: nil)) }
        state = .failed
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

// MARK: - Liquid Glass capsule (iOS 26) with a tinted fallback

extension View {
    /// Small accent capsule behind a pill button: tinted, interactive Liquid Glass on iOS 26
    /// (native touch-following highlight), the existing flat tinted capsule before that.
    @ViewBuilder
    func accentPillBackground(_ accent: Color) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(accent.opacity(0.22)).interactive(), in: Capsule())
        } else {
            self.background(Capsule().fill(accent.opacity(0.14)))
        }
        #else
        self.background(Capsule().fill(accent.opacity(0.14)))
        #endif
    }
}
