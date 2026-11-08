import SwiftUI

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 10
    var color: Color? = nil
    var showsPercentage: Bool = true

    @Environment(\.themeAccent) private var accent

    private var clamped: Double { min(max(progress, 0), 1) }
    private var tint: Color { color ?? accent }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(clamped))
                .stroke(
                    LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: clamped)
            if showsPercentage {
                Text("\(Int(clamped * 100))%")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(clamped * 100)) percent")
    }
}

struct ProgressBar: View {
    var progress: Double
    var height: CGFloat = 8
    var color: Color? = nil

    @Environment(\.themeAccent) private var accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill((color ?? accent).opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: [(color ?? accent).opacity(0.75), color ?? accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * CGFloat(min(max(progress, 0), 1))))
                    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(min(max(progress, 0), 1) * 100)) percent")
    }
}
