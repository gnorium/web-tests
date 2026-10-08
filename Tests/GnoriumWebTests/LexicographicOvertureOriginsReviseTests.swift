import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A lexicographic overture's Revise page edits its origins as a
/// bibliographic overture's does (user, 2026-10-08): its Origin rows under
/// its identity, the record it files for kept out (`data-origin-own`); one
/// Suggest files them as a revision, whose page shows the origins proposed
/// and whose thread line names Origin among what changed. A scratch
/// lexicographic folksong and overture of a throwaway admin, removed after.
@Suite("Lexicographic overture origins revision", .serialized)
struct LexicographicOvertureOriginsReviseTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aRevisionEditsTheOrigins(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let submission = UUID().uuidString.lowercased()
    let folksong = UUID().uuidString.lowercased()
    let overture = UUID().uuidString.lowercased()
    func remove() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM locutions WHERE locutable_type = 'lexicographic_overture' AND locutable_id = '\(overture)';
        DELETE FROM revisions WHERE revisable_id = '\(overture)';
        DELETE FROM lexicographic_overtures WHERE id = '\(overture)';
        UPDATE lexicographic_folksongs SET deleted_at = now(), deleted_by = '\(admin.username)'
          WHERE id = '\(folksong)' AND deleted_at IS NULL;
        COMMIT;
        """)
    }
    do {
      let user = try admin.column("id")
      let form = #"{"title":"webtestsorigins","languageCode":"eng","class":"noun","spellings":[],"inflections":[],"origin":{"etymons":[],"citations":[],"derivation":""}}"#
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO submissions (id, user_id) VALUES ('\(submission)', '\(user)');
        INSERT INTO lexicographic_folksongs (id, batch_id, language, order_in_batch, processing_status,
          title_form_json, anchors_json, created_at)
          VALUES ('\(folksong)', '\(submission)', 'eng', 0, 'pending', '\(form)', '[]', now());
        INSERT INTO lexicographic_overtures (id, lexicographic_folksong_id, title_form_json, anchors_json, created_at)
          VALUES ('\(overture)', '\(folksong)', '\(form)', '[]', now());
        COMMIT;
        """)
      let page = "/mission-control/overtures/lexicographic/\(overture)"
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { tab in
        try await tab.openHydrated("\(page)/revise")
        try await tab.expectNoErrors()
        try await tab.expectNoHorizontalOverflow()
        let block = tab.locator("[data-revise-form] .origin-field-view")
        try await expect(block).toHaveCount(1)
        let row = block.locator("[data-origin-row='true']").first
        let relation = row.locator(".dropdown-view").first
        try await relation.locator(".dropdown-trigger").click()
        try await relation.locator(".dropdown-option[data-value='inherited_from']").click()
        try await relation.locator(".dropdown-trigger").click()
        try await row.locator("input[name$='-form']").first.fill("webtestsetymon")
        try await tab.locator("button[type='submit']").filter(hasText: "Suggest").click()
        try await expect(tab, timeout: .seconds(15)).toHaveURL("/mission-control/revisions") { url in
          url.path.hasPrefix("/mission-control/revisions")
        }
        let revision = try TestAdmin.query(
          "SELECT id FROM revisions WHERE revisable_id = '\(overture)' ORDER BY created_at DESC LIMIT 1;")
        #expect(!revision.isEmpty, "no revision was filed")
        // The revision's page: the origins proposed.
        try await tab.openHydrated("\(page)/revisions/\(revision)")
        try await tab.expectNoErrors()
        try await tab.expectNoHorizontalOverflow()
        try await expect(tab.locator("main")).toContainText("webtestsetymon")
        // The thread's line names Origin among what changed.
        try await tab.openHydrated(page)
        try await expect(tab.locator(".locution-thread")).toContainText("Origin")
      }
    } catch {
      remove()
      try await admin.remove(after: error)
    }
    remove()
    try await admin.remove()
  }
}
