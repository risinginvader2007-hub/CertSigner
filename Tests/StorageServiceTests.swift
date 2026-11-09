import XCTest
@testable import CertSigner

/// Storage sizes add up every file inside, at any depth (nested folders, .app bundles), and the
/// report's totals, shares, reclaimable logs and formatting behave.
final class StorageServiceTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("storage-test-\(UUID().uuidString)")
        let bundle = folder.appendingPathComponent("Payload/Demo.app/PlugIns/Share.appex", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data(count: 100_000).write(to: folder.appendingPathComponent("app.ipa"))
        try Data(count: 40_000).write(to: folder.appendingPathComponent("Payload/Demo.app/Demo"))
        try Data(count: 25_000).write(to: bundle.appendingPathComponent("Share"))
        try Data(count: 4).write(to: folder.appendingPathComponent("tiny.txt"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testRecursiveSizeCountsEveryNestedFile() {
        let size = StorageService.size(of: folder)
        print("measured \(size) bytes for 165,004 bytes of files")
        // On-disk (allocated) size is at least the logical bytes, never just the folder entry.
        XCTAssertGreaterThanOrEqual(size, 165_004)
        XCTAssertLessThan(size, 400_000)
        XCTAssertGreaterThanOrEqual(StorageService.size(of: folder.appendingPathComponent("app.ipa")), 100_000)
        XCTAssertEqual(StorageService.size(of: folder.appendingPathComponent("missing")), 0)
    }

    func testReportTotalsSharesAndFormatting() {
        let old = Date().addingTimeInterval(-40 * 24 * 3600)
        let report = StorageReport(entries: [
            .signed: [StorageEntry(category: .signed, key: "a", name: "A", date: old, urls: [], bytes: 3_000_000),
                      StorageEntry(category: .signed, key: "b", name: "B", date: Date(), urls: [], bytes: 1_000_000)],
            .logs: [StorageEntry(category: .logs, key: "l1", name: "old", date: old, urls: [], bytes: 500),
                    StorageEntry(category: .logs, key: "l2", name: "new", date: Date(), urls: [], bytes: 500)],
            .cache: [StorageEntry(category: .cache, key: "c", name: "tmp", date: nil, urls: [], bytes: 6_000_000)]
        ], calculatedAt: Date(), deviceAvailable: nil, deviceTotal: nil)
        XCTAssertEqual(report.total, 10_001_000)
        XCTAssertEqual(report.share(.cache), 6_000_000 / 10_001_000, accuracy: 0.0001)
        XCTAssertEqual(report.largestItem?.name, "tmp")
        XCTAssertEqual(report.oldestSignedApp?.name, "A")
        XCTAssertEqual(report.oldLogs.map(\.name), ["old"])
        XCTAssertEqual(StorageService.format(0), "Empty")
        XCTAssertNotEqual(StorageService.format(6_700_000), "Empty")
        XCTAssertEqual(StorageCategory.signed.countText(1), "1 app")
        XCTAssertEqual(StorageCategory.signed.countText(3), "3 apps")
        XCTAssertEqual(Set(StorageCategory.allCases.map { "\($0.color)" }).count, 5, "five distinct colours")
    }

    func testDeviceCapacityIsReadable() {
        let capacity = StorageService.deviceCapacity()
        print("device free \(capacity.available.map(StorageService.format) ?? "nil") of \(capacity.total.map(StorageService.format) ?? "nil")")
        XCTAssertNotNil(capacity.total)
    }
}
