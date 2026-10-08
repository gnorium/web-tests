import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An admin deletes a pending folksong and restores it (user, 2026-10-07):
/// Delete on its page discards its overture with it and marks it Deleted,
/// the folksongs register drops it unless the State filter asks for the
/// deleted, and Restore brings both back. A scratch lexicographic folksong
/// and overture of a throwaway admin, removed after.
@Suite("Folksong deletion")
struct FolksongDeletionTests {
  @Test(arguments: gnorium.engines)
  func anAdminDeletesAndRestoresAPendingFolksong(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let submission = UUID().uuidString.lowercased()
    let folksong = UUID().uuidString.lowercased()
    let overture = UUID().uuidString.lowercased()
    func remove() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM lexicographic_overtures WHERE id = '\(overture)';
        UPDATE lexicographic_folksongs SET deleted_at = now(), deleted_by = '\(admin.username)'
          WHERE id = '\(folksong)' AND deleted_at IS NULL;
        COMMIT;
        """)
    }
    do {
      let user = try admin.column("id")
      // A whole title form, as Submit Sentiment writes one (ScratchWord):
      // the folksong page reads it.
      let form = #"{"title":"webtestsdeletion","languageCode":"eng","class":"noun","spellings":[],"inflections":[],"origin":{"etymons":[],"citations":[],"derivation":""}}"#
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
      let page = "/mission-control/folksongs/lexicographic/\(folksong)"
      let register = "/mission-control/folksongs/lexicographic"
      try await withPage(engine, gnorium, cookies: [admin.cookie]) { tab in
        let status = tab.locator(".mission-control-object-header-status-chip")
        try await tab.openHydrated(page)
        try await expect(status).toContainText("Submitted")
        try await expect(tab.locator("button[form='deletion-restore']")).toHaveCount(0)
        try await tab.locator("button[form='deletion-delete']").click()
        try await expect(status).toContainText("Deleted")
        try await expect(tab.locator(".pedigree-view")).toContainText("Deleted")
        #expect(try TestAdmin.query("SELECT deleted_by FROM lexicographic_overtures WHERE id = '\(overture)';")
          == admin.username)

        // Gone from the register; there with the State filter.
        try await tab.openHydrated(register)
        // The register spells ids in capitals; the match ignores case.
        try await expect(tab.locator("a[href='\(page)' i]")).toHaveCount(0)
        try await tab.openHydrated(register + "?status=deleted")
        try await expect(tab.locator("a[href='\(page)' i]").first).toBeVisible()

        try await tab.openHydrated(page)
        try await tab.locator("button[form='deletion-restore']").click()
        try await expect(status).toContainText("Submitted")
        try await expect(tab.locator("button[form='deletion-delete']")).toHaveCount(1)
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
