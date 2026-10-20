import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A quote is shown in its testament (user, 2026-09-27): a sentiment's
/// quote is read in its testament's reader (SENSES-DESIGN 8.4), fetched
/// only once it comes into view, opened at its page with the page either
/// side drawn and its sentence (split across a page break here) in view,
/// the sentence and, more strongly, the word marked; its image off. It is
/// headed by its testament's Chicago note (user, 2026-10-18), its title a
/// link to the testament's row on its record's page at the quote's
/// page; no breadcrumb, no header box. Anywhere in
/// its highlight opens its gloss (user, 2026-10-09): its testament's Chicago
/// note, its title linked to the testament at its page, then its words. A throwaway
/// admin owns a scratch work with a permitted testament and a scratch word
/// attested in it, made by SQL and removed after.
@Suite("Quote", .serialized)
struct QuoteTests {
  /// Five pages; the quote on the third, its sentence ending on the
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
  func aQuoteIsShownInItsTestament(engine: BrowserEngine, layout: Layout) async throws {
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
          imageID: "https://example.org/iiif/webtests-p3", page: 3, line: 3, word: 3, surface: "scratchword"))
      word = scratchWord
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(scratchWord.path)
        let row = page.locator("#record-row-\(scratchWord.leaf)")
        let attestation = row.locator(".attestation-view")
        // Its first attestation against the margin, in the house style.
        try await expect(row.locator(".record-row-date").first).toHaveText("AD 1901")
        // Closed, its quote is not fetched.
        try await expect(row.locator(".attestation-quote")).toHaveAttribute("data-loaded", "false")
        let fetchedBefore = try await page.evaluate(
          "performance.getEntriesByType('resource').filter(e => e.name.includes('/quote?')).length")
        #expect(fetchedBefore == .number(0))

        try await page.locator("#record-row-\(scratchWord.leaf) > .accordion-summary").click()
        try await expect(row).toHaveAttribute("data-open-finished", "true")
        let quote = attestation.locator(".testament-view")
        try await expect(quote).toHaveCount(1)
        // Headed by its testament's Chicago note, above the reader, nothing
        // else: no breadcrumb, no header box.
        let heading = attestation.locator(".attestation-quote > .chicago-citation-view")
        try await expect(heading).toHaveCount(1)
        let work = scratch.reading.work
        try await expect(heading).toHaveText("\(work.author), \(work.title) (1958), 3.")
        let headingAbove = try await attestation.evaluate(
          "(view) => { const h = view.querySelector('.chicago-citation-view').getBoundingClientRect(); const q = view.querySelector('.testament-view').getBoundingClientRect(); return h.bottom <= q.top }")
        #expect(headingAbove == .bool(true), "the citation is not above the quote")
        try await expect(attestation.locator(".breadcrumb-view")).toHaveCount(0)
        try await expect(attestation.locator(".header-view")).toHaveCount(0)
        // Its title links to the testament's leaf row on the record's page,
        // its reader on the quote's page.
        let headingLink = heading.locator("cite a")
        try await expect(headingLink).toHaveCount(1)
        let leafUUID = try TestAdmin.query(
          "SELECT shape_json::jsonb -> ('manifest-' || upper(f.id::text)) ->> 'uuid' FROM biblio_record_versions v, bibliographic_fountains f WHERE v.id = '\(scratch.versionID)' AND f.id = (SELECT bibliographic_fountain_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())');"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        try await expect(headingLink).toHaveAttribute("href", "\(work.path)?image=2#record-row-\(leafUUID)")
        // The page and the page either side drawn; the rest wait to be
        // turned to.
        try await expect(quote.locator(".artifact-markup .tei-page")).toHaveCount(3)
        try await expect(quote).not.toContainText("Page 1,")
        try await expect(quote).not.toContainText("Page 5,")
        // The sentence on both sides of the page break; the word more strongly.
        let third = quote.locator(".tei-page[data-service-id='https://example.org/iiif/webtests-p3']")
        try await expect(third.locator("mark[data-highlight='sentence']")).toHaveTexts(["Here the", "begins"])
        try await expect(
          quote.locator(".tei-page[data-service-id='https://example.org/iiif/webtests-p4'] mark[data-highlight='sentence']")
        ).toHaveCount(1)
        let title = third.locator("mark[data-highlight='title']")
        try await expect(title).toHaveText("scratchword")
        // Stronger by color alone: its weight is the text's own.
        let weights = try await quote.evaluate(
          "box => [...box.querySelectorAll('mark')].map(m => getComputedStyle(m).fontWeight).join(' ')")
        #expect(weights == .string("400 400 400 400"))
        // The word boxed as the OED boxes it; the sentence unboxed.
        try await expect(title).toHaveCSS("border-top-style", "solid")
        try await expect(quote.locator("mark[data-highlight='sentence']").first).toHaveCSS("border-top-style", "none")
        // One reader, its image off at first.
        try await expect(attestation.locator(".artifact-view")).toHaveCount(1)
        try await expect(attestation.locator(".artifact-canvas-toggle button")).toHaveAttribute("aria-pressed", "false")

        // Opened with the sentence in view in the markup pane.
        let pane = try #require(try await quote.locator(".artifact-markup").first.boundingBox())
        let mark = try #require(try await title.boundingBox())
        #expect(pane.y <= mark.y)
        #expect(mark.y + mark.height <= pane.y + pane.height)

        // A word inside the quote opens the quote's gloss: its
        // Chicago note—the voice, the title italic (a report is
        // book-length), the date, the page as printed (its pb n)—then its
        // words, the one clicked expanded.
        try await quote.locator(".tei-word").filter(hasText: "begins").first.click()
        let gloss = quote.locator(".gloss-sheet[data-state='open']")
        try await expect(gloss).toHaveCount(1)
        try await expect(gloss.locator(".gloss-sheet-title .record-label-title")).toHaveText("scratchword")
        try await expect(gloss.locator(".gloss-sheet-title .record-label-meta")).toHaveCount(0)
        // Public, under the lexico-record quoting it.
        let address = try await quote.evaluate(
          "(box) => box.closest('[data-quote-gloss]').getAttribute('data-quote-gloss')")
        #expect(address.string?.contains("/quotes/") == true && address.string?.hasPrefix("/lexico-records/") == true, "the gloss is at \(address), the record at \(scratchWord.path)")
        let citation = gloss.locator(".chicago-citation-view")
        try await expect(citation).toHaveText("\(work.author), \(work.title) (1958), 3.")
        try await expect(citation.locator("cite.chicago-citation-title")).toHaveCSS("font-style", "italic")
        let begins = gloss.locator(".gloss-word-row").filter(hasText: "begins")
        try await expect(begins).toHaveCount(1)
        let open = try await begins.evaluate("(row) => row.querySelector('.accordion-details').hasAttribute('open')")
        #expect(open == .bool(true), "the word clicked is not expanded in the quote's gloss")
        try await expect(gloss.locator(".gloss-word-row").filter(hasText: "scratchword")).toHaveCount(1)

        // Its title opens the testament's page at the quote's page.
        let landed = try await page.evaluate(
          """
          fetch(document.querySelector('#record-row-\(scratchWord.leaf) .gloss-sheet .chicago-citation-view a').href)
            .then(r => (r.ok ? '' : 'HTTP ' + r.status + ' ') + new URL(r.url).pathname + new URL(r.url).search)
          """)
        #expect(landed == .string("\(scratch.reading.work.path)/vignettes/\(scratch.versionID)?image=2"))
        try await page.keyboard.press("Escape")
        try await expect(page.locator(".gloss-sheet[data-state='open']")).toHaveCount(0)

        // On the record's Disputorium object, whose record need not be
        // permitted yet, the same gloss is served under the object's page.
        let objectPath = "/mission-control/madrigals/lexicographic/\(scratchWord.madrigalID)"
        try await page.openHydrated(objectPath)
        _ = try await page.evaluate(
          """
          (() => { const slot = document.querySelector('.attestation-view');
            for (let d = slot.closest('.accordion-details'); d; d = d.parentElement.closest('.accordion-details'))
              if (!d.open) d.querySelector(':scope > .accordion-summary').click();
            slot.scrollIntoView({ block: 'center' }); return true })()
          """)
        let objectQuote = page.locator(".attestation-view .testament-view").first
        try await expect(objectQuote).toHaveCount(1)
        let objectAddress = try await objectQuote.evaluate(
          "(box) => box.closest('[data-quote-gloss]').getAttribute('data-quote-gloss')")
        #expect(
          objectAddress.string?.hasPrefix(objectPath + "/quotes/") == true,
          "the object's gloss is at \(objectAddress)")
        try await objectQuote.locator(".tei-word").filter(hasText: "begins").first.click()
        let objectGloss = objectQuote.locator(".gloss-sheet[data-state='open']")
        try await expect(objectGloss.locator(".chicago-citation-view")).toHaveText(
          "\(work.author), \(work.title) (1958), 3.")
        try await expect(objectGloss.locator(".gloss-word-row").filter(hasText: "begins")).toHaveCount(1)
        try await page.keyboard.press("Escape")

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
