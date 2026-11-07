import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The Biblio-record field of Submit Testament: a searchable dropdown of
/// every record from the start, its label until one is chosen, each in
/// two rows (its language › its title, a breadcrumb with BreadcrumbView's
/// own chevron; then the rest of its identity as its address takes it:
/// its class, its voice names only where another record shares its
/// language, title and class, user 2026-11-02), a note ending a list cut at 100; the
/// closed dropdown names the chosen record so too. Once the work's
/// language, title, author and type are filled, the match is offered
/// first and chosen for the submitter (Submit Testament makes records: a
/// work a record already is goes to its amendment, user, 2026-10-03). A
/// record found by typing (by
/// its title, never its author) and picked offers its amendment, the
/// form's Submit waiting. Nothing is submitted (`SubmissionTests` submits). A throwaway
/// admin owns a scratch work—its author, figurant, overture, antiphon,
/// madrigal, record and explicated version, made by SQL—removed after.
@Suite("Record choice", .serialized)
struct RecordChoiceTests {
  static let form = "/mission-control/submit/bibliographic/testament"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func choosingARecordAndPlacingTheTestament(engine: BrowserEngine, layout: Layout) async throws {
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
      // A dropdown of every record from the start, none chosen: a new record.
      let dropdown = field.locator(".dropdown-view")
      try await expect(dropdown.locator(".dropdown-selected-text")).toHaveText("Biblio-record")
      // Cut at 100 records, as every option list is (a page's rows,
      // `PaginationView.perList`), the list says so after its last option,
      // and only then; the note is no option. The list is in title order,
      // so the scratch work is among the options only when nothing was cut:
      // past 100 (other suites' amended scratch works stay) it can sort
      // after the cut, and typing finds it below. (Unasked if the count
      // crossed 100 while the page was drawn.)
      let cap = 100
      let note = dropdown.locator(".dropdown-options-list:not([data-dropdown-results]) > .dropdown-note")
      let options = dropdown.locator(".dropdown-options-list:not([data-dropdown-results]) > .dropdown-option")
      if before > cap && after > cap {
        try await expect(note).toHaveText("Showing the first \(cap).")
        try await expect(note).not.toHaveAttribute("data-dropdown-option", "true")
        try await expect(options).toHaveCount(cap)
      } else if before <= cap && after <= cap {
        try await expect(note).toHaveCount(0)
        try await expect(dropdown.locator(".dropdown-option[data-value='\(work.recordID)']")).toHaveCount(1)
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

      // The scratch work is the match, offered first and chosen for the
      // submitter; no "New title". (Asked after a 500ms pause; with
      // every suite running, the answer can take longer than the usual 5s.)
      try await expect(dropdown.locator(".dropdown-option").first, timeout: .seconds(15))
        .toHaveAttribute("data-value", work.recordID)
      try await expect(dropdown.locator(".dropdown-selected-text .breadcrumb-label-text"), timeout: .seconds(15))
        .toHaveText(work.title)
      try await expect(dropdown.locator(".dropdown-option[data-value='new']")).toHaveCount(0)
      // Settled: a later answer to the key fields' asks redraws the field.
      // Each field typed asks again after a 500ms pause, and with every
      // suite running an answer can take seconds: wait until the field has
      // not been redrawn for 1.5s.
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
      // Chosen: its amendment offered, the form's Submit waiting.
      try await expect(field.locator("input[name='biblio-record']")).toHaveValue(work.recordID)
      try await expect(field.locator("[data-record-choice-amendment] .record-choice-amendment-button"))
        .toBeVisible()
      try await expect(form.locator(".record-actions button[type='submit']")).toBeDisabled()
      // Two rows: its language › its title; its class, and its voice names
      // only where its address takes them (user, 2026-11-02): the scratch
      // title is its own, so its class alone, never its author.
      // No path, and no language in the second row.
      let option = dropdown.locator(".dropdown-option[data-value='\(work.recordID)']")
      try await expect(option.locator(":scope > span")).toHaveCount(2)
      let label = option.locator(".dropdown-option-display-text .breadcrumb-label-view")
      try await expect(label.locator(".breadcrumb-label-context")).toHaveText("English")
      try await expect(label.locator(".breadcrumb-separator-view .chevron-right-icon-view")).toHaveCount(1)
      try await expect(label.locator(".breadcrumb-label-text")).toHaveText(work.title)
      try await expect(option.locator(".dropdown-option-alt-text")).toHaveText("Report")
      try await expect(option).not.toContainText(work.path)
      // One running line that wraps, as a breadcrumb does: the chevron on the
      // language's line, the page breadcrumb's icon at its size. (Its color
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
          const trail = document.querySelector('.breadcrumb-view .breadcrumb-separator-view .chevron-right-icon-view');
          const measured = {
            display: getComputedStyle(el).display,
            sameLine: Math.abs((chevron.top + chevron.bottom) / 2 - (context.top + context.bottom) / 2) < 8,
            after: chevron.left >= context.right,
            size: el.querySelector('.breadcrumb-separator-view .chevron-right-icon-view').getBoundingClientRect().height,
            trail: trail ? trail.getBoundingClientRect().height : null,
          };
          menu.dataset.open = 'false';
          return measured;
        }
        """)
      #expect(row["display"].string == "inline")
      #expect(row["sameLine"].bool == true, "the chevron left the language's line")
      #expect(row["after"].bool == true)
      #expect(row["size"].double == 16, "the chevron is punctuation: its long edge, its height, is the 16px text's font size")
      if let trail = row["trail"].double { #expect(row["size"].double == trail) }

      // Afresh: found by typing, picked, and its amendment offered.
      try await page.openHydrated(Self.form)
      try await expect(dropdown.locator(".dropdown-selected-text")).toHaveText("Biblio-record")
      // A search that fails first (user, 2026-11-05): the wait under the
      // records it lists, then one vague message in the wait's place, a
      // field's error, those records kept; the next key asks again, the
      // message gone once its answer is in. Failed in the page (`fetch`
      // wrapped), shortly, as a server's error would come.
      let failing = "Web tests fails \(work.suffix)"
      #expect(
        try await page.evaluate(
          """
          (() => {
            const fetched = window.fetch;
            window.fetch = (url, options) => {
              const asked = new URL(String(url), location.href);
              if (asked.pathname.startsWith('/mission-control/record-choices/')
                && asked.searchParams.get('q') === '\(failing)') {
                return new Promise((resolve) => setTimeout(() => resolve(new Response('', { status: 503 })), 300));
              }
              return fetched(url, options);
            };
            return true;
          })()
          """, as: Bool.self))
      try await dropdown.locator(".dropdown-trigger").click()
      let status = dropdown.locator(".dropdown-menu > .options-status-view")
      let failed = status.locator(":scope > .options-status-failed")
      // Watched once its menu is open: the field is drawn again only once
      // it closes.
      _ = try await status.evaluate(
        """
        (status) => {
          window.recordStates = [];
          new MutationObserver(() => window.recordStates.push(status.dataset.state))
            .observe(status, { attributes: true, attributeFilter: ['data-state'] });
        }
        """)
      try await dropdown.locator(".dropdown-search-input .search-input").fill(failing)
      try await expect(failed).toBeVisible()
      try await expect(failed.locator(".field-validation-message-text")).toHaveText(
        "The options could not be loaded.")
      try await expect(failed.locator(".field-validation-message-view")).toHaveAttribute("data-status", "error")
      try await expect(status.locator(":scope > .options-status-loading")).toBeHidden()
      try await expect(dropdown.locator(".dropdown-options-list:not([data-dropdown-results])"))
        .not.toHaveAttribute("hidden")
      try await dropdown.locator(".dropdown-search-input .search-input").fill(work.suffix)
      let results = dropdown.locator(".dropdown-options-list[data-dropdown-results='true']")
      try await expect(results).toBeVisible()
      try await expect(results.locator(".dropdown-option")).toHaveCount(1)
      try await expect(results.locator(".dropdown-note")).toHaveCount(0)
      try await expect(failed).toBeHidden()
      let states = try await page.evaluate("window.recordStates.join(' ')").string
      #expect(
        states == "busy failed busy idle", "the wait, the message, the wait again, then the records: \(states ?? "—")")
      let found = results.locator(".dropdown-option[data-value='\(work.recordID)']")
      try await expect(found.locator(".breadcrumb-label-context")).toHaveText("English")
      try await expect(found.locator(".breadcrumb-label-text")).toHaveText(work.title)
      try await expect(found.locator(".dropdown-option-alt-text")).toHaveText("Report")
      // Found by its title only, never its author's name.
      try await dropdown.locator(".dropdown-search-input .search-input").fill("Web Tests Author \(work.suffix)")
      try await expect(results.locator(".dropdown-option")).toHaveCount(0)
      try await dropdown.locator(".dropdown-search-input .search-input").fill(work.suffix)
      try await expect(results.locator(".dropdown-option")).toHaveCount(1)
      try await found.click()

      try await expect(field.locator("input[name='biblio-record']")).toHaveValue(work.recordID)
      try await expect(dropdown.locator(".dropdown-selected-text .breadcrumb-label-text"), timeout: .seconds(15))
        .toHaveText(work.title)
      try await expect(dropdown.locator(".dropdown-selected-text .breadcrumb-label-context")).toHaveText("English")
      // Submit Testament makes records: chosen, its Submit waits and the
      // record's amendment is offered in its place.
      try await expect(field.locator("[data-record-choice-amendment] .record-choice-amendment-button"), timeout: .seconds(15))
        .toBeVisible()
      try await expect(form.locator(".record-actions button[type='submit']")).toBeDisabled()
      // Chosen, not asked about again: the choice stands.
      try await Task.sleep(for: .milliseconds(800))
      try await expect(field.locator("input[name='biblio-record']")).toHaveValue(work.recordID)
    }
  }
}
