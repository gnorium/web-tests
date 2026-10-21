import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A lexicographic overture's page has what a bibliographic overture's
/// has: an admin's Discard on a working copy, marking it Discarded, with
/// Restore to bring it back; and its locutions thread, whose box
/// posts a locution that the page then shows. A scratch lexicographic
/// figurant and overture of a throwaway admin, removed after.
@Suite("Lexicographic overture discard and thread")
struct LexicographicOvertureDiscardTests {
  @Test(arguments: gnorium.engines)
  func anAdminDiscardsAndRestoresAnOvertureAndPostsALocutionOnIt(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let submission = UUID().uuidString.lowercased()
    let figurant = UUID().uuidString.lowercased()
    let overture = UUID().uuidString.lowercased()
    func remove() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM locutions WHERE locutable_type = 'lexicographic_overture' AND locutable_id = '\(overture)';
        DELETE FROM lexicographic_overtures WHERE id = '\(overture)';
        UPDATE lexicographic_figurants SET discarded_at = now(), discarded_by = '\(admin.username)'
          WHERE id = '\(figurant)' AND discarded_at IS NULL;
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
        INSERT INTO lexicographic_figurants (id, batch_id, language, order_in_batch, processing_status,
          title_form_json, anchors_json, created_at)
          VALUES ('\(figurant)', '\(submission)', 'eng', 0, 'pending', '\(form)', '[]', now());
        INSERT INTO lexicographic_overtures (id, lexicographic_figurant_id, title_form_json, anchors_json, created_at)
          VALUES ('\(overture)', '\(figurant)', '\(form)', '[]', now());
        COMMIT;
        """)
      let page = "/mission-control/overtures/lexicographic/\(overture)"
      try await withPage(engine, gnorium, cookies: [admin.cookie]) { tab in
        let status = tab.locator(".mission-control-object-header-status-chip")
        try await tab.openHydrated(page)
        try await expect(status).toContainText("Pending")
        try await expect(tab.locator("button[form='overture-restore']")).toHaveCount(0)

        // The thread: its opening, and the box that posts to the overture.
        try await expect(tab.locator("[id='creation-\(overture)' i]")).toHaveCount(1)
        try await tab.locator("#locution-thread-locution-body").fill("The class is a verb here.")
        try await tab.locator(".locution-thread-submit").click()
        try await expect(tab.locator(".locution-thread")).toContainText("The class is a verb here.")

        // Discard: to the register, the overture Discarded, the row kept.
        try await tab.locator("button[form='overture-discard']").click()
        try await expect(tab, timeout: .seconds(15)).toHaveURL("/mission-control/overtures/lexicographic")
        try await tab.openHydrated(page)
        try await expect(status).toContainText("Discarded")
        try await expect(tab.locator(".pedigree-view")).toContainText("Discarded")
        try await expect(tab.locator("button[form='overture-discard']")).toHaveCount(0)
        #expect(try TestAdmin.query("SELECT discarded_by FROM lexicographic_overtures WHERE id = '\(overture)';")
          == admin.username)

        try await tab.locator("button[form='overture-restore']").click()
        try await expect(status).toContainText("Pending")
        try await expect(tab.locator("button[form='overture-discard']")).toHaveCount(1)
        #expect(try TestAdmin.query("SELECT coalesce(discarded_by, '') FROM lexicographic_overtures WHERE id = '\(overture)';")
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
