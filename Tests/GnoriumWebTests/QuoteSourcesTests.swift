import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A sentiment's quotes sit in Sources (user, 2026-11-01), each its own
/// Source accordion holding only its data (user, 2026-11-02, 2026-11-03):
/// its source (a permitted record › any of its nodes, or a URL) and its
/// Pages where the quote is typed; its Quote cards under it, outside it,
/// each its artifact; then one row, "+ Quote" and "− Source". "+ Source"
/// stamps another from the page's template, each "− Source" shown while
/// there is more than one; the keys post in order. No Image URL field, and
/// no "range" anywhere in the form.
@Suite("Quote sources")
struct QuoteSourcesTests {
  static let sentimentForm = "/mission-control/submit/lexicographic/sentiment"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func aSentimentsQuotesSitInSourceBoxes(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated(Self.sentimentForm)
      let sources = page.locator(".submit-sentiment-form .quote-sources-view")
      let boxes = sources.locator(".quote-source")
      try await expect(boxes).toHaveCount(1)
      let first = boxes.first
      // Its own Source accordion, no box around it (user, 2026-11-03): its
      // fields, then its Quote cards, the card its artifact, then its own
      // row, "+ Quote" and "− Source", all inside it; the node's "+
      // Source" below every accordion, alone in its row.
      try await expect(first.locator(".source-accordion-view")).toHaveCount(1)
      try await expect(first.locator(".source-accordion-view").first).toContainText("Source")
      try await expect(first.locator(":scope > .form-item-legend")).toHaveCount(0)
      try await expect(first.locator(".source-accordion-view .quote-passage-reader")).toHaveCount(1)
      try await expect(first.locator(".source-accordion-view .quote-passage-actions")).toHaveCount(1)
      let inside = try await first.evaluate(
        """
        (box) => { const body = box.querySelector('.source-accordion-view .quote-passage-body');
          return [...body.children].filter((c) => c.tagName !== 'TEMPLATE')
            .map((c) => c.classList.contains('quote-passage-fields') ? 'fields'
              : c.classList.contains('quote-passage-quotes') ? 'quotes'
              : c.classList.contains('quote-passage-actions') ? 'row' : 'other').join(','); }
        """
      ).string
      #expect(inside == "fields,quotes,row", "its fields, its Quote cards, its row: \(inside ?? "")")
      let alone = try await sources.evaluate(
        """
        (s) => { const add = s.querySelector(':scope > .quote-sources-add');
          return !!add && add.previousElementSibling?.classList.contains('quote-sources-list')
            && add.querySelectorAll('button').length === 1; }
        """
      ).bool
      #expect(alone == true, "the node's + Source below the accordions, alone in its row")
      let cards = first.locator(".quote-passage-quotes > .quote-passage-quote")
      try await expect(cards).toHaveCount(1)
      try await expect(cards.first.locator(".form-item-legend")).toHaveText("Quote")
      try await expect(cards.first.locator(":scope > .quote-passage-reader")).toHaveCount(1)
      try await expect(first.locator(".quote-passage-quote-text")).toHaveCount(0)
      try await expect(first.locator(".quote-passage-actions .button-label")).toHaveTexts(["Quote", "Source"])
      // Its record field, asked for as the page opens: Record, then
      // Testament once a record is picked.
      try await expect(first.locator(".quote-passage-record .origin-record-field-view"), timeout: .seconds(15))
        .toHaveCount(1)
      try await expect(first.locator(".quote-passage-record input[name='quote-s1-record']")).toHaveCount(1)
      // No Image URL; its source, then the hidden quote and images the
      // reader fills, in that order.
      try await expect(sources.locator("[name$='image-url']")).toHaveCount(0)
      let order = try await first.evaluate(
        """
        (box) => ['.quote-passage-record', "[name='quote-s1-source-url']", "[name='quote-s1-start-image']",
          "[name='quote-s1-end-image']", "[name='quote-s1-quote']"]
          .map((s) => box.querySelector(s))
          .every((el, i, all) => el && (i === 0 || (all[i - 1].compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING)))
        """
      ).bool
      #expect(order == true, "the Source box reads its source, then what the reader fills")
      // The box always shows the same fields (user, 2026-11-02): its
      // Value too, frozen while no record is picked; with neither a record
      // nor a URL (a sourceless work) its Title, Language, Class, rights
      // and Pages typed, and the text-only reader open to type the quote.
      try await expect(first.locator(".quote-passage-record input[name='quote-s1-record-node']")).toHaveCount(1)
      for suffix in ["source-url-title", "source-url-language", "source-url-class", "rights-statement", "work-license"] {
        try await expect(first.locator("[name='quote-s1-\(suffix)']")).toHaveCount(1)
      }
      try await expect(first.locator(".quote-passage-own")).toBeVisible()
      try await expect(first.locator(".quote-passage-pages")).toBeVisible()
      try await expect(first.locator(".quote-passage-reader .quote-passage-text"), timeout: .seconds(15)).toBeVisible()
      let text = try await sources.evaluate("(el) => el.textContent.toLowerCase()").string ?? ""
      #expect(!text.contains("range"), "the Source box says range")
      // One box: no "− Source".
      try await expect(first.locator(".quote-passage-source-remove")).toBeHidden()

      // "+ Source": a second box at once, both removable, the keys in order.
      let add = sources.locator(".quote-sources-add-btn")
      try await expect(add).toHaveText("Source")
      try await expect(add).toHaveAttribute("aria-label", "Add source")
      try await add.click()
      try await expect(boxes).toHaveCount(2)
      let second = boxes.nth(1)
      try await expect(second.locator(".source-accordion-view").first).toContainText("Source")
      try await expect(second.locator(".quote-passage-record .origin-record-field-view"), timeout: .seconds(15))
        .toHaveCount(1)
      let keys = sources.locator("input[name='quote-keys']")
      let key = try await second.getAttribute("data-quote-source-key") ?? ""
      #expect(key.hasPrefix("quote-sn"), "a stamped box's key: \(key)")
      try await expect(keys).toHaveValue("quote-s1,\(key)")
      try await expect(first.locator(".quote-passage-source-remove")).toBeVisible()
      try await expect(second.locator(".quote-passage-source-remove")).toBeVisible()
      try await expect(second.locator(".quote-passage-source-remove")).toHaveAttribute("aria-label", "Remove source")
      try await expect(first.locator(".quote-passage-actions .button-label")).toHaveTexts(["Quote", "Source"])
      try await page.expectArtifactsUnclipped()

      // "− Source": the first goes, the second stays, alone again.
      try await first.locator(".quote-passage-source-remove").click()
      try await expect(boxes).toHaveCount(1)
      try await expect(keys).toHaveValue(key)
      try await expect(boxes.first.locator(".quote-passage-source-remove")).toBeHidden()
      try await page.expectNoErrors()
    }
  }

  /// A testament leaf's Source accordion holds only its URL (user,
  /// 2026-11-02): no Images start or end (its images are all of its
  /// source's), no Quote; open on Submit, under the leaf's Metadata and Note.
  @Test(arguments: gnorium.engines)
  func aTestamentsDigitizationHasASourceBox(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine)) { page in
      try await page.openHydrated("/mission-control/submit/bibliographic/testament")
      let box = page.locator(".testament-source-view")
      try await expect(box).toHaveCount(1)
      try await expect(box.locator(".accordion-title").first).toHaveText("Source")
      let url = box.locator("input[name='source-url']")
      try await expect(url).toBeVisible()
      try await expect(url).toHaveAttribute("placeholder", "URL")
      let shape = try await box.evaluate(
        """
        (b) => {
          const note = document.querySelector("textarea[name='digitization_note']");
          return !b.querySelector("[name='testament-start-image'], [name='testament-end-image'], textarea")
            && !!note && !!(note.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING);
        }
        """
      ).bool
      #expect(shape == true, "its URL alone, after the leaf's Note")
      try await page.expectNoErrors()
    }
  }

  static let service = "https://example.org/iiif/webtests-source-box"
  static let tei = """
    <TEI><text><body><pb n="1" facs="\(service)/full/1300,/0/default.jpg"/>\
    <p><s><w xml:id="w1.1" lemma="the" class="article">The</w> <w xml:id="w1.2" lemma="scratchword" class="noun">scratchwords</w> \
    <w xml:id="w1.3" lemma="stand" class="verb">stood</w><pc>.</pc></s></p></body></text></TEI>
    """

  /// A pending quote (by a URL Gnorium does not have yet) reads as any
  /// quote item (user, 2026-11-02): its Source box, its URL, then its
  /// sentence in the text-only reader's text pane; no chip, no Images, no
  /// sentence field.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aPendingQuoteReadsAsAnyQuote(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    var holder: ScratchOverture?
    do {
      let overture = try ScratchOverture(owner: admin, sealed: false)
      holder = overture
      let source = "https://web-tests.invalid/pending-shape.json"
      // Its evidence its outgoing citations, each claiming the step
      // (user, 2026-11-03).
      let step = UUID().uuidString
      let origins =
        #"[{"id":"\#(step)","relations":["based_on"],"typed":{"title":"Web tests source","voices":[]},"origins":[],"#
        + #""outgoingCitations":[{"id":"\#(UUID().uuidString)","claim":{"field":"origin","row":"\#(step)"},"#
        + #""quotes":[{"id":"\#(UUID().uuidString)","anchors":[],"#
        + #""pending":{"sourceURL":"\#(source)","images":[1,2],"text":"The pendingword stood fast","title":"Pending shape","language":"eng","class":"play"}}]}]}]"#
      _ = try TestAdmin.query(
        "UPDATE bibliographic_overtures SET origins_json = '\(origins)' WHERE id = '\(overture.overtureID)';")
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(overture.path)
        let pending = page.locator(".pending-quote-view").first
        try await expect(pending, timeout: .seconds(15)).toBeAttached()
        try await expect(pending.locator(".quote-source-view")).toHaveCount(1)
        // A Disputorium read: the form's fields frozen, each its value.
        let fields = pending.locator(".quote-source-fields")
        try await expect(fields.locator("input[placeholder='URL']")).toHaveValue(source)
        try await expect(fields.locator("input[placeholder='Title']")).toHaveValue("Pending shape")
        try await expect(fields.locator("input[placeholder='Language']")).toHaveValue("English")
        try await expect(fields.locator("input[placeholder='Class']")).toHaveValue("Play")
        try await expect(pending.locator(".testament-view")).toHaveCount(1)
        try await expect(pending.locator(".testament-view .artifact-markup")).toContainText("pendingword")
        // Its Source accordion, then its Quote card, the card its reader;
        // the row is its Citation card's (user, 2026-11-03), disabled:
        // "+ Quote" and "− Citation".
        let shape = try await pending.evaluate(
          "(v) => { const frame = v.querySelector('.quote-source-frame'); return [...frame.children].map((n) => n.matches('.source-accordion-frame') ? 'source' : n.matches('.quote-source-quote') ? 'quote' : n.matches('.quote-source-actions') ? 'row' : 'other').join(',') }"
        ).string
        #expect(shape == "source,quote", "a pending quote shows its Source accordion and its Quote card")
        let citation = page.locator(".outgoing-citation:has(.pending-quote-view)").first
        try await expect(citation.locator(".outgoing-citation-actions button[disabled]")).toHaveCount(2)
        try await expect(pending.locator(".quote-source-quote .testament-view")).toHaveCount(1)
        try await expect(pending.locator(".info-chip-text")).toHaveCount(0)
        try await expect(pending).not.toContainText("Images")
        try await expect(pending.locator(".pending-quote-status")).toHaveCount(0)
      }
    } catch {
      holder?.remove()
      try await admin.remove(after: error)
    }
    holder?.remove()
    try await admin.remove()
  }

  /// A Source box holds only what is not in the artifact (user,
  /// 2026-11-02): a permitted record's leaf opens under it with its text
  /// pane, its URL filled in and frozen; selecting the sentence there fills
  /// the hidden quote and image (the image it is on) and marks its words,
  /// then a selection and "+ Form" pick the quote's own word (magenta),
  /// posted by its xml:id. With no record, the URL is typed, the record left empty.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aRecordsTextPaneTakesTheQuote(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    var testament: ScratchTestament?
    func clean() async throws {
      testament?.remove()
      try await admin.remove()
    }
    do {
      let scratch = try ScratchTestament(owner: admin, tei: Self.tei)
      testament = scratch
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(Self.sentimentForm)
        let box = page.locator(".submit-sentiment-form .quote-source").first
        try await expect(box.locator(".quote-passage-record input[name='quote-s1-record']"), timeout: .seconds(15))
          .toHaveCount(1)
        let typed = box.locator(".quote-passage-typed")
        try await expect(typed).toBeHidden()
        try await expect(box.locator("textarea")).toHaveCount(0)
        // The record picked: its leaf read under the box.
        _ = try await box.evaluate(
          """
          (b) => { const input = b.querySelector("input[name='quote-s1-record']");
            input.value = '\(scratch.reading.work.recordID.lowercased())';
            input.dispatchEvent(new Event('change', { bubbles: true })); return true; }
          """)
        let words = box.locator(".quote-passage-reader .artifact-markup .tei-word")
        try await expect(words.first, timeout: .seconds(20)).toBeAttached()
        try await expect(box.locator("input[name='quote-s1-source-url']")).toBeDisabled()
        // Its leaf named by its Value (user, 2026-11-02): a dropdown of the
        // record's testaments by number and whole value, posting the node id.
        try await expect(box.locator(".quote-passage-record [data-placeholder='Value']"), timeout: .seconds(10)).toHaveCount(1)
        try await expect(box.locator(".quote-passage-record")).toContainText("Value")
        // Each leaf offered by its number, then its whole value; it posts
        // the leaf's UUID.
        let leaves = try await box.evaluate(
          """
          (b) => { const field = b.querySelector("[name='quote-s1-record-node']").closest('.dropdown-view');
            const options = [...field.querySelectorAll('[data-dropdown-option]')];
            return options.length > 0 && options.every((o) =>
              /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(o.dataset.value)
              && o.dataset.number.length > 0 && o.dataset.display.length > 0
              && o.querySelector('.dropdown-option-number')?.textContent === o.dataset.number
              && o.textContent.includes(o.dataset.display)); }
          """
        ).bool
        #expect(leaves == true, "each leaf reads its number, then its value")
        // Picked, the closed field reads the same: its number, then its
        // whole value, on one line inside the box.
        let node = box.locator(".dropdown-view:has([name='quote-s1-record-node'])")
        try await node.locator(".dropdown-trigger").click()
        let option = node.locator(".dropdown-option").first
        let value = try await option.getAttribute("data-display") ?? ""
        let number = try await option.getAttribute("data-number") ?? ""
        try await option.click()
        let closed = box.locator(".dropdown-view:has([name='quote-s1-record-node']) .dropdown-selected-text")
        try await expect(closed, timeout: .seconds(10)).toContainText(value)
        try await expect(closed).toContainText(number)
        // One line inside the box, its tail edge-faded where it runs past
        // (the closed value fades without expand), as the Record's does.
        let fits = try await box.evaluate(
          """
          (b) => { const field = b.querySelector("[name='quote-s1-record-node']").closest('.dropdown-view');
            const text = field.querySelector('.dropdown-selected-text');
            const t = text.getBoundingClientRect();
            const trigger = field.querySelector('.dropdown-trigger').getBoundingClientRect();
            const own = b.getBoundingClientRect();
            return trigger.right <= own.right + 0.5 && trigger.left >= own.left - 0.5
              && t.left >= trigger.left && t.right <= trigger.right && t.height < 40
              && getComputedStyle(text).overflowX !== 'visible'
              && (text.scrollWidth <= text.clientWidth || text.dataset.edgeFadeView === 'true'); }
          """
        ).bool
        #expect(fits == true, "the closed Testament UUID runs out of its box")
        // The sentence selected in its text pane fills the quote.
        _ = try await box.evaluate(
          """
          (b) => { const words = b.querySelectorAll('.quote-passage-reader .artifact-markup .tei-word');
            const range = document.createRange(); range.setStartBefore(words[0]); range.setEndAfter(words[2]);
            const selection = getSelection(); selection.removeAllRanges(); selection.addRange(range);
            b.querySelector('.quote-passage-reader').dispatchEvent(new PointerEvent('pointerup', { bubbles: true }));
            return true; }
          """)
        // The whole sentence the selection touches (user, 2026-11-02).
        try await expect(box.locator("input[name='quote-s1-quote']")).toHaveValue("The scratchwords stood.")
        try await expect(box.locator("input[name='quote-s1-start-image']")).toHaveValue("1")
        try await expect(box.locator("input[name='quote-s1-end-image']")).toHaveValue("")
        try await expect(box.locator(".quote-passage-reader .tei-word.tei-highlight")).toHaveCount(3)
        // No form guessed: the second step is the person's, a selection
        // and "+ Form", its word magenta, posted by its xml:id.
        try await expect(box.locator(".quote-passage-reader .tei-word[data-highlight='title']")).toHaveCount(0)
        try await page.addForm(in: box, from: ".quote-passage-reader .artifact-markup .tei-word[data-word-id='w1.2']")
        try await expect(box.locator(".quote-passage-reader .tei-word[data-highlight='title']")).toHaveCount(1)
        try await expect(box.locator("input[name='quote-s1-forms']")).toHaveValue(#"[[["w1.2"]]]"#)
        try await page.expectArtifactsUnclipped()

        // No record: the URL typed, the record and its leaf empty.
        _ = try await box.evaluate(
          """
          (b) => { const input = b.querySelector("input[name='quote-s1-record']"); input.value = '';
            input.dispatchEvent(new Event('change', { bubbles: true })); return true; }
          """)
        let url = box.locator("input[name='quote-s1-source-url']")
        try await expect(url, timeout: .seconds(10)).toBeEnabled()
        try await url.fill("https://web-tests.invalid/source-box.json")
        try await Task.sleep(for: .milliseconds(1500))
        try await expect(typed).toBeHidden()
        try await expect(box.locator("input[name='quote-s1-record']")).toHaveValue("")
      }
    } catch {
      testament?.remove()
      try await admin.remove(after: error)
    }
    try await clean()
  }
}
