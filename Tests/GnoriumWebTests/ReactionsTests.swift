import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A locution's reactions (user, 2026-10-12, 2026-10-15): one row under
/// the controls, the pills most reacted first and the picker at its end;
/// each pill one chip hugging its emoji and count, the reader's own held
/// pressed, naming who reacted when hovered; a count opens who reacted, a
/// table in a dialog loaded into the page—a second pass of the page's
/// hydration, which leaves every ⓘ and its time as they were.
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
          VALUES (gen_random_uuid(), 'locution', '\(locutionID)', '\(readerID)', '🎉', now() - interval '2 hours'),
                 (gen_random_uuid(), 'locution', '\(locutionID)', '\(otherID)', '🎉', now() - interval '1 hour'),
                 (gen_random_uuid(), 'locution', '\(locutionID)', '\(otherID)', '👍', now());
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [reader.cookie]) { page in
        try await page.openHydrated(scratch.madrigalPath)
        let locution = page.locator("#locution-\(locutionID.uppercased())")
        try await expect(locution).toBeAttached()
        // Reactions are only on locutions: the thread's acts—here the
        // madrigal's creation—carry no picker and no pills.
        let creation = page.locator("#creation-\(scratch.madrigalID.uppercased())")
        try await expect(creation).toBeAttached()
        try await expect(creation.locator(".reaction-picker-trigger")).toHaveCount(0)
        try await expect(creation.locator(".reactions-reaction")).toHaveCount(0)
        try await expect(locution.locator(".reaction-picker-trigger")).toHaveCount(1)
        // Counted by the thread, most reacted first—two 🎉, the reader's
        // among them, before one 👍, though the picker lists 👍 first.
        let party = locution.locator(".reactions-reaction").nth(0)
        let thumbs = locution.locator(".reactions-reaction").nth(1)
        try await expect(party.locator(".reactions-emoji")).toHaveText("🎉")
        try await expect(party).toHaveAttribute("data-reacted", "true")
        try await expect(party.locator(".reactions-count")).toHaveText("2")
        try await expect(thumbs.locator(".reactions-emoji")).toHaveText("👍")
        try await expect(thumbs).toHaveAttribute("data-reacted", "false")
        // One row (user, 2026-10-15): the pills, the picker that ends them,
        // then the controls at the row's end, all on one line.
        let layout = try await locution.evaluate(
          """
          (el) => {
            const row = el.querySelector('.reactions-row');
            const pills = [...row.querySelectorAll('.reactions-reaction')].map(p => p.getBoundingClientRect());
            const picker = row.querySelector('.reaction-picker-trigger').getBoundingClientRect();
            const controls = row.querySelector('.reactions-controls').getBoundingClientRect();
            const last = pills[pills.length - 1], middle = picker.top + picker.height / 2;
            return [
              picker.right <= controls.left,
              !el.querySelector('.reactions-controls .reaction-picker-trigger'),
              picker.left >= last.right,
              middle > last.top && middle < last.bottom,
              middle > controls.top && middle < controls.bottom,
            ].join(' ');
          }
          """)
        #expect(layout == .string("true true true true true"), "Pills, the picker, then the controls, one row: \(layout)")
        // One chip: emoji and count in one button, the picker's height, and
        // no form: a pill never toggles.
        let chip = try await party.evaluate(
          """
          (el) => {
            const buttons = el.querySelectorAll('button');
            const trigger = el.closest('.reactions-row').querySelector('.reaction-picker-trigger');
            return [buttons.length, !el.querySelector('form'), !!buttons[0].querySelector('.reactions-emoji'),
              !!buttons[0].querySelector('.reactions-count'),
              Math.abs(buttons[0].getBoundingClientRect().height - trigger.getBoundingClientRect().height) < 0.5].join(' ');
          }
          """)
        #expect(chip == .string("1 true true true true"), "One chip: \(chip)")
        // Each pill hugs what it holds: a longer count, a wider pill, and
        // the other pill as it was.
        let hugs = try await locution.evaluate(
          """
          (el) => {
            const [a, b] = el.querySelectorAll('.reactions-reaction');
            const before = [a.getBoundingClientRect().width, b.getBoundingClientRect().width];
            const count = a.querySelector('.reactions-count'), text = count.textContent;
            count.textContent = '120K';
            const after = [a.getBoundingClientRect().width, b.getBoundingClientRect().width];
            count.textContent = text;
            return Math.abs(before[0] - before[1]) < 1 && after[0] > after[1] + 8 && Math.abs(after[1] - before[1]) < 0.5
              && !el.querySelector('[data-count-width]');
          }
          """)
        #expect(hugs == .bool(true), "Each pill as wide as its own content")

        // Hovered, a pill names who reacted, first as the dialog lists them.
        let bubble = page.locator(".tooltip-view[data-portal='true'][data-visible='true'] .tooltip-content")
        try await party.locator(".reactions-count-button").hover()
        try await expect(bubble).toHaveText("\(other.username) and \(reader.username)")
        try await thumbs.locator(".reactions-count-button").hover()
        try await expect(bubble).toHaveText(other.username)
        try await page.mouse.move(x: 0, y: 0)
        try await expect(bubble).toHaveCount(0)

        // A pill pressed anywhere, its emoji too, opens who reacted; it
        // toggles nothing (user, 2026-10-15).
        let openDialog = page.locator(".reactions-reactors-dialog.dialog-view:modal")
        try await thumbs.locator(".reactions-emoji").click()
        try await expect(openDialog).toBeAttached()
        try await page.keyboard.press("Escape")
        try await expect(openDialog).toHaveCount(0)
        try await expect(thumbs).toHaveAttribute("data-reacted", "false")
        try await expect(thumbs.locator(".reactions-count")).toHaveText("1")

        // Reacting is the picker's, the reader's own selected in it. A
        // choice redraws the pills in place from the server, sorted and
        // named anew, the picker still at the row's end; the old pills'
        // bubbles go with them.
        let trigger = locution.locator(".reaction-picker-trigger")
        let choice = { (emoji: String) in locution.locator(".reaction-picker-choices form[action$='/\(emoji)'] button") }
        try await trigger.click()
        try await expect(choice("🎉")).toHaveAttribute("aria-pressed", "true")
        try await expect(choice("👍")).toHaveAttribute("aria-pressed", "false")
        try await choice("👍").click()
        try await expect(thumbs).toHaveAttribute("data-reacted", "true")
        try await expect(thumbs.locator(".reactions-count")).toHaveText("2")
        // A tie at two: 🎉, reacted with first, stays first.
        try await expect(party.locator(".reactions-emoji")).toHaveText("🎉")
        try await expect(locution.locator(".reactions-row > .reaction-picker-view .reaction-picker-trigger"))
          .toHaveCount(1)
        try await page.mouse.move(x: 0, y: 0)
        try await expect(bubble).toHaveCount(0)
        try await thumbs.locator(".reactions-count-button").hover()
        try await expect(bubble).toHaveText("\(reader.username) and \(other.username)")
        try await trigger.click()
        try await expect(choice("👍")).toHaveAttribute("aria-pressed", "true")
        try await choice("👍").click()
        try await expect(thumbs).toHaveAttribute("data-reacted", "false")
        try await expect(thumbs.locator(".reactions-count")).toHaveText("1")
        try await page.mouse.move(x: 0, y: 0)
        let icons = "[...document.querySelectorAll('.reactions-when')].every(w => w.querySelector('svg'))"
        #expect(try await page.evaluate(icons, as: Bool.self), "Every ⓘ holds its icon")

        // The count opens who reacted: newest first, the reader last.
        let count = party.locator(".reactions-count-button")
        try await expect(count).toHaveAttribute("aria-label", "2 reactions: 🎉, show who reacted")
        try await count.click()
        let dialog = page.locator(".reactions-reactors-dialog.dialog-view:modal")
        try await expect(dialog).toBeAttached()
        try await expect(dialog.locator(".modal-dialog-title .reactions-emoji")).toHaveText("🎉")
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

        // The picker's framed box is a medium button's height, border
        // included—40, small's 32 under the phone step at 320—as the pills
        // and the picker trigger are (user, 2026-10-15).
        let picker = locution.locator(".reaction-picker-choices")
        let frame = """
          (() => { const el = document.querySelector('#locution-\(locutionID.uppercased())');
            return [el.querySelector('.reaction-picker-choices').getBoundingClientRect().height,
              el.querySelector('.reactions-reaction button').getBoundingClientRect().height
                - el.querySelector('.reaction-picker-trigger').getBoundingClientRect().height]; })()
          """
        try await locution.locator(".reaction-picker-trigger").click()
        try await expect(locution.locator(".reaction-picker-choices.reaction-picker-settled")).toBeVisible()
        #expect(try await page.evaluate(frame, as: [Double].self) == [40, 0])
        try await page.setViewport(width: 320, height: 812)
        #expect(try await page.evaluate(frame, as: [Double].self) == [32, 0])
        try await page.keyboard.press("Escape")
        try await expect(picker).toBeHidden()
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
