import XCTest
import UIKit
@testable import CertSigner

/// System / Light / Dark switched quickly and repeatedly: every switch lays a snapshot over the
/// window that fades out; nothing is left behind and the change itself always runs.
@MainActor
final class AppearanceCrossfadeTests: XCTestCase {
    private var window: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }
    }

    func testRapidSwitchingLeavesNoSnapshotsBehind() async throws {
        let window = try XCTUnwrap(window, "test host has a key window")
        var changes = 0
        let styles: [UIUserInterfaceStyle] = [.light, .dark, .unspecified]
        for round in 0..<12 {
            AppearanceCrossfade.run {
                window.overrideUserInterfaceStyle = styles[round % styles.count]
                changes += 1
            }
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
        XCTAssertEqual(changes, 12)
        let during = window.subviews.filter { $0.tag == AppearanceCrossfade.snapshotTag }.count
        print("snapshots on screen mid-switching: \(during)")
        XCTAssertGreaterThan(during, 0, "a cross-fade covers each switch")
        try? await Task.sleep(nanoseconds: 700_000_000)
        let after = window.subviews.filter { $0.tag == AppearanceCrossfade.snapshotTag }.count
        XCTAssertEqual(after, 0, "all snapshots removed after the 0.35 s fades")
        window.overrideUserInterfaceStyle = .unspecified
    }
}
