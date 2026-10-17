import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A locution is retracted, never deleted (user, 2026-10-18). Its Retract
/// asks first in a dialog with no title: one sentence, Cancel and a red
/// solid Retract. Cancelled, nothing changes; confirmed, its words and every
/// earlier instance's are erased, its rows and numbers stay, it reads
/// "[retracted]", and the thread says so—"‹user› retracted locution ‹id›"—
/// beside its Edit's act, "submitted locution ‹id› instance 1, creating
/// instance 2".
@Suite("Locution retraction", .serialized)
struct LocutionRetractTests {
  static let sentence =
    "Retracting deletes this locution's content and every earlier instance of it, which can't be undone."
  static let words = ["The catchword is misread.", "The catchword is misread on this page."]

  @Test(arguments: [BrowserEngine.chrome])
  func retractAsksFirstThenErasesTheWordsAndKeepsTheActs(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let reader = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let scratch: ScratchCommit
    do { scratch = try ScratchCommit(owner: reader) } catch { try await reader.remove(after: error) }
    let locutionID = UUID().uuidString.lowercased()
    let madrigalID = scratch.madrigalID.lowercased()
    func removeLocutions() {
      _ = try? TestAdmin.query("""
        BEGIN;
        DELETE FROM locution_instances WHERE locution_id IN (SELECT id FROM locutions WHERE locutable_id = '\(madrigalID)');
        DELETE FROM locutions WHERE locutable_id = '\(madrigalID)';
        COMMIT;
        """)
    }
    do {
      let readerID = try reader.column("id")
      _ = try TestAdmin.query("""
        BEGIN;
        INSERT INTO locutions (id, locutable_type, locutable_id, author_id, content, instance_count, created_at)
          VALUES ('\(locutionID)', 'bibliographic_madrigal', '\(madrigalID)', '\(readerID)',
                  '\(Self.words[1])', 2, now() - interval '2 minutes');
        INSERT INTO locution_instances (id, locution_id, instance, body, superseded_by, superseded_at)
          VALUES (gen_random_uuid(), '\(locutionID)', 1, '\(Self.words[0])', '\(readerID)', now() - interval '1 minute');
        COMMIT;
        """)
      let id = locutionID.uppercased()
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [reader.cookie]) { page in
        try await page.openHydrated(scratch.madrigalPath)
        let locution = page.locator("#locution-\(id)")
        let retract = locution.locator(".locution-retract")
        let dialog = locution.locator(".locution-retract-dialog")
        try await expect(retract).toHaveText("Retract")
        try await expect(dialog).toBeHidden()

        // Asked: no title, the one sentence, Cancel and a red solid Retract.
        try await retract.click()
        try await expect(dialog).toBeVisible()
        try await expect(dialog.locator(".dialog-header")).toHaveCount(0)
        try await expect(dialog.locator(".dialog-body")).toHaveText(Self.sentence)
        let cancel = dialog.locator(".dialog-default-button button")
        let confirm = dialog.locator(".dialog-primary-button button")
        try await expect(dialog.locator(".dialog-footer-actions button")).toHaveCount(2)
        try await expect(cancel).toHaveText("Cancel")
        try await expect(confirm).toHaveText("Retract")
        try await expect(confirm).toHaveAttribute("data-color", "red")
        try await expect(confirm).toHaveAttribute("data-weight", "solid")

        // Cancelled: nothing retracted.
        try await cancel.click()
        try await expect(dialog).toBeHidden()
        #expect(try TestAdmin.query("SELECT (retracted_at IS NULL)::text FROM locutions WHERE id = '\(locutionID)'") == "true")
        try await expect(locution.locator(".locution-page:not([hidden]) .locution-body-rendered")).toHaveText(Self.words[1])

        // Confirmed: retracted, as it now reads.
        try await retract.click()
        try await expect(dialog).toBeVisible()
        try await confirm.click()
        let body = page.locator("#locution-\(id) .locution-body")
        try await expect(body, timeout: .seconds(15)).toHaveAttribute("data-retracted", "true")
        try await expect(body.locator(".locution-body-rendered")).toHaveText("[retracted]")
        try await expect(page.locator("#locution-\(id) .locution-retract")).toHaveCount(0)
        try await expect(page.locator("#locution-\(id) .locution-pages-nav")).toHaveCount(0)

        // The acts stay: its Edit's, a new instance, and its retraction.
        let acts = page.locator(".locution-thread-event-line")
        try await expect(acts.filter(hasText: "submitted locution \(id) instance 1, creating instance 2"))
          .toHaveCount(1)
        let retraction = acts.filter(hasText: "retracted locution \(id)")
        try await expect(retraction).toHaveCount(1)
        try await expect(retraction).toContainText("\(reader.username) retracted locution \(id)")
        try await page.expectNoErrors()
      }

      // Its words and its earlier instance's erased; its rows, its numbers
      // and the logged act kept.
      #expect(try TestAdmin.query("""
        SELECT l.content || '|' || l.instance_count || '|' || count(i.id) || '|' || coalesce(string_agg(i.body, ','), '')
        FROM locutions l LEFT JOIN locution_instances i ON i.locution_id = l.id
        WHERE l.id = '\(locutionID)' GROUP BY l.id
        """) == "|2|1|")
      #expect(try TestAdmin.query("""
        SELECT count(*) FROM event_logs WHERE action = 'retract' AND resource_id = '\(locutionID)' AND user_id = '\(readerID)'
        """) == "1")
    } catch {
      removeLocutions()
      scratch.remove()
      try await reader.remove(after: error)
    }
    removeLocutions()
    scratch.remove()
    try await reader.remove()
  }
}
