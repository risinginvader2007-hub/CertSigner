import SwiftUI

/// Short animated intro, shown once on first launch. Tap anywhere (or Skip) to dismiss.
/// Matches the launch-screen colour so launch → intro → app is seamless. Fades only with Reduce Motion.
struct IntroOverlay: View {
    let onFinish: () -> Void

    @Environment(\.themeGradient) private var gradient
    @Environment(\.themeAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = 0
    @State private var finished = false

    var body: some View {
        ZStack {
            Color(red: 0.027, green: 0.031, blue: 0.055).ignoresSafeArea()
            AuroraBackground(intensity: 1.4)
                .opacity(stage >= 1 ? 1 : 0)
                .environment(\.colorScheme, .dark)

            VStack(spacing: Space.x5) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [accent.opacity(0.55), .clear], center: .center, startRadius: 10, endRadius: 120))
                        .frame(width: 240, height: 240)
                        .scaleEffect(stage >= 1 ? 1 : 0.4)
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                            .fill(LinearGradient(colors: [Color.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)))
                        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                        .frame(width: 112, height: 112)
                        .shadow(color: accent.opacity(0.6), radius: 30, y: 10)
                    Image(systemName: "signature")
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundColor(.white)
                        .symbolBounce(value: stage)
                }
                .scaleEffect(reduceMotion ? 1 : (stage >= 1 ? 1 : 0.6))
                .opacity(stage >= 1 ? 1 : 0)

                VStack(spacing: Space.x2) {
                    Text("CertSigner")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .displayTracking()
                        .foregroundColor(.white)
                    Text("Sign. Install. Yours.")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.65))
                }
                .opacity(stage >= 2 ? 1 : 0)
                .offset(y: reduceMotion || stage >= 2 ? 0 : 12)
            }

            VStack {
                HStack {
                    Spacer()
                    Button("Skip") { finish() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.horizontal, Space.x4)
                }
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("CertSigner")
        .accessibilityAction(named: "Skip intro") { finish() }
        .task {
            let animation = Motion.adaptive(Motion.bouncy, reduceMotion: reduceMotion)
            withAnimation(animation) { stage = 1 }
            try? await Task.sleep(nanoseconds: 350_000_000)
            withAnimation(Motion.adaptive(Motion.smooth, reduceMotion: reduceMotion)) { stage = 2 }
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        Haptics.impact(.light)
        onFinish()
    }
}
