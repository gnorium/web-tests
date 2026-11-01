import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A form's Source box selects its quote a sentence at a time (user,
/// 2026-11-01): in its text pane no word opens a gloss nor turns blue; the
/// sentence under the pointer is tinted violet and its lemma (the form's
/// title) magenta; a tap selects the sentence, which fills the Quote and
/// marks its words, its lemma as a quote's. The reader keeps its footer on
/// one row in the form's leaf node, the outline scrolling instead. A word
/// that opens a gloss carries no tooltip of its own (a tap opens the
/// gloss alone).
@Suite("Sentence selection")
struct SentenceSelectionTests {
  static let sentimentForm = "/mission-control/submit/lexicographic/sentiment"
  static let service = "https://example.org/iiif/webtests-sentence-selection"
  static let tei = """
    <TEI><text><body><pb n="1" facs="\(service)/full/1300,/0/default.jpg"/>\
    <p><s><w xml:id="w1.1" lemma="the" class="article">The</w> <w xml:id="w1.2" lemma="scratchword" class="noun">scratchwords</w> \
    <w xml:id="w1.3" lemma="stand" class="verb">stood</w><pc>.</pc></s> \
    <s><w xml:id="w1.4" lemma="they" class="pronoun">They</w> <w xml:id="w1.5" lemma="fall" class="verb"><choice><abbr>fel</abbr>\
    <expan>fell</expan></choice></w><pc>.</pc></s></p></body></text></TEI>
    """

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aTapSelectsTheSentence(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    var testament: ScratchTestament?
    do {
      let scratch = try ScratchTestament(owner: admin, tei: Self.tei)
      testament = scratch
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(Self.sentimentForm)
        let box = page.locator(".submit-sentiment-form .quote-source").first
        try await expect(box.locator(".quote-passage-record input[name='quote-s1-record']"), timeout: .seconds(15))
          .toHaveCount(1)
        // The record's title, then its source picked.
        _ = try await page.evaluate(
          """
          (() => { const title = document.querySelector(".submit-sentiment-form input[name='title']");
            if (title) { title.value = 'scratchword'; } return !!title; })()
          """)
        _ = try await box.evaluate(
          """
          (b) => { const input = b.querySelector("input[name='quote-s1-record']");
            input.value = '\(scratch.reading.work.recordID.lowercased())';
            input.dispatchEvent(new Event('change', { bubbles: true })); return true; }
          """)
        let words = box.locator(".quote-passage-reader .artifact-markup .tei-word")
        try await expect(words.first, timeout: .seconds(20)).toBeAttached()
        // Each word names its sentence; no tooltip inside a word.
        try await expect(box.locator(".quote-passage-reader .tei-word[data-sentence='0']")).toHaveCount(3)
        try await expect(box.locator(".quote-passage-reader .tei-word .tei-run-alternative")).toHaveCount(0)

        if layout == .desktop {
          // The sentence under the pointer violet, its lemma magenta.
          try await words.nth(2).hover()
          try await expect(box.locator(".quote-passage-reader[data-selects-sentences='true']")).toHaveCount(1)
          let tinted = try await page.evaluate(
            """
            (() => { const s = CSS.highlights.get('tei-sentence'), t = CSS.highlights.get('tei-sentence-title');
              return (s ? [...s][0].toString() : '') + '|' + (t ? [...t].map((r) => r.toString()).join(',') : ''); })()
            """
          ).string ?? ""
          #expect(tinted.hasPrefix("The scratchwords stood.|"), "the sentence under the pointer: \(tinted)")
          #expect(tinted.hasSuffix("|scratchwords"), "its lemma: \(tinted)")
          // Never blue: no word marked as the scan's.
          let color = try await words.nth(2).evaluate("(w) => getComputedStyle(w).cursor").string ?? ""
          #expect(color == "pointer", "the hand over a word: \(color)")
        }

        // A tap selects it: the quote filled, its words marked, its lemma
        // magenta (picked to begin with), no gloss.
        try await words.nth(2).click()
        let quote = box.locator("input[name='quote-s1-quote']")
        try await expect(box.locator(".quote-passage-reader .tei-word.tei-highlight"), timeout: .seconds(5))
          .toHaveCount(3)
        let taken = try await quote.evaluate("(q) => q.value").string ?? ""
        #expect(taken == "The scratchwords stood.", "the sentence taken, its stop too: \(taken)")
        try await expect(box.locator("input[name='quote-s1-start-image']")).toHaveValue("1")
        try await expect(box.locator(".quote-passage-reader .tei-word[data-highlight='title']")).toHaveText(
          "scratchwords")
        try await expect(page.locator(".gloss-sheet[data-state='open']")).toHaveCount(0)
        let collapsed = try await page.evaluate("getSelection().isCollapsed").bool
        #expect(collapsed == true, "the selection let go once taken")
        let picked = box.locator("input[name='quote-s1-words']")
        try await expect(picked).toHaveValue("w1.2")

        // The second step (user, 2026-11-02): a tap on another of its words
        // picks it too; on a picked one lets it go, never the last.
        try await words.nth(0).click()
        try await expect(picked).toHaveValue("w1.1,w1.2")
        try await words.nth(1).click()
        try await expect(picked).toHaveValue("w1.1")
        try await words.nth(0).click()
        try await expect(picked).toHaveValue("w1.1")
        let still = try await quote.evaluate("(q) => q.value").string ?? ""
        #expect(still == "The scratchwords stood.", "the sentence stays taken: \(still)")

        // The next sentence replaces it.
        try await words.nth(3).click()
        try await expect(box.locator(".quote-passage-reader .tei-word[data-highlight='title']")).toHaveCount(0)
        let next = try await quote.evaluate("(q) => q.value").string ?? ""
        #expect(next == "They fel.", "the next sentence: \(next)")

        // In the form's leaf node the footer is one row; the outline
        // scrolls, never the page.
        let oneRow = try await box.locator(".quote-passage-reader .artifact-footer").evaluate(
          """
          (f) => { const items = [...f.children].filter((c) => c.getClientRects().length > 0);
            const top = items[0].getBoundingClientRect().top;
            return items.every((c) => Math.abs(c.getBoundingClientRect().top - top) < 2); }
          """
        ).bool
        #expect(oneRow == true, "the reader's footer on one row")
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      testament?.remove()
      try await admin.remove(after: error)
    }
    testament?.remove()
    try await admin.remove()
  }
}
