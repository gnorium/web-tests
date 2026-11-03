import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A form's Source box selects its quote a sentence at a time (user,
/// 2026-11-01): in its text pane no word opens a gloss nor turns blue; the
/// sentence under the pointer is tinted violet; a tap takes the sentence,
/// no word of it picked: forms are the person's, never inferred (user,
/// 2026-11-03). A form is made with the browser's own text selection in a
/// sentence taken and "+ Form" on the bar above it, exactly those words,
/// one form (magenta); a click on a form selects it (ringed, every part),
/// clicked again or Escape lets it go; with one selected, "+ Form" adds the
/// selection to it as another part ("The … stood"), "− Form" dissolves it.
/// The bar's "− Sentence" lets the sentence last tapped go, and with it
/// every form with a word in it. Each Quote card is its own artifact, a
/// tap in it editing its quote: a sentence beside it extends it, one apart
/// moves it; "+ Quote" adds a card on the same source, each with "− Quote"
/// while there are two; a middle sentence let go splits the quote, its
/// later run a card of its own; a quote's first and last sentences each
/// hold a form; the Quote a line a sentence, a blank line between two
/// quotes, the forms a list a quote. The new sentiment's Forms list each
/// form once, "…" where its words stand apart. The reader keeps its footer
/// on one row in the form's leaf node.
@Suite("Sentence selection")
struct SentenceSelectionTests {
  static let sentimentForm = "/mission-control/submit/lexicographic/sentiment"
  static let service = "https://example.org/iiif/webtests-sentence-selection"
  static let tei = """
    <TEI><text><body><pb n="1" facs="\(service)/full/1300,/0/default.jpg"/>\
    <p><s><w xml:id="w1.1" lemma="the" class="article">The</w> <w xml:id="w1.2" lemma="scratchword" class="noun">scratchwords</w> \
    <w xml:id="w1.3" lemma="stand" class="verb">stood</w><pc>.</pc></s> \
    <s><w xml:id="w1.4" lemma="they" class="pronoun">They</w> <w xml:id="w1.5" lemma="fall" class="verb"><choice><abbr>fel</abbr>\
    <expan>fell</expan></choice></w><pc>.</pc></s> \
    <s><w xml:id="w1.6" lemma="a" class="article">A</w> <w xml:id="w1.7" lemma="scratchword" class="noun">scratchword</w> \
    <w xml:id="w1.8" lemma="lie" class="verb">lay</w><pc>.</pc></s></p></body></text></TEI>
    """

  /// A word of the pane by its id.
  static func word(_ id: String) -> String { ".quote-passage-reader .tei-word[data-word-id='\(id)']" }

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
        // The Source accordion holds its fields, then its Quote cards, then
        // its own row (user, 2026-11-03).
        let accordion = box.locator(".source-accordion-view").first
        try await expect(accordion.locator(".quote-passage-quotes > .quote-passage-quote")).toHaveCount(1)
        try await expect(accordion.locator(".quote-passage-actions .quote-passage-quote-add")).toHaveCount(1)
        try await expect(accordion.locator(".quote-passage-actions .quote-passage-source-remove")).toHaveCount(1)

        if layout == .desktop {
          // The sentence under the pointer violet; nothing guessed in it.
          try await words.nth(2).hover()
          try await expect(box.locator(".quote-passage-reader[data-selects-sentences='true']")).toHaveCount(1)
          let tinted = try await page.evaluate(
            """
            (() => { const s = CSS.highlights.get('tei-sentence'), t = CSS.highlights.get('tei-sentence-title');
              return (s ? [...s][0].toString() : '') + '|' + (t ? [...t].length : 0); })()
            """
          ).string ?? ""
          #expect(tinted == "The scratchwords stood.|0", "the sentence under the pointer, no lemma: \(tinted)")
          let cursor = try await words.nth(2).evaluate("(w) => getComputedStyle(w).cursor").string ?? ""
          #expect(cursor == "pointer", "the hand over a word: \(cursor)")
        }

        // A tap selects it: the quote filled, its words marked, no form
        // picked for it, no gloss.
        try await words.nth(2).click()
        let quote = box.locator("input[name='quote-s1-quote']")
        let forms = box.locator("input[name='quote-s1-forms']")
        try await expect(box.locator(".quote-passage-reader .tei-word.tei-highlight"), timeout: .seconds(5))
          .toHaveCount(3)
        let taken = try await quote.evaluate("(q) => q.value").string ?? ""
        #expect(taken == "The scratchwords stood.", "the sentence taken, its stop too: \(taken)")
        try await expect(box.locator("input[name='quote-s1-start-image']")).toHaveValue("1")
        try await expect(box.locator(".quote-passage-reader [data-highlight='title']")).toHaveCount(0)
        try await expect(forms).toHaveValue("")
        try await expect(page.locator(".gloss-sheet[data-state='open']")).toHaveCount(0)
        let collapsed = try await page.evaluate("getSelection().isCollapsed").bool
        #expect(collapsed == true, "the selection let go once taken")

        // The bar stands over the sentence last tapped: "− Sentence" alone.
        let bar = box.locator(".quote-passage-bar")
        let remove = bar.locator(".quote-passage-sentence-remove")
        let addForm = bar.locator(".quote-passage-form-add")
        let removeForm = bar.locator(".quote-passage-form-remove")
        try await expect(bar).toBeVisible()
        try await expect(remove).toHaveAttribute("aria-label", "Remove sentence")
        try await expect(remove).toHaveText("Sentence")
        try await expect(addForm).toBeHidden()
        try await expect(removeForm).toBeHidden()
        let above = try await page.evaluate(
          """
          (() => { const bar = document.querySelector('.quote-passage-bar').getBoundingClientRect();
            const word = document.querySelector('.quote-passage-reader .tei-word[data-word-id="w1.1"]')
              .getBoundingClientRect();
            return bar.bottom <= word.top + 1; })()
          """
        ).bool
        #expect(above == true, "the bar above its sentence")

        // A form is a text selection and "+ Form": exactly its words, one
        // form, magenta; the selection let go.
        try await page.addForm(in: box, from: Self.word("w1.2"))
        try await expect(forms).toHaveValue(#"[[["w1.2"]]]"#)
        try await expect(box.locator(Self.word("w1.2"))).toHaveAttribute("data-highlight", "title")
        try await expect(addForm).toHaveAttribute("aria-label", "Add form")
        try await expect(addForm).toHaveText("Form")
        try await expect(addForm).toBeHidden()
        // Two words side by side made one form are one form.
        try await page.addForm(in: box, from: Self.word("w1.1"))
        try await expect(forms).toHaveValue(#"[[["w1.1"],["w1.2"]]]"#)

        // A click on a form selects it, ringed; with it selected "+ Form"
        // adds another part: one form apart.
        try await box.locator(Self.word("w1.1")).click()
        try await expect(box.locator("[data-quote-form-selected='true']")).toHaveCount(1)
        try await expect(removeForm).toBeVisible()
        try await expect(removeForm).toHaveAttribute("aria-label", "Remove form")
        // Ringed as its strip, never a box a word (user, 2026-11-03): its
        // strip's ends closed, the form beside it unringed.
        let ring = try await box.locator(Self.word("w1.1")).evaluate(
          "(w) => { const a = getComputedStyle(w, '::after'); return [a.borderTopStyle, a.borderLeftStyle].join(','); }"
        ).string
        #expect(ring == "solid,solid", "a selected form ringed: \(ring ?? "")")
        let beside = try await box.locator(Self.word("w1.2")).evaluate(
          "(w) => getComputedStyle(w, '::after').borderTopStyle").string
        #expect(beside == "none", "the form beside it unringed: \(beside ?? "")")
        try await page.addForm(in: box, from: Self.word("w1.3"))
        try await expect(forms).toHaveValue(#"[[["w1.1","w1.3"],["w1.2"]]]"#)
        try await expect(box.locator("[data-quote-form-selected='true']")).toHaveCount(2)
        // A form apart is a strip a part, each ringed whole; the word between
        // is the other form's strip.
        try await expect(box.locator("[data-quote-strip-selected='true'][data-quote-strip-start][data-quote-strip-end]"))
          .toHaveCount(2)
        // Its Forms: each form once, its words apart joined by "…".
        let derived = page.locator(".submit-sentiment-form .derived-forms-view .derived-forms-card input")
        try await expect(derived.nth(0)).toHaveValue("The … stood")
        try await expect(derived.nth(2)).toHaveValue("scratchwords")
        // Escape lets it go; clicked again, "− Form" dissolves it whole.
        try await page.keyboard.press("Escape")
        try await expect(box.locator("[data-quote-form-selected]")).toHaveCount(0)
        try await expect(removeForm).toBeHidden()
        try await box.locator(Self.word("w1.3")).click()
        try await expect(box.locator("[data-quote-form-selected='true']")).toHaveCount(2)
        try await removeForm.click()
        try await expect(forms).toHaveValue(#"[[["w1.2"]]]"#)
        try await expect(box.locator(".quote-passage-reader [data-highlight='title']")).toHaveCount(1)
        let still = try await quote.evaluate("(q) => q.value").string ?? ""
        #expect(still == "The scratchwords stood.", "the sentence stays taken: \(still)")

        // One quote is active (user, 2026-11-03): a sentence apart MOVES
        // it there, what it held let go with its forms; one beside it
        // extends it.
        try await words.nth(6).click()
        try await expect(box.locator(".quote-passage-reader .tei-word.tei-highlight")).toHaveCount(3)
        let moved = try await quote.evaluate("(q) => q.value").string ?? ""
        #expect(moved == "A scratchword lay.", "the quote moved: \(moved)")
        try await expect(forms).toHaveValue("")
        try await words.nth(3).click()
        let extended = try await quote.evaluate("(q) => q.value").string ?? ""
        #expect(extended == "They fel.\nA scratchword lay.", "the quote extended: \(extended)")
        try await expect(box.locator("input[name='quote-s1-start-image']")).toHaveValue("1,1")

        // Its first sentence holds no form (user, 2026-11-03): a Submit is
        // refused, the message at the bottom of the node; a form clears it.
        try await page.addForm(in: box, from: Self.word("w1.7"))
        let refused = try await box.evaluate(
          """
          (b) => { const e = new Event('submit', { cancelable: true, bubbles: true });
            b.closest('form').dispatchEvent(e); return e.defaultPrevented; }
          """
        ).bool
        #expect(refused == true, "a quote whose first sentence holds no form is refused")
        let message = page.locator(".submit-sentiment-form .node-message")
        try await expect(message).toHaveText(
          "Add a form in the first and the last sentence of each quote, or let those sentences go.")
        try await page.addForm(in: box, from: Self.word("w1.4"))
        try await expect(message).toHaveCount(0)
        try await expect(forms).toHaveValue(#"[[["w1.4"],["w1.7"]]]"#)

        // Its Quote card IS its artifact (legend "Quote"), never its text;
        // no "− Quote" while alone.
        let groups = box.locator(".quote-passage-quotes > .quote-passage-quote")
        try await expect(groups).toHaveCount(1)
        try await expect(groups.first.locator(".form-item-legend")).toHaveText("Quote")
        try await expect(box.locator(".quote-passage-quote-text")).toHaveCount(0)
        try await expect(groups.first.locator(".quote-passage-quote-remove")).toBeHidden()
        let add = box.locator(".quote-passage-actions .quote-passage-quote-add")
        try await expect(add).toHaveAttribute("aria-label", "Add quote")
        try await expect(add).toHaveText("Quote")

        // "+ Quote": a second card, its artifact on the same source, a tap
        // in it taking its own quote, its forms its own.
        try await add.click()
        try await expect(groups).toHaveCount(2)
        let others = groups.nth(1).locator(".quote-passage-reader .artifact-markup .tei-word")
        try await expect(others.first, timeout: .seconds(20)).toBeAttached()
        try await others.nth(0).click()
        let second = try await quote.evaluate("(q) => q.value").string ?? ""
        #expect(second == "They fel.\nA scratchword lay.\n\nThe scratchwords stood.", "two quotes: \(second)")
        try await expect(box.locator("input[name='quote-s1-start-image']")).toHaveValue("1,1,1")
        try await expect(forms).toHaveValue(#"[[["w1.4"],["w1.7"]],[]]"#)
        try await page.addForm(in: groups.nth(1), from: ".tei-word[data-word-id='w1.2']")
        try await expect(forms).toHaveValue(#"[[["w1.4"],["w1.7"]],[["w1.2"]]]"#)
        try await expect(groups.nth(0).locator(".tei-word.tei-highlight")).toHaveCount(5)
        try await expect(groups.nth(1).locator(".tei-word.tei-highlight")).toHaveCount(3)
        try await expect(groups.first.locator(".quote-passage-quote-remove")).toBeVisible()

        // "− Quote" lets the second go.
        try await groups.nth(1).locator(".quote-passage-quote-remove").click()
        try await expect(groups).toHaveCount(1)
        let back = try await quote.evaluate("(q) => q.value").string ?? ""
        #expect(back == "They fel.\nA scratchword lay.", "the second let go: \(back)")
        try await expect(forms).toHaveValue(#"[[["w1.4"],["w1.7"]]]"#)

        // The sentence before extends it: one quote of the three.
        try await words.nth(0).click()
        let one = try await quote.evaluate("(q) => q.value").string ?? ""
        #expect(one == "The scratchwords stood.\nThey fel.\nA scratchword lay.", "one run: \(one)")
        try await expect(box.locator("input[name='quote-s1-start-image']")).toHaveValue("1,1,1")
        // The middle tapped: the bar over it.
        try await words.nth(4).click()

        // The bar lets go of the sentence last tapped: its quote's middle,
        // so the quote splits, its later run a card of its own after it,
        // read on the same source; the middle's form goes with it.
        try await remove.click()
        let apart = try await quote.evaluate("(q) => q.value").string ?? ""
        #expect(apart == "The scratchwords stood.\n\nA scratchword lay.", "the middle let go: \(apart)")
        try await expect(groups).toHaveCount(2)
        try await expect(groups.nth(1).locator(".tei-word.tei-highlight"), timeout: .seconds(20)).toHaveCount(3)
        try await expect(forms).toHaveValue(#"[[],[["w1.7"]]]"#)
        try await groups.nth(1).locator(".quote-passage-quote-remove").click()
        let first = try await quote.evaluate("(q) => q.value").string ?? ""
        #expect(first == "The scratchwords stood.", "the split quote let go: \(first)")
        try await expect(forms).toHaveValue("")
        try await words.nth(1).click()
        try await remove.click()
        try await expect(box.locator(".quote-passage-reader .tei-word.tei-highlight")).toHaveCount(0)
        try await expect(quote).toHaveValue("")
        try await expect(bar).toBeHidden()

        // In the form's leaf node the footer is one row; the outline
        // scrolls, never the page.
        let oneRow = try await box.locator(".quote-passage-reader .artifact-footer").first.evaluate(
          """
          (f) => { const items = [...f.children].filter((c) => c.getClientRects().length > 0);
            const top = items[0].getBoundingClientRect().top;
            return items.every((c) => Math.abs(c.getBoundingClientRect().top - top) < 2); }
          """
        ).bool
        #expect(oneRow == true, "the reader's footer on one row")
        try await page.expectArtifactsUnclipped()
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
