import SwiftUI

struct Toast: Identifiable, Equatable {
    enum Kind { case success, error, warning, info }

    let id = UUID()
    let kind: Kind
    let message: String

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

    func show(_ message: String, kind: Toast.Kind = .info) {
        switch kind {
        case .success: Haptics.success()
        case .error: Haptics.error()
        case .warning: Haptics.warning()
        case .info: Haptics.impact(.light)
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            current = Toast(kind: kind, message: message)
        }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if Task.isCancelled { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        withAnimation(.easeInOut(duration: 0.25)) { current = nil }
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
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
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(
            LinearGradient(colors: [toast.color.opacity(0.55), Color.white.opacity(0.08)],
                           startPoint: .leading, endPoint: .trailing), lineWidth: 1))
        .shadow(color: toast.color.opacity(0.18), radius: 18, x: 0, y: 8)
        .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 6)
        .padding(.horizontal, 24)
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
                ToastView(toast: toast)
                    .id(toast.id)
                    .padding(.top, 6)
                    .offset(y: min(0, drag) + max(0, drag) * 0.15) // rubber-band when pulled down
                    .opacity(1 + Double(min(0, drag)) / 120)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .scale(scale: 0.9)).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)))
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
                    .accessibilityHint("Tap or swipe up to dismiss")
                    .zIndex(1)
            }
        }
    }
}
