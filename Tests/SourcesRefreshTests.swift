import XCTest
@testable import CertSigner

@MainActor
final class SourcesRefreshTests: XCTestCase {
    private func waitUntilIdle(_ store: RepositoryStore, timeout: TimeInterval = 45) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !store.refreshing.isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// The original bug: the caller's task (a view's .task / .refreshable) gets cancelled mid-refresh.
    /// The refresh must keep going, load the apps and show no "cancelled" warning.
    func testCancelledCallerDoesNotCancelRefresh() async throws {
        let store = RepositoryStore()
        for repo in store.repositories { store.remove(repo.id) }
        let repo = try await store.add("https://apps.sidestore.io/")
        print("added \(repo.name): \(repo.apps.count) apps")

        let caller = Task { await store.refreshAll() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        caller.cancel()   // like leaving the screen / pull-to-refresh ending
        XCTAssertTrue(store.refreshing.contains(repo.id), "refresh keeps running after the caller is cancelled")

        // A second refresh while one is running reuses it instead of starting / cancelling another.
        let first = store.startRefresh(repo.id)
        let second = store.startRefresh(repo.id)
        XCTAssertTrue(first == second, "same running task is reused")

        await waitUntilIdle(store)
        let refreshed = try XCTUnwrap(store.repository(repo.id))
        print("after refresh: \(refreshed.apps.count) apps, error=\(refreshed.lastError ?? "none"), etag=\(refreshed.etag ?? "none"), lastModified=\(refreshed.lastModified ?? "none")")
        XCTAssertNil(refreshed.lastError)
        XCTAssertFalse(refreshed.apps.isEmpty)
        XCTAssertNotNil(refreshed.lastUpdated)

        // Conditional request: a second refresh may come back 304 and must keep the apps.
        await store.refresh(repo.id)
        let again = try XCTUnwrap(store.repository(repo.id))
        XCTAssertNil(again.lastError)
        XCTAssertEqual(again.apps.count, refreshed.apps.count)
        store.remove(repo.id)
    }

    func testCancellationIsNeverAnErrorAndReasonsAreReadable() {
        XCTAssertTrue(RepositoryStore.isCancellation(URLError(.cancelled)))
        XCTAssertTrue(RepositoryStore.isCancellation(CancellationError()))
        XCTAssertFalse(RepositoryStore.isCancellation(URLError(.timedOut)))
        XCTAssertTrue(RepositoryStore.looksLikeCancellation("cancelled"))
        XCTAssertEqual(RepositoryStore.reason(for: URLError(.notConnectedToInternet)), "You're offline. Check Wi-Fi or mobile data.")
        XCTAssertEqual(RepositoryStore.reason(for: URLError(.timedOut)), "The source didn't respond within 20 seconds.")
        XCTAssertEqual(RepositoryStore.reason(for: RepositoryError.http(404)), "The server answered with HTTP 404.")
        XCTAssertEqual(RepositoryStore.reason(for: RepositoryError.notJSON), "The source didn't return valid JSON.")
    }

    func testCertificateDisplayNames() {
        XCTAssertTrue(Certificate.looksLikeRawID("00008140-001A3C661E01801C62S28G_dev"))
        XCTAssertFalse(Certificate.looksLikeRawID("Personal Dev Cert"))
        XCTAssertFalse(Certificate.looksLikeRawID("WuXu"))
        XCTAssertEqual(Certificate.personName("Apple Development: Jane Doe (ABCDE12345)"), "Jane Doe")
        XCTAssertEqual(Certificate.personName("iPhone Distribution: Acme Inc."), "Acme Inc.")

        var record = CertificateRecord(id: UUID(), nickname: "00008140-001A3C661E01801C62S28G_dev", dateAdded: Date(),
                                       signingCertificate: nil, matchesProfile: nil)
        var cert = Certificate(record: record, profile: nil, hasPassword: true)
        XCTAssertEqual(cert.displayName, "Development certificate")
        XCTAssertEqual(cert.rawIDLine, "00008140-001A3C661E01801C62S28G_dev")
        record.signingCertificate = CertificateSummary(commonName: "Apple Distribution: Acme Inc. (ABCDE12345)",
                                                       organization: nil, organizationalUnit: nil, notBefore: nil, notAfter: nil)
        cert = Certificate(record: record, profile: nil, hasPassword: true)
        XCTAssertEqual(cert.displayName, "Acme Inc.")
        XCTAssertTrue(cert.typeAndExpiry.hasPrefix("Dist"))
        record.nickname = "My Work Cert"
        cert = Certificate(record: record, profile: nil, hasPassword: true)
        XCTAssertEqual(cert.displayName, "My Work Cert")
        XCTAssertNil(cert.rawIDLine)
    }
}
