import XCTest
@testable import CertSigner

/// The in-app updater's rules: which releases count, how a download is verified, and which
/// certificate signs the update.
final class UpdateServiceTests: XCTestCase {
    private let sha = String(repeating: "ab", count: 32)

    private func manifest(build: Int = 92, bundleID: String = "com.certsigner.app", size: Int64 = 6_000_000,
                          sha256: String? = nil, schema: Int = 1, name: String = "CertSigner.ipa") -> ReleaseManifest {
        ReleaseManifest(schema: schema, build: build, version: "1.0", commit: "abc", bundleID: bundleID,
                        minimumOS: "16.0", ipa: .init(name: name, size: size, sha256: sha256 ?? sha),
                        published: "2026-11-13T17:00:00Z", notes: ["Light-mode glows"])
    }

    private func release(size: Int64 = 6_000_000,
                         url: String = "https://github.com/risinginvader2007-hub/CertSigner/releases/download/latest/CertSigner.ipa",
                         prerelease: Bool = false) -> GitHubRelease {
        GitHubRelease(name: "CertSigner (build 92)", pageURL: nil, draft: false, prerelease: prerelease,
                      assets: [.init(name: "CertSigner.ipa", size: size, downloadURL: URL(string: url)!),
                               .init(name: "update.json", size: 500,
                                     downloadURL: URL(string: "https://github.com/risinginvader2007-hub/CertSigner/releases/download/latest/update.json")!)])
    }

    // MARK: Release checks

    func testNewerReleaseIsOffered() throws {
        let update = try UpdateRules.update(release: release(), manifest: manifest(), installedBuild: 90)
        XCTAssertEqual(update?.build, 92)
        XCTAssertEqual(update?.ipaURL.lastPathComponent, "CertSigner.ipa")
    }

    func testSameOrOlderBuildIsNotOfferedAgain() throws {
        XCTAssertNil(try UpdateRules.update(release: release(), manifest: manifest(build: 92), installedBuild: 92))
        XCTAssertNil(try UpdateRules.update(release: release(), manifest: manifest(build: 91), installedBuild: 92))
    }

    func testBuildsBeforeTheUpdaterCountAsOlder() {
        XCTAssertEqual(UpdateRules.build(from: "1"), 1)
        XCTAssertEqual(UpdateRules.build(from: nil), 0)
        XCTAssertEqual(UpdateRules.build(from: "x"), 0)
    }

    func testReleaseThatIsNotCertSignerIsRejected() {
        let cases: [(GitHubRelease, ReleaseManifest)] = [
            (release(), manifest(bundleID: "com.evil.app")),
            (release(), manifest(sha256: "nothex")),
            (release(), manifest(schema: 2)),
            (release(), manifest(name: "Other.ipa")),
            (release(size: 5_000_000), manifest()),
            (release(url: "https://example.com/CertSigner.ipa"), manifest()),
            (release(url: "http://github.com/risinginvader2007-hub/CertSigner/releases/download/latest/CertSigner.ipa"), manifest()),
            (release(url: "https://github.com/someone/CertSigner/releases/download/latest/CertSigner.ipa"), manifest()),
            (release(prerelease: true), manifest())
        ]
        for (index, (release, manifest)) in cases.enumerated() {
            XCTAssertThrowsError(try UpdateRules.update(release: release, manifest: manifest, installedBuild: 1), "case \(index)")
        }
    }

    func testGitHubReleaseDecodes() throws {
        let json = """
        {"name":"CertSigner (build 92)","html_url":"https://github.com/risinginvader2007-hub/CertSigner/releases/tag/latest",
         "draft":false,"prerelease":false,"tag_name":"latest",
         "assets":[{"name":"CertSigner.ipa","size":6000000,"browser_download_url":"https://github.com/risinginvader2007-hub/CertSigner/releases/download/latest/CertSigner.ipa"}]}
        """
        let decoded = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.assets.first?.size, 6_000_000)
        XCTAssertNotNil(decoded.pageURL)
    }

    func testManifestDecodesWhatCIWrites() throws {
        let json = """
        {"schema":1,"build":92,"version":"1.0","commit":"abc","bundleID":"com.certsigner.app","minimumOS":"16.0",
         "ipa":{"name":"CertSigner.ipa","size":6000000,"sha256":"\(sha)"},"published":"2026-11-13T17:00:00Z","notes":["a","b"]}
        """
        let decoded = try JSONDecoder().decode(ReleaseManifest.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, manifest(build: 92).withNotes(["a", "b"]))
        XCTAssertNotNil(decoded.publishedDate)
    }

    func testMinimumOS() {
        let ios17 = OperatingSystemVersion(majorVersion: 17, minorVersion: 4, patchVersion: 1)
        XCTAssertTrue(UpdateRules.osSatisfies("16.0", current: ios17))
        XCTAssertTrue(UpdateRules.osSatisfies("17.4.1", current: ios17))
        XCTAssertFalse(UpdateRules.osSatisfies("17.5", current: ios17))
        XCTAssertTrue(UpdateRules.osSatisfies("", current: ios17))
    }

    // MARK: Verifying the download

    func testVerificationChecksSizeAndChecksum() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("update-\(UUID().uuidString).ipa")
        try Data("not the release".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let digest = try UpdateRules.sha256(of: url)
        XCTAssertTrue(UpdateRules.isSHA256(digest))
        XCTAssertThrowsError(try UpdateRules.verify(ipa: url, against: manifest(size: 999))) // size
        XCTAssertThrowsError(try UpdateRules.verify(ipa: url, against: manifest(size: 15)))  // checksum
        XCTAssertThrowsError(try UpdateRules.verify(ipa: url, against: manifest(size: 15, sha256: digest))) // not an IPA
    }

    /// A real IPA with the right size and checksum is still refused when it isn't CertSigner.
    func testVerificationRefusesAnotherAppsIPA() throws {
        guard let path = ProcessInfo.processInfo.environment["CS_FIXTURES"] else { throw XCTSkip("CS_FIXTURES not set") }
        let ipa = URL(fileURLWithPath: path).appendingPathComponent("test.ipa")
        let size = (try FileManager.default.attributesOfItem(atPath: ipa.path)[.size] as? NSNumber)?.int64Value ?? 0
        let other = manifest(size: size, sha256: try UpdateRules.sha256(of: ipa))
        XCTAssertThrowsError(try UpdateRules.verify(ipa: ipa, against: other)) { error in
            XCTAssertTrue((error as? UpdateError)?.localizedDescription.contains("bundle ID") == true)
        }
    }

    // MARK: Certificate choice

    private func candidate(team: String?, signedThisCopy: Bool = false, usable: Bool = true, active: Bool = false,
                           expires: TimeInterval = 100) -> UpdateCertificateMatcher.Candidate {
        .init(id: UUID(), teamID: team, signedThisCopy: signedThisCopy, usable: usable, isActive: active,
              expires: Date(timeIntervalSince1970: expires))
    }

    func testPrefersTheCertificateThatSignedThisCopy() {
        let exact = candidate(team: "TEAM1", signedThisCopy: true)
        let active = candidate(team: "TEAM1", active: true, expires: 999)
        XCTAssertEqual(UpdateCertificateMatcher.pick([active, exact], runningTeam: "TEAM1")?.id, exact.id)
    }

    func testNeverPicksAnotherTeam() {
        let other = candidate(team: "TEAM2", signedThisCopy: false, active: true)
        XCTAssertNil(UpdateCertificateMatcher.pick([other], runningTeam: "TEAM1"))
        let renewed = candidate(team: "TEAM1")
        XCTAssertEqual(UpdateCertificateMatcher.pick([other, renewed], runningTeam: "TEAM1")?.id, renewed.id)
    }

    func testPrefersUsableThenActiveThenLatestExpiry() {
        let broken = candidate(team: "T", usable: false, active: true)
        let older = candidate(team: "T", expires: 10)
        let newer = candidate(team: "T", expires: 20)
        XCTAssertEqual(UpdateCertificateMatcher.pick([broken, older, newer], runningTeam: "T")?.id, newer.id)
        let active = candidate(team: "T", active: true, expires: 5)
        XCTAssertEqual(UpdateCertificateMatcher.pick([older, newer, active], runningTeam: "T")?.id, active.id)
    }

    func testUnknownRunningTeamAllowsAnyCertificate() {
        let any = candidate(team: "X")
        XCTAssertEqual(UpdateCertificateMatcher.pick([any], runningTeam: nil)?.id, any.id)
    }

    // MARK: Signing the update

    func testReadOnlyFilesBecomeWritableForSigning() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("writable-\(UUID().uuidString)", isDirectory: true)
        let framework = root.appendingPathComponent("Payload/App.app/Frameworks/Lib.framework", isDirectory: true)
        try fm.createDirectory(at: framework, withIntermediateDirectories: true)
        let binary = framework.appendingPathComponent("Lib")
        try Data([0xcf, 0xfa, 0xed, 0xfe]).write(to: binary)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: binary.path)
        defer { try? fm.removeItem(at: root) }

        XCTAssertEqual(AppBundlePatcher.makeWritable(root), 1)
        let mode = (try fm.attributesOfItem(atPath: binary.path)[.posixPermissions] as? NSNumber)?.int16Value ?? 0
        XCTAssertEqual(mode, 0o755, "owner write added, executable bits kept")
        XCTAssertEqual(AppBundlePatcher.makeWritable(root), 0, "nothing left to change")
    }

    func testSigningFailuresAreExplainedInPlainWords() {
        let zsign = SigningError.sign("zsign couldn't sign the app. See the log for details.")
        let parse = UpdateService.explainSigningFailure(zsign, lines: [
            (">>> Warning: Skipping non-Mach-O file: \tFrameworks/OpenSSL.framework/OpenSSL", false),
            (">>> Can't parse BundleExecute file! /tmp/x/OpenSSL", true)
        ])
        XCTAssertTrue(parse.cause.contains("program files"))
        XCTAssertFalse(parse.cause.contains("See the log"))
        let password = UpdateService.explainSigningFailure(
            SigningError.sign("Couldn't load the certificate. Check the .p12 password and that it matches the profile."), lines: [])
        XCTAssertTrue(password.fix.contains("password"))
    }

    // MARK: Skipping

    @MainActor
    func testSkippedBuildIsNotHighlightedButNewerOneIs() {
        let defaults = UserDefaults(suiteName: "UpdateServiceTests-\(UUID().uuidString)")!
        let service = UpdateService(defaults: defaults)
        let update = AvailableUpdate(manifest: manifest(build: 92), ipaURL: URL(string: "https://github.com/x")!, pageURL: nil)
        service.skip(update)
        XCTAssertEqual(defaults.integer(forKey: UpdateService.Keys.skippedBuild), 92)
        XCTAssertEqual(UpdateService(defaults: defaults).skippedBuild, 92)
    }

    // MARK: Update dot (cached check result)

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "UpdateServiceTests-\(UUID().uuidString)")!
    }

    private func cache(_ build: Int) -> UpdateCheckCache {
        UpdateCheckCache(latestBuild: build, version: "1.0", checked: Date(timeIntervalSince1970: 1_800_000_000))
    }

    @MainActor
    func testDotShowsFromCacheAtLaunchWithoutNetwork() {
        let defaults = freshDefaults()
        UpdateDotRules.save(cache(101), to: defaults)
        let service = UpdateService(defaults: defaults, installedBuild: 100)
        XCTAssertEqual(service.cache, cache(101), "read back from disk")
        XCTAssertEqual(service.checkState, .idle, "no check has run")
        XCTAssertTrue(service.showsDot)
    }

    @MainActor
    func testDotClearsWhenInstalledBuildReachesCachedLatest() {
        let defaults = freshDefaults()
        UpdateDotRules.save(cache(101), to: defaults)
        XCTAssertFalse(UpdateService(defaults: defaults, installedBuild: 101).showsDot)
        XCTAssertFalse(UpdateService(defaults: defaults, installedBuild: 102).showsDot)
        XCTAssertFalse(UpdateService(defaults: freshDefaults(), installedBuild: 100).showsDot, "no cache, no dot")
    }

    @MainActor
    func testSkippedBuildHidesDotUntilANewerBuild() {
        let defaults = freshDefaults()
        UpdateDotRules.save(cache(101), to: defaults)
        let service = UpdateService(defaults: defaults, installedBuild: 100)
        service.skip(AvailableUpdate(manifest: manifest(build: 101), ipaURL: URL(string: "https://github.com/x")!, pageURL: nil))
        XCTAssertFalse(service.showsDot)
        XCTAssertFalse(UpdateService(defaults: defaults, installedBuild: 100).showsDot, "skip survives a relaunch")
        UpdateDotRules.save(cache(102), to: defaults)
        XCTAssertTrue(UpdateService(defaults: defaults, installedBuild: 100).showsDot, "a newer build shows it again")
    }

    func testDotHiddenWhileInstalling() {
        XCTAssertTrue(UpdateDotRules.showsDot(cache: cache(101), installedBuild: 100, skippedBuild: 0, installing: false))
        XCTAssertFalse(UpdateDotRules.showsDot(cache: cache(101), installedBuild: 100, skippedBuild: 0, installing: true))
    }

    @MainActor
    func testFailedCheckKeepsCachedStateAndResultsReplaceIt() {
        let old = cache(101)
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        func after(_ state: UpdateService.CheckState) -> UpdateCheckCache? {
            UpdateDotRules.cache(after: state, previous: old, installedBuild: 100, installedVersion: "1.0", now: now)
        }
        XCTAssertEqual(after(.failed("GitHub answered 500.")), old, "a failed check keeps the old state")
        XCTAssertEqual(after(.checking), old)
        XCTAssertNil(UpdateDotRules.cache(after: .failed("offline"), previous: nil, installedBuild: 100,
                                            installedVersion: "1.0", now: now), "and never creates a dot")

        let newer = AvailableUpdate(manifest: manifest(build: 105), ipaURL: URL(string: "https://github.com/x")!, pageURL: nil)
        XCTAssertEqual(after(.available(newer)), UpdateCheckCache(latestBuild: 105, version: "1.0", checked: now))

        let upToDate = after(.upToDate(now))
        XCTAssertEqual(upToDate?.latestBuild, 100, "no newer build: the feed's answer removes the dot")
        XCTAssertFalse(UpdateDotRules.showsDot(cache: upToDate, installedBuild: 100, skippedBuild: 0, installing: false))
    }

    // MARK: Update sheet content (never blank)

    /// Build 102 bug: the sheet opened with only a title and Close. Every state must show something:
    /// the saved check alone (dot shown, no details loaded yet) is a visible "Loading build N…".
    @MainActor
    func testSheetShowsLoadingWhenOnlyTheSavedCheckExists() {
        let defaults = freshDefaults()
        UpdateDotRules.save(cache(104), to: defaults)
        let service = UpdateService(defaults: defaults, installedBuild: 102)
        XCTAssertTrue(service.showsDot, "red dot from the saved check")
        XCTAssertNil(service.available, "no release details loaded yet: the sheet has to load them")
        XCTAssertEqual(service.sheetContent, .loading(savedBuild: 104))
    }

    @MainActor
    func testSheetContentForEveryCheckState() {
        let update = AvailableUpdate(manifest: manifest(build: 104), ipaURL: URL(string: "https://github.com/x")!, pageURL: nil)
        func content(_ state: UpdateService.CheckState, cache saved: UpdateCheckCache? = nil, installed: Int = 102) -> UpdateService.SheetContent {
            UpdateService.sheetContent(checkState: state, cache: saved, installedBuild: installed)
        }
        XCTAssertEqual(content(.idle), .loading(savedBuild: nil), "nothing saved: 'Checking for updates…'")
        XCTAssertEqual(content(.checking, cache: cache(104)), .loading(savedBuild: 104), "background check running")
        XCTAssertEqual(content(.checking, cache: cache(102)), .loading(savedBuild: nil), "saved build isn't newer")
        XCTAssertEqual(content(.failed("GitHub answered 500.")), .failed("GitHub answered 500."), "error state with Try Again")
        XCTAssertEqual(content(.upToDate(Date())), .upToDate)
        XCTAssertEqual(content(.available(update), cache: cache(104)), .update(update), "installed 102 < saved 104: details")
    }
}

private extension ReleaseManifest {
    func withNotes(_ notes: [String]) -> ReleaseManifest {
        ReleaseManifest(schema: schema, build: build, version: version, commit: commit, bundleID: bundleID,
                        minimumOS: minimumOS, ipa: ipa, published: published, notes: notes)
    }
}
