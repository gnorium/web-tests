import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A person's edited locution pages its instances (user, 2026-10-17): its
/// words before each edit, then as they read now, numbered from 1. The
/// pager ends the reactions row, right after the ⓘ, the latest shown, a
/// size down on a phone; paged back, the earlier words read as they were,
/// and the reaction picker, Reply and Edit are disabled, not hidden: a
/// reaction and a reply are made to the current instance only, which they
/// record. Each Edit is a new instance, an act of the thread, "submitted
/// locution ‹id› instance 1, creating instance 2" (user, 2026-10-18), its
/// instances linked to the locution shown at them.
@Suite("Locution instances", .serialized)
struct LocutionInstancesTests {
  static let words = ["The long s is consistent.", "The long s is consistent through the page.",
    "The long s is consistent through the whole page."]

  @Test(arguments: [BrowserEngine.chrome])
  func anEditedLocutionPagesItsInstances(engine: BrowserEngine) async throws {
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
        DELETE FROM reactions WHERE reactable_id IN (SELECT id FROM locutions WHERE locutable_id = '\(madrigalID)');
        DELETE FROM locution_instances WHERE locution_id IN (SELECT id FROM locutions WHERE locutable_id = '\(madrigalID)');
        DELETE FROM locutions WHERE locutable_id = '\(madrigalID)' AND parent_id IS NOT NULL;
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
                  '\(Self.words[2])', 3, now() - interval '3 minutes');
        INSERT INTO locution_instances (id, locution_id, instance, body, superseded_by, superseded_at)
          VALUES (gen_random_uuid(), '\(locutionID)', 1, '\(Self.words[0])', '\(readerID)', now() - interval '2 minutes'),
                 (gen_random_uuid(), '\(locutionID)', 2, '\(Self.words[1])', '\(readerID)', now() - interval '1 minute');
        COMMIT;
        """)
      let id = locutionID.uppercased()
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [reader.cookie]) { page in
        try await page.openHydrated(scratch.madrigalPath)
        let locution = page.locator("#locution-\(id)")
        let pager = locution.locator(".reactions-controls > .locution-pages-nav")
        try await expect(pager).toHaveCount(1)
        try await expect(pager).toHaveAttribute("data-count", "3")
        try await expect(pager.locator(".page-box")).toHaveValue("3")
        try await expect(pager).toHaveAttribute("aria-label", "Instances")
        // At the row's end, right after the ⓘ, 8 apart (the ⓘ a bare icon).
        #expect(try await pager.evaluate("""
          el => el.previousElementSibling?.classList.contains('reactions-raw-info') === true && !el.nextElementSibling
            && Math.abs(el.getBoundingClientRect().left
              - el.previousElementSibling.querySelector('.reactions-when').getBoundingClientRect().right - 8) <= 1
          """).bool == true, "The pager follows the ⓘ, 8 apart")
        // The latest shown, first in the document.
        let shown = locution.locator(".locution-page:not([hidden]) .locution-body-rendered")
        try await expect(shown).toHaveText(Self.words[2])
        try await expect(locution.locator(".locution-page").first).toHaveAttribute("data-page", "3")
        let picker = locution.locator(".reaction-picker-trigger")
        let replyLink = locution.locator(".locution-reply-button")
        let editLink = locution.locator(".locution-edit-button")
        try await expect(picker).toBeEnabled()

        // Paged back: instance 2's words, as they were; what acts on the
        // locution disabled, still shown.
        try await pager.locator(".pagination-prev").click()
        try await expect(shown).toHaveText(Self.words[1])
        try await expect(pager.locator(".page-box")).toHaveValue("2")
        try await expect(locution.locator(".locution-page").first).toHaveAttribute("data-page", "2")
        try await expect(picker).toBeDisabled()
        try await expect(picker).toBeVisible()
        try await expect(replyLink).toHaveAttribute("aria-disabled", "true")
        try await expect(editLink).toHaveAttribute("aria-disabled", "true")
        try await expect(replyLink).toBeVisible()
        #expect(try await replyLink.evaluate("el => getComputedStyle(el).pointerEvents").string == "none")
        // Its number typed: instance 1.
        try await pager.locator(".page-box").fill("1")
        try await pager.locator(".page-box").press("Enter")
        try await expect(shown).toHaveText(Self.words[0])
        try await expect(pager.locator(".pagination-prev")).toBeDisabled()

        // The thread's acts: each Edit, its instances linked; followed, the
        // locution is paged to it.
        let acts = page.locator(".locution-thread-event-line").filter(hasText: "submitted locution \(id) instance")
        try await expect(acts).toHaveCount(2)
        try await expect(acts.first).toContainText("submitted locution \(id) instance 1, creating instance 2")
        try await expect(acts.nth(1)).toContainText("submitted locution \(id) instance 2, creating instance 3")
        try await acts.nth(1).locator("a[href='#locution-\(id)-instance-3']").click()
        try await expect(shown).toHaveText(Self.words[2])
        try await expect(pager.locator(".page-box")).toHaveValue("3")
        try await expect(picker).toBeEnabled()
        #expect(try await replyLink.evaluate("el => el.hasAttribute('aria-disabled')").bool == false)
        try await acts.first.locator("a[href='#locution-\(id)-instance-1']").click()
        try await expect(shown).toHaveText(Self.words[0])
        try await pager.locator(".pagination-next").click()
        try await pager.locator(".pagination-next").click()
        try await expect(shown).toHaveText(Self.words[2])

        // A reaction, on the current instance, records it.
        try await picker.click()
        try await locution.locator(".reaction-picker-choices form[action$='/👍'] button").click()
        try await expect(locution.locator(".reactions-reaction")).toHaveCount(1)
        #expect(try TestAdmin.query("SELECT instance FROM reactions WHERE reactable_id = '\(locutionID)'") == "3")

        // A reply, to the current instance, records it and quotes its words.
        try await replyLink.click()
        try await expect(page.locator(".locution-thread-replying .locution-quote-text")).toHaveText(Self.words[2])
        try await page.locator("#locution-thread-locution-body").fill("Agreed, on this reading.")
        try await page.locator(".locution-thread-submit").click()
        try await expect(page.locator(".locution-view .locution-quote-text").filter(hasText: Self.words[2]),
          timeout: .seconds(15)).toHaveCount(1)
        #expect(try TestAdmin.query("""
          SELECT parent_instance || '|' || quoted_content FROM locutions WHERE parent_id = '\(locutionID)'
          """) == "3|\(Self.words[2])")
        try await page.expectNoHorizontalOverflow()
      }
      // On a phone the pager steps down a size, as every medium pager does.
      try await withPage(engine, gnorium, viewport: Layout.phone.viewport(for: engine), cookies: [reader.cookie]) { page in
        try await page.openHydrated(scratch.madrigalPath)
        let box = page.locator("#locution-\(id) .locution-pages-nav .page-box")
        try await expect(box).toHaveCSS("font-size", "14px")
        try await page.expectNoHorizontalOverflow()
      }
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
