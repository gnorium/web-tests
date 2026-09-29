import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A word of a transcript opens what it is (user, 2026-09-29): in the
/// testament reader and in an utterance, a click, a tap, or Enter on a
/// focused word opens a dialog as large as the screen over the reader — the
/// word as written, its lemma, part of speech and morphology, then the
/// lexico-record a word→sentiment link puts it to, read at a glance: its
/// language, title and type, its Origin, its sentiments laid open without
/// utterances, the word's own emphasized with its Translations open (each
/// linked), and "View English … (Noun)" to its page. A word with no link is
/// its own data, "—" for the rest. Esc closes it and the word has the focus
/// again; the arrow keys move between a page's words. Phone and desktop,
/// nothing scrolling sideways. A throwaway admin owns a scratch work with a
/// permitted testament and a scratch word linked from it, made by SQL and
/// removed after.
@Suite("Word details", .serialized)
struct WordDetailsTests {
  static let service = "https://example.org/iiif/webtests-words"
  static let tei = """
    <TEI><text><body><pb n="1" facs="\(service)/full/1300,/0/default.jpg"/>\
    <p><s><w lemma="the" type="article" msd="Definite=Def|PronType=Art">The</w> \
    <w lemma="scratchword" type="noun" msd="Number=Plur">scratchwords</w> \
    <w lemma="stand" type="verb" msd="Tense=Past">stood</w><pc>.</pc></s></p></body></text></TEI>
    """

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWordOpensItsRecordAtAGlance(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    var testament: ScratchTestament?
    var words: [ScratchWord] = []
    func clean() async {
      if let testament {
        _ = try? TestAdmin.query("DELETE FROM word_lemma_refs WHERE version_id = '\(testament.versionID)';")
      }
      for word in words { word.remove() }
      testament?.remove()
      await admin.remove()
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
        let dialog = page.locator(".word-details-dialog")
        try await expect(dialog).toBeVisible()
        try await expect(dialog.locator(".dialog-header-title")).toHaveText("scratchwords")
        let details = dialog.locator(".word-details-view")
        try await expect(details.locator(".word-details-view-word .datum-label")).toHaveTexts([
          "Lemma", "Type", "Morphology",
        ])
        try await expect(details.locator(".word-details-view-word .datum-value")).toHaveTexts([
          "scratchword", "Noun", "Number: Plural",
        ])
        // The record at a glance.
        try await expect(details.locator(".record-kind-label")).toHaveText("English")
        try await expect(details.locator(".record-title")).toHaveText(english.title)
        try await expect(details.locator(".record-type-view").first).toHaveText("Noun")
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
        let recordLink = details.locator(".word-details-view-link a")
        try await expect(recordLink).toHaveText("View English \(english.title) (Noun)")
        try await expect(recordLink).toHaveAttribute("href", english.path)
        // As large as the screen inside the backdrop's margin, on a phone and
        // a desktop alike.
        let screen = try #require(try await dialog.boundingBox())
        let shell = try #require(try await dialog.locator(".dialog-shell").boundingBox())
        #expect(shell.width >= screen.width - 2 * 16 - 1)
        #expect(shell.height >= screen.height - 2 * 16 - 1)
        try await page.expectNoHorizontalOverflow()

        // Closed by a click, the word has the focus again, with no focus
        // ring; the reader under it where it was.
        try await dialog.locator(".dialog-close-button").first.click()
        try await expect(dialog).toBeHidden()
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
        try await expect(dialog).toBeVisible()
        try await expect(dialog.locator(".dialog-header-title")).toHaveText("stood")
        try await expect(details.locator(".word-details-view-word .datum-value")).toHaveTexts([
          "stand", "Verb", "Tense: Past",
        ])
        try await expect(details.locator(".record-view")).toHaveCount(0)
        try await expect(details.locator(".datum-view").filter(hasText: "Lexico-record")).toContainText("—")
        // Tab stays inside while it is open.
        for _ in 0..<3 { try await page.keyboard.press("Tab") }
        let inside = try await page.evaluate(
          "!!document.activeElement.closest('.word-details-dialog')")
        #expect(inside == .bool(true))
        // Esc closes it; from the keyboard, the word's focus ring shows.
        try await page.keyboard.press("Escape")
        try await expect(dialog).toBeHidden()
        try await expect(stood).toBeFocused()
        try await expect(stood).toHaveCSS("outline-style", "solid")
        // The scratch work's manifest (example.org) is never reachable.
        try await page.expectNoErrors(ignoring: ["Failed to fetch"])

        // The word's address answers JSON too: its data and the same body.
        let json = try await page.evaluate(
          """
          fetch('\(scratch.reading.work.path)/testaments/\(scratch.versionID)/words?semblance='
            + encodeURIComponent('\(Self.service)') + '&line=1&word=2', { headers: { Accept: 'application/json' } })
            .then(r => r.json())
            .then(j => [j.surface, j.lemma, j.type, j.morphology, j.record.title, j.sentiment.id,
              j.equivalents[0].form, j.equivalents[0].relation, j.html.includes('word-details-view')].join('|'))
          """)
        #expect(json == .string("scratchwords|scratchword|Noun|Number: Plural|\(english.title)|s-1-1|\(german.title)|broader sense|true"))

        // An utterance's words open the same dialog.
        try await page.openHydrated(english.path)
        try await page.locator("#record-row-s-1-1 > .accordion-summary").click()
        let utterance = page.locator("#record-row-s-1-1 .utterance-view")
        let word = utterance.locator(".tei-word").filter(hasText: "scratchwords")
        try await expect(word).toHaveCount(1)
        try await word.click()
        let again = page.locator(".word-details-dialog")
        try await expect(again).toBeVisible()
        try await expect(again.locator(".dialog-header-title")).toHaveText("scratchwords")
        try await expect(again.locator(".record-row-title[data-current='true']")).toHaveText("A leaf sense.")
        try await page.expectNoHorizontalOverflow()
        try await page.keyboard.press("Escape")
        try await expect(again).toBeHidden()
        try await page.expectNoErrors(ignoring: ["Failed to fetch"])
      }
    } catch {
      await clean()
      throw error
    }
    await clean()
  }
}
