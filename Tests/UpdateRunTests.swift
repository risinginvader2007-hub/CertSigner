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

    /// `payloadBytes` adds a file of that size to the app, for a realistically large IPA.
    private func makeFixture(checksum: String? = nil, payloadBytes: Int = 0) throws -> Fixture {
        let build = 990_000 + Int.random(in: 0..<9_999)
        let info = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": "com.certsigner.app", "CFBundleVersion": "\(build)",
            "CFBundleShortVersionString": "1.0", "CFBundleName": "CertSigner",
        ], format: .xml, options: 0)
        let ipa = FileManager.default.temporaryDirectory.appendingPathComponent("UpdateRun-\(UUID().uuidString).ipa")
        var entries: [ZipEntry] = [.init(name: "Payload/CertSigner.app/Info.plist", content: .data(info))]
        if payloadBytes > 0 { entries.append(.init(name: "Payload/CertSigner.app/Payload.bin", content: .pattern(payloadBytes))) }
        try Self.writeStoredZip(entries, to: ipa)
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

    /// Lets a step reach the service that runs it (set after the service is created).
    private final class ServiceBox: @unchecked Sendable { weak var service: UpdateService? }

    /// Temporary files the fake downloader handed over.
    private final class Temps: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        func add(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
        var all: [URL] { lock.lock(); defer { lock.unlock() }; return urls }
    }

    /// Steps that copy the fixture IPA as the "download", sign by writing "attempt N", and record installs.
    /// `afterDownload` runs once the temporary file exists, before it's returned.
    /// `holdVerify` holds the first verification of a fresh download until opened.
    private func steps(_ fixture: Fixture, recorder: Recorder, holdFirstSign blocker: Blocker? = nil,
                       temps: Temps = Temps(), afterDownload: (@Sendable () async -> Void)? = nil,
                       holdVerify: Blocker? = nil, verifyFinished: Recorder? = nil) -> UpdateService.RunSteps {
        let source = fixture.sourceIPA
        let verifyCalls = Recorder()
        return UpdateService.RunSteps(
            download: { _, _, _ in
                recorder.download()
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("UpdateRun-dl-\(UUID().uuidString)")
                try FileManager.default.copyItem(at: source, to: temp)
                temps.add(temp)
                await afterDownload?()
                return temp
            },
            verify: { ipa, manifest in
                let call = verifyCalls.beginSign()
                defer { verifyCalls.endSign(); verifyFinished?.download() }
                if call == 1, let holdVerify { await holdVerify.wait() }
                try await UpdateRules.verifyInBackground(ipa: ipa, against: manifest)
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

    // MARK: Follow-up review: hand-off, double start, cache replacement, verify cancel, large IPA

    /// Cancel lands while the downloader is handing over its file: the temporary IPA is deleted,
    /// nothing is signed or installed, and the existing cache file is left alone.
    func testCancelDuringDownloadHandoffDeletesTheTemporaryFile() async throws {
        let fixture = try makeFixture()
        try FileManager.default.createDirectory(at: fixture.folder, withIntermediateDirectories: true)
        try Data("old cache".utf8).write(to: fixture.downloaded) // fails verification, so a download starts
        let recorder = Recorder(), temps = Temps(), box = ServiceBox()
        let service = UpdateService(defaults: freshDefaults(), installedBuild: 100,
                                    steps: steps(fixture, recorder: recorder, temps: temps,
                                                 afterDownload: { await MainActor.run { box.service?.cancel() } }))
        box.service = service
        start(service, fixture)
        try await waitUntil("the downloader handed over a file") { temps.all.count == 1 }
        let temp = try XCTUnwrap(temps.all.first)
        try await waitUntil("the handed-over file is deleted") { !FileManager.default.fileExists(atPath: temp.path) }
        XCTAssertEqual(recorder.signCalls, 0)
        XCTAssertTrue(recorder.installs.isEmpty)
        XCTAssertEqual(try String(contentsOf: fixture.downloaded, encoding: .utf8), "old cache",
                       "the cancelled attempt didn't replace the cache")
        XCTAssertEqual(service.runState, .idle)
    }

    /// Two immediate Update taps: one run, one install.
    func testTwoImmediateStartsInstallOnce() async throws {
        let fixture = try makeFixture()
        let recorder = Recorder()
        let service = UpdateService(defaults: freshDefaults(), installedBuild: 100, steps: steps(fixture, recorder: recorder))
        start(service, fixture)
        start(service, fixture)
        try await waitUntil("installed") { !recorder.installs.isEmpty }
        XCTAssertEqual(recorder.installs, ["attempt 1"])
        XCTAssertEqual(recorder.downloads, 1)
        XCTAssertEqual(recorder.signCalls, 1)
        XCTAssertEqual(service.installingBuild, fixture.build, "the row names the build being installed")
    }

    /// A corrupt file in the update cache is replaced by a valid fresh download.
    func testCorruptCacheIsReplacedByAFreshDownload() async throws {
        let fixture = try makeFixture()
        try FileManager.default.createDirectory(at: fixture.folder, withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: fixture.downloaded)
        let recorder = Recorder()
        let service = UpdateService(defaults: freshDefaults(), installedBuild: 100, steps: steps(fixture, recorder: recorder))
        start(service, fixture)
        try await waitUntil("installed") { !recorder.installs.isEmpty }
        XCTAssertEqual(recorder.downloads, 1)
        XCTAssertEqual(try Data(contentsOf: fixture.downloaded), try Data(contentsOf: fixture.sourceIPA))
    }

    /// Cancel while the downloaded IPA is being verified: that attempt never signs. A retry then
    /// runs normally, which also proves the cancelled run has ended.
    func testCancelDuringVerificationPreventsSigning() async throws {
        let fixture = try makeFixture()
        let recorder = Recorder(), verifyGate = Blocker()
        let verifies = Recorder() // counts finished verifications (its download counter)
        let service = UpdateService(defaults: freshDefaults(), installedBuild: 100,
                                    steps: steps(fixture, recorder: recorder, holdVerify: verifyGate, verifyFinished: verifies))
        start(service, fixture)
        try await waitUntil("verifying") { service.runState == .running(.verify, 0) }
        service.cancel()
        verifyGate.open()
        try await waitUntil("the held verification finished") { verifies.downloads == 1 }
        XCTAssertEqual(recorder.signCalls, 0, "the cancelled attempt doesn't sign")

        start(service, fixture)
        try await waitUntil("the retry installed") { !recorder.installs.isEmpty }
        XCTAssertEqual(recorder.signCalls, 1, "only the retry signed")
        XCTAssertEqual(recorder.installs, ["attempt 1"])
    }

    /// A realistically large IPA: verification hashes it off the main actor, so the main actor
    /// keeps running (counted with a 5 ms ticker). The same work on the main actor, measured for
    /// comparison, blocks the ticker for its whole duration.
    func testLargeIPAVerificationKeepsTheMainActorResponsive() async throws {
        let megabytes = 128
        let fixture = try makeFixture(payloadBytes: megabytes * 1_024 * 1_024)
        let manifest = fixture.update.manifest

        func measure(_ work: () async throws -> Void) async rethrows -> (seconds: Double, ticks: Int, maxGap: Double) {
            let ticks = TickLog()
            let ticker = Task { @MainActor in
                while !Task.isCancelled {
                    ticks.dates.append(Date())
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
            }
            await Task.yield()
            let started = Date()
            try await work()
            let ended = Date()
            ticker.cancel()
            let during = ticks.dates.filter { $0 > started && $0 < ended }
            let points = [started] + during + [ended]
            let maxGap = zip(points, points.dropFirst()).map { $1.timeIntervalSince($0) }.max() ?? 0
            return (ended.timeIntervalSince(started), during.count, maxGap)
        }

        let background = try await measure { try await UpdateRules.verifyInBackground(ipa: fixture.sourceIPA, against: manifest) }
        let onMain = try await measure { try UpdateRules.verify(ipa: fixture.sourceIPA, against: manifest) }
        print(String(format: "PERF update verify %d MB: background %.2f s, %d main-actor ticks, max gap %.0f ms | on main %.2f s, %d ticks, max gap %.0f ms",
                     megabytes, background.seconds, background.ticks, background.maxGap * 1000,
                     onMain.seconds, onMain.ticks, onMain.maxGap * 1000))
        XCTAssertGreaterThan(background.ticks, 0, "the main actor ran while the IPA was hashed")
        XCTAssertEqual(onMain.ticks, 0, "control: hashing on the main actor blocks it")
        if onMain.seconds > 0.2 {
            XCTAssertLessThan(background.maxGap, onMain.seconds / 2, "no main-actor stall close to the hashing time")
        }
    }

    @MainActor private final class TickLog { var dates: [Date] = [] }

    // MARK: Minimal ZIP writer (stored entries, streamed to disk), so the test needs no extra package

    private struct ZipEntry {
        enum Content { case data(Data), pattern(Int) }
        let name: String
        let content: Content
    }

    private static func writeStoredZip(_ entries: [ZipEntry], to url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        func u16(_ v: Int, _ d: inout Data) { var x = UInt16(v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func u32(_ v: UInt32, _ d: inout Data) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        // A large entry is a repeating 1 MB chunk of varied bytes (not zeros), written chunk by chunk.
        let chunk = Data((0..<(1 << 20)).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        func chunks(_ content: ZipEntry.Content, _ body: (Data) throws -> Void) rethrows {
            switch content {
            case .data(let data): try body(data)
            case .pattern(let size):
                var left = size
                while left > 0 { let n = min(left, chunk.count); try body(n == chunk.count ? chunk : chunk.prefix(n)); left -= n }
            }
        }
        var directory = Data(), offset = 0
        for entry in entries {
            var crc = CRC32()
            var size = 0
            chunks(entry.content) { crc.update($0); size += $0.count }
            let name = Data(entry.name.utf8)
            var header = Data()
            u32(0x0403_4b50, &header); u16(20, &header); u16(0, &header); u16(0, &header); u16(0, &header); u16(0x21, &header)
            u32(crc.value, &header); u32(UInt32(size), &header); u32(UInt32(size), &header)
            u16(name.count, &header); u16(0, &header); header.append(name)
            file.write(header)
            chunks(entry.content) { file.write($0) }

            u32(0x0201_4b50, &directory); u16(20, &directory); u16(20, &directory); u16(0, &directory); u16(0, &directory)
            u16(0, &directory); u16(0x21, &directory); u32(crc.value, &directory)
            u32(UInt32(size), &directory); u32(UInt32(size), &directory)
            u16(name.count, &directory); u16(0, &directory); u16(0, &directory); u16(0, &directory); u16(0, &directory)
            u32(0, &directory); u32(UInt32(offset), &directory); directory.append(name)
            offset += header.count + size
        }
        var end = Data()
        u32(0x0605_4b50, &end); u16(0, &end); u16(0, &end); u16(entries.count, &end); u16(entries.count, &end)
        u32(UInt32(directory.count), &end); u32(UInt32(offset), &end); u16(0, &end)
        file.write(directory)
        file.write(end)
    }

    /// Table-driven CRC-32 (zip's), updated chunk by chunk.
    private struct CRC32 {
        private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
            var c = UInt32(n)
            for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB8_8320 : c >> 1 }
            return c
        }
        private var crc: UInt32 = 0xFFFF_FFFF
        mutating func update(_ data: Data) {
            var c = crc
            data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                for byte in bytes { c = Self.table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
            }
            crc = c
        }
        var value: UInt32 { ~crc }
    }
}
