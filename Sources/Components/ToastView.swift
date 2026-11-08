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
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 6)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

struct ToastHost: ViewModifier {
    @ObservedObject var center: ToastCenter

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = center.current {
                ToastView(toast: toast)
                    .id(toast.id)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { center.dismiss() }
                    .zIndex(1)
            }
        }
    }
}
