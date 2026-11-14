import SwiftUI

/// Small red "needs attention" dot with no number (e.g. an update is available). Same red as the
/// count badges (`Theme.danger`). Pops in with scale + fade, fade only with Reduce Motion; it also
/// pops in when it is already visible on first appearance (the cached state at launch).
struct NotificationDot: View {
    let visible: Bool
    var size: CGFloat = 9

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            if visible && appeared {
                Circle()
                    .fill(Theme.danger)
                    .frame(width: size, height: size)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .animation(Motion.adaptive(Motion.bouncy, reduceMotion: reduceMotion), value: visible && appeared)
        .onAppear { appeared = true }
        .accessibilityHidden(true)
    }
}
