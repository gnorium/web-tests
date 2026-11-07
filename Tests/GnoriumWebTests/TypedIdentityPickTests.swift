import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A record typed where its record field stands that is exactly one
/// record picks that record in the field, as the person's own pick (user,
/// 2026-11-05): a bibliographic Origin step by its Title, Language, Class and
/// voice names; a lexicographic one by its Title, Language and Class; a Source box by
/// its Title, Language and Class with no URL and no record. Exactly: the
/// title byte for byte the record's, never its case aside; typed so but
/// for its case, nothing is picked. Never cut at the field's search limit:
/// records alike but for their case that fill its list never hide the
/// exact one. A pick the person unsets stays unset until the identity
/// changes again. A throwaway admin owns scratch records, removed after.
@Suite("Typed identity picks its record", .serialized)
struct TypedIdentityPickTests {
  @Test(arguments: gnorium.engines)
  func anOriginStepTypedExactlyPicksItsRecord(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine), cookies: [admin.cookie]) {
        page in
        try await page.openHydrated("/mission-control/submit/bibliographic/testament")
        let row = page.locator(".origin-field-view [data-origin-row='true']").first
        let key = try await row.getAttribute("data-origin-key") ?? ""
        let record = row.locator(".origin-field-record input[name='\(key)-record']")
        let typed = row.locator(".origin-field-typed[data-origin-typed='true']")
        let title = row.locator("#\(key)-title")
        // Its record field asked for and come.
        try await expect(record).toHaveCount(1)
        try await expect(record).toHaveValue("")

        // The work's identity but for its title's case: nothing picked.
        let voices = row.locator(
          ".origin-field-typed > .form-items-view [data-item-section='true']:not([data-item-template] *)")
        try await voices.first.locator(".text-input-input").fill(work.author)
        try await Self.choose(row.locator(".dropdown-view:has(#\(key)-language)"), "eng", searching: "English")
        try await Self.choose(row.locator(".dropdown-view:has(#\(key)-type)"), "report", searching: "Report")
        try await title.fill(work.title.lowercased())
        try await Task.sleep(for: .milliseconds(1500))
        try await expect(record).toHaveValue("")
        try await expect(typed).toBeVisible()

        // Exactly the work's: picked as a pick is, its typed fields set
        // aside, the field naming it.
        try await title.fill(work.title)
        try await expect(record).toHaveValue(work.recordID)
        try await expect(typed).toBeHidden()
        try await expect(row.locator(".origin-field-record .dropdown-selected-text").first).toContainText(work.title)

        // Unset by the person: the typed fields back, as typed, and the
        // record not picked again over them.
        let picker = row.locator(".origin-record-field-view .dropdown-view").first
        try await picker.locator(".dropdown-trigger").click()
        let chosen = picker.locator(".dropdown-option[data-value='\(work.recordID)']").first
        try await expect(chosen).toBeVisible()
        try await chosen.click()
        try await expect(typed).toBeVisible()
        try await expect(title).toHaveValue(work.title)
        try await Task.sleep(for: .milliseconds(1500))
        try await expect(record).toHaveValue("")
        try await page.expectNoErrors()
      }
    } catch {
      work.remove()
      try await admin.remove(after: error)
    }
    work.remove()
    try await admin.remove()
  }

  @Test(arguments: gnorium.engines)
  func aSourcelessSourceTypedExactlyPicksItsRecord(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine), cookies: [admin.cookie]) {
        page in
        try await page.openHydrated("/mission-control/submit/lexicographic/sentiment")
        let source = page.locator(".submit-sentiment-form .quote-sources-view .quote-source").first
        let record = source.locator(".quote-passage-record input[name='quote-s1-record']")
        let own = source.locator(".quote-passage-own")
        let title = source.locator("input[name='quote-s1-source-url-title']")
        try await expect(record, timeout: .seconds(15)).toHaveCount(1)
        try await expect(record).toHaveValue("")

        // No URL, no record: the work's identity but for its title's case
        // picks nothing.
        try await Self.choose(
          source.locator(".dropdown-view:has(#quote-s1-source-url-language)"), "eng", searching: "English")
        try await Self.choose(
          source.locator(".dropdown-view:has(#quote-s1-source-url-class)"), "report", searching: "Report")
        try await title.fill(work.title.lowercased())
        try await Task.sleep(for: .milliseconds(1500))
        try await expect(record).toHaveValue("")
        try await expect(own).toBeVisible()

        // Exactly the work's: picked, its typed fields set aside.
        try await title.fill(work.title)
        try await expect(record).toHaveValue(work.recordID)
        try await expect(own).toBeHidden()
        try await page.expectNoErrors()
      }
    } catch {
      work.remove()
      try await admin.remove(after: error)
    }
    work.remove()
    try await admin.remove()
  }

  @Test(arguments: gnorium.engines)
  func aWordStepTypedExactlyPicksItsRecord(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine), cookies: [admin.cookie]) {
        page in
        try await page.openHydrated("/mission-control/submit/lexicographic/sentiment")
        let row = page.locator(".origin-field-view [data-origin-row='true']").first
        let key = try await row.getAttribute("data-origin-key") ?? ""
        let record = row.locator(".origin-field-record input[name='\(key)-record']")
        let typed = row.locator(".origin-field-typed[data-origin-typed='true']")
        // A word's title is posted as its form.
        let title = row.locator("#\(key)-form")
        try await expect(record).toHaveCount(1)
        try await expect(record).toHaveValue("")

        // The word's title and language exactly, with no class: nothing
        // picked (user, 2026-11-05: a word's identity takes its class, as
        // Submit Sentiment's pre-select does).
        try await Self.choose(row.locator(".dropdown-view:has(#\(key)-language)"), "eng", searching: "English")
        try await title.fill(word.title)
        try await Task.sleep(for: .milliseconds(1500))
        try await expect(record).toHaveValue("")
        try await expect(typed).toBeVisible()

        // The word's identity but for its title's case: nothing picked.
        try await title.fill(word.title.uppercased())
        try await Self.choose(row.locator(".dropdown-view:has(#\(key)-type)"), "noun", searching: "Noun")
        try await Task.sleep(for: .milliseconds(1500))
        try await expect(record).toHaveValue("")
        try await expect(typed).toBeVisible()

        // Exactly the word's, no voices typed (a word has none to type):
        // picked as a pick is, its typed fields set aside, the field naming
        // it.
        try await title.fill(word.title)
        try await expect(record).toHaveValue(word.recordID)
        try await expect(typed).toBeHidden()
        try await expect(row.locator(".origin-field-record .dropdown-selected-text").first).toContainText(word.title)
        try await page.expectNoErrors()
      }
    } catch {
      word.remove()
      try await admin.remove(after: error)
    }
    word.remove()
    try await admin.remove()
  }

  /// A title typed in either Unicode encoding of its letters is the same
  /// title (user, 2026-11-05: NFC everywhere titles are compared): typed
  /// with an e and a combining acute, the word stored with a precomposed é
  /// is picked, the browser putting the typed text in NFC
  /// (`stringNormalize`) as the server stores titles.
  @Test(arguments: gnorium.engines)
  func aWordTypedInEitherEncodingPicksItsRecord(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let suffix = String(UUID().uuidString.prefix(8)).lowercased()
    let word = try ScratchWord(owner: admin, title: "webtestscaf\u{E9}\(suffix)")
    do {
      // Stored as the server stores a title, in NFC (`TestAdmin.query`
      // writes text beyond ASCII byte for byte).
      #expect(
        try TestAdmin.query("SELECT (title IS NFC NORMALIZED)::text FROM lexico_records WHERE id = '\(word.recordID)'")
          == "true", "the scratch word's title is not stored in NFC")
      try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine), cookies: [admin.cookie]) {
        page in
        try await page.openHydrated("/mission-control/submit/lexicographic/sentiment")
        let row = page.locator(".origin-field-view [data-origin-row='true']").first
        let key = try await row.getAttribute("data-origin-key") ?? ""
        let record = row.locator(".origin-field-record input[name='\(key)-record']")
        try await Self.choose(row.locator(".dropdown-view:has(#\(key)-language)"), "eng", searching: "English")
        try await Self.choose(row.locator(".dropdown-view:has(#\(key)-type)"), "noun", searching: "Noun")
        try await row.locator("#\(key)-form").fill("webtestscafe\u{301}\(suffix)")
        try await expect(record).toHaveValue(word.recordID)
        try await page.expectNoErrors()
      }
    } catch {
      word.remove()
      try await admin.remove(after: error)
    }
    word.remove()
    try await admin.remove()
  }

  /// More records alike but for their case than the field's search lists
  /// (its first 100, `PaginationView.perList`) never hide the exact one:
  /// the search for its title leaves the work out, and the work typed
  /// exactly is picked all the same.
  @Test(arguments: gnorium.engines)
  func anExactPickIsNeverCutAtTheSearchLimit(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    // Upper case sorts before the work's own title among titles alike but
    // for their case: 101 bare records fill the search's 100 first.
    let alike = work.title.uppercased()
    let removeAlike = { _ = try? TestAdmin.query("DELETE FROM biblio_records WHERE title = '\(alike)';") }
    do {
      _ = try TestAdmin.query(
        """
        BEGIN;
        \(ScratchWork.corpus)
        INSERT INTO biblio_records (id, corpus_id, title, title_slug, type, language, genres, year, date_display, created_at, updated_at)
          SELECT gen_random_uuid(), \(ScratchWork.corpusID), '\(alike)', 'web-tests-placement-\(work.suffix)',
            'report', 'eng', '[]', 1958, 'AD 1958', now(), now()
          FROM generate_series(1, 101);
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine), cookies: [admin.cookie]) {
        page in
        try await page.openHydrated("/mission-control/submit/bibliographic/testament")
        let searched = try await page.evaluate(
          "fetch('/mission-control/record-choices/biblio-record/options?q=' + encodeURIComponent('\(work.title)'))"
            + ".then((r) => r.text())",
          as: String.self)
        #expect(searched.contains("Showing the first 100."))
        #expect(!searched.contains("data-value=\"\(work.recordID)\""), "the search lists the work: past its 100?")

        let row = page.locator(".origin-field-view [data-origin-row='true']").first
        let key = try await row.getAttribute("data-origin-key") ?? ""
        let record = row.locator(".origin-field-record input[name='\(key)-record']")
        try await expect(record).toHaveCount(1)
        try await expect(record).toHaveValue("")
        let voices = row.locator(
          ".origin-field-typed > .form-items-view [data-item-section='true']:not([data-item-template] *)")
        try await voices.first.locator(".text-input-input").fill(work.author)
        try await Self.choose(row.locator(".dropdown-view:has(#\(key)-language)"), "eng", searching: "English")
        try await Self.choose(row.locator(".dropdown-view:has(#\(key)-type)"), "report", searching: "Report")
        try await row.locator("#\(key)-title").fill(work.title)
        try await expect(record).toHaveValue(work.recordID)
        try await expect(row.locator(".origin-field-typed[data-origin-typed='true']")).toBeHidden()
        try await page.expectNoErrors()
      }
    } catch {
      removeAlike()
      work.remove()
      try await admin.remove(after: error)
    }
    removeAlike()
    work.remove()
    try await admin.remove()
  }

  /// A dropdown's option chosen: opened, searched where it has a search,
  /// the visible option clicked.
  private static func choose(_ dropdown: Locator, _ value: String, searching name: String) async throws {
    try await dropdown.locator(".dropdown-trigger").click()
    let search = dropdown.locator(".dropdown-search-input .search-input")
    if try await search.count() > 0 { try await search.fill(name) }
    try await dropdown.locator(".dropdown-option[data-value='\(value)']").filter(visible: true).first.click()
  }
}
