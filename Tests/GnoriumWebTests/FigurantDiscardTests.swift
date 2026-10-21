import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An admin discards a pending figurant and restores it (user, 2026-10-07):
/// Discard on its page discards its overture with it and marks it Discarded,
/// the figurants register drops it unless the State filter asks for the
/// discarded, and Restore brings both back. A scratch lexicographic figurant
/// and overture of a throwaway admin, removed after.
@Suite("Figurant discard")
struct FigurantDiscardTests {
  @Test(arguments: gnorium.engines)
  func anAdminDiscardsAndRestoresAPendingFigurant(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let submission = UUID().uuidString.lowercased()
    let figurant = UUID().uuidString.lowercased()
    let overture = UUID().uuidString.lowercased()
    func remove() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM lexicographic_overtures WHERE id = '\(overture)';
        UPDATE lexicographic_figurants SET discarded_at = now(), discarded_by = '\(admin.username)'
          WHERE id = '\(figurant)' AND discarded_at IS NULL;
        COMMIT;
        """)
    }
    do {
      let user = try admin.column("id")
      // A whole title form, as Submit Sentiment writes one (ScratchWord):
      // the figurant page reads it.
      let form = #"{"title":"webtestsdiscard","languageCode":"eng","class":"noun","spellings":[],"inflections":[],"origin":{"etymons":[],"citations":[],"derivation":""}}"#
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
      let page = "/mission-control/figurants/lexicographic/\(figurant)"
      let register = "/mission-control/figurants/lexicographic"
      try await withPage(engine, gnorium, cookies: [admin.cookie]) { tab in
        let status = tab.locator(".mission-control-object-header-status-chip")
        try await tab.openHydrated(page)
        try await expect(status).toContainText("Submitted")
        try await expect(tab.locator("button[form='object-restore']")).toHaveCount(0)
        try await tab.locator("button[form='object-discard']").click()
        try await expect(status).toContainText("Discarded")
        try await expect(tab.locator(".pedigree-view")).toContainText("Discarded")
        #expect(try TestAdmin.query("SELECT discarded_by FROM lexicographic_overtures WHERE id = '\(overture)';")
          == admin.username)

        // Gone from the register; there with the State filter.
        try await tab.openHydrated(register)
        // The register spells ids in capitals; the match ignores case.
        try await expect(tab.locator("a[href='\(page)' i]")).toHaveCount(0)
        try await tab.openHydrated(register + "?status=discarded")
        try await expect(tab.locator("a[href='\(page)' i]").first).toBeVisible()

        try await tab.openHydrated(page)
        try await tab.locator("button[form='object-restore']").click()
        try await expect(status).toContainText("Submitted")
        try await expect(tab.locator("button[form='object-discard']")).toHaveCount(1)
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
