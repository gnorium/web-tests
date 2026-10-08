import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A word inside a phrase (`<phr>`) opens the phrase's gloss first (user,
/// 2026-09-29, 2026-10-08): headed by the record a link over its words puts
/// it to, linked; its Term (as printed, lemma, class, language); the record
/// at a glance; then Words, each word an accordion with every row of its own
/// gloss, the one opened expanded. Phone and desktop, nothing
/// scrolling sideways. Scratch rows made and removed by SQL.
@Suite("Gloss phrases", .serialized)
struct GlossPhraseTests {
  static let idiomService = "https://example.org/iiif/webtests-phrase"
  static let idiomTEI = """
    <TEI><text><body><pb n="1" facs="\(idiomService)/full/1300,/0/default.jpg"/>\
    <p><s><w lemma="he" type="pronoun">He</w> <phr type="idiom" lemma="kick the bucket">\
    <w lemma="kick" type="verb" msd="Tense=Past">kicked</w> <w lemma="the" type="article">the</w> \
    <w lemma="bucket" type="noun">bucket</w></phr><pc>.</pc></s></p></body></text></TEI>
    """

  /// A word inside a phrase opens the phrase first: its type and lemma and
  /// the record a link over its words puts it to, then Words, each word an
  /// accordion, the one opened expanded.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWordOfAPhraseOpensThePhrase(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    var testament: ScratchTestament?
    var idiom: ScratchWord?
    func clean() async throws {
      if let testament {
        _ = try? TestAdmin.query("DELETE FROM word_lemma_refs WHERE version_id = '\(testament.versionID)';")
      }
      idiom?.remove()
      testament?.remove()
      try await admin.remove()
    }
    do {
      let scratch = try ScratchTestament(owner: admin, tei: Self.idiomTEI)
      testament = scratch
      let word = try ScratchWord(owner: admin)
      idiom = word
      _ = try TestAdmin.query(
        """
        INSERT INTO word_lemma_refs (id, biblio_record_id, version_id, canvas_id, page, start_line, start_word,
            start_surface, end_line, end_word, end_surface, surface, lexico_record_id, sentiment_id, antedates, created_at)
          VALUES (gen_random_uuid(), '\(scratch.reading.work.recordID.lowercased())', '\(scratch.versionID)',
            '\(Self.idiomService)', 1, 1, 2, 'kicked', 1, 4, 'bucket', 'kicked the bucket',
            '\(word.recordID.lowercased())', 's-1-1', false, now());
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(scratch.reading.work.path)
        _ = try await page.evaluate(
          """
          (() => { document.querySelector("[data-reader-url*='\(scratch.versionID)' i]").closest('.record-row')
            .querySelector(':scope > .accordion-details > .accordion-summary').click(); return true; })()
          """)
        let reader = page.locator(".artifact-view .tei-view").first
        try await reader.locator(".tei-word[data-line='1'][data-word='3']").click()
        let sheet = page.locator(".artifact-transcript .gloss-sheet")
        try await expect(sheet).toHaveAttribute("data-state", "open")
        let heading = sheet.locator(".gloss-sheet-heading")
        try await expect(heading.locator(".breadcrumb-label-text")).toHaveText(word.title)
        try await expect(heading.locator("a.record-label-title")).toHaveAttribute("href", word.path)
        let details = sheet.locator(".gloss-view")
        let term = details.locator(".metadata-group-view").first
        try await expect(term.locator(".datum-label")).toHaveTexts(["As printed", "Lemma", "Class", "Language"])
        try await expect(term.locator(".datum-value")).toHaveTexts([
          "kicked the bucket", "kick the bucket", "Idiom", "English",
        ])
        try await expect(details.locator(".record-row-title[data-current='true']")).toHaveText("A leaf sense.")
        // Its words, the one opened expanded, each with its own gloss.
        let rows = details.locator(".gloss-word-row")
        try await expect(rows).toHaveCount(3)
        try await expect(rows.locator(".accordion-summary")).toHaveTexts(["kicked", "the", "bucket"])
        try await expect(rows.nth(1).locator(".gloss-word")).toBeVisible()
        try await expect(rows.nth(0).locator(".gloss-word")).toBeHidden()
        try await expect(rows.nth(1).locator(".datum-label")).toHaveTexts([
          "As printed", "Lemma", "Class", "Morphology", "Language", "Phrase", "Phrase lemma", "Phrase type",
          "Lexico-record",
        ])
        try await expect(rows.nth(1).locator(".datum-value")).toHaveTexts([
          "the", "the", "Article", "—", "English", "kicked the bucket", "kick the bucket", "Idiom", "—",
        ])
        try await page.expectNoHorizontalOverflow()
        try await page.keyboard.press("Escape")
        try await expect(sheet).toHaveAttribute("data-state", "closed")
        try await page.expectNoErrors(ignoring: ["Failed to fetch"])
      }
    } catch {
      do { try await clean() } catch let removal {
        throw WebTestError("\(error)\n…and cleaning up failed too: \(removal)")
      }
      throw error
    }
    try await clean()
  }
}
