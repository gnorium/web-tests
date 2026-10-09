import Foundation
import Testing
import WebTests
import WebTestsTesting

/// What a transcript encodes opens a gloss (user, 2026-09-29, 2026-10-08):
/// in the testament reader and in an utterance, a click, a tap, or Enter on
/// a focused word opens a sheet over the ordinance pane only—as the ellipsis
/// menu's, a blurred backdrop and a panel filling the pane—headed by the
/// record as the search menu offers one ("English › title", its class under
/// it, linked; no separate link to it), then the Term at full width, one
/// datum a row (as printed, lemma linked to the record, class and language
/// plain, each morphological feature its own row, spelled out), then the
/// Lexico-record read at a glance: its Origin, its sentiments laid open
/// without utterances, the word's own emphasized with its Translations open
/// (each linked). A word with no link is its own data, headed by itself and
/// its class, with no Lexico-record. What is no word but encoded (a running
/// head's page number, a gap) opens its own. Esc closes it and what was
/// opened has the focus again; the arrow keys move between a page's words.
/// Phone and desktop, nothing scrolling sideways. A throwaway admin owns a
/// scratch work with a permitted testament and a scratch word linked from
/// it, made by SQL and removed after.
@Suite("Glosses", .serialized)
struct GlossTests {
  static let service = "https://example.org/iiif/webtests-words"
  static let tei = """
    <TEI><text><body><pb n="1" facs="\(service)/full/1300,/0/default.jpg"/>\
    <p><s><w lemma="the" type="article" msd="Definite=Def|PronType=Art">The</w> \
    <w lemma="scratchword" type="noun" msd="Number=Plur">scratchwords</w> \
    <w lemma="stand" type="verb" msd="Tense=Past">stood</w><pc>.</pc></s></p><fw type="pageNum">12</fw>\
    </body></text></TEI>
    """

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWordOpensItsRecordAtAGlance(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    var testament: ScratchTestament?
    var words: [ScratchWord] = []
    func clean() async throws {
      if let testament {
        _ = try? TestAdmin.query("DELETE FROM word_lemma_refs WHERE version_id = '\(testament.versionID)';")
      }
      for word in words { word.remove() }
      testament?.remove()
      try await admin.remove()
    }
    do {
      let scratch = try ScratchTestament(owner: admin, tei: Self.tei)
      testament = scratch
      let german = try ScratchWord(owner: admin, language: "deu")
      words.append(german)
      // Attested in the testament, at the word the link puts to its leaf.
      let english = try ScratchWord(
        owner: admin,
        anchor: .init(
          recordID: scratch.reading.work.recordID, versionID: scratch.versionID, canvasID: Self.service, page: 1,
          line: 1, word: 2, surface: "scratchwords"))
      words.append(english)
      _ = try TestAdmin.query(
        """
        BEGIN;
        UPDATE lexico_record_versions SET record_json = jsonb_set(record_json::jsonb, '{senses,1,translations}',
            '[{"form":"\(german.title)","languageCode":"deu","recordPath":"\(german.path)#record-row-s-1-1","equivalence":"broader"}]')::text
          WHERE id = '\(english.versionID.lowercased())';
        INSERT INTO word_lemma_refs (id, biblio_record_id, version_id, canvas_id, page, start_line, start_word,
            start_surface, end_line, end_word, end_surface, surface, lexico_record_id, sentiment_id, antedates, created_at)
          VALUES (gen_random_uuid(), '\(scratch.reading.work.recordID.lowercased())', '\(scratch.versionID)',
            '\(Self.service)', 1, 1, 2, 'scratchwords', 1, 2, 'scratchwords', 'scratchwords',
            '\(english.recordID.lowercased())', 's-1-1', false, now());
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        // The testament reader, fetched into its row.
        try await page.openHydrated(scratch.reading.work.path)
        _ = try await page.evaluate(
          """
          (() => { document.querySelector("[data-reader-url*='\(scratch.versionID)' i]").closest('.record-row')
            .querySelector(':scope > .accordion-details > .accordion-summary').click(); return true; })()
          """)
        let reader = page.locator(".artifact-view .tei-view").first
        let linked = reader.locator(".tei-word[data-line='1'][data-word='2']")
        try await expect(linked).toHaveText("scratchwords")
        // One stop in the tab order: the page's first word.
        try await expect(reader.locator(".tei-word[tabindex='0']")).toHaveTexts(["The"])

        try await linked.click()
        let sheet = page.locator(".artifact-transcript .gloss-sheet")
        try await expect(sheet).toHaveAttribute("data-state", "open")
        // Over the ordinance pane only: the pane holds it, the semblance and
        // the page's chrome stay outside it.
        let pane = page.locator(".artifact-transcript").first
        try await expect(pane.locator(".gloss-sheet")).toHaveCount(1)
        // Once the panel has slid in (the ellipsis menu's motion), it is the
        // pane's visible box: its padding box, its border aside.
        let covers = try await pane.evaluate(
          """
          async (el) => {
            await new Promise((r) => setTimeout(r, 400));
            const p = el.getBoundingClientRect(), s = el.querySelector('.gloss-sheet .sheet-panel').getBoundingClientRect();
            return Math.abs(s.top - p.top) <= 1 && Math.abs(s.left - p.left) <= 1
              && Math.abs(s.height - el.clientHeight) <= 1 && Math.abs(s.width - el.clientWidth) <= 1;
          }
          """)
        #expect(covers.bool == true, "the gloss does not cover the ordinance pane")
        // The title is the record, as the search menu offers one, linked.
        let title = sheet.locator(".gloss-sheet-title")
        try await expect(title.locator(".breadcrumb-label-context")).toHaveText("English")
        try await expect(title.locator(".breadcrumb-label-text")).toHaveText(english.title)
        try await expect(title.locator("a.record-label-title")).toHaveAttribute("href", english.path)
        try await expect(title.locator(".record-label-meta")).toHaveText("Noun")
        let details = sheet.locator(".gloss-view")
        try await expect(details.locator("a").filter(hasText: "View English")).toHaveCount(0)
        // The Term, full width, one datum a row, its values linked.
        let term = details.locator(".metadata-group-view").first
        try await expect(term.locator(".metadata-group-title")).toHaveText("Term")
        try await expect(term.locator(".datum-label")).toHaveTexts([
          "As printed", "Lemma", "Class", "Number", "Language",
        ])
        try await expect(term.locator(".datum-value")).toHaveTexts([
          "scratchwords", "scratchword", "Noun", "Plural", "English",
        ])
        // Only the lemma links, to the record; class and language are plain.
        try await expect(term.locator(".datum-value a")).toHaveCount(1)
        try await expect(term.locator(".datum-value a")).toHaveAttribute("href", english.path)
        let rows = try await term.locator(".datum-view").first.evaluate(
          "(el) => { const p = el.parentElement.getBoundingClientRect(), r = el.getBoundingClientRect(); return Math.abs(p.width - r.width) <= 1 }")
        #expect(rows.bool == true, "a datum is not full width")
        // The Lexico-record at a glance.
        try await expect(details.locator(".metadata-group-title").filter(hasText: "Lexico-record")).toHaveCount(1)
        try await expect(details.locator(".record-title")).toHaveCount(0)
        try await expect(details.locator("#origin .origin-view")).toHaveText("—")
        try await expect(details.locator(".record-row-title")).toHaveTexts(["A branch sense.", "A leaf sense."])
        let current = details.locator(".record-row-title[data-current='true']")
        try await expect(current).toHaveText("A leaf sense.")
        try await expect(current).toHaveCSS("font-weight", "600")
        // No utterances; the page's own row ids are never reused.
        try await expect(details.locator(".attestation-view")).toHaveCount(0)
        try await expect(details.locator("#record-row-s-1-1")).toHaveCount(0)
        // The word's sentiment's Translations, open, each linked.
        let translation = details.locator(".lexicographic-translations-view a").filter(hasText: german.title)
        try await expect(translation).toBeVisible()
        try await expect(translation).toHaveAttribute("href", "\(german.path)#record-row-s-1-1")
        try await page.expectNoHorizontalOverflow()

        // Closed by a click, the word has the focus again, with no focus
        // ring; the reader under it where it was.
        try await sheet.locator(".dialog-sheet-close").first.click()
        try await expect(sheet).toHaveAttribute("data-state", "closed")
        try await expect(linked).toBeFocused()
        try await expect(linked).toHaveCSS("outline-style", "none")

        // From the keyboard: the arrow keys move between the page's words,
        // Enter opens one. A word with no link is its own data alone.
        try await linked.press("ArrowRight")
        let stood = reader.locator(".tei-word[data-line='1'][data-word='3']")
        try await expect(stood).toBeFocused()
        // From the keyboard, the focus ring every control has.
        try await expect(stood).toHaveCSS("outline-style", "solid")
        try await expect(stood).toHaveAttribute("tabindex", "0")
        try await page.keyboard.press("Enter")
        try await expect(sheet).toHaveAttribute("data-state", "open")
        try await expect(title.locator(".record-label-title")).toHaveText("stood")
        try await expect(title.locator(".record-label-meta")).toHaveText("Verb")
        try await expect(title.locator("a")).toHaveCount(0)
        try await expect(details.locator(".metadata-group-view").first.locator(".datum-value")).toHaveTexts([
          "stood", "stand", "Verb", "Past", "English",
        ])
        try await expect(details.locator(".record-view")).toHaveCount(0)
        try await expect(details.locator(".metadata-group-title").filter(hasText: "Lexico-record")).toHaveCount(0)
        // Tab stays inside while it is open.
        for _ in 0..<3 { try await page.keyboard.press("Tab") }
        let inside = try await page.evaluate(
          "!!document.activeElement.closest('.dialog-sheet-content')")
        #expect(inside == .bool(true))
        // Esc closes it; from the keyboard, the word's focus ring shows.
        try await page.keyboard.press("Escape")
        try await expect(sheet).toHaveAttribute("data-state", "closed")
        try await expect(stood).toBeFocused()
        try await expect(stood).toHaveCSS("outline-style", "solid")
        // What is no word but encoded opens its own: the running head's
        // page number.
        let folio = reader.locator("[data-gloss-element]").filter(hasText: "12").first
        try await folio.click()
        try await expect(sheet).toHaveAttribute("data-state", "open")
        try await expect(title.locator(".record-label-title")).toHaveText("Page number")
        try await expect(title.locator(".record-label-meta")).toHaveText("12")
        try await expect(details.locator(".datum-label")).toHaveTexts(["Page number"])
        try await page.keyboard.press("Escape")
        try await expect(sheet).toHaveAttribute("data-state", "closed")
        // The scratch work's manifest (example.org) is never reachable.
        try await page.expectNoErrors(ignoring: ["Failed to fetch"])

        // The gloss's address answers JSON too: its data and the same body.
        let json = try await page.evaluate(
          """
          fetch('\(scratch.reading.work.path)/testaments/\(scratch.versionID)/glosses?semblance='
            + encodeURIComponent('\(Self.service)') + '&line=1&word=2', { headers: { Accept: 'application/json' } })
            .then(r => r.json())
            .then(j => [j.surface, j.lemma, j.type, j.morphology, j.record.title, j.sentiment.id,
              j.equivalents[0].form, j.equivalents[0].relation, j.html.includes('gloss-view'), j.data[0].label].join('|'))
          """)
        #expect(json == .string("scratchwords|scratchword|Noun|Number: Plural|\(english.title)|s-1-1|\(german.title)|broader sense|true|As printed"))

        // A word inside an utterance opens the utterance's gloss, over the
        // utterance's box, as a word of a phrase opens the phrase's (user,
        // 2026-10-09): its testament's Chicago note, then its words, the
        // word clicked expanded with its own gloss's rows and its record.
        try await page.openHydrated(english.path)
        try await page.locator("#record-row-s-1-1 > .accordion-summary").click()
        let utterance = page.locator("#record-row-s-1-1 .utterance-view")
        let word = utterance.locator(".tei-word").filter(hasText: "scratchwords")
        try await expect(word).toHaveCount(1)
        try await word.click()
        let again = utterance.locator(".gloss-sheet[data-state='open']")
        try await expect(again).toHaveCount(1)
        // Headed by the utterance's words alone: no meta row.
        try await expect(again.locator(".gloss-sheet-title .record-label-title")).toHaveText("scratchwords")
        try await expect(again.locator(".gloss-sheet-title .record-label-meta")).toHaveCount(0)
        let work = scratch.reading.work
        try await expect(again.locator(".chicago-citation-view")).toHaveText("\(work.author), \(work.title) (1958), 1.")
        let wordRows = again.locator(".gloss-word-row")
        try await expect(wordRows).toHaveCount(3)
        let opened = wordRows.filter(hasText: "scratchwords")
        let open = try await opened.evaluate("(row) => row.querySelector('.accordion-details').hasAttribute('open')")
        #expect(open == .bool(true), "the word clicked is not expanded")
        try await expect(opened.locator(".gloss-word")).toContainText("scratchword")
        try await expect(opened.locator(".gloss-word")).toContainText(english.title)
        try await page.expectNoHorizontalOverflow()
        try await page.keyboard.press("Escape")
        try await expect(page.locator(".gloss-sheet[data-state='open']")).toHaveCount(0)
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
