import XCTest
import SwiftUI
@testable import CertSigner

/// Data side of the delete redesign: the list loses the item immediately, Undo restores it in place,
/// files are deleted only when the Undo window closes, and the shared motion runs in order.
@MainActor
final class DeleteFlowTests: XCTestCase {
    private func makeApp(_ store: SignedAppsStore, name: String, signedAt: Date) -> SignedApp {
        let (id, folder) = store.reserve()
        let file = "\(name).ipa"
        try? Data("ipa".utf8).write(to: folder.appendingPathComponent(file))
        let app = SignedApp(id: id, name: name, bundleID: "com.test.\(name.lowercased())", version: "1.0",
                            signedAt: signedAt, certificateID: UUID(), certificateName: "Test", expiresAt: nil,
                            fileName: file, iconFileName: nil, size: 3, sourceAppID: nil)
        store.add(app, iconSource: nil)
        return app
    }

    private func freshStore() -> SignedAppsStore {
        let store = SignedAppsStore()
        for app in store.apps { store.delete(app) }
        return store
    }

    func testDeleteFirstMiddleLastWithUndoAndFinalize() {
        let store = freshStore()
        let now = Date()
        let c = makeApp(store, name: "C", signedAt: now.addingTimeInterval(-30))
        let b = makeApp(store, name: "B", signedAt: now.addingTimeInterval(-20))
        let a = makeApp(store, name: "A", signedAt: now.addingTimeInterval(-10))
        XCTAssertEqual(store.apps.map(\.name), ["A", "B", "C"])

        // Middle: gone from the list at once, file kept, Undo puts it back in the same place.
        let middle = store.removeForUndo(b)
        XCTAssertEqual(store.apps.map(\.name), ["A", "C"], "removed before the list re-renders")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.ipaURL(for: b).path), "file kept during Undo window")
        store.restore(middle!)
        XCTAssertEqual(store.apps.map(\.name), ["A", "B", "C"], "Undo restores in place")

        // First, then finalize: same removal as the old delete.
        let first = store.removeForUndo(a)!
        store.finalizeDeletion(first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.folder(for: a.id).path))
        XCTAssertEqual(store.apps.map(\.name), ["B", "C"])

        // Last item, twice quickly: the second call is a no-op, nothing crashes.
        let last = store.removeForUndo(c)
        XCTAssertNil(store.removeForUndo(c))
        XCTAssertEqual(store.apps.map(\.name), ["B"])
        store.finalizeDeletion(last!)

        // Reload from disk: deleted apps stay deleted.
        store.load()
        XCTAssertEqual(store.apps.map(\.name), ["B"])
        store.delete(b)
    }

    func testToastUndoAndExpiry() async {
        let toasts = ToastCenter()
        var undone = 0, expired = 0
        toasts.show("Deleted A", kind: .success, actionTitle: "Undo", duration: 5,
                    action: { undone += 1 }, onExpire: { expired += 1 })
        XCTAssertEqual(toasts.current?.actionTitle, "Undo")
        toasts.performAction()
        XCTAssertEqual(undone, 1)
        XCTAssertEqual(expired, 0, "Undo must not also finalize")
        XCTAssertNil(toasts.current)

        // A second delete replaces the toast: the first one's files are finalized right away.
        toasts.show("Deleted B", kind: .success, actionTitle: "Undo", duration: 5,
                    action: { undone += 1 }, onExpire: { expired += 1 })
        toasts.show("Deleted C", kind: .success, actionTitle: "Undo", duration: 0.3,
                    action: { undone += 1 }, onExpire: { expired += 1 })
        XCTAssertEqual(expired, 1)
        try? await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(expired, 2, "times out → finalized")
        XCTAssertNil(toasts.current)

        // Plain toasts last 2.5 s and have no button.
        toasts.show("Saved", kind: .info)
        XCTAssertNil(toasts.current?.actionTitle)
    }

    func testSharedMotionRunsInOrderAndRemovesOnce() async {
        var phases: [DeletePhase?] = []
        var removals = 0
        let start = Date()
        var removedAt: TimeInterval = 0
        DeleteMotion.run(reduceMotion: false, setPhase: { phases.append($0) }) {
            removals += 1
            removedAt = Date().timeIntervalSince(start)
        }
        try? await Task.sleep(nanoseconds: 1_300_000_000)
        print("phases: \(phases.map { $0.map { "\($0)" } ?? "nil" }), removed at \(String(format: "%.2f", removedAt)) s")
        XCTAssertEqual(phases, [.pressed, .leaving, nil])
        XCTAssertEqual(removals, 1)
        XCTAssertGreaterThan(removedAt, 0.3)
        XCTAssertLessThan(removedAt, 0.6, "row is gone ≈ 0.33 s in; collapse brings the total to ≈ 0.45 s+")

        // Reduce Motion: no press/scale phase, fade only.
        phases = []
        DeleteMotion.run(reduceMotion: true, setPhase: { phases.append($0) }) {}
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertEqual(phases, [.leaving, nil])
    }
}
