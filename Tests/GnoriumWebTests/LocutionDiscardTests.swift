import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An admin's Discard of a locution (user, 2026-10-21): a link in the small
/// row under it, beside Reply, Edit and Nullify, wearing the trash; no
/// dialog, since it can be taken back. The public then reads "[discarded]"
/// and is offered nothing on it; its author reads the words with a note that
/// an admin discarded it; an admin reads them with Recover (the archive
/// taken back) in Discard's place. The thread says "‹admin› discarded
/// locution ‹id›" and, once recovered, "‹admin› recovered locution ‹id›".
@Suite("Locution discard", .serialized)
struct LocutionDiscardTests {
  static let words = "The catchword is misread on this page."
  static let note = "An admin discarded this locution; only its author and admins can read it."

  @Test(arguments: [BrowserEngine.chrome])
  func anAdminDiscardsAndRecoversAndEachReaderReadsWhatTheRulesSay(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reader: TestAdmin
    do { reader = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false) } catch { try await admin.remove(after: error) }
    let other: TestAdmin
    do { other = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false) } catch {
      try await reader.remove(); try await admin.remove(after: error)
    }
    let scratch: ScratchCommit
    do { scratch = try ScratchCommit(owner: reader) } catch {
      try await other.remove(); try await reader.remove(); try await admin.remove(after: error)
    }
    let locutionID = UUID().uuidString.lowercased()
    let madrigalID = scratch.madrigalID.lowercased()
    func removeLocutions() {
      _ = try? TestAdmin.query("DELETE FROM locutions WHERE locutable_id = '\(madrigalID)'")
    }
    func removeAll() async throws {
      removeLocutions()
      scratch.remove()
      try await other.remove()
      try await reader.remove()
      try await admin.remove()
    }
    do {
      let readerID = try reader.column("id")
      _ = try TestAdmin.query("""
        INSERT INTO locutions (id, locutable_type, locutable_id, author_id, content, instance_count, created_at)
          VALUES ('\(locutionID)', 'bibliographic_madrigal', '\(madrigalID)', '\(readerID)',
                  '\(Self.words)', 1, now() - interval '2 minutes')
        """)
      let id = locutionID.uppercased()

      // An admin: Discard, beside Nullify, wearing the trash; no dialog.
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated(scratch.madrigalPath)
        let locution = page.locator("#locution-\(id)")
        let discard = locution.locator(".locution-discard")
        try await expect(discard).toHaveText("Discard")
        try await expect(discard.locator(".trash-2-icon-view")).toHaveCount(1)
        try await expect(locution.locator(".locution-recover")).toHaveCount(0)
        try await expect(locution.locator(".locution-nullify")).toHaveCount(1)
        try await discard.click()

        // Discarded: the admin still reads the words, with the note, and
        // Recover stands where Discard stood.
        let body = page.locator("#locution-\(id) .locution-body")
        try await expect(page.locator("#locution-\(id) .locution-recover"), timeout: .seconds(15)).toBeVisible()
        try await expect(body.locator(".locution-body-rendered")).toHaveText(Self.words)
        try await expect(page.locator("#locution-\(id) .locution-discarded-note")).toHaveText(Self.note)
        try await expect(page.locator("#locution-\(id) .locution-discard")).toHaveCount(0)
        let recover = page.locator("#locution-\(id) .locution-recover")
        try await expect(recover).toHaveText("Recover")
        try await expect(recover.locator(".archive-restore-icon-view")).toHaveCount(1)
        let discarding = page.locator(".thread-event-line").filter(hasText: "discarded locution \(id)")
        try await expect(discarding).toHaveCount(1)
        try await expect(discarding).toContainText("\(admin.username) discarded locution \(id)")
        try await page.expectNoErrors()
      }
      #expect(try TestAdmin.query("SELECT discarded_by FROM locutions WHERE id = '\(locutionID)'") == admin.username)
      #expect(try TestAdmin.query("""
        SELECT count(*) FROM event_logs WHERE action = 'discard' AND resource_id = '\(locutionID)'
        """) == "1")

      // Its author: the words and the note; no Edit, Reply or Discard.
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [reader.cookie]) { page in
        try await page.openHydrated(scratch.madrigalPath)
        let locution = page.locator("#locution-\(id)")
        try await expect(locution.locator(".locution-body-rendered")).toHaveText(Self.words)
        try await expect(locution.locator(".locution-discarded-note")).toHaveText(Self.note)
        try await expect(locution.locator(".locution-edit-button")).toHaveCount(0)
        try await expect(locution.locator(".locution-reply-button")).toHaveCount(0)
        try await expect(locution.locator(".locution-discard")).toHaveCount(0)
        try await expect(locution.locator(".locution-recover")).toHaveCount(0)
        try await expect(locution.locator(".locution-nullify")).toHaveCount(1)
      }

      // The public: the placeholder, nothing else, and the act in the thread.
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [other.cookie]) { page in
        try await page.openHydrated(scratch.madrigalPath)
        let locution = page.locator("#locution-\(id)")
        try await expect(locution.locator(".locution-body")).toHaveAttribute("data-withheld", "true")
        try await expect(locution.locator(".locution-body-rendered")).toHaveText("[discarded]")
        try await expect(locution.locator(".locution-discarded-note")).toHaveCount(0)
        try await expect(locution.locator(".locution-reply-button")).toHaveCount(0)
        try await expect(locution.locator(".locution-nullify")).toHaveCount(0)
        try await expect(page.locator(".thread-event-line").filter(hasText: "discarded locution \(id)"))
          .toHaveCount(1)
        let html = try await page.evaluate("document.documentElement.outerHTML").string ?? ""
        #expect(!html.contains(Self.words), "the words never reach the public page")
      }

      // Recover: it stands again, and the thread says so.
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated(scratch.madrigalPath)
        try await page.locator("#locution-\(id) .locution-recover").click()
        try await expect(page.locator("#locution-\(id) .locution-discard"), timeout: .seconds(15)).toBeVisible()
        try await expect(page.locator("#locution-\(id) .locution-discarded-note")).toHaveCount(0)
        let recovering = page.locator(".thread-event-line").filter(hasText: "recovered locution \(id)")
        try await expect(recovering).toHaveCount(1)
        try await expect(recovering).toContainText("\(admin.username) recovered locution \(id)")
        try await page.expectNoErrors()
      }
      #expect(try TestAdmin.query("SELECT coalesce(discarded_by, '') FROM locutions WHERE id = '\(locutionID)'") == "")
      #expect(try TestAdmin.query("""
        SELECT count(*) FROM event_logs WHERE action = 'recover' AND resource_id = '\(locutionID)'
        """) == "1")
    } catch {
      removeLocutions()
      scratch.remove()
      try await other.remove()
      try await reader.remove()
      try await admin.remove(after: error)
    }
    try await removeAll()
  }
}
