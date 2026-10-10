import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An object's thread is its own (user, 2026-10-10): the act that created
/// it, each commit of it, and the locutions written on it—never an earlier
/// version's acts or locutions, though they share an argument; its pedigree
/// shows those. The count counts what it shows.
@Suite("Locution thread scope", .serialized)
struct LocutionThreadScopeTests {
  @Test(arguments: [BrowserEngine.chrome])
  func aMadrigalsThreadShowsOnlyItsOwnActsAndLocutions(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let scratch: ScratchCommit
    do { scratch = try ScratchCommit(owner: contributor) }
    catch { try await contributor.remove(after: error) }
    let antiphonID = UUID().uuidString.lowercased()
    let laterID = UUID().uuidString.lowercased()
    let earlierLocutionID = UUID().uuidString.lowercased()
    let laterLocutionID = UUID().uuidString.lowercased()
    func removeLater() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM locutions WHERE id IN ('\(earlierLocutionID)', '\(laterLocutionID)');
        DELETE FROM bibliographic_madrigals WHERE id = '\(laterID)';
        DELETE FROM bibliographic_antiphons WHERE id = '\(antiphonID)';
        COMMIT;
        """)
    }
    do {
      let user = try contributor.column("id")
      // The scratch madrigal committed into an antiphon, submitted as a
      // later version in its argument.
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, resemblance_service_ids_json, processing_status, created_at, updated_at)
          VALUES ('\(antiphonID)', '\(scratch.madrigalID)', '\(user)', '[]', 'submitted', now(), now());
        INSERT INTO bibliographic_madrigals (id, thread_id, bibliographic_antiphon_id, proposed_content_json, metadata_json, processing_status, created_at, updated_at)
          VALUES ('\(laterID)', '\(scratch.madrigalID)', '\(antiphonID)', '{"teiXml":""}', '{"language":"eng","sourceUrl":"\(ScratchCommit.sourceURL)","sourceKind":"iiif-manifest"}', 'pending', now(), now());
        INSERT INTO locutions (id, locutable_type, locutable_id, author_id, content, created_at)
          VALUES ('\(earlierLocutionID)', 'bibliographic_madrigal', '\(scratch.madrigalID.lowercased())', '\(user)', 'On the earlier reading.', now()),
                 ('\(laterLocutionID)', 'bibliographic_madrigal', '\(laterID)', '\(user)', 'On the later reading.', now());
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        // The later version: its creation and its own locution alone.
        try await page.openHydrated("/mission-control/madrigals/bibliographic/\(laterID)")
        let events = page.locator(".locution-thread-event")
        try await expect(events).toHaveCount(1)
        try await expect(page.locator("#creation-\(laterID.uppercased())")).toHaveCount(1)
        try await expect(page.locator("#locution-\(laterLocutionID.uppercased())")).toHaveCount(1)
        try await expect(page.locator("#locution-\(earlierLocutionID.uppercased())")).toHaveCount(0)
        try await expect(page.locator(".locution-thread-count")).toHaveText("2")

        // The earlier one: its creation and its commit, never the later's.
        try await page.openHydrated(scratch.madrigalPath)
        try await expect(events).toHaveCount(2)
        try await expect(page.locator("#creation-\(scratch.madrigalID.uppercased())")).toHaveCount(1)
        try await expect(page.locator("#creation-\(antiphonID.uppercased())")).toHaveCount(1)
        try await expect(page.locator("#creation-\(laterID.uppercased())")).toHaveCount(0)
        try await expect(page.locator("#locution-\(earlierLocutionID.uppercased())")).toHaveCount(1)
        try await expect(page.locator("#locution-\(laterLocutionID.uppercased())")).toHaveCount(0)
        try await expect(page.locator(".locution-thread-count")).toHaveText("3")
        try await page.expectNoErrors()
      }
    } catch {
      removeLater()
      scratch.remove()
      try await contributor.remove(after: error)
    }
    removeLater()
    scratch.remove()
    try await contributor.remove()
  }
}
