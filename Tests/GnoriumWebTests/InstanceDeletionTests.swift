import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An admin deletes a pending instance and restores it (user, 2026-10-07):
/// Delete on its page discards its overture with it and marks it Deleted,
/// the instances register drops it unless the State filter asks for the
/// deleted, and Restore brings both back. A scratch lexicographic instance
/// and overture of a throwaway admin, removed after.
@Suite("Instance deletion")
struct InstanceDeletionTests {
  @Test(arguments: gnorium.engines)
  func anAdminDeletesAndRestoresAPendingInstance(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let submission = UUID().uuidString.lowercased()
    let instance = UUID().uuidString.lowercased()
    let overture = UUID().uuidString.lowercased()
    func remove() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM lexicographic_overtures WHERE id = '\(overture)';
        UPDATE lexicographic_instances SET deleted_at = now(), deleted_by = '\(admin.username)'
          WHERE id = '\(instance)' AND deleted_at IS NULL;
        COMMIT;
        """)
    }
    do {
      let user = try admin.column("id")
      let form = #"{"title":"webtestsdeletion","languageCode":"eng","type":"noun"}"#
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO submissions (id, user_id) VALUES ('\(submission)', '\(user)');
        INSERT INTO lexicographic_instances (id, batch_id, language, order_in_batch, processing_status,
          title_form_json, anchors_json, created_at)
          VALUES ('\(instance)', '\(submission)', 'eng', 0, 'pending', '\(form)', '[]', now());
        INSERT INTO lexicographic_overtures (id, lexicographic_instance_id, title_form_json, anchors_json, created_at)
          VALUES ('\(overture)', '\(instance)', '\(form)', '[]', now());
        COMMIT;
        """)
      let page = "/mission-control/instances/lexicographic/\(instance)"
      let register = "/mission-control/instances/lexicographic"
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
        try await expect(tab.locator("a[href='\(page)']")).toHaveCount(0)
        try await tab.openHydrated(register + "&state=deleted")
        try await expect(tab.locator("a[href='\(page)']").first).toBeVisible()

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
