import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Ticking fields for attribution on the Submit Amendment form: a box
/// before every field, every row and every part of the date, ticked by editing the field, drawn
/// blue when ticked and unedited. Nothing is submitted. Needs a signed-in
/// account, made for the test and removed after (see `TestAdmin`).
@Suite("Amendment attribution", .serialized)
struct AmendmentAttributionTests {
  /// The Bosworth–Toller record, kept on the dev database.
  static let form =
    "/biblio-records/ang/an-anglo-saxon-dictionary/joseph-bosworth-and-thomas-northcote-toller/amendments/new"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func tickingFields(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await run(engine: engine, viewport: layout.viewport(for: engine), admin: admin)
    } catch {
      await admin.remove()
      throw error
    }
    await admin.remove()
  }

  private func run(engine: BrowserEngine, viewport: Viewport, admin: TestAdmin) async throws {
    try await withPage(engine, gnorium, viewport: viewport, cookies: [admin.cookie]) { page in
      try await page.openHydrated(Self.form)
      let work = page.locator(".submit-amendment-work")
      let title = work.locator(".attribute-field-view[data-attribute-key='title']")
      let titleBox = title.locator(".attribute-field-view-checkbox .checkbox-input")
      let titleInput = title.locator(".text-input-input")
      let script = work.locator(".attribute-field-view[data-attribute-key='script']")
      let scriptBox = script.locator(".attribute-field-view-checkbox .checkbox-input")

      // A real input per field and per row, unticked.
      try await expect(titleBox).toHaveAttribute("name", "attribute[]")
      try await expect(titleBox).toBeChecked(false)
      try await expect(work.locator(".attribute-field-view[data-attribute-key='author[1]']:not([data-item-template] *)")).toHaveCount(1)

      // The work's fields sit in its Metadata accordion: open it if shut.
      if !(try await titleInput.isVisible()) {
        try await work.locator(".accordion-summary").first.click()
      }
      try await expect(titleInput).toBeVisible()

      // The box sits inline in the field's label row, before its label, and
      // the control under it starts at the row's own edge: no indent. The
      // same in a repeated row's card (the first author).
      for field in [title, work.locator(".attribute-field-view[data-attribute-key='author[1]']:not([data-item-template] *)")] {
        let layout = try await field.evaluate(
          """
          (el) => {
            const box = el.querySelector('.attribute-field-view-checkbox').getBoundingClientRect();
            const row = el.querySelector('.text-input-label-row').getBoundingClientRect();
            const text = el.querySelector('.text-input-label').getBoundingClientRect();
            const input = el.querySelector('.text-input-input').getBoundingClientRect();
            const inRow = box.top >= row.top - 1 && box.bottom <= row.bottom + 1;
            const before = box.right <= text.left;
            const flush = Math.abs(box.left - input.left) <= 1 && Math.abs(row.left - input.left) <= 1;
            return inRow && before && flush ? 'ok' : JSON.stringify({box, row, text, input});
          }
          """
        ).string ?? ""
        #expect(layout == "ok", "the attribute box is not inline in the label row: \(layout)")
      }

      // "This is a translation" is a value, not a sourced fact: it has no
      // attribute box, and none stands around it.
      try await expect(work.locator(".is-translation-checkbox-wrapper")).toHaveCount(1)
      try await expect(work.locator(".attribute-field-view .is-translation-checkbox-wrapper")).toHaveCount(0)

      // Editing a field ticks it; undoing the edit unticks it again.
      let before = try await titleInput.inputValue()
      try await titleInput.fill(before + " (edited)")
      try await expect(titleBox).toBeChecked()
      try await titleInput.fill(before)
      try await expect(titleBox).toBeChecked(false)

      // An unedited field can be ticked by hand, and its control is drawn
      // blue, border and ring.
      try await scriptBox.check()
      let trigger = script.locator(".dropdown-trigger")
      let ring = try await trigger.evaluate("(el) => getComputedStyle(el).boxShadow").string ?? ""
      let blue = try await page.evaluate(
        "getComputedStyle(document.documentElement).getPropertyValue('--border-color-blue').trim()"
      ).string ?? ""
      #expect(!blue.isEmpty)
      #expect(ring.contains("1px"), "the ticked field's control has no ring: \(ring)")
      try await scriptBox.uncheck()
      try await expect(scriptBox).toBeChecked(false)

      // The date is ticked part by part: a box in each part's own label row,
      // and none for the whole date, which would stand on the qualifier's row
      // alone. The record's date is a range, so its end parts show.
      func datePart(_ part: String) -> Locator {
        work.locator(".attribute-field-view[data-attribute-key='date.\(part)']")
      }
      try await expect(work.locator(".attribute-field-view[data-attribute-key='date']")).toHaveCount(0)
      for part in ["yearQualifier", "era", "year", "month", "day", "eraEnd", "yearEnd"] {
        try await expect(datePart(part)).toHaveCount(1)
      }
      for part in ["yearQualifier", "era", "year", "eraEnd", "yearEnd"] {
        let layout = try await datePart(part).evaluate(
          """
          (el) => {
            const box = el.querySelector('.attribute-field-view-checkbox').getBoundingClientRect();
            const row = el.querySelector('.text-input-label-row, label:has(> .dropdown-label-text)')
              .getBoundingClientRect();
            const inRow = box.top >= row.top - 1 && box.bottom <= row.bottom + 1;
            return inRow && box.width > 0 ? 'ok' : JSON.stringify({box, row});
          }
          """
        ).string ?? ""
        #expect(layout == "ok", "date.\(part)'s box is not in its own label row: \(layout)")
      }

      // Editing the year ticks the year alone.
      let yearBox = datePart("year").locator(".attribute-field-view-checkbox .checkbox-input")
      let yearInput = datePart("year").locator(".text-input-input")
      let year = try await yearInput.inputValue()
      try await yearInput.fill("1897")
      try await expect(yearBox).toBeChecked()
      try await expect(datePart("yearQualifier").locator(".attribute-field-view-checkbox .checkbox-input"))
        .toBeChecked(false)
      try await yearInput.fill(year)
      try await expect(yearBox).toBeChecked(false)
    }
  }
}
