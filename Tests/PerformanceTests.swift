import XCTest
import SwiftUI
import Combine
@testable import CertSigner

/// Numbers for the performance work (iOS simulator on the CI Mac, so absolute times only compare
/// within one run, not to an iPhone):
/// - how many times one accent change publishes (each publish re-renders every accent reader),
/// - how long one background frame takes to render: the previous view-per-light version (copied
///   below, unchanged) against the current single-Canvas version, in the same run.
@MainActor
final class PerformanceTests: XCTestCase {
    func testThemeChangeInvalidationCount() {
        let store = ThemeStore(option: .purple)
        var publishes = 0
        let token = store.objectWillChange.sink { _ in publishes += 1 }
        store.apply(.orange)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        token.cancel()
        print("PERF theme publishes per accent change: \(publishes)")
        XCTAssertGreaterThan(publishes, 0)
    }

    private func renderMilliseconds<V: View>(_ make: (Double) -> V, frames: Int = 120) -> Double {
        let size = CGSize(width: 440, height: 956)  // iPhone 16 Pro Max points
        func render(_ t: Double) {
            let renderer = ImageRenderer(content: make(t).frame(width: size.width, height: size.height))
            renderer.scale = 3
            _ = renderer.cgImage   // a fresh renderer each frame, so nothing is cached
        }
        render(0)  // warm up
        let start = CACurrentMediaTime()
        for frame in 0..<frames { render(Double(frame) / 30) }
        return (CACurrentMediaTime() - start) / Double(frames) * 1000
    }

    func testBackgroundFrameRenderCost() {
        for scheme in [ColorScheme.dark, .light] {
            let name = scheme == .dark ? "dark" : "light"
            let old = renderMilliseconds { t in
                LegacyAurora(time: t, gradient: AccentOption.aurora.gradient).environment(\.colorScheme, scheme)
            }
            let new = renderMilliseconds { _ in
                AuroraBackground(intensity: 1)
                    .environment(\.themeGradient, AccentOption.aurora.gradient)
                    .environment(\.colorScheme, scheme)
            }
            print(String(format: "PERF background frame %@ 1320x2868 px: before (view per light) %.2f ms, after (one Canvas) %.2f ms",
                         name, old, new))
        }
    }
}

/// The previous background body (4 Circle views with radial gradient fills, blend mode per view,
/// drawingGroup), kept verbatim for the comparison only.
private struct LegacyAurora: View {
    let time: Double
    let gradient: [Color]
    @Environment(\.colorScheme) private var scheme

    private struct Blob {
        let colorPosition: Double, size: CGFloat, base: CGPoint, amplitude: CGSize, period: Double, phase: Double, opacity: Double
    }

    private static let blobs: [Blob] = [
        Blob(colorPosition: 0, size: 1.25, base: CGPoint(x: 0.12, y: 0.10), amplitude: CGSize(width: 0.20, height: 0.08), period: 26, phase: 0, opacity: 1),
        Blob(colorPosition: 0.5, size: 1.10, base: CGPoint(x: 0.88, y: 0.16), amplitude: CGSize(width: 0.18, height: 0.10), period: 34, phase: 1.7, opacity: 0.85),
        Blob(colorPosition: 1, size: 0.95, base: CGPoint(x: 0.55, y: 0.36), amplitude: CGSize(width: 0.24, height: 0.11), period: 21, phase: 3.1, opacity: 0.6),
        Blob(colorPosition: 0.25, size: 1.05, base: CGPoint(x: 0.30, y: 0.78), amplitude: CGSize(width: 0.22, height: 0.07), period: 39, phase: 4.4, opacity: 0.35)
    ]

    private func color(at position: Double) -> Color {
        let index = Int((position * Double(gradient.count - 1)).rounded())
        return gradient[min(max(index, 0), gradient.count - 1)]
    }

    var body: some View {
        let strength = (scheme == .dark ? 0.85 : 0.36)
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Theme.background
                ZStack {
                    ForEach(Self.blobs.indices, id: \.self) { index in
                        let blob = Self.blobs[index]
                        let angle = 2 * Double.pi * time / blob.period + blob.phase
                        let size = w * blob.size * CGFloat(1 + 0.12 * sin(angle + 1.1))
                        let pulse = 0.825 + 0.175 * sin(angle * 2 + 2.3)
                        let opacity = min(1, strength * blob.opacity * pulse)
                        let c = color(at: blob.colorPosition)
                        Circle()
                            .fill(RadialGradient(colors: [c.opacity(opacity), c.opacity(opacity * 0.55), c.opacity(0)],
                                                 center: .center, startRadius: 0, endRadius: size / 2))
                            .frame(width: size, height: size)
                            .position(x: w * (blob.base.x + blob.amplitude.width * CGFloat(sin(angle))),
                                      y: h * (blob.base.y + blob.amplitude.height * CGFloat(sin(2 * angle + blob.phase))))
                            .blendMode(scheme == .dark ? .plusLighter : .normal)
                    }
                }
                .frame(width: w, height: h)
                .drawingGroup()
            }
            .frame(width: w, height: h)
        }
    }
}
