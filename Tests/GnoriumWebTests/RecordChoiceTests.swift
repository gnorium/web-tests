import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The Biblio-record field of Submit Testament: a searchable dropdown of
/// every record from the start, each in two rows (its language › its title,
/// a breadcrumb with BreadcrumbView's own chevron; its voices and
/// type), a note ending a list cut at 50; the closed dropdown names the
/// chosen record so too. Once the
/// work's language, title, author and type are filled, the match is
/// chosen; choosing it again unselects it, back to "—", no choice. A record
/// found by typing and picked fills those fields in from it. The chosen
/// record's chronicle tree follows with the new testament in it, the only
/// node that moves. Nothing is submitted. A throwaway admin owns a
/// scratch work — its author, evidence, overture, concerto, hallmark, record
/// and attributed version, made by SQL — removed after.
@Suite("Record choice", .serialized)
struct RecordChoiceTests {
  static let form = "/mission-control/submit/bibliographic/evidence-testament"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func choosingARecordAndPlacingTheTestament(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    do {
      try await run(engine: engine, viewport: layout.viewport(for: engine), admin: admin, work: work)
    } catch {
      work.remove()
      await admin.remove()
      throw error
    }
    work.remove()
    await admin.remove()
  }

  private func run(engine: BrowserEngine, viewport: Viewport, admin: TestAdmin, work: ScratchWork) async throws {
    try await withPage(engine, gnorium, viewport: viewport, cookies: [admin.cookie]) { page in
      // Counted either side of the page's drawing: other suites' scratch
      // works come and go meanwhile.
      let before = Int(try TestAdmin.query("SELECT count(*) FROM biblio_records")) ?? 0
      try await page.openHydrated(Self.form)
      let after = Int(try TestAdmin.query("SELECT count(*) FROM biblio_records")) ?? 0
      let field = page.locator(".record-choice-field-view")
      let form = page.locator(".submit-testament-form")
      let author = form.locator(
        "[data-item-list='work-voice'] [data-item-section='true']:not([data-item-template] *) .text-input-input"
      ).first
      try await expect(field.locator("legend")).toContainText("Biblio-record")
      // A dropdown of every record from the start, none chosen: "—".
      let dropdown = field.locator(".dropdown-view")
      try await expect(dropdown.locator(".dropdown-selected-text")).toHaveText("—")
      try await expect(dropdown.locator(".dropdown-option[data-value='\(work.recordID)']")).toHaveCount(1)
      // Cut at 50 records, the list says so after its last option, and
      // only then; the note is no option. (Unasked if the count crossed 50
      // while the page was drawn.)
      let note = dropdown.locator(".dropdown-options-list:not([data-dropdown-results]) > .dropdown-note")
      if before > 50 && after > 50 {
        try await expect(note).toHaveText("Showing the first 50. Type to narrow the list.")
        try await expect(note).not.toHaveAttribute("data-dropdown-option", "true")
      } else if before <= 50 && after <= 50 {
        try await expect(note).toHaveCount(0)
      }

      // The key fields: a dropdown tells its hidden input, as a pick does.
      _ = try await page.evaluate(
        """
        (() => {
          for (const [id, value] of [['work-language', 'eng'], ['work-type', 'report']]) {
            const input = document.getElementById(id);
            input.value = value;
            input.dispatchEvent(new Event('change'));
          }
        })()
        """)
      try await form.locator("input[name='title']").fill(work.title)
      try await author.fill(work.author)

      // The scratch work is the match, chosen, first; no "New title". The
      // closed dropdown names it as its option does: English › its title.
      // (Asked after a 500ms pause; with every suite running, the answer can
      // take longer than the usual 5s.)
      try await expect(dropdown.locator(".dropdown-selected-text .breadcrumb-label-context"), timeout: .seconds(15))
        .toHaveText("English")
      try await expect(dropdown.locator(".dropdown-selected-text .breadcrumb-label-text")).toHaveText(work.title)
      try await expect(dropdown.locator(".dropdown-option").first).toHaveAttribute("data-value", work.recordID)
      try await expect(dropdown.locator(".dropdown-option[data-value='new']")).toHaveCount(0)
      // Settled: a later answer to the key fields' asks redraws the field, and
      // it could land after the move below, undoing it. Each field typed asks
      // again after a 500ms pause, and with every suite running an answer
      // can take seconds: wait until the field has not been redrawn for 1.5s.
      _ = try await field.evaluate(
        """
        (el) => new Promise((resolve) => {
          const slot = el.querySelector('.record-choice-field-slot');
          let quiet;
          const settle = () => { clearTimeout(quiet); quiet = setTimeout(() => { observer.disconnect(); resolve(true); }, 1500); };
          const observer = new MutationObserver(settle);
          observer.observe(slot, { childList: true });
          settle();
          setTimeout(() => { observer.disconnect(); resolve(false); }, 15000);
        })
        """, timeout: .seconds(20))
      // Two rows: its language › its title; its voices and type.
      // No path, and no language in the second row.
      let option = dropdown.locator(".dropdown-option[data-value='\(work.recordID)']")
      try await expect(option.locator(":scope > span")).toHaveCount(2)
      let label = option.locator(".dropdown-option-display-text .breadcrumb-label-view")
      try await expect(label.locator(".breadcrumb-label-context")).toHaveText("English")
      try await expect(label.locator(".breadcrumb-separator-view .next-icon-view")).toHaveCount(1)
      try await expect(label.locator(".breadcrumb-label-text")).toHaveText(work.title)
      try await expect(option.locator(".dropdown-option-alt-text")).toHaveText("\(work.author) · report")
      try await expect(option).not.toContainText(work.path)
      // One running line that wraps, as a breadcrumb does: the chevron on the
      // language's line, the page breadcrumb's icon at its size. (Its colour
      // is the Search menu suite's: this option, chosen, is drawn inverted.)
      // Measured with its menu shown for the moment, and hidden again, with
      // no click: the field's state is not touched.
      let row = try await label.evaluate(
        """
        (el) => {
          const menu = el.closest('.dropdown-menu');
          menu.dataset.open = 'true';
          const box = (s) => el.querySelector(s).getBoundingClientRect();
          const context = box('.breadcrumb-label-context'), chevron = box('.breadcrumb-separator-view');
          const trail = document.querySelector('.breadcrumb-view .breadcrumb-separator-view .next-icon-view');
          const measured = {
            display: getComputedStyle(el).display,
            sameLine: Math.abs((chevron.top + chevron.bottom) / 2 - (context.top + context.bottom) / 2) < 8,
            after: chevron.left >= context.right,
            size: el.querySelector('.breadcrumb-separator-view .next-icon-view').getBoundingClientRect().width,
            trail: trail ? trail.getBoundingClientRect().width : null,
          };
          menu.dataset.open = 'false';
          return measured;
        }
        """)
      #expect(row["display"].string == "inline")
      #expect(row["sameLine"].bool == true, "the chevron left the language's line")
      #expect(row["after"].bool == true)
      #expect(row["size"].double == 8)
      if let trail = row["trail"].double { #expect(row["size"].double == trail) }

      // Its tree: the edition it has, fixed, and the new testament after it.
      let tree = field.locator(".record-placement-view")
      try await expect(tree).toBeVisible()
      let fixed = tree.locator(
        ".outliner-item:not([data-outliner-id='edition-new']) > .outliner-row > .record-placement-node > .record-placement-row")
      try await expect(fixed.first.locator(".record-placement-label")).toContainText("First edition")
      try await expect(fixed.first.locator(".outliner-handle")).toBeDisabled()
      let new = tree.locator(".outliner-item[data-outliner-id='edition-new']")
      try await expect(new.locator(".record-placement-number").first).toHaveText("2")
      try await expect(field.locator("input[name='placement-version']")).toHaveValue(work.versionID)

      // Moved up, it takes the first place; the arrangement posts it.
      try await new.locator(".outliner-handle").first.click()
      try await page.locator(".outliner-toolbar [data-outliner-action='up']").click()
      try await page.locator(".outliner-toolbar [data-outliner-action='done']").click()
      try await expect(new.locator(".record-placement-number").first).toHaveText("1")
      let placement = try await field.locator("input[name='placement']").inputValue()
      #expect(placement.contains(#""edition-new":{"parent":"work","position":0}"#), "\(placement)")

      // Chosen again, it is unselected: "—", no record, no tree, and
      // nothing cleared; it stays so (the best match is not chosen again).
      try await dropdown.locator(".dropdown-trigger").click()
      try await option.click()
      try await expect(dropdown.locator(".dropdown-selected-text")).toHaveText("—")
      try await expect(field.locator(".record-placement-view")).toHaveCount(0)
      try await expect(field.locator("input[name='placement-version']")).toHaveCount(0)
      try await expect(field.locator("input[name='biblio-record']")).toHaveValue("")
      try await expect(form.locator("input[name='title']")).toHaveValue(work.title)
      try await expect(author).toHaveValue(work.author)
      try await Task.sleep(for: .milliseconds(800))
      try await expect(field.locator("input[name='biblio-record']")).toHaveValue("")

      // Afresh: found by typing, picked, and the key fields are its.
      try await page.openHydrated(Self.form)
      try await expect(dropdown.locator(".dropdown-option[data-value='\(work.recordID)']")).toHaveCount(1)
      try await dropdown.locator(".dropdown-trigger").click()
      try await dropdown.locator(".dropdown-search-input").fill(work.suffix)
      let results = dropdown.locator(".dropdown-options-list[data-dropdown-results='true']")
      try await expect(results).toBeVisible()
      try await expect(results.locator(".dropdown-option")).toHaveCount(1)
      try await expect(results.locator(".dropdown-note")).toHaveCount(0)
      let found = results.locator(".dropdown-option[data-value='\(work.recordID)']")
      try await expect(found.locator(".breadcrumb-label-context")).toHaveText("English")
      try await expect(found.locator(".breadcrumb-label-text")).toHaveText(work.title)
      try await expect(found.locator(".dropdown-option-alt-text")).toHaveText("\(work.author) · report")
      // Found by its title only, never its author's name.
      try await dropdown.locator(".dropdown-search-input").fill("Web Tests Author \(work.suffix)")
      try await expect(results.locator(".dropdown-option")).toHaveCount(0)
      try await dropdown.locator(".dropdown-search-input").fill(work.suffix)
      try await expect(results.locator(".dropdown-option")).toHaveCount(1)
      try await found.click()

      try await expect(field.locator("input[name='biblio-record']")).toHaveValue(work.recordID)
      try await expect(dropdown.locator(".dropdown-selected-text .breadcrumb-label-text"), timeout: .seconds(15))
        .toHaveText(work.title)
      try await expect(form.locator("#work-language")).toHaveValue("eng")
      try await expect(form.locator("[data-dropdown-id='work-language'] .dropdown-selected-text")).toHaveText("English")
      try await expect(form.locator("#work-type")).toHaveValue("report")
      try await expect(form.locator("[data-dropdown-id='work-type'] .dropdown-selected-text")).toHaveText("report")
      try await expect(form.locator("input[name='title']")).toHaveValue(work.title)
      try await expect(author).toHaveValue(work.author)
      try await expect(field.locator(".record-placement-view")).toBeVisible()
      try await expect(field.locator("input[name='placement-version']")).toHaveValue(work.versionID)
      // Filled in, not asked about: the choice stands.
      try await Task.sleep(for: .milliseconds(800))
      try await expect(field.locator("input[name='biblio-record']")).toHaveValue(work.recordID)
    }
  }
}
