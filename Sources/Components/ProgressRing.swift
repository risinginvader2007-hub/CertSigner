import SwiftUI

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 10
    var color: Color? = nil
    var showsPercentage: Bool = true

    @Environment(\.themeAccent) private var accent
    @Environment(\.themeGradient) private var gradient

    private var clamped: Double { min(max(progress, 0), 1) }
    private var tint: Color { color ?? accent }
    private var strokeColors: [Color] { color.map { [$0.opacity(0.7), $0] } ?? gradient }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(clamped))
                .stroke(
                    AngularGradient(colors: strokeColors + [strokeColors[0]], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(360 * max(clamped, 0.01))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.35), radius: lineWidth * 0.6)
                .animation(.linear(duration: 0.25), value: clamped)
            if showsPercentage {
                Text("\(Int(clamped * 100))%")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .transaction { $0.animation = nil }
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
    @Environment(\.themeGradient) private var gradient

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill((color ?? accent).opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: color.map { [$0.opacity(0.75), $0] } ?? gradient,
                                         startPoint: .leading, endPoint: .trailing))
                    .shadow(color: (color ?? accent).opacity(0.35), radius: height * 0.6)
                    .frame(width: max(height, geo.size.width * CGFloat(min(max(progress, 0), 1))))
                    .animation(.linear(duration: 0.25), value: progress)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(min(max(progress, 0), 1) * 100)) percent")
    }
}
