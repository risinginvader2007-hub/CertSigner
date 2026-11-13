import XCTest
@testable import CertSigner

/// Sources list one app per bundle ID with its versions newest first, whatever the JSON layout.
final class RepositoryMergeTests: XCTestCase {
    private let base = URL(string: "https://example.com/repo.json")!

    private func parse(_ json: String) throws -> RepositoryParser.Parsed {
        try RepositoryParser.parse(Data(json.utf8), sourceURL: base)
    }

    // MARK: Version order

    func testVersionComparisonUsesNumbersNotText() {
        XCTAssertLessThan(VersionOrder.compare("9.0", "10.0"), 0)
        XCTAssertGreaterThan(VersionOrder.compare("454.0.0", "453.2.1"), 0)
        XCTAssertGreaterThan(VersionOrder.compare("1.2.3.4", "1.2.3"), 0)
        XCTAssertGreaterThan(VersionOrder.compare("1.10", "1.9.9"), 0)
        XCTAssertEqual(VersionOrder.compare("1.2.3", "1.2.3.0"), 0)
        XCTAssertEqual(VersionOrder.compare("v2.1", "2.1"), 0)
    }

    func testPreReleasesComeBeforeTheRelease() {
        let newestFirst = ["2.3", "2.3rc", "2.3b3", "2.3b2", "2.3a", "2.2.9"]
        let shuffled = ["2.3b2", "2.2.9", "2.3", "2.3a", "2.3rc", "2.3b3"]
        let sorted = shuffled.sorted { VersionOrder.compare($0, $1) > 0 }
        XCTAssertEqual(sorted, newestFirst)
        XCTAssertLessThan(VersionOrder.compare("1.0-beta.2", "1.0"), 0)
        XCTAssertLessThan(VersionOrder.compare("1.0-beta.1", "1.0-beta.2"), 0)
    }

    func testUnreadableVersionsAreOldestAndDatesBreakTies() {
        XCTAssertLessThan(VersionOrder.compare("–", "0.1"), 0)
        let older = RepoVersion(version: "1.0", date: Date(timeIntervalSince1970: 100), downloadURL: base)
        let newer = RepoVersion(version: "1.0", date: Date(timeIntervalSince1970: 200), downloadURL: URL(string: "https://example.com/b.ipa"))
        XCTAssertTrue(VersionOrder.newestFirst(newer, older))
        XCTAssertFalse(VersionOrder.newestFirst(older, newer))
    }

    // MARK: Legacy layout: one app entry per version (e.g. AppTesters)

    private let legacy = """
    {"name":"Legacy Repo","apps":[
      {"name":"Instagram","bundleIdentifier":"com.burbn.instagram","version":"451.0.0","versionDate":"2026-10-24",
       "size":345086224,"downloadURL":"https://example.com/ig-451.ipa","iconURL":"https://example.com/ig.png","localizedDescription":"Photos"},
      {"name":"Instagram","bundleIdentifier":"com.burbn.instagram","version":"454.0.0","versionDate":"2026-11-04",
       "size":380812690,"downloadURL":"https://example.com/ig-454.ipa","minOSVersion":"16.0"},
      {"name":"Instagram","bundleIdentifier":"com.burbn.instagram","version":"99.0","versionDate":"2020-01-01",
       "size":100,"downloadURL":"https://example.com/ig-99.ipa"},
      {"name":"Instagram","bundleIdentifier":"com.burbn.instagram","version":"454.0.0","versionDate":"2026-11-04",
       "size":380812690,"downloadURL":"https://example.com/ig-454.ipa"},
      {"name":"WeatherLive","bundleIdentifier":"com.apalonapps.wlf","version":"7.1","downloadURL":"https://example.com/w71.ipa"},
      {"name":"Weather","bundleIdentifier":"com.apalonapps.wlf","version":"7.10","downloadURL":"https://example.com/w710.ipa"},
      {"name":"No Link","bundleIdentifier":"com.example.nolink","version":"1.0"}
    ]}
    """

    func testLegacyEntriesBecomeOneAppWithItsVersions() throws {
        let parsed = try parse(legacy)
        XCTAssertEqual(parsed.rawEntries, 7)
        XCTAssertEqual(parsed.apps.count, 3, "one app per bundle ID")
        XCTAssertEqual(parsed.duplicatesRemoved, 1, "the repeated 454.0.0 entry")

        let instagram = try XCTUnwrap(parsed.apps.first { $0.bundleID == "com.burbn.instagram" })
        XCTAssertEqual(instagram.versions.map(\.version), ["454.0.0", "451.0.0", "99.0"])
        XCTAssertEqual(instagram.latest.size, 380_812_690)
        XCTAssertEqual(instagram.latest.minOSVersion, "16.0")
        XCTAssertEqual(instagram.latest.downloadURL?.lastPathComponent, "ig-454.ipa")
        XCTAssertNotNil(instagram.latest.date)
        // App details are kept even when the newest entry doesn't repeat them.
        XCTAssertEqual(instagram.iconURL?.lastPathComponent, "ig.png")
        XCTAssertEqual(instagram.appDescription, "Photos")
        XCTAssertEqual(Set(instagram.versions.map(\.id)).count, instagram.versions.count, "version ids are unique")

        // The same bundle ID under another name is the same iOS app; the newest entry names it.
        let weather = try XCTUnwrap(parsed.apps.first { $0.bundleID == "com.apalonapps.wlf" })
        XCTAssertEqual(weather.versions.map(\.version), ["7.10", "7.1"])
        XCTAssertEqual(weather.name, "Weather")
    }

    func testVersionWithoutDownloadIsKeptWithoutALink() throws {
        let parsed = try parse(legacy)
        let app = try XCTUnwrap(parsed.apps.first { $0.bundleID == "com.example.nolink" })
        XCTAssertNil(app.latest.downloadURL)
    }

    // MARK: AltStore layout: one app with a versions array

    func testVersionsArrayKeepsEachVersionsOwnDetails() throws {
        let json = """
        {"name":"AltStore-style","apps":[{"name":"Delta","bundleIdentifier":"com.rileytestut.Delta",
          "localizedDescription":"Emulator","versions":[
            {"version":"1.9","date":"2025-01-01","size":10,"downloadURL":"https://example.com/d19.ipa","localizedDescription":"Old","minOSVersion":"14.0"},
            {"version":"1.10","date":"2026-01-01","size":20,"downloadURL":"https://example.com/d110.ipa","localizedDescription":"New","minOSVersion":"15.0"},
            {"version":"1.10b1","date":"2025-12-01","size":15,"downloadURL":"https://example.com/d110b1.ipa"}
          ]}]}
        """
        let parsed = try parse(json)
        XCTAssertEqual(parsed.rawEntries, 1)
        XCTAssertEqual(parsed.apps.count, 1)
        let delta = parsed.apps[0]
        XCTAssertEqual(delta.versions.map(\.version), ["1.10", "1.10b1", "1.9"])
        XCTAssertEqual(delta.versions.map(\.size), [20, 15, 10])
        XCTAssertEqual(delta.latest.notes, "New")
        XCTAssertEqual(delta.latest.minOSVersion, "15.0")
        XCTAssertEqual(delta.versions.last?.downloadURL?.lastPathComponent, "d19.ipa")
        XCTAssertEqual(delta.appDescription, "Emulator")
    }

    // MARK: Refresh and lists

    func testMergingAgainOrRefreshingNeverDuplicates() throws {
        let parsed = try parse(legacy)
        XCTAssertEqual(RepositoryParser.merge(parsed.apps).apps, parsed.apps, "merging is idempotent")
        // A refresh replaces the list; even if both lists were combined, the result is the same apps.
        let combined = RepositoryParser.merge(parsed.apps + parsed.apps)
        XCTAssertEqual(combined.apps.count, parsed.apps.count)
        XCTAssertEqual(combined.apps.map { $0.versions.count }, parsed.apps.map { $0.versions.count })
        XCTAssertEqual(try parse(legacy).apps, parsed.apps, "parsing the same data twice gives the same apps")
    }

    func testEveryListShowsOneRowPerAppPerSource() throws {
        let apps = try parse(legacy).apps
        let repoA = Repository(id: UUID(), url: base, name: "A", apps: apps, dateAdded: Date())
        let repoB = Repository(id: UUID(), url: URL(string: "https://other.example/repo.json")!, name: "B", apps: apps, dateAdded: Date())
        var entries = (repoA.apps.map { SourceEntry(repo: repoA, app: $0) } + repoB.apps.map { SourceEntry(repo: repoB, app: $0) })
        entries += entries   // even if a list were handed the same entries twice
        XCTAssertEqual(Set(apps.map(\.id)).count, apps.count)

        let all = SourceSearch.filter(entries, query: "", sortByName: true)
        XCTAssertEqual(all.count, apps.count * 2, "one row per app per source")
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)

        let instagram = SourceSearch.filter(entries, query: "Instag", sortByName: true)
        XCTAssertEqual(instagram.map(\.repo.name), ["A", "B"], "Instagram once per source")
        XCTAssertTrue(SourceSearch.filter(entries, query: "", sortByName: true, emptyQueryShowsAll: false).isEmpty)
    }

    func testSourceAddressesMatchIgnoringTrailingSlashAndCase() {
        XCTAssertTrue(RepositoryStore.sameSource(URL(string: "https://Repo.example.org/")!, URL(string: "https://repo.example.org")!))
        XCTAssertFalse(RepositoryStore.sameSource(URL(string: "https://a.example/x")!, URL(string: "https://a.example/y")!))
    }
}
