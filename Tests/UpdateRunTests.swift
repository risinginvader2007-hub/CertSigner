import XCTest
@testable import CertSigner

/// The in-app update run with its outside steps (download, sign, install) replaced, so the real
/// orchestration and verification run deterministically: signing can be paused, cancelled and
/// retried, and the test sees exactly which attempt published an IPA and started an install.
@MainActor
final class UpdateRunTests: XCTestCase {

    // MARK: Fixture

    /// Thread-safe record of what the steps were asked to do.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _signCalls = 0, _activeSigns = 0, _maxActiveSigns = 0, _downloads = 0, _signsFinished = 0
        var installs: [String] = [] // main actor only

        func beginSign() -> Int {
            lock.lock(); defer { lock.unlock() }
            _signCalls += 1; _activeSigns += 1; _maxActiveSigns = max(_maxActiveSigns, _activeSigns)
            return _signCalls
        }
        func endSign() { lock.lock(); _activeSigns -= 1; _signsFinished += 1; lock.unlock() }
        func download() { lock.lock(); _downloads += 1; lock.unlock() }
        var signCalls: Int { lock.lock(); defer { lock.unlock() }; return _signCalls }
        var signsFinished: Int { lock.lock(); defer { lock.unlock() }; return _signsFinished }
        var maxActiveSigns: Int { lock.lock(); defer { lock.unlock() }; return _maxActiveSigns }
        var downloads: Int { lock.lock(); defer { lock.unlock() }; return _downloads }
    }

    /// Holds the first signing attempt until the test opens it.
    private final class Blocker: @unchecked Sendable {
        private let lock = NSLock()
        private var opened = false
        private var waiting: CheckedContinuation<Void, Never>?

        func wait() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if opened { lock.unlock(); continuation.resume() } else { waiting = continuation; lock.unlock() }
            }
        }
        func open() {
            lock.lock(); opened = true; let continuation = waiting; waiting = nil; lock.unlock()
            continuation?.resume()
        }
    }

    private struct Fixture {
        let build: Int
        let sourceIPA: URL
        let update: AvailableUpdate
        let plan: UpdatePlan
        let folder: URL
        var downloaded: URL { folder.appendingPathComponent(UpdateRules.assetName) }
        var partial: URL {
            folder.appendingPathComponent("CertSigner-\(build)-\(plan.certificate!.id.uuidString.prefix(8)).ipa.partial")
        }
    }

    private var cleanup: [URL] = []

    override func tearDown() {
        for url in cleanup { try? FileManager.default.removeItem(at: url) }
        cleanup = []
        super.tearDown()
    }

    private func makeFixture(checksum: String? = nil) throws -> Fixture {
        let build = 990_000 + Int.random(in: 0..<9_999)
        let info = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": "com.certsigner.app", "CFBundleVersion": "\(build)",
            "CFBundleShortVersionString": "1.0", "CFBundleName": "CertSigner",
        ], format: .xml, options: 0)
        let ipa = FileManager.default.temporaryDirectory.appendingPathComponent("UpdateRun-\(UUID().uuidString).ipa")
        try Self.storedZip(["Payload/CertSigner.app/Info.plist": info]).write(to: ipa)
        cleanup.append(ipa)
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: ipa.path)[.size] as? NSNumber).int64Value
        let sha256 = try checksum ?? UpdateRules.sha256(of: ipa)
        let manifest = ReleaseManifest(schema: 1, build: build, version: "1.0", commit: "abc", bundleID: "com.certsigner.app",
                                       minimumOS: "16.0",
                                       ipa: .init(name: "CertSigner.ipa", size: size, sha256: sha256),
                                       published: "2026-11-28T00:00:00Z", notes: [])
        let update = AvailableUpdate(manifest: manifest, ipaURL: URL(string: "https://github.com/x/CertSigner.ipa")!, pageURL: nil)
        let certificate = Certificate(record: CertificateRecord(id: UUID(), nickname: "Test", dateAdded: Date(),
                                                                signingCertificate: nil, matchesProfile: true),
                                      profile: nil, hasPassword: true)
        let running = RunningSignature(bundleID: "com.certsigner.app", displayName: "CertSigner", teamID: "ABCDE12345",
                                       teamName: nil, certificates: [])
        let folder = UpdateService.folder.appendingPathComponent("\(build)", isDirectory: true)
        cleanup.append(folder)
        return Fixture(build: build, sourceIPA: ipa, update: update,
                       plan: UpdatePlan(certificate: certificate, running: running, checks: []), folder: folder)
    }

    /// Steps that copy the fixture IPA as the "download", sign by writing "attempt N", and record installs.
    private func steps(_ fixture: Fixture, recorder: Recorder, holdFirstSign blocker: Blocker? = nil) -> UpdateService.RunSteps {
        let source = fixture.sourceIPA
        return UpdateService.RunSteps(
            download: { _, _, _ in
                recorder.download()
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("UpdateRun-dl-\(UUID().uuidString)")
                try FileManager.default.copyItem(at: source, to: temp)
                return temp
            },
            password: { _, _ in "test" },
            sign: { input, emit in
                let attempt = recorder.beginSign()
                defer { recorder.endSign() }
                if attempt == 1, let blocker {
                    await blocker.wait()
                    emit(.log("line from the cancelled attempt", isError: false))
                    emit(.progress(0.9))
                }
                try Data("attempt \(attempt)".utf8).write(to: input.outputURL)
                return SigningOutput(bundleID: "com.certsigner.app", displayName: "CertSigner", version: "1.0", size: 9)
            },
            install: { _, ipa, _ in
                recorder.installs.append((try? String(contentsOf: ipa, encoding: .utf8)) ?? "unreadable")
            }
        )
    }

    private func start(_ service: UpdateService, _ fixture: Fixture) {
        service.start(fixture.update, plan: fixture.plan, certificates: CertificateStore(),
                      serverCertificates: ServerCertificateStore(), method: .automatic, paleraFallback: true)
    }

    /// Waits for a state the run reaches on its own (no fixed delays).
    private func waitUntil(_ what: String, timeout: TimeInterval = 15, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out waiting until \(what)") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "UpdateRunTests-\(UUID().uuidString)")!
    }

    // MARK: P1: cancel during signing, then retry

    func testCancelledSigningNeverPublishesAndOnlyTheRetryInstalls() async throws {
        let fixture = try makeFixture()
        let recorder = Recorder(), blocker = Blocker()
        let service = UpdateService(defaults: freshDefaults(), installedBuild: 100,
                                    steps: steps(fixture, recorder: recorder, holdFirstSign: blocker))

        start(service, fixture)
        try await waitUntil("the first attempt is signing") { recorder.signCalls == 1 }
        service.cancel()
        XCTAssertEqual(service.runState, .idle, "Cancel shows idle at once")

        start(service, fixture) // the retry, while the first zsign run is still going
        XCTAssertTrue(service.isRunning, "the retry reserves the run immediately")
        blocker.open()          // the cancelled attempt now finishes signing

        try await waitUntil("the retry started the install") { !recorder.installs.isEmpty }
        XCTAssertEqual(recorder.installs, ["attempt 2"], "only the retry's IPA is installed")
        XCTAssertEqual(recorder.signCalls, 2)
        XCTAssertEqual(recorder.maxActiveSigns, 1, "the retry waits for the cancelled signing to end")
        XCTAssertEqual(service.runState, .installing)
        XCTAssertFalse(service.log.contains { $0.text.contains("line from the cancelled attempt") },
                       "the cancelled attempt's output doesn't reach the retry's log")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.partial.path), "no half-signed file left")
        let signed = fixture.partial.deletingPathExtension()
        XCTAssertEqual(try String(contentsOf: signed, encoding: .utf8), "attempt 2")
    }

    func testCancelledSigningAloneLeavesNothingBehind() async throws {
        let fixture = try makeFixture()
        let recorder = Recorder(), blocker = Blocker()
        let service = UpdateService(defaults: freshDefaults(), installedBuild: 100,
                                    steps: steps(fixture, recorder: recorder, holdFirstSign: blocker))
        start(service, fixture)
        try await waitUntil("signing") { recorder.signCalls == 1 }
        service.cancel()
        blocker.open()
        // The cancelled signing writes its output and returns; the run must then discard it.
        try await waitUntil("the cancelled signing returned") { recorder.signsFinished == 1 }
        try await waitUntil("its partial file is removed") { !FileManager.default.fileExists(atPath: fixture.partial.path) }
        XCTAssertTrue(recorder.installs.isEmpty, "a cancelled attempt never installs")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.partial.deletingPathExtension().path), "nor publishes a signed IPA")
        XCTAssertEqual(service.runState, .idle)
    }

    // MARK: P2: verification (cached retry, fresh download, bad checksum)

    func testCachedVerifiedDownloadIsReusedWithoutDownloading() async throws {
        let fixture = try makeFixture()
        try FileManager.default.createDirectory(at: fixture.folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture.sourceIPA, to: fixture.downloaded)
        let recorder = Recorder()
        let service = UpdateService(defaults: freshDefaults(), installedBuild: 100, steps: steps(fixture, recorder: recorder))
        start(service, fixture)
        try await waitUntil("installed") { !recorder.installs.isEmpty }
        XCTAssertEqual(recorder.downloads, 0)
        XCTAssertTrue(service.log.contains { $0.text.contains("download from the last attempt") })
        XCTAssertEqual(recorder.installs, ["attempt 1"])
    }

    func testFreshDownloadIsVerifiedThenSigned() async throws {
        let fixture = try makeFixture()
        let recorder = Recorder()
        let service = UpdateService(defaults: freshDefaults(), installedBuild: 100, steps: steps(fixture, recorder: recorder))
        start(service, fixture)
        try await waitUntil("installed") { !recorder.installs.isEmpty }
        XCTAssertEqual(recorder.downloads, 1)
        XCTAssertTrue(service.log.contains { $0.text.hasPrefix("Verified:") })
    }

    func testBadChecksumIsRejectedBeforeSigning() async throws {
        let fixture = try makeFixture(checksum: String(repeating: "00", count: 32))
        let recorder = Recorder()
        let service = UpdateService(defaults: freshDefaults(), installedBuild: 100, steps: steps(fixture, recorder: recorder))
        start(service, fixture)
        try await waitUntil("the run failed") { if case .failed = service.runState { return true }; return false }
        guard case .failed(let stage, let message) = service.runState else { return XCTFail("not failed") }
        XCTAssertEqual(stage, .verify)
        XCTAssertTrue(message.contains("checksum"), message)
        XCTAssertEqual(recorder.signCalls, 0, "an unverified IPA is never signed")
        XCTAssertTrue(recorder.installs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.downloaded.path), "the bad download is deleted")
    }

    // MARK: Minimal ZIP writer (stored entries), so the test needs no extra package

    private static func storedZip(_ files: [String: Data]) -> Data {
        var body = Data(), directory = Data()
        func u16(_ v: Int, _ d: inout Data) { var x = UInt16(v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u32(_ v: UInt32, _ d: inout Data) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        for (name, data) in files.sorted(by: { $0.key < $1.key }) {
            let nameData = Data(name.utf8), crc = crc32(data), offset = UInt32(body.count)
            u32(0x0403_4b50, &body); u16(20, &body); u16(0, &body); u16(0, &body); u16(0, &body); u16(0x21, &body)
            u32(crc, &body); u32(UInt32(data.count), &body); u32(UInt32(data.count), &body)
            u16(nameData.count, &body); u16(0, &body); body.append(nameData); body.append(data)

            u32(0x0201_4b50, &directory); u16(20, &directory); u16(20, &directory); u16(0, &directory); u16(0, &directory)
            u16(0, &directory); u16(0x21, &directory); u32(crc, &directory)
            u32(UInt32(data.count), &directory); u32(UInt32(data.count), &directory)
            u16(nameData.count, &directory); u16(0, &directory); u16(0, &directory); u16(0, &directory); u16(0, &directory)
            u32(0, &directory); u32(offset, &directory); directory.append(nameData)
        }
        var end = Data()
        u32(0x0605_4b50, &end); u16(0, &end); u16(0, &end); u16(files.count, &end); u16(files.count, &end)
        u32(UInt32(directory.count), &end); u32(UInt32(body.count), &end); u16(0, &end)
        return body + directory + end
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}
