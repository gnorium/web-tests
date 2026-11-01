import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A sentiment's quotes sit in Source boxes (user, 2026-11-01), the same
/// pattern as the Voice and Agent boxes: each legended "Source", its fields
/// in order Source (a permitted record › testament, asked for as the page
/// opens, or a Source URL), its Images start and optional Images end (the
/// start or the next), Quote (one sentence). "+ Source" stamps
/// another from the page's template, each "− Source" shown while there is
/// more than one; the boxes' keys post in order. No Image URL field, and
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
      try await expect(first.locator(".form-item-legend").first).toHaveText("Source")
      // Its record field, asked for as the page opens: Record, then
      // Testament once a record is picked.
      try await expect(first.locator(".quote-passage-record .origin-record-field-view"), timeout: .seconds(15))
        .toHaveCount(1)
      try await expect(first.locator(".quote-passage-record input[name='quote-s1-record']")).toHaveCount(1)
      // No Image URL; Source, Images, Quote in that order.
      try await expect(sources.locator("[name$='image-url']")).toHaveCount(0)
      let order = try await first.evaluate(
        """
        (box) => ['.quote-passage-record', "[name='quote-s1-source-url']", "[name='quote-s1-start-image']",
          "[name='quote-s1-end-image']", "[name='quote-s1-quote']"]
          .map((s) => box.querySelector(s))
          .every((el, i, all) => el && (i === 0 || (all[i - 1].compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING)))
        """
      ).bool
      #expect(order == true, "the Source box reads Source, Images, Quote")
      let text = try await sources.evaluate("(el) => el.textContent.toLowerCase()").string ?? ""
      #expect(!text.contains("range"), "the Source box says range")
      // One box: no "− Source".
      try await expect(first.locator(".quote-source-remove-btn")).toBeHidden()

      // "+ Source": a second box at once, both removable, the keys in order.
      let add = sources.locator(".quote-sources-add-btn")
      try await expect(add).toHaveText("Source")
      try await expect(add).toHaveAttribute("aria-label", "Add source")
      try await add.click()
      try await expect(boxes).toHaveCount(2)
      let second = boxes.nth(1)
      try await expect(second.locator(".form-item-legend").first).toHaveText("Source")
      try await expect(second.locator(".quote-passage-record .origin-record-field-view"), timeout: .seconds(15))
        .toHaveCount(1)
      let keys = sources.locator("input[name='quote-keys']")
      let key = try await second.getAttribute("data-quote-source-key") ?? ""
      #expect(key.hasPrefix("quote-sn"), "a stamped box's key: \(key)")
      try await expect(keys).toHaveValue("quote-s1,\(key)")
      try await expect(first.locator(".quote-source-remove-btn")).toBeVisible()
      try await expect(second.locator(".quote-source-remove-btn")).toBeVisible()
      try await expect(second.locator(".quote-source-remove-btn")).toHaveAttribute("aria-label", "Remove source")
      try await page.expectNoHorizontalOverflow()

      // "− Source": the first goes, the second stays, alone again.
      try await first.locator(".quote-source-remove-btn").click()
      try await expect(boxes).toHaveCount(1)
      try await expect(keys).toHaveValue(key)
      try await expect(boxes.first.locator(".quote-source-remove-btn")).toBeHidden()
      try await page.expectNoErrors()
    }
  }

  /// A testament's digitization has the same Source box: its Source URL,
  /// then its Images start and Images end, frozen (its source's first and
  /// last, filled once the Source URL is read), and no Quote.
  @Test(arguments: gnorium.engines)
  func aTestamentsDigitizationHasASourceBox(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine)) { page in
      try await page.openHydrated("/mission-control/submit/bibliographic/testament")
      let box = page.locator(".testament-source")
      try await expect(box).toHaveCount(1)
      try await expect(box.locator(".form-item-legend").first).toHaveText("Source")
      let shape = try await box.evaluate(
        """
        (b) => {
          const url = b.querySelector("[name='source-url']"), start = b.querySelector("[name='testament-start-image']"),
            end = b.querySelector("[name='testament-end-image']");
          return !!url && !!start && !!end && !b.querySelector("textarea") && start.disabled && end.disabled
            && !!(url.compareDocumentPosition(start) & Node.DOCUMENT_POSITION_FOLLOWING)
            && !!(start.compareDocumentPosition(end) & Node.DOCUMENT_POSITION_FOLLOWING) && start.value === '';
        }
        """
      ).bool
      #expect(shape == true, "Source URL, then Images start and Images end frozen and empty until it is read, and no Quote")
      try await page.expectNoErrors()
    }
  }

  static let service = "https://example.org/iiif/webtests-source-box"
  static let tei = """
    <TEI><text><body><pb n="1" facs="\(service)/full/1300,/0/default.jpg"/>\
    <p><s><w lemma="the" class="article">The</w> <w lemma="scratchword" class="noun">scratchwords</w> \
    <w lemma="stand" class="verb">stood</w><pc>.</pc></s></p></body></text></TEI>
    """

  /// A Source box shows only what is needed (user, 2026-11-01): a
  /// permitted record's testament opens under it with its text pane, and
  /// no Images or Quote; selecting the sentence there fills them (the
  /// image it is on) and marks its words. A Source URL alone shows them,
  /// as typed, where its source cannot be read.
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
        try await expect(typed).toBeVisible()
        // The record picked: its testament read under the box, no Images
        // or Quote.
        _ = try await box.evaluate(
          """
          (b) => { const input = b.querySelector("input[name='quote-s1-record']");
            input.value = '\(scratch.reading.work.recordID.lowercased())';
            input.dispatchEvent(new Event('change', { bubbles: true })); return true; }
          """)
        let words = box.locator(".quote-passage-reader .artifact-markup .tei-word")
        try await expect(words.first, timeout: .seconds(20)).toBeAttached()
        try await expect(typed).toBeHidden()
        // The sentence selected in its text pane fills the quote.
        _ = try await box.evaluate(
          """
          (b) => { const words = b.querySelectorAll('.quote-passage-reader .artifact-markup .tei-word');
            const range = document.createRange(); range.setStartBefore(words[0]); range.setEndAfter(words[2]);
            const selection = getSelection(); selection.removeAllRanges(); selection.addRange(range);
            b.querySelector('.quote-passage-reader').dispatchEvent(new PointerEvent('pointerup', { bubbles: true }));
            return true; }
          """)
        try await expect(box.locator("textarea[name='quote-s1-quote']")).toHaveValue("The scratchwords stood")
        try await expect(box.locator("input[name='quote-s1-start-image']")).toHaveValue("1")
        try await expect(box.locator("input[name='quote-s1-end-image']")).toHaveValue("")
        try await expect(box.locator(".quote-passage-reader .tei-word.tei-highlight")).toHaveCount(3)
        try await page.expectNoHorizontalOverflow()

        // No record, a Source URL that cannot be read: the fields as typed.
        _ = try await box.evaluate(
          """
          (b) => { const input = b.querySelector("input[name='quote-s1-record']"); input.value = '';
            input.dispatchEvent(new Event('change', { bubbles: true })); return true; }
          """)
        try await expect(typed, timeout: .seconds(10)).toBeVisible()
        try await box.locator("input[name='quote-s1-source-url']").fill("https://web-tests.invalid/source-box.json")
        try await Task.sleep(for: .milliseconds(1500))
        try await expect(typed).toBeVisible()
        try await expect(box.locator("input[name='quote-s1-start-image']")).toBeEnabled()
        try await expect(box.locator("textarea[name='quote-s1-quote']")).toBeEnabled()
      }
    } catch {
      testament?.remove()
      try await admin.remove(after: error)
    }
    try await clean()
  }
}
