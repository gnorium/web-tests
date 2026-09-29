import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A word inside a phrase (`<phr>`) opens the phrase first (user,
/// 2026-09-29): the phrase as written for the title, its type and lemma, the
/// record a link over its words puts it to at a glance, then Words, each word
/// an accordion, the one opened expanded. Phone and desktop, nothing
/// scrolling sideways. Scratch rows made and removed by SQL.
@Suite("Word phrases", .serialized)
struct WordPhraseTests {
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
    func clean() async {
      if let testament {
        _ = try? TestAdmin.query("DELETE FROM word_lemma_refs WHERE version_id = '\(testament.versionID)';")
      }
      idiom?.remove()
      testament?.remove()
      await admin.remove()
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
        let dialog = page.locator(".word-details-dialog")
        try await expect(dialog).toBeVisible()
        try await expect(dialog.locator(".dialog-header-title")).toHaveText("kicked the bucket")
        let details = dialog.locator(".word-details-view")
        try await expect(details.locator(".word-details-view-word").first.locator(".datum-value")).toHaveTexts([
          "Idiom", "kick the bucket",
        ])
        try await expect(details.locator(".record-title")).toHaveText(word.title)
        try await expect(details.locator(".record-row-title[data-current='true']")).toHaveText("A leaf sense.")
        // Its words, the one opened expanded.
        let rows = details.locator(".word-details-view-word-row")
        try await expect(rows).toHaveCount(3)
        try await expect(rows.locator(".accordion-summary")).toHaveTexts(["kicked", "the", "bucket"])
        try await expect(rows.nth(1).locator(".word-details-view-word")).toBeVisible()
        try await expect(rows.nth(0).locator(".word-details-view-word")).toBeHidden()
        try await expect(rows.nth(1).locator(".datum-value")).toHaveTexts(["the", "Article", "—", "—"])
        try await page.expectNoHorizontalOverflow()
        try await page.keyboard.press("Escape")
        try await expect(dialog).toBeHidden()
        try await page.expectNoErrors(ignoring: ["Failed to fetch"])
      }
    } catch {
      await clean()
      throw error
    }
    await clean()
  }
}
