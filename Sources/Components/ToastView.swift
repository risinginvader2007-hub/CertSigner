import SwiftUI

struct Toast: Identifiable, Equatable {
    enum Kind { case success, error, warning, info }

    let id = UUID()
    let kind: Kind
    let message: String
    /// Optional trailing button (e.g. "Undo").
    var actionTitle: String? = nil

    var systemImage: String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var color: Color {
        switch kind {
        case .success: return Theme.success
        case .error: return Theme.danger
        case .warning: return Theme.warning
        case .info: return .blue
        }
    }
}

@MainActor
final class ToastCenter: ObservableObject {
    @Published private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?
    private var action: (() -> Void)?
    /// Runs once when the current toast goes away without its action being tapped
    /// (timed out, swiped away, or replaced by another toast).
    private var onExpire: (() -> Void)?

    /// Plain toasts show for 2.5 s. A toast with an action (e.g. Undo) stays for `duration`.
    func show(_ message: String, kind: Toast.Kind = .info, actionTitle: String? = nil,
              duration: TimeInterval? = nil, action: (() -> Void)? = nil, onExpire: (() -> Void)? = nil) {
        switch kind {
        case .success: Haptics.success()
        case .error: Haptics.error()
        case .warning: Haptics.warning()
        case .info: Haptics.impact(.light)
        }
        expirePrevious()
        self.action = action
        self.onExpire = onExpire
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            current = Toast(kind: kind, message: message, actionTitle: action == nil ? nil : actionTitle)
        }
        dismissTask?.cancel()
        let seconds = duration ?? 2.5
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        expirePrevious()
        withAnimation(.easeIn(duration: 0.25)) { current = nil }
    }

    /// The toast's button was tapped: run the action instead of the expiry.
    func performAction() {
        let action = self.action
        self.action = nil
        onExpire = nil
        dismissTask?.cancel()
        withAnimation(.easeIn(duration: 0.25)) { current = nil }
        action?()
    }

    private func expirePrevious() {
        let expire = onExpire
        onExpire = nil
        action = nil
        expire?()
    }
}

struct ToastView: View {
    let toast: Toast
    var onAction: () -> Void = {}

    var body: some View {
        HStack(spacing: Space.x3) {
            Image(systemName: toast.systemImage)
                .foregroundColor(toast.color)
                .font(.body.weight(.semibold))
                .symbolBounce(value: toast.id)
                .ambientGlow(toast.color, radius: 6, opacity: 0.5)
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let title = toast.actionTitle {
                Button(action: onAction) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, Space.x3)
                        .padding(.vertical, Space.x2)
                        .background(Capsule().fill(Color.primary.opacity(0.1)))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle(scale: 0.94))
                .accessibilityLabel(title)
            }
        }
        .padding(.horizontal, Space.x4)
        .padding(.vertical, Space.x3)
        .frame(minHeight: 44)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(
            LinearGradient(colors: [toast.color.opacity(0.55), Color.white.opacity(0.08)],
                           startPoint: .leading, endPoint: .trailing), lineWidth: 1))
        .shadow(color: toast.color.opacity(0.18), radius: 18, x: 0, y: 8)
        .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 6)
        .padding(.horizontal, Space.x6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

struct ToastHost: ViewModifier {
    @ObservedObject var center: ToastCenter
    /// Upward drag in progress (swipe up to dismiss).
    @State private var drag: CGFloat = 0

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = center.current {
                ToastView(toast: toast, onAction: { center.performAction() })
                    .id(toast.id)
                    // Below the navigation bar's button row, so it never covers Back / toolbar buttons.
                    .padding(.top, 50)
                    .offset(y: min(0, drag) + max(0, drag) * 0.15) // rubber-band when pulled down
                    .opacity(1 + Double(min(0, drag)) / 120)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { center.dismiss() }
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { drag = $0.translation.height }
                            .onEnded { value in
                                if value.translation.height < -24 || value.predictedEndTranslation.height < -60 {
                                    center.dismiss()
                                }
                                withAnimation(Motion.snappy) { drag = 0 }
                            }
                    )
                    .accessibilityHint(toast.actionTitle == nil ? "Tap or swipe up to dismiss" : "Swipe up to dismiss")
                    .zIndex(1)
            }
        }
    }
}
