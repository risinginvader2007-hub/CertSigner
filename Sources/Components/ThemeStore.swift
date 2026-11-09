import SwiftUI
import UIKit

/// The live accent theme, in one observable object. RootView feeds `accent` / `gradient` into
/// `.tint`, `\.themeAccent` and `\.themeGradient`, so every view (background blobs, buttons, icons,
/// tab bar, progress bars, badges) reads the same values.
///
/// Changing the accent runs ONE shared 0.6 s ease-in-out colour interpolation driven by a display
/// link: each frame publishes the in-between colours, so everything fades together, with no per-view
/// animations to fall out of sync, no instant jumps and no flicker. When it finishes, the exact
/// target colours are published.
@MainActor
final class ThemeStore: ObservableObject {
    static let transitionDuration: Double = 0.6

    @Published private(set) var accent: Color
    @Published private(set) var gradient: [Color]

    private var option: AccentOption
    private var link: CADisplayLink?
    private var linkTarget: DisplayLinkTarget?
    private var start: CFTimeInterval = 0
    private var fromAccent = RGBA.clear
    private var toAccent = RGBA.clear
    private var fromStops: [RGBA] = []
    private var toStops: [RGBA] = []

    init(option: AccentOption) {
        self.option = option
        accent = option.color
        gradient = option.gradient
    }

    /// Fades from what is on screen right now (also mid-fade) to `newOption`.
    func apply(_ newOption: AccentOption) {
        guard newOption != option else { return }
        let traits = Self.currentTraits
        fromAccent = RGBA(accent, traits: traits)
        fromStops = Self.samples(gradient, traits: traits)
        option = newOption
        toAccent = RGBA(newOption.color, traits: traits)
        toStops = Self.samples(newOption.gradient, traits: traits)
        start = CACurrentMediaTime()
        if link == nil {
            let target = DisplayLinkTarget { [weak self] in self?.tick() }
            let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.fire))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            self.link = link
            linkTarget = target
        }
    }

    private func tick() {
        let progress = min(1, (CACurrentMediaTime() - start) / Self.transitionDuration)
        guard progress < 1 else {
            link?.invalidate()
            link = nil
            linkTarget = nil
            accent = option.color
            gradient = option.gradient
            return
        }
        // easeInOut (cubic)
        let t = progress < 0.5 ? 4 * progress * progress * progress : 1 - pow(-2 * progress + 2, 3) / 2
        accent = fromAccent.mixed(with: toAccent, t).color
        gradient = zip(fromStops, toStops).map { $0.mixed(with: $1, t).color }
    }

    /// Gradients have 2 or 3 stops; sample at 0, ½, 1 so any two can be blended.
    private static func samples(_ colors: [Color], traits: UITraitCollection) -> [RGBA] {
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

private final class DisplayLinkTarget: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire(_ link: CADisplayLink) { action() }
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

    func setRunning(_ running: Bool) {
        let now = Date()
        if running {
            if resumedAt == nil { resumedAt = now }
        } else if let resumedAt {
            accumulated += max(0, now.timeIntervalSince(resumedAt))
            self.resumedAt = nil
        }
    }
}
