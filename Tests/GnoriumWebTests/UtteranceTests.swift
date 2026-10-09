import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An utterance is shown in its testament (user, 2026-09-27): a sentiment's
/// utterance is the transcript
/// of its page and the pages either side, one after another in one bounded
/// box, each opened by its label, fetched only once it comes into view and
/// opened with its sentence (split across a page break here) in the middle,
/// the sentence and, more strongly, the word marked; no images; credited
/// under it as a Chicago note (user, 2026-10-09), its title linked to the
/// testament at its page. A throwaway
/// admin owns a scratch work with a permitted testament and a scratch word
/// attested in it, made by SQL and removed after.
@Suite("Utterance", .serialized)
struct UtteranceTests {
  /// Five pages; the utterance on the third, its sentence ending on the
  /// fourth. On the third page the word is the third of its third line
  /// (after two `<lb/>`s: "Here the scratchword begins"): page 3, line 3, word 3.
  static let tei: String = {
    func page(_ number: Int, _ body: String) -> String {
      #"<pb n="\#(number)" facs="https://example.org/iiif/webtests-p\#(number)/full/1300,/0/default.jpg"/>"# + body
    }
    func lines(_ number: Int) -> String {
      (1...10).map { "<s>Page \(number), line \($0).</s><lb/>" }.joined()
    }
    return "<TEI><text><body>"
      + page(1, "<p>\(lines(1))</p>")
      + page(2, "<p>\(lines(2))</p>")
      + page(
        3,
        #"<p><s>Third page, first line.</s><lb/><s>Third page, second line.</s><lb/><s part="I">Here the <w>scratchword</w> begins</s></p>"#)
      + page(4, #"<p><s part="F">and ended on the next page.</s><lb/>\#(lines(4))</p>"#)
      + page(5, "<p>\(lines(5))</p>")
      + "</body></text></TEI>"
  }()

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func anUtteranceIsShownInItsTestament(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    var testament: ScratchTestament?
    var word: ScratchWord?
    func clean() async throws {
      word?.remove()
      testament?.remove()
      try await admin.remove()
    }
    do {
      let scratch = try ScratchTestament(owner: admin, tei: Self.tei)
      testament = scratch
      let scratchWord = try ScratchWord(
        owner: admin,
        anchor: .init(
          recordID: scratch.reading.work.recordID, versionID: scratch.versionID,
          canvasID: "https://example.org/iiif/webtests-p3", page: 3, line: 3, word: 3, surface: "scratchword"))
      word = scratchWord
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(scratchWord.path)
        let row = page.locator("#record-row-s-1-1")
        let attestation = row.locator(".attestation-view")
        // Its first attestation against the margin, in the house style.
        try await expect(row.locator(".record-row-date").first).toHaveText("AD 1901")
        // Closed, its utterance is not fetched.
        try await expect(row.locator(".attestation-utterance")).toHaveAttribute("data-loaded", "false")
        let fetchedBefore = try await page.evaluate(
          "performance.getEntriesByType('resource').filter(e => e.name.includes('/utterance?')).length")
        #expect(fetchedBefore == .number(0))

        try await page.locator("#record-row-s-1-1 > .accordion-summary").click()
        try await expect(row).toHaveAttribute("data-open-finished", "true")
        let utterance = attestation.locator(".utterance-view")
        try await expect(utterance).toHaveCount(1)
        // Credited under the reader, as a quotation is: a Chicago note—the
        // voice, the title italic (a report is book-length), the date, the
        // locus (the semblance's place: no manifest is read).
        let work = scratch.reading.work
        let citation = attestation.locator(".chicago-citation-view")
        try await expect(citation).toHaveText("\(work.author), \(work.title) (1958), 3.")
        try await expect(citation.locator("cite.chicago-citation-title")).toHaveCSS("font-style", "italic")
        let credit = try await attestation.evaluate(
          """
          (el) => { const c = el.querySelector('.chicago-citation-view'), u = el.querySelector('.utterance-view');
            return c.getBoundingClientRect().top >= u.getBoundingClientRect().bottom }
          """)
        #expect(credit == .bool(true), "the utterance's source is not credited under its reader")
        // The page and the pages either side, each opened by its label.
        try await expect(utterance.locator(".tei-transcript")).toHaveCount(3)
        try await expect(utterance.locator(".tei-line-mark")).toHaveTexts(["2", "3", "4"])
        try await expect(utterance).not.toContainText("Page 1,")
        try await expect(utterance).not.toContainText("Page 5,")
        // The sentence on both sides of the page break; the word more strongly.
        try await expect(utterance.locator("mark[data-highlight='sentence']")).toHaveTexts([
          "Here the", "begins", "and ended on the next page.",
        ])
        let title = utterance.locator("mark[data-highlight='title']")
        try await expect(title).toHaveText("scratchword")
        // Stronger by color alone: its weight is the text's own.
        let weights = try await utterance.evaluate(
          "box => [...box.querySelectorAll('mark')].map(m => getComputedStyle(m).fontWeight).join(' ')")
        #expect(weights == .string("400 400 400 400"))
        // The word boxed as the OED boxes it; the sentence unboxed.
        try await expect(title).toHaveCSS("border-top-style", "solid")
        try await expect(utterance.locator("mark[data-highlight='sentence']").first).toHaveCSS("border-top-style", "none")
        // No images.
        try await expect(utterance.locator("img")).toHaveCount(0)
        try await expect(attestation.locator(".artifact-view")).toHaveCount(0)

        // A bounded box, opened with the sentence in view.
        let box = try #require(try await utterance.boundingBox())
        let mark = try #require(try await title.boundingBox())
        // Fourteen lines of 26px, its padding and border.
        let tallest: Double = 14 * 26 + 2 * 16 + 2 + 1
        #expect(box.height <= tallest)
        let markBottom = mark.y + mark.height
        let boxBottom = box.y + box.height
        #expect(box.y <= mark.y)
        #expect(markBottom <= boxBottom)
        // Scrolled to the sentence only where the passage overflows its box:
        // reflowed at every width (user, 2026-10-07), a short one fits.
        let scrolled = try await utterance.evaluate(
          "box => box.scrollHeight > box.clientHeight + 1 ? box.scrollTop : -1")
        if case .number(let top) = scrolled { #expect(top != 0) } else { Issue.record("No scrollTop") }

        // The link opens the testament's page at the utterance's page.
        let landed = try await page.evaluate(
          """
          fetch(document.querySelector('#record-row-s-1-1 .chicago-citation-view a').href)
            .then(r => (r.ok ? '' : 'HTTP ' + r.status + ' ') + new URL(r.url).pathname + new URL(r.url).search)
          """)
        #expect(landed == .string("\(scratch.reading.work.path)/vignettes/\(scratch.versionID)?semblance=2"))

        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()

        // Read again, the testament changed the word: the utterance is read where
        // it was anchored, still marked, and says it awaits explication again.
        _ = try TestAdmin.query(
          """
          INSERT INTO word_reanchorings (id, from_version_id, to_version_id, anchor_json, status, reason, utterance_id, created_at)
            VALUES ('\(UUID().uuidString.lowercased())', '\(scratch.versionID)', '\(scratch.reading.work.versionID.lowercased())',
              '{}', 'flagged', 'Its reading changed in the later version: scratchword', 'u-1', now());
          """)
        try await page.openHydrated(scratchWord.path)
        try await page.locator("#record-row-s-1-1 > .accordion-summary").click()
        try await expect(row).toHaveAttribute("data-open-finished", "true")
        let notice = attestation.locator(".reading-changed-view")
        try await expect(notice).toHaveText(
          "A later reading of this testament changed this word (Its reading changed in the later version: scratchword). It awaits explication again.")
        try await expect(attestation.locator(".utterance-view mark[data-highlight='title']")).toHaveText("scratchword")
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
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
