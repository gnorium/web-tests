import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Ticking fields for attribution on the Submit Amendment form: a box
/// before every field, every row, every part of the date and every field of
/// an edition's publication statement, never a whole group, ticked by editing the field, drawn
/// blue when ticked and unedited. Nothing is submitted. Needs a signed-in
/// account, made for the test and removed after (see `TestAdmin`).
@Suite("Amendment attribution", .serialized)
struct AmendmentAttributionTests {
  /// The Bosworth–Toller record, kept on the dev database.
  static let form =
    "/biblio-records/ang/an-anglo-saxon-dictionary/dictionary/amendments/new"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func tickingFields(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    // A work with an edition in its tree, for the edition's publication.
    let scratch = try ScratchWork(owner: admin)
    do {
      try await run(engine: engine, viewport: layout.viewport(for: engine), admin: admin, scratch: scratch)
    } catch {
      scratch.remove()
      await admin.remove()
      throw error
    }
    scratch.remove()
    await admin.remove()
  }

  private func run(engine: BrowserEngine, viewport: Viewport, admin: TestAdmin, scratch: ScratchWork) async throws {
    try await withPage(engine, gnorium, viewport: viewport, cookies: [admin.cookie]) { page in
      try await page.openHydrated(Self.form)
      let work = page.locator(".submit-amendment-work")
      let title = work.locator(".selectable-field-view[data-selectable-key='title']")
      let titleBox = title.locator(".selectable-field-view-checkbox .checkbox-input")
      let titleInput = title.locator(".text-input-input")
      let script = work.locator(".selectable-field-view[data-selectable-key='script']")
      let scriptBox = script.locator(".selectable-field-view-checkbox .checkbox-input")

      // A real input per field and per row, unticked.
      try await expect(titleBox).toHaveAttribute("name", "attribute[]")
      try await expect(titleBox).toBeChecked(false)
      try await expect(work.locator(".selectable-field-view[data-selectable-key='author[1].name']:not([data-item-template] *)")).toHaveCount(1)

      // The work's fields sit in its Metadata accordion: open it if shut.
      if !(try await titleInput.isVisible()) {
        try await work.locator(".accordion-summary").first.click()
      }
      try await expect(titleInput).toBeVisible()

      // The box sits inline in the field's label row, before its label, and
      // the control under it starts at the row's own edge: no indent. The
      // same in a repeated row's card (the first author).
      for field in [title, work.locator(".selectable-field-view[data-selectable-key='author[1].name']:not([data-item-template] *)")] {
        let layout = try await field.evaluate(
          """
          (el) => {
            const box = el.querySelector('.selectable-field-view-checkbox').getBoundingClientRect();
            const row = el.querySelector('.text-input-label-row, .combobox-label').getBoundingClientRect();
            const text = el.querySelector('.text-input-label, .combobox-label-text').getBoundingClientRect();
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

      // A voice's row is ticked field by field: its role and its name
      // each have a box, the row none. Editing the second one's name ticks
      // that name alone.
      func authorName(_ row: Int) -> Locator {
        work.locator(".selectable-field-view[data-selectable-key='author[\(row)].name']:not([data-item-template] *)")
      }
      for row in [1, 2] {
        try await expect(work.locator(".selectable-field-view[data-selectable-key='author[\(row)]']")).toHaveCount(0)
        try await expect(authorName(row)).toHaveCount(1)
      }
      try await expect(authorName(2).locator(".selectable-field-view-checkbox .label-text"))
        .toHaveText("Select Voice 2 name")
      let secondAuthor = authorName(2).locator(".text-input-input")
      let secondName = try await secondAuthor.inputValue()
      try await secondAuthor.fill(secondName + " (edited)")
      try await expect(authorName(2).locator(".selectable-field-view-checkbox .checkbox-input")).toBeChecked()
      try await expect(authorName(1).locator(".selectable-field-view-checkbox .checkbox-input")).toBeChecked(false)
      try await expect(titleBox).toBeChecked(false)
      try await secondAuthor.fill(secondName)
      try await expect(authorName(2).locator(".selectable-field-view-checkbox .checkbox-input")).toBeChecked(false)

      // No "This is a translation" box: a translation is an Origin step.
      try await expect(work.locator(".is-translation-checkbox-wrapper")).toHaveCount(0)

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
        work.locator(".selectable-field-view[data-selectable-key='date.\(part)']")
      }
      try await expect(work.locator(".selectable-field-view[data-selectable-key='date']")).toHaveCount(0)
      for part in ["yearQualifier", "era", "year", "month", "day", "eraEnd", "yearEnd"] {
        try await expect(datePart(part)).toHaveCount(1)
      }
      for part in ["yearQualifier", "era", "year", "eraEnd", "yearEnd"] {
        let layout = try await datePart(part).evaluate(
          """
          (el) => {
            const box = el.querySelector('.selectable-field-view-checkbox').getBoundingClientRect();
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
      let yearBox = datePart("year").locator(".selectable-field-view-checkbox .checkbox-input")
      let yearInput = datePart("year").locator(".text-input-input")
      let year = try await yearInput.inputValue()
      try await yearInput.fill("1897")
      try await expect(yearBox).toBeChecked()
      try await expect(datePart("yearQualifier").locator(".selectable-field-view-checkbox .checkbox-input"))
        .toBeChecked(false)
      try await yearInput.fill(year)
      try await expect(yearBox).toBeChecked(false)

      // The work's place is its own field, with its own box; the work has
      // no creation statement.
      try await expect(work.locator(".selectable-field-view[data-selectable-key='place']")).toHaveCount(1)
      try await expect(work.locator("[data-as-namespace='creation']")).toHaveCount(0)

      // An edition's publication is ticked field by field (on a work whose
      // tree has an edition): its place, each
      // agent's role and name, each part of its date, each box in its own
      // label row; never the statement or an agent's row whole.
      try await page.openHydrated("\(scratch.path)/amendments/new")
      let edition = page.locator(".testament-outliner-form:has([data-as-namespace='publication'])").first
      func statementField(_ key: String) -> Locator {
        edition.locator(".selectable-field-view[data-selectable-key='\(key)']:not([data-item-template] *)")
      }
      for group in ["publication", "publication[1]", "publication.date"] {
        try await expect(edition.locator(".selectable-field-view[data-selectable-key='\(group)']")).toHaveCount(0)
      }
      let statementKeys =
        ["publication.place", "publication[1].role", "publication[1].agent"]
        + ["yearQualifier", "era", "year", "month", "day", "eraEnd", "yearEnd"].map { "publication.date.\($0)" }
      for key in statementKeys {
        try await expect(statementField(key)).toHaveCount(1)
      }
      let place = statementField("publication.place").locator(".text-input-input")
      // The Carrier shows the card it calls for: a scratch work's testament
      // has none, so printed is chosen (its node opened first).
      let carrier = edition.locator(".dropdown-view:has(input[name='carrier'])").first
      if !(try await carrier.isVisible()) {
        _ = try await edition.evaluate(
          """
          (el) => {
            const chain = [];
            for (let d = el.closest('details'); d; d = d.parentElement.closest('details')) chain.unshift(d);
            for (const d of chain) if (!d.open) d.querySelector(':scope > summary').click();
            return chain.length;
          }
          """)
      }
      if (try await carrier.locator("input[name='carrier']").inputValue()).isEmpty {
        try await carrier.locator(".dropdown-trigger").click()
        try await carrier.locator(".dropdown-option[data-value='printed']").click()
      }
      if !(try await place.isVisible()) {
        // Its node's Metadata, and every accordion round it, opened.
        _ = try await edition.evaluate(
          """
          (el) => {
            const chain = [];
            for (let d = el.closest('details'); d; d = d.parentElement.closest('details')) chain.unshift(d);
            for (const d of chain) if (!d.open) d.querySelector(':scope > summary').click();
            return chain.length;
          }
          """)
      }
      try await expect(place).toBeVisible()
      for key in ["publication.place", "publication[1].role", "publication[1].agent", "publication.date.year"] {
        let layout = try await statementField(key).evaluate(
          """
          (el) => {
            const box = el.querySelector('.selectable-field-view-checkbox').getBoundingClientRect();
            const row = el.querySelector('.text-input-label-row, label:has(> .dropdown-label-text)')
              .getBoundingClientRect();
            const inRow = box.top >= row.top - 1 && box.bottom <= row.bottom + 1;
            return inRow && box.width > 0 ? 'ok' : JSON.stringify({box, row});
          }
          """
        ).string ?? ""
        #expect(layout == "ok", "\(key)'s box is not in its own label row: \(layout)")
      }

      // Editing the first agent's name ticks that name alone: not its role,
      // not the place, not the date.
      func statementBox(_ key: String) -> Locator {
        statementField(key).locator(".selectable-field-view-checkbox .checkbox-input")
      }
      let agent = statementField("publication[1].agent").locator(".text-input-input")
      let name = try await agent.inputValue()
      try await agent.fill(name + " Jr.")
      try await expect(statementBox("publication[1].agent")).toBeChecked()
      for key in ["publication[1].role", "publication.place", "publication.date.year", "publication.date.yearQualifier"] {
        try await expect(statementBox(key)).toBeChecked(false)
      }
      try await agent.fill(name)
      try await expect(statementBox("publication[1].agent")).toBeChecked(false)

      // Editing the place ticks the place alone.
      let placeValue = try await place.inputValue()
      try await place.fill(placeValue + " (edited)")
      try await expect(statementBox("publication.place")).toBeChecked()
      try await expect(statementBox("publication[1].agent")).toBeChecked(false)
      try await place.fill(placeValue)
      try await expect(statementBox("publication.place")).toBeChecked(false)

      // A day its month has not is marked as it is typed: 29 February only
      // in a leap year.
      let dateYear = statementField("publication.date.year").locator(".text-input-input")
      let day = statementField("publication.date.day").locator(".text-input-input")
      // Chosen as the dropdowns choose: their hidden inputs, changed. An
      // exact date shows its month and day.
      for (part, value) in [("yearQualifier", "exact"), ("month", "february")] {
        _ = try await statementField("publication.date.\(part)").evaluate(
          """
          (el) => {
            const input = el.querySelector('input[type=hidden]');
            input.value = '\(value)';
            input.dispatchEvent(new Event('change'));
            return input.value;
          }
          """)
      }
      let (yearBefore, dayBefore) = (try await dateYear.inputValue(), try await day.inputValue())
      try await dateYear.fill("1613")
      try await day.fill("29")
      try await expect(day).toHaveAttribute("data-validation", "invalid")
      try await dateYear.fill("1612")
      #expect(try await day.getAttribute("data-validation") == nil, "1612 is a leap year")
      try await dateYear.fill(yearBefore)
      try await day.fill(dayBefore)
    }
  }
}
