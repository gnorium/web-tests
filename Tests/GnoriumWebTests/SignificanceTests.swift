import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Significance selection shown (user, 2026-09-28): a title's utterances on
/// the admins' page, each with why it was chosen (or "Not selected") and its
/// density features as plain datums; and an utterance on a record page with
/// the same datums under it. The selection rows are a scratch title's, made
/// by SQL (not stale, so the page reads them as kept) and removed after, as
/// are a throwaway admin, a scratch testament and a scratch word.
@Suite("Significance", .serialized)
struct SignificanceTests {
  static func anchor(versionID: String, recordID: String, canvas: String, page: Int, line: Int, word: Int, surface: String)
    -> String
  {
    #"{"biblioRecordID":"\#(recordID)","canvasID":"\#(canvas)","end":{"line":\#(line),"surface":"\#(surface)","word":\#(word)},"id":"u-\#(page)-\#(line)-\#(word)","page":\#(page),"start":{"line":\#(line),"surface":"\#(surface)","word":\#(word)},"versionID":"\#(versionID)"}"#
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aTitlesUtterancesShowWhyTheyAreSignificant(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    var testament: ScratchTestament?
    var word: ScratchWord?
    func clean() async {
      if let word {
        _ = try? TestAdmin.query("DELETE FROM significance_selections WHERE title = '\(word.title)';")
      }
      word?.remove()
      testament?.remove()
      await admin.remove()
    }
    do {
      let scratch = try ScratchTestament(owner: admin, tei: UtteranceTests.tei)
      testament = scratch
      let canvas = "https://example.org/iiif/webtests-p3"
      let scratchWord = try ScratchWord(
        owner: admin,
        anchor: .init(
          recordID: scratch.reading.work.recordID, versionID: scratch.versionID,
          canvasID: canvas, page: 3, line: 3, word: 3, surface: "scratchword"))
      word = scratchWord
      let chosen = Self.anchor(
        versionID: scratch.versionID, recordID: scratch.reading.work.recordID, canvas: canvas, page: 3, line: 3,
        word: 3, surface: "scratchword")
      let plain = Self.anchor(
        versionID: scratch.versionID, recordID: scratch.reading.work.recordID,
        canvas: "https://example.org/iiif/webtests-p1", page: 1, line: 1, word: 1, surface: "Page")
      let density = #"{"content_lemmas":["begin"],"contrast_markers":0,"density_version":"tei-sentence-density-v1","emphasis":0,"figurative":0,"headword_emphasized":false,"headword_frames":["term"],"lexical_density":0.5,"metalinguistic":{"gloss":0,"mentioned":0,"soCalled":0,"term":1},"nominalizations":0,"rarity_max":1.25,"rarity_mean":1.25,"sentence_type":"definition","subordination":0,"uncertain_lemmas":0}"#
      _ = try TestAdmin.query(
        """
        INSERT INTO significance_selections (id, language_code, title, type, forms_json, anchor_json, version_id, canvas_id,
          start_line, start_word, end_line, end_word, text, dated_year, density_json, reasons_json, new_collocates_json,
          stale, computed_at)
        VALUES
          ('\(UUID().uuidString.lowercased())', 'eng', '\(scratchWord.title)', 'noun', '[]', '\(chosen)',
            '\(scratch.versionID.lowercased())', '\(canvas)', 3, 3, 3, 3, 'Here the scratchword begins', 1901,
            '\(density)', '["definition","term","earliest"]', '["begin"]', false, now()),
          ('\(UUID().uuidString.lowercased())', 'eng', '\(scratchWord.title)', 'noun', '[]', '\(plain)',
            '\(scratch.versionID.lowercased())', 'https://example.org/iiif/webtests-p1', 1, 1, 1, 1,
            'Page 1, line 1.', 1901, NULL, '[]', '[]', false, now());
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        // The admins' page: every utterance of the title, why each was chosen.
        _ = try await page.goto(
          "/mission-control/lexicographic/significance?language=eng&title=\(scratchWord.title)&type=noun")
        let view = page.locator(".significant-utterances-view-content")
        try await expect(view.locator("h1")).toHaveText("Significant utterances")
        try await expect(view.locator(".significant-utterances-view-summary")).toContainText("1 of 2")
        let items = view.locator(".significant-utterances-view-item")
        try await expect(items).toHaveCount(2)
        // In reading order: page 1's line first, then the word on page 3.
        try await expect(items.first).toContainText("Not selected")
        try await expect(items.nth(1)).toContainText("Definition, Term, Earliest attestation")
        try await expect(items.nth(1)).toContainText("Lexical density")
        try await expect(items.nth(1)).toContainText("0.50")
        let overflow = try await page.evaluate("document.documentElement.scrollWidth > window.innerWidth").bool
        #expect(overflow == false)

        // The record page: the utterance, once fetched, shows the same datums.
        try await page.openHydrated(scratchWord.path)
        let row = page.locator("#record-row-s-1-1")
        try await page.locator("#record-row-s-1-1 > .accordion-summary").click()
        try await expect(row).toHaveAttribute("data-open-finished", "true")
        let density = row.locator(".attestation-view .utterance-density-view")
        try await expect(density).toHaveCount(1)
        try await expect(density).toContainText("Definition, Term, Earliest attestation")
        try await expect(density).toContainText("begin")
        let overflowRecord = try await page.evaluate("document.documentElement.scrollWidth > window.innerWidth").bool
        #expect(overflowRecord == false)
      }
    } catch {
      await clean()
      throw error
    }
    await clean()
  }
}
