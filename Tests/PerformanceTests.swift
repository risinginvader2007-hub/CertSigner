import XCTest
import SwiftUI
import Combine
@testable import CertSigner

/// Numbers for the performance work (simulator on the CI Mac, so absolute times are only
/// comparable run to run, not to an iPhone):
/// - how many times one accent change invalidates the theme (every reader re-renders per publish),
/// - how long one frame of the animated background takes to render.
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

    func testBackgroundFrameRenderCost() {
        let size = CGSize(width: 440, height: 956)  // iPhone 16 Pro Max points
        for scheme in [ColorScheme.dark, .light] {
            let view = AuroraBackground(intensity: 1)
                .environment(\.themeGradient, AccentOption.aurora.gradient)
                .environment(\.colorScheme, scheme)
                .frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            _ = renderer.uiImage  // warm up
            let frames = 30
            let start = CACurrentMediaTime()
            for _ in 0..<frames { _ = renderer.uiImage }
            let ms = (CACurrentMediaTime() - start) / Double(frames) * 1000
            print(String(format: "PERF background frame (%@, 1320x2868 px): %.2f ms", scheme == .dark ? "dark" : "light", ms))
        }
    }
}
