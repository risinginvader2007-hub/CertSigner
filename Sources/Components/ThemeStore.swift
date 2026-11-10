import SwiftUI
import UIKit

/// The live accent theme, in one observable object. RootView feeds `accent` / `gradient` into
/// `.tint`, `\.themeAccent` and `\.themeGradient`, so every view reads the same values.
///
/// An accent change publishes ONCE, inside one shared 0.35 s ease-in-out animation: every view
/// that reads the accent re-renders a single time and SwiftUI interpolates the colours on the
/// render side, so nothing re-renders per frame. The animated background (a Canvas that redraws
/// itself anyway) blends its own colours from `fade`, and a second publish clears `fade` when
/// the transition is over. (Before: one publish per display-link frame, about 21 per change, and
/// the whole tree re-rendered on each.)
@MainActor
final class ThemeStore: ObservableObject {
    static let transitionDuration: Double = Motion.themeCrossfade

    struct State: Equatable {
        var accent: Color
        var gradient: [Color]
        var onAccent: Color = .white
        var fade: ThemeFade?
    }

    @Published private(set) var state: State

    var accent: Color { state.accent }
    var gradient: [Color] { state.gradient }
    var fade: ThemeFade? { state.fade }
    /// Black or white: the label colour for content on the accent gradient.
    var onAccent: Color { state.onAccent }
    /// True while a colour transition runs (the background holds its drift still meanwhile).
    var isTransitioning: Bool { state.fade != nil }

    private var option: Accent
    private var finishTask: Task<Void, Never>?

    init(accent: Accent) {
        option = accent
        state = State(accent: accent.tint, gradient: accent.gradient, onAccent: accent.onAccent, fade: nil)
    }

    convenience init(option: AccentOption) { self.init(accent: Accent(option)) }

    func apply(_ option: AccentOption, animated: Bool = true) { apply(Accent(option), animated: animated) }


    /// Fades from what is on screen right now (also mid-fade) to `newOption`.
    func apply(_ newOption: Accent, animated: Bool = true) {
        guard newOption != option else { return }
        let traits = Self.currentTraits
        let now = CACurrentMediaTime()
        let fromStops = state.fade?.stops(at: now) ?? Self.samples(state.gradient, traits: traits)
        option = newOption
        let fade = ThemeFade(from: fromStops, to: Self.samples(newOption.gradient, traits: traits),
                             start: now, duration: Self.transitionDuration)
        let next = State(accent: newOption.tint, gradient: newOption.gradient, onAccent: newOption.onAccent,
                         fade: animated ? fade : nil)
        if animated {
            AuroraClock.shared.hold("theme", true)
            withAnimation(.easeInOut(duration: Self.transitionDuration)) { state = next }
        } else {
            state = next
        }
        finishTask?.cancel()
        guard animated else { return }
        finishTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((Self.transitionDuration + 0.05) * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            var done = self.state
            done.fade = nil
            self.state = done
            AuroraClock.shared.hold("theme", false)
        }
    }

    /// Gradients have 2 or 3 stops; sample at 0, ½, 1 so any two can be blended.
    static func samples(_ colors: [Color], traits: UITraitCollection) -> [RGBA] {
        let stops = colors.map { RGBA($0, traits: traits) }
        guard let first = stops.first else { return [.clear, .clear, .clear] }
        guard stops.count > 1 else { return [first, first, first] }
        func sample(_ x: Double) -> RGBA {
            let position = x * Double(stops.count - 1)
            let index = min(Int(position), stops.count - 2)
            return stops[index].mixed(with: stops[index + 1], position - Double(index))
        }
        return [sample(0), sample(0.5), sample(1)]
    }

    /// Resolve dynamic colours (e.g. `.blue`) for the scheme actually on screen.
    static var currentTraits: UITraitCollection {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        return window?.traitCollection ?? UITraitCollection.current
    }
}

/// One accent transition for views that draw every frame themselves (the background Canvas):
/// blended gradient stops at any moment, with the same 0.35 s ease-in-out curve.
struct ThemeFade: Equatable {
    var from: [RGBA]
    var to: [RGBA]
    var start: CFTimeInterval
    var duration: Double

    func progress(at time: CFTimeInterval) -> Double {
        let p = min(1, max(0, (time - start) / duration))
        return p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
    }

    func isRunning(at time: CFTimeInterval) -> Bool { time - start < duration }

    func stops(at time: CFTimeInterval) -> [RGBA] {
        let t = progress(at: time)
        return zip(from, to).map { $0.mixed(with: $1, t) }
    }
}

private struct ThemeFadeKey: EnvironmentKey {
    static let defaultValue: ThemeFade? = nil
}

extension EnvironmentValues {
    /// The accent transition in progress, if any (read only by views that draw per frame).
    var themeFade: ThemeFade? {
        get { self[ThemeFadeKey.self] }
        set { self[ThemeFadeKey.self] = newValue }
    }
}


struct RGBA: Equatable {
    var r: Double, g: Double, b: Double, a: Double
    static let clear = RGBA(r: 0, g: 0, b: 0, a: 0)

    init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(_ color: Color, traits: UITraitCollection) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
    }

    func mixed(with other: RGBA, _ t: Double) -> RGBA {
        RGBA(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t, a: a + (other.a - a) * t)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

/// System / Light / Dark switch without a flash: a snapshot of the current screen is laid over
/// the window, the appearance changes underneath, and the snapshot fades out over 0.35 s.
/// Rapid repeated switches stack snapshots of whatever is on screen, so nothing ever jumps.
@MainActor
enum AppearanceCrossfade {
    static let snapshotTag = 0xC5F0

    static func run(reduceMotion: Bool = false, _ change: () -> Void) {
        guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: { $0.isKeyWindow }),
              let snapshot = window.snapshotView(afterScreenUpdates: false) else {
            change()
            return
        }
        snapshot.tag = snapshotTag
        snapshot.isUserInteractionEnabled = false
        snapshot.frame = window.bounds
        window.addSubview(snapshot)
        change()
        UIView.animate(withDuration: reduceMotion ? 0.2 : Motion.themeCrossfade, delay: 0.02,
                       options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]) {
            snapshot.alpha = 0
        } completion: { _ in
            snapshot.removeFromSuperview()
        }
    }
}

/// Low Power Mode, observed once for the whole app.
@MainActor
final class PowerMonitor: ObservableObject {
    static let shared = PowerMonitor()
    @Published private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
    }
}

/// Clock for the living background. It only advances while the app is active, so the blobs pick up
/// where they left off instead of jumping, and every screen shows the same moment of the loop.
@MainActor
final class AuroraClock {
    static let shared = AuroraClock()
    private var accumulated: TimeInterval = 0
    private var resumedAt: Date? = Date()

    func time(at date: Date) -> TimeInterval {
        accumulated + (resumedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    /// Reasons the drift is held still (app inactive, scrolling, sheet up, accent transition).
    /// The clock stops while any hold is on, so the lights resume where they were (no jump).
    private var holds: Set<String> = []

    func setRunning(_ running: Bool) { hold("app", !running) }

    func hold(_ reason: String, _ on: Bool) {
        if on { holds.insert(reason) } else { holds.remove(reason) }
        let now = Date()
        if holds.isEmpty {
            if resumedAt == nil { resumedAt = now }
        } else if let resumedAt {
            accumulated += max(0, now.timeIntervalSince(resumedAt))
            self.resumedAt = nil
        }
    }
}
