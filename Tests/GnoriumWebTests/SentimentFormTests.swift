import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Submit Sentiment, the parallel of Submit Testament, the record page in
/// edit mode: the record first (Lexico-record, Language, Script, Title,
/// Type), then the tree with the new sentiment alone, open, its fields in
/// its Metadata (its Form rows, Definition, the Grammar, Register, Domain,
/// Region and Currency labels). No card, no placement widget. No utterance
/// is cited, nothing is derived and no passage coins the word: the pipeline
/// finds the utterances by the title and the forms. A region is offered
/// under its language. A picked lexico-record stands with its own fields,
/// its tree in the tree section, and stays chosen; unset, the typed fields
/// come back as they were left. Nothing is submitted (`SubmissionTests`
/// submits).
@Suite("Sentiment form", .serialized)
struct SentimentFormTests {
  static let path = "/mission-control/submit/lexicographic/evidence-sentiment"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func theRecordThenTheSentiment(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    do {
      try await run(engine: engine, layout: layout, admin: admin, word: word)
    } catch {
      word.remove()
      try await admin.remove(after: error)
    }
    word.remove()
    try await admin.remove()
  }

  private func run(engine: BrowserEngine, layout: Layout, admin: TestAdmin, word: ScratchWord) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
      try await page.openHydrated(Self.path)
      let form = page.locator(".submit-sentiment-form")
      try await shoot(page, "top", layout)

      // The record, then the new sentiment in the tree, in order.
      let order = try await form.evaluate(
        """
        (form) => {
          const chain = [
            '.record-choice-field-view', '#language', '#script', '#title', '#type', '.submit-sentiment-tree',
            "[data-submission-draft='true']", '#definition', '#label-grammar',
            '#label-register', '#label-domain', '#label-region', '#label-currency',
          ];
          for (let i = 1; i < chain.length; i++) {
            const a = form.querySelector(chain[i - 1]), b = form.querySelector(chain[i]);
            if (!a || !b) return 'missing ' + (a ? chain[i] : chain[i - 1]);
            if (!(a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING)) return chain[i] + ' before ' + chain[i - 1];
          }
          return 'ok';
        }
        """
      ).string
      #expect(order == "ok", "\(order ?? "")")
      // Nothing cited, nothing derived, nothing coined.
      for gone in ["[id^='utterance-accordion']", "input[name='coins[]']", "[data-derived-scope]", "input[name='anchors']"] {
        try await expect(form.locator(gone)).toHaveCount(0)
      }
      try await expect(form.locator(".framed-accordion-view, #sentiment-accordion, #sentiment-placement"))
        .toHaveCount(0)
      // Language a dropdown, English; placeholders their labels.
      try await expect(form.locator("#language")).toHaveValue("eng")
      try await expect(form.locator("[data-dropdown-id='language'] .dropdown-selected-text")).toHaveText("English")
      try await expect(form.locator("input[name='title']")).toHaveAttribute("placeholder", "Title")
      try await expect(form.locator("#definition")).toHaveAttribute("placeholder", "Definition")

      // No Form rows: a sentiment's forms are its utterances', never typed.
      try await expect(form.locator("[data-item-list='title-form'], .title-form-json")).toHaveCount(0)
      try await expect(form.locator("button[aria-label='Add Form']")).toHaveCount(0)

      // Grammar in lowercase; each region under its language.
      try await expect(page.locator(".dropdown-option[data-value='often_in_plural']"))
        .toHaveAttribute("data-display", "often in plural")
      let british = page.locator(".dropdown-option[data-value='british_english']")
      try await expect(british).toHaveAttribute("data-display", "British")
      try await expect(british.locator(".breadcrumb-label-context")).toHaveText("English")
      try await expect(page.locator(".dropdown-option[data-value='received_pronunciation']")).toHaveCount(0)

      // Typed, then a record picked: its own fields stand in place of the
      // typed ones and its tree in the tree section, and it stays chosen.
      try await form.locator("input[name='title']").fill("\(word.title)s")
      let field = form.locator(".record-choice-field-view")
      let dropdown = field.locator(".dropdown-view")
      // The typed title redraws the field once its answer is in: picked
      // only after, so the answer does not close the menu or drop the
      // choice. The search's answer is waited for in full.
      try await expect(field.locator(".record-choice-field-slot"), timeout: .seconds(20))
        .toHaveAttribute("aria-busy", "false")
      try await dropdown.locator(".dropdown-trigger").click()
      try await dropdown.locator(".dropdown-search-input .search-input").fill(word.title)
      let found = dropdown.locator(
        ".dropdown-options-list[data-dropdown-results='true'] .dropdown-option[data-value='\(word.recordID)']")
      try await expect(found, timeout: .seconds(20)).toBeVisible()
      try await found.click()
      try await expect(field.locator("input[name='lexico-record']")).toHaveValue(word.recordID)
      let tree = form.locator(".submit-sentiment-tree")
      try await expect(tree.locator(".outliner-view"), timeout: .seconds(15)).toHaveCount(1)
      let frozen = form.locator(".submit-sentiment-apparatus .record-choice-apparatus")
      try await expect(frozen).toContainText(word.title)
      try await expect(form.locator("input[name='title']")).toHaveCount(0)
      try await expect(field.locator(".submission-tree-view")).toHaveCount(0)
      try await expect(form.locator("input[name='placement-version']")).toHaveCount(1)
      try await shoot(page, "picked", layout)
      try await Task.sleep(for: .milliseconds(900))
      try await expect(field.locator("input[name='lexico-record']")).toHaveValue(word.recordID)
      try await expect(tree.locator(".outliner-view")).toHaveCount(1)

      // Unset: the typed fields back as they were left, the tree a new
      // record's.
      try await dropdown.locator(".dropdown-trigger").click()
      try await dropdown.locator(".dropdown-option.is-selected").first.click()
      try await expect(dropdown.locator(".dropdown-selected-text")).toHaveText("New record")
      try await expect(form.locator("input[name='title']")).toHaveValue("\(word.title)s")
      try await expect(form.locator("#language")).toHaveValue("eng")
      try await expect(frozen).toHaveCount(0)
      try await expect(tree.locator(".outliner-view"), timeout: .seconds(15)).toHaveCount(0)
      try await expect(tree.locator("[data-submission-draft='true']")).toHaveCount(1)
      try await expect(form.locator("input[name='placement-version']")).toHaveCount(0)
    }
  }

  /// A refresh the typed title asks for, landing while the record field's
  /// dropdown is open, waits for it to close: redrawing the field closed the
  /// menu mid-choice. The slot is busy until the waiting answer is put in.
  @Test(arguments: gnorium.engines)
  func aRefreshWaitsForTheOpenDropdown(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine), cookies: [admin.cookie]) {
        page in
        try await page.openHydrated(Self.path)
        let field = page.locator(".submit-sentiment-form .record-choice-field-view")
        let slot = field.locator(".record-choice-field-slot")
        let dropdown = field.locator(".dropdown-view")
        try await expect(slot, timeout: .seconds(20)).toHaveAttribute("aria-busy", "false")
        // The field as drawn now, marked; each record-choice answer counted
        // once its callback has run.
        _ = try await slot.evaluate(
          """
          (slot) => {
            slot.firstElementChild.dataset.drawn = 'before';
            window.recordChoiceAnswers = 0;
            const fetched = window.fetch;
            window.fetch = (...args) => fetched(...args).then((response) => {
              if (!String(args[0]).includes('record-choice')) return response;
              const text = response.text.bind(response);
              response.text = () => text().then((html) => {
                setTimeout(() => { window.recordChoiceAnswers += 1; }, 0);
                return html;
              });
              return response;
            });
            return true;
          }
          """)
        try await dropdown.locator(".dropdown-trigger").click()
        let menu = dropdown.locator(".dropdown-menu")
        try await expect(menu).toHaveAttribute("data-open", "true")
        // Typed with no click, which would close the menu.
        _ = try await page.evaluate(
          """
          (() => {
            const title = document.querySelector(".submit-sentiment-form input[name='title']");
            title.value = 'refreshwhileopen';
            title.dispatchEvent(new Event('input', { bubbles: true }));
          })()
          """)
        try await expect(slot).toHaveAttribute("aria-busy", "true")
        let landed = try await slot.evaluate(
          """
          () => new Promise((resolve) => {
            const started = Date.now();
            const poll = () => {
              if (window.recordChoiceAnswers > 0) return setTimeout(() => resolve(true), 200);
              if (Date.now() - started > 20000) return resolve(false);
              setTimeout(poll, 50);
            };
            poll();
          })
          """, timeout: .seconds(25)).bool
        #expect(landed == true, "The typed title's answer landed")
        // Landed and waiting: the menu open, the field as it was, still busy.
        try await expect(menu).toHaveAttribute("data-open", "true")
        try await expect(slot.locator(":scope > [data-drawn='before']")).toHaveCount(1)
        try await expect(slot).toHaveAttribute("aria-busy", "true")
        // Closed: the waiting answer is put in, and the slot is no longer busy.
        try await dropdown.locator(".dropdown-trigger").click()
        try await expect(slot).toHaveAttribute("aria-busy", "false")
        try await expect(slot.locator(":scope > [data-drawn='before']")).toHaveCount(0)
        try await expect(field.locator(".dropdown-menu")).toHaveAttribute("data-open", "false")
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }

  private func shoot(_ page: Page, _ name: String, _ layout: Layout) async throws {
    guard let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"] else { return }
    try await page.screenshot(to: URL(fileURLWithPath: directory).appendingPathComponent("sentiment-\(layout)-\(name).png"))
  }
}
