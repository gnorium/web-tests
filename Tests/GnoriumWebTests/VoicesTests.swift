import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Submit Testament's voices: a person a row ("Voice", "+ Add voice") under
/// no heading (the row labels say what they are), each with a role (Author, Translator,
/// Compiler: an editor is the edition's), a row added starting as an author;
/// the form posts each row's role and name; the form's own Biblio-record
/// comes first. A translation is an Origin row, not a box and a chain.
/// Nothing is submitted (the submit event is dispatched by hand, which runs
/// the form's script but never posts). A throwaway admin owns a scratch
/// work, removed after.
@Suite("Voices", .serialized)
struct VoicesTests {
  static let form = "/mission-control/submit/bibliographic/evidence-testament"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func typedRows(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    do {
      try await run(engine: engine, viewport: layout.viewport(for: engine), admin: admin, work: work)
    } catch {
      work.remove()
      try await admin.remove(after: error)
    }
    work.remove()
    try await admin.remove()
  }

  private func run(engine: BrowserEngine, viewport: Viewport, admin: TestAdmin, work: ScratchWork) async throws {
    try await withPage(engine, gnorium, viewport: viewport, cookies: [admin.cookie]) { page in
      try await page.openHydrated(Self.form)
      let form = page.locator(".submit-testament-form")
      let list = form.locator("[data-item-list='work-voice']")
      let rows = list.locator("[data-item-section='true']:not([data-item-template] *)")
      // One row to start, an author, labeled "Voice", with no heading over
      // the rows (their labels say what they are); three roles, Title Case,
      // no editor.
      try await expect(rows).toHaveCount(1)
      try await expect(list.locator(":scope > .form-items-heading")).toHaveCount(0)
      // Its name a combobox: the voices already on works suggested as typed.
      try await expect(rows.first.getByRole(.combobox, name: "Voice name")).toHaveCount(1)
      try await expect(rows.first.locator(".text-input-input")).toHaveAttribute("placeholder", "Voice name")
      try await expect(rows.first).toContainText("Voice role")
      let firstType = rows.first.locator(".dropdown-view")
      try await expect(firstType.locator(".dropdown-selected-text")).toHaveText("Author")
      try await expect(rows.first.locator("input[id$='-dropdown']")).toHaveValue("author")
      for (value, display) in [("author", "Author"), ("translator", "Translator"), ("compiler", "Compiler")] {
        try await expect(firstType.locator(".dropdown-option[data-value='\(value)']")).toHaveAttribute("data-display", display)
      }
      try await expect(firstType.locator(".dropdown-option[data-value='editor']")).toHaveCount(0)
      // "+ Add voice": the Codex add icon, then its words (no "+" character).
      try await expect(list.locator("[data-item-add-btn='true'] button")).toHaveText("Add voice")
      try await expect(list.locator("[data-item-add-btn='true'] button svg.add-icon-view")).toHaveCount(1)
      try await rows.first.locator(".text-input-input").fill("Homer")

      // A second row starts as an author; made a translator.
      try await list.locator("[data-item-add-btn='true'] button").click()
      try await expect(rows).toHaveCount(2)
      let second = rows.nth(1)
      try await expect(second.locator("input[id$='-dropdown']")).toHaveValue("author")
      try await second.locator(".dropdown-trigger").click()
      try await second.locator(".dropdown-option[data-value='translator']").click()
      try await expect(second.locator(".dropdown-selected-text")).toHaveText("Translator")
      try await second.locator(".text-input-input").fill("Alexander Pope")

      // A third row, taken away again by its own "− Remove voice" (the Codex
      // subtract icon, then its words), on its own line under the row's
      // fields, at the row's start, as "+ Add voice" sits under the list.
      try await list.locator("[data-item-add-btn='true'] button").click()
      try await expect(rows).toHaveCount(3)
      let remove = rows.nth(2).locator(".item-remove-btn")
      try await expect(remove).toHaveText("Remove voice")
      try await expect(remove.locator("svg.subtract-icon-view")).toHaveCount(1)
      let ownLine = try await rows.nth(2).evaluate(
        "(r) => { const b = r.querySelector(':scope > .form-actions-view > .item-remove-btn').getBoundingClientRect(); const f = r.querySelector(':scope > .form-items-view-fields').getBoundingClientRect(); const n = r.querySelector('[id$=\\'-text-input\\']').closest('.combobox-view, .text-input-view').getBoundingClientRect(); return b.top >= n.bottom && b.top >= f.bottom && Math.abs(b.left - f.left) < 2 && b.width <= f.width + 1 }"
      ).bool
      #expect(ownLine == true, "the row's − Remove voice should sit on its own line under its fields, at the start")
      // A phone: every add/remove button full width, stacked; wider,
      // content-width (user, 2026-09-29). One form never mixes the two.
      let widths = try await list.evaluate(
        """
        (l) => [...l.querySelectorAll('.form-actions-view')].filter(g => g.offsetParent)
          .flatMap(g => [...g.querySelectorAll(':scope > .button-view')].filter(b => b.offsetParent)
            .map(b => b.getBoundingClientRect().width / g.getBoundingClientRect().width))
        """
      ).array?.compactMap(\.double) ?? []
      #expect(!widths.isEmpty)
      if viewport.width <= 768 {
        #expect(widths.allSatisfy { $0 > 0.99 }, "phone buttons full width: \(widths)")
      } else {
        #expect(widths.allSatisfy { $0 < 0.6 }, "wide buttons content-width: \(widths)")
      }
      try await remove.click()
      try await expect(rows).toHaveCount(2)

      // What the form posts: each row's role and name, in order.
      let posted = try await list.evaluate(
        """
        (group) => {
          // The page's own check would stop an unfinished form's submit
          // before its script writes the JSON: this reads the script alone.
          group.closest('form').removeAttribute('novalidate');
          group.closest('form').dispatchEvent(new Event('submit', { cancelable: true }));
          return group.querySelector('.work-voice-json').value;
        }
        """
      ).string ?? ""
      let items = try JSONDecoder().decode([[String: String]].self, from: Data(posted.utf8))
      #expect(items == [["role": "author", "value": "Homer"], ["role": "translator", "value": "Alexander Pope"]])

      // The record field comes first, above the fields it fills in.
      let first = try await form.evaluate(
        """
        (form) => {
          const field = form.querySelector('.record-choice-field-view');
          const language = form.querySelector('#work-language');
          return !!(field.compareDocumentPosition(language) & Node.DOCUMENT_POSITION_FOLLOWING);
        }
        """
      ).bool
      #expect(first == true, "the Biblio-record field is not above Language")

      // No translation box, no chain: a translation is an Origin row
      // (`OriginTests`).
      try await expect(form.locator(".is-translation-checkbox-wrapper")).toHaveCount(0)
      try await expect(form.locator(".translation-chain-view")).toHaveCount(0)
      try await expect(form.locator(".origin-field-view")).toHaveCount(1)
    }
  }
}
