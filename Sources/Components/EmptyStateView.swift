import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var actionSystemImage: String = "plus"
    var action: (() -> Void)? = nil

    @Environment(\.themeAccent) private var accent
    @Environment(\.themeGradient) private var gradient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var floating = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                // Soft halo
                Circle()
                    .fill(RadialGradient(colors: [accent.opacity(0.28), .clear], center: .center, startRadius: 10, endRadius: 90))
                    .frame(width: 180, height: 180)
                Circle()
                    .fill(LinearGradient(colors: gradient.map { $0.opacity(0.22) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    .frame(width: 112, height: 112)
                Image(systemName: systemImage)
                    .font(.system(size: 46, weight: .semibold))
                    .accentGradientForeground(gradient)
                    .symbolPulse(appeared)
            }
            .frame(height: 140)
            .offset(y: floating ? -4 : 4)
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)

            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, systemImage: actionSystemImage, action: action)
                    .frame(maxWidth: 260)
                    .opacity(appeared ? 1 : 0)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(Motion.adaptive(Motion.bouncy, reduceMotion: reduceMotion).delay(0.05)) { appeared = true }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) { floating = true }
        }
    }
}
