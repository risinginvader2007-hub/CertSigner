import SwiftUI

// MARK: - Shimmer

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.35), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: -geo.size.width * 0.6 + phase * geo.size.width * 1.6)
                }
                .allowsHitTesting(false)
            )
            .mask(content)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

/// Grey rounded block used for loading placeholders.
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.09))
            .frame(width: width, height: height)
            .shimmering()
            .accessibilityHidden(true)
    }
}

// MARK: - Shake

struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 9
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * shakes * 2), y: 0))
    }
}

extension View {
    /// Increment `trigger` inside `withAnimation(.linear(duration: 0.45))` to shake.
    func shake(_ trigger: Int) -> some View {
        modifier(ShakeEffect(animatableData: CGFloat(trigger)))
    }
}

// MARK: - Animated result icons

struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.53))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.68))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.73, y: rect.minY + rect.height * 0.36))
        return path
    }
}

struct CrossShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.33
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        path.move(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        return path
    }
}

/// Circle that pops in, then draws a checkmark (success) or cross (failure).
struct AnimatedResultIcon: View {
    enum Result { case success, failure }

    let result: Result
    var size: CGFloat = 96

    @State private var drawn: CGFloat = 0
    @State private var scale: CGFloat = 0.5

    private var color: Color { result == .success ? Theme.success : Theme.danger }
    private var stroke: StrokeStyle { StrokeStyle(lineWidth: size * 0.075, lineCap: .round, lineJoin: .round) }

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.15))
            Circle().strokeBorder(color.opacity(0.35), lineWidth: 3)
            if result == .success {
                CheckmarkShape().trim(from: 0, to: drawn).stroke(color, style: stroke)
            } else {
                CrossShape().trim(from: 0, to: drawn).stroke(color, style: stroke)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(scale)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { scale = 1 }
            withAnimation(.easeOut(duration: 0.45).delay(0.18)) { drawn = 1 }
        }
        .accessibilityElement()
        .accessibilityLabel(result == .success ? "Success" : "Failed")
    }
}

// MARK: - iOS 18 zoom navigation transition (falls back to standard push)

extension View {
    @ViewBuilder
    func zoomSource<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func zoomTransition<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}
