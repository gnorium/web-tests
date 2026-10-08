import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A lexicographic overture's page has what a bibliographic overture's
/// has: an admin's Delete on a working copy, marking it Deleted, with
/// Restore to bring it back; and its interventions thread, whose box
/// posts an intervention that the page then shows. A scratch lexicographic
/// folksong and overture of a throwaway admin, removed after.
@Suite("Lexicographic overture deletion and thread")
struct LexicographicOvertureDeletionTests {
  @Test(arguments: gnorium.engines)
  func anAdminDeletesAndRestoresAnOvertureAndIntervenesOnIt(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let submission = UUID().uuidString.lowercased()
    let folksong = UUID().uuidString.lowercased()
    let overture = UUID().uuidString.lowercased()
    func remove() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM interventions WHERE intervenable_type = 'lexicographicOverture' AND intervenable_id = '\(overture)';
        DELETE FROM lexicographic_overtures WHERE id = '\(overture)';
        UPDATE lexicographic_folksongs SET deleted_at = now(), deleted_by = '\(admin.username)'
          WHERE id = '\(folksong)' AND deleted_at IS NULL;
        COMMIT;
        """)
    }
    do {
      let user = try admin.column("id")
      let form = #"{"title":"webtestsoverture","languageCode":"eng","class":"noun","spellings":[],"inflections":[],"origin":{"etymons":[],"citations":[],"derivation":""}}"#
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
      try await withPage(engine, gnorium, cookies: [admin.cookie]) { tab in
        let status = tab.locator(".mission-control-object-header-status-chip")
        try await tab.openHydrated(page)
        try await expect(status).toContainText("Pending")
        try await expect(tab.locator("button[form='overture-restore']")).toHaveCount(0)

        // The thread: its opening, and the box that posts to the overture.
        try await expect(tab.locator("#creation-\(overture)")).toHaveCount(1)
        try await tab.locator("#intervention-thread-intervention-body").fill("The class is a verb here.")
        try await tab.locator(".intervention-thread-submit").click()
        try await expect(tab.locator(".intervention-thread")).toContainText("The class is a verb here.")

        // Delete: to the register, the overture Deleted, the row kept.
        try await tab.locator("button[form='overture-delete']").click()
        try await expect(tab, timeout: .seconds(15)).toHaveURL("/mission-control/overtures/lexicographic")
        try await tab.openHydrated(page)
        try await expect(status).toContainText("Deleted")
        try await expect(tab.locator(".pedigree-view")).toContainText("Deleted")
        try await expect(tab.locator("button[form='overture-delete']")).toHaveCount(0)
        #expect(try TestAdmin.query("SELECT deleted_by FROM lexicographic_overtures WHERE id = '\(overture)';")
          == admin.username)

        try await tab.locator("button[form='overture-restore']").click()
        try await expect(status).toContainText("Pending")
        try await expect(tab.locator("button[form='overture-delete']")).toHaveCount(1)
        #expect(try TestAdmin.query("SELECT coalesce(deleted_by, '') FROM lexicographic_overtures WHERE id = '\(overture)';")
          == "")
      }
    } catch {
      remove()
      try await admin.remove(after: error)
    }
    remove()
    try await admin.remove()
  }
}
