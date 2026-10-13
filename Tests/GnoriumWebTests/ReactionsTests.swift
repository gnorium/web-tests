import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A locution's reactions (user, 2026-10-12): their own row of pills under
/// the controls, each counted by the thread, the reader's own pill held
/// pressed; a count opens who reacted, a table in a dialog loaded into the
/// page—a second pass of the page's hydration, which leaves every ⓘ and
/// its time as they were.
@Suite("Reactions", .serialized)
struct ReactionsTests {
  @Test(arguments: [BrowserEngine.chrome])
  func aCountOpensWhoReactedAndTheSecondPassLeavesTheTimes(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let reader = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let other: TestAdmin
    do { other = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false) }
    catch { try await reader.remove(after: error) }
    let scratch: ScratchCommit
    do { scratch = try ScratchCommit(owner: reader) }
    catch {
      try? await other.remove()
      try await reader.remove(after: error)
    }
    let locutionID = UUID().uuidString.lowercased()
    func removeLocution() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM reactions WHERE reactable_id = '\(locutionID)';
        DELETE FROM locutions WHERE id = '\(locutionID)';
        COMMIT;
        """)
    }
    do {
      let readerID = try reader.column("id")
      let otherID = try other.column("id")
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO locutions (id, locutable_type, locutable_id, author_id, content, created_at)
          VALUES ('\(locutionID)', 'bibliographic_madrigal', '\(scratch.madrigalID.lowercased())', '\(readerID)',
                  'The long s is consistent through the page.', now());
        INSERT INTO reactions (id, reactable_type, reactable_id, author_id, emoji, created_at)
          VALUES (gen_random_uuid(), 'locution', '\(locutionID)', '\(readerID)', '👍', now() - interval '2 hours'),
                 (gen_random_uuid(), 'locution', '\(locutionID)', '\(otherID)', '👍', now() - interval '1 hour'),
                 (gen_random_uuid(), 'locution', '\(locutionID)', '\(otherID)', '🎉', now());
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [reader.cookie]) { page in
        try await page.openHydrated(scratch.madrigalPath)
        let locution = page.locator("#locution-\(locutionID.uppercased())")
        try await expect(locution).toBeAttached()
        // Counted by the thread: two 👍, the reader's among them, one 🎉.
        let thumbs = locution.locator(".reactions-reaction").nth(0)
        try await expect(thumbs).toHaveAttribute("data-reacted", "true")
        try await expect(thumbs.locator(".reactions-count")).toHaveText("2")
        try await expect(locution.locator(".reactions-reaction").nth(1)).toHaveAttribute("data-reacted", "false")
        // The controls on their own row, the pills on the next.
        let rows = try await locution.evaluate(
          """
          (el) => {
            const chips = el.querySelector('.reactions-chips').getBoundingClientRect();
            const controls = el.querySelector('.reactions-controls').getBoundingClientRect();
            return chips.top >= controls.bottom - 1;
          }
          """)
        #expect(rows == .bool(true), "The pills under the controls")
        let icons = "[...document.querySelectorAll('.reactions-when')].every(w => w.querySelector('svg'))"
        #expect(try await page.evaluate(icons, as: Bool.self), "Every ⓘ holds its icon")

        // The count opens who reacted: newest first, the reader last.
        let count = thumbs.locator(".reactions-count-button")
        try await expect(count).toHaveAttribute("aria-label", "See who reacted with 👍 (2)")
        try await count.click()
        let dialog = page.locator(".reactions-reactors-dialog.dialog-view[data-open='true']")
        try await expect(dialog).toBeAttached()
        try await expect(dialog.locator(".modal-dialog-title .reactions-emoji")).toHaveText("👍")
        let table = dialog.locator(".reactors-view .table-tbody tr")
        try await expect(table).toHaveCount(2)
        try await expect(table.nth(0)).toContainText(other.username)
        try await expect(table.nth(1)).toContainText(reader.username)

        // Loading it ran the page's time hydration again: every ⓘ keeps its
        // icon, and its bubble still holds when, in the reader's clock.
        #expect(try await page.evaluate(icons, as: Bool.self), "A second pass leaves every ⓘ its icon")
        let stamps = try await page.evaluate(
          """
          [...document.querySelectorAll('[data-local-time-iso]')].every(w => w.dataset.localTimeWritten === w.dataset.localTimeIso)
          """, as: Bool.self)
        #expect(stamps, "Each stamp written once, in the reader's clock")

        // Filtering loads into the dialog, never the page.
        let address = try await page.evaluate("location.href", as: String.self)
        let field = dialog.locator(".filter-bar-view input[type='text']").first
        try await field.fill(other.username)
        try await field.press("Enter")
        try await expect(table).toHaveCount(1)
        #expect(try await page.evaluate("location.href", as: String.self) == address)

        // Escape closes it, and the focus is back on the count.
        try await page.keyboard.press("Escape")
        try await expect(dialog).toHaveCount(0)
        #expect(try await page.evaluate(
          "document.activeElement.classList.contains('reactions-count-button')", as: Bool.self))
        try await page.expectNoErrors()
      }
    } catch {
      removeLocution()
      scratch.remove()
      try? await other.remove()
      try await reader.remove(after: error)
    }
    removeLocution()
    scratch.remove()
    try await other.remove()
    try await reader.remove()
  }
}
