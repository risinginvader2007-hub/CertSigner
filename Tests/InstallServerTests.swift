import XCTest
@testable import CertSigner

/// The install server logs every request (status, bytes, time), serves the IPA in full, and a
/// restarted session gets a new port while the old one is really gone.
final class InstallServerTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [LocalHTTPServer.Event] = []
        func add(_ event: LocalHTTPServer.Event) { lock.lock(); items.append(event); lock.unlock() }
        var events: [LocalHTTPServer.Event] { lock.lock(); defer { lock.unlock() }; return items }
        var served: [String] { events.compactMap { if case .served(let text) = $0 { return text } else { return nil } } }
        var completed: Bool { events.contains { if case .payloadCompleted = $0 { return true } else { return false } } }
    }

    func testRequestsAreLoggedAndRestartUsesFreshPort() async throws {
        let ipa = FileManager.default.temporaryDirectory.appendingPathComponent("server-test-\(UUID().uuidString).ipa")
        try Data((0..<300_000).map { UInt8($0 % 251) }).write(to: ipa)
        defer { try? FileManager.default.removeItem(at: ipa) }

        let recorder = Recorder()
        let first = LocalHTTPServer(identity: nil) { recorder.add($0) }
        let port = try await first.start()
        first.setRoute("/tok1/manifest.plist", .data(Data("<plist/>".utf8), contentType: "text/xml"))
        first.setRoute("/tok1/app.ipa", .file(ipa, contentType: "application/octet-stream"))

        let base = "http://127.0.0.1:\(port)"
        let (manifest, r1) = try await URLSession.shared.data(from: URL(string: base + "/tok1/manifest.plist")!)
        XCTAssertEqual((r1 as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(decoding: manifest, as: UTF8.self), "<plist/>")
        let (payload, r2) = try await URLSession.shared.data(from: URL(string: base + "/tok1/app.ipa")!)
        XCTAssertEqual((r2 as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(payload.count, 300_000)
        let (_, r3) = try await URLSession.shared.data(from: URL(string: base + "/old-token/app.ipa")!)
        XCTAssertEqual((r3 as? HTTPURLResponse)?.statusCode, 404)
        try await Task.sleep(nanoseconds: 300_000_000)

        print("served log:\n" + recorder.served.joined(separator: "\n"))
        XCTAssertTrue(recorder.served.contains { $0.hasPrefix("GET /…/manifest.plist → 200 · 8 bytes in") })
        XCTAssertTrue(recorder.served.contains { $0.hasPrefix("GET /…/app.ipa → 200 · ") && $0.contains(" in ") })
        XCTAssertTrue(recorder.served.contains { $0.contains("→ 404") })
        XCTAssertFalse(recorder.served.joined().contains("tok1"), "one-time token stays out of the log")
        XCTAssertTrue(recorder.completed)

        // A new session: the old server stops, the new one avoids the old port.
        first.stop()
        let second = LocalHTTPServer(identity: nil) { _ in }
        let newPort = try await second.start(avoiding: port)
        XCTAssertNotEqual(newPort, port)
        print("first port \(port), second port \(newPort)")
        var request = URLRequest(url: URL(string: base + "/tok1/manifest.plist")!)
        request.timeoutInterval = 3
        do {
            _ = try await URLSession.shared.data(for: request)
            XCTFail("the stopped server must not answer")
        } catch {
            print("old server refused: \((error as? URLError)?.code.rawValue ?? 0)")
        }
        second.stop()
    }
}
