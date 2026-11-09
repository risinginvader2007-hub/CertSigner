import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// When the animated background should hold still to save frames for the content: while the
/// user is dragging / a scroll view is coasting, and while a sheet is up. Published only on
/// changes (start / stop), never per touch.
@MainActor
final class BackgroundActivity: ObservableObject {
    static let shared = BackgroundActivity()

    @Published private(set) var scrolling = false {
        didSet { AuroraClock.shared.hold("scroll", scrolling) }
    }
    @Published private(set) var sheets = 0 {
        didSet { AuroraClock.shared.hold("sheet", sheets > 0) }
    }

    var paused: Bool { scrolling || sheets > 0 }

    private let windows = NSHashTable<UIWindow>.weakObjects()
    private var settleTask: Task<Void, Never>?
    /// A flick keeps coasting after the finger lifts; resume the background after this.
    static let coastSeconds: Double = 0.8

    func installIfNeeded() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where !windows.contains(window) {
                window.addGestureRecognizer(DragActivityRecognizer { [weak self] moving in
                    self?.setDragging(moving)
                })
                windows.add(window)
            }
        }
    }

    func setDragging(_ dragging: Bool) {
        settleTask?.cancel()
        if dragging {
            if !scrolling { scrolling = true }
        } else if scrolling {
            settleTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.coastSeconds * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                self.scrolling = false
            }
        }
    }

    func sheetAppeared() { sheets += 1 }
    func sheetDisappeared() { sheets = max(0, sheets - 1) }
}

/// Watches touches on the window without taking part: it never recognizes (stays "possible"
/// until the touch ends, then fails), never cancels or delays touches, and recognizes
/// simultaneously with everything, so scrolling, taps and buttons behave exactly as before.
private final class DragActivityRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let onChange: (Bool) -> Void
    private var origin: CGPoint?
    private var reported = false

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if origin == nil { origin = touches.first?.location(in: nil) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard !reported, let origin, let point = touches.first?.location(in: nil) else { return }
        if hypot(point.x - origin.x, point.y - origin.y) > 10 {
            reported = true
            onChange(true)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { finish(event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { finish(event) }

    private func finish(_ event: UIEvent) {
        let active = event.allTouches?.contains { $0.phase != .ended && $0.phase != .cancelled } ?? false
        guard !active else { return }
        if reported { onChange(false) }
        state = .failed
    }

    override func reset() {
        origin = nil
        reported = false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
