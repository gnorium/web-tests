import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Evidence first (user, 2026-11-03): a node's claims rest on its
/// Outgoing citations, one accordion a node under its Note. On Submit
/// Testament a copy's "+ Citation" stamps a card: its Claim (the copy's
/// fields, and each former owner by name as it is typed), its Source
/// accordion holding its fields, its Quote cards (a sourceless work's
/// text-only reader, its quote typed there) and its own row, "+ Quote" and
/// "− Source" (user, 2026-11-03). A typed quote's words naming the claim
/// are picked as any quote's (a text selection and "+ Form"), never
/// matched by the owner's name. The copy's list posts as JSON, each new
/// card its claim and its Source, its forms by place.
@Suite("Outgoing citations")
struct FormerOwnerSourcesTests {
  static let form = "/mission-control/submit/bibliographic/testament"

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aCopyCitesItsOwner(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated(Self.form)
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.openHydrated(Self.form)

      try await page.locator("input[name='former-owner-item1-text-input']").fill("Sir Henry Bunbury")
      let view = page.locator(".outgoing-citations-view:has(#outgoing-citations-4)")
      try await expect(view).toHaveCount(1)
      // Its owners' Start and End cards stacked, one column.
      let owner = page.locator("[data-item-list='former-owner'] > [data-item-section='true']").first
      let stacked = try await owner.evaluate(
        """
        (o) => { const s = o.querySelector('.form-items-period-start').getBoundingClientRect();
          const e = o.querySelector('.form-items-period-end').getBoundingClientRect();
          return e.top >= s.bottom - 0.5 && Math.abs(e.left - s.left) < 1; }
        """
      ).bool
      #expect(stacked == true, "Start over End, one column")

      // "+ Citation": a card, its Claim offering the owner by name.
      let add = view.locator(".outgoing-citations-actions .outgoing-citations-add")
      try await expect(add).toHaveText("Citation")
      try await expect(add).toHaveAttribute("aria-label", "Add citation")
      try await add.click()
      let cards = view.locator(".outgoing-citations-list > .outgoing-citation")
      try await expect(cards).toHaveCount(1)
      let card = cards.first
      let claim = card.locator(".outgoing-citation-claim")
      try await expect(claim.locator(".dropdown-option[data-value^='formerOwners:']"))
        .toHaveText("Former owner › Sir Henry Bunbury")
      try await claim.locator(".dropdown-trigger").click()
      try await claim.locator(".dropdown-option[data-value^='formerOwners:']").filter(visible: true).first.click()

      // Its Source: a sourceless work, its quote typed in its card.
      let source = card.locator(".evidence-source-view")
      try await expect(source.locator(".source-accordion-view .accordion-title").first).toHaveText("Source")
      try await source.locator("input[name$='-source-url-title']").fill("A Catalogue of the Library")
      let quotes = source.locator(".quote-passage-quotes > .quote-passage-quote")
      try await expect(quotes).toHaveCount(1)
      // Inside its Source accordion, after its fields, then its own row.
      try await expect(source.locator(".source-accordion-view .quote-passage-quotes > .quote-passage-quote")).toHaveCount(1)
      try await expect(source.locator(".source-accordion-view .quote-passage-actions .button-label"))
        .toHaveTexts(["Quote", "Source"])
      let pane = quotes.first.locator(".quote-passage-text .tei-page-text")
      try await expect(pane, timeout: .seconds(15)).toBeAttached()
      // The whole typing area the caret's (user, 2026-11-03): its
      // placeholder and the empty room under it show the I-beam, and a
      // click there puts the caret at the end of the text.
      let markup = quotes.first.locator(".quote-passage-text .artifact-markup")
      let beams = try await markup.evaluate(
        """
        (m) => { const p = m.querySelector('.tei-page-text');
          return [getComputedStyle(m).cursor, getComputedStyle(p).cursor, getComputedStyle(p, '::before').cursor,
            getComputedStyle(p, '::before').content].join('|'); }
        """
      ).string ?? ""
      #expect(beams == "text|text|text|\"Quote\"", "the I-beam over the typing area, its placeholder Quote: \(beams)")
      try await pane.fill("Bought of Sir")
      let room = try await markup.evaluate(
        """
        (m) => { m.scrollIntoView({ block: 'center' });
          const p = m.querySelector('.tei-page-text').getBoundingClientRect(), b = m.getBoundingClientRect();
          const x = b.left + b.width / 2, y = Math.min(b.bottom - 2, p.bottom + 8);
          const off = document.elementFromPoint(x, y)?.closest('.tei-page-text') === null;
          // The pointer lands in the visual viewport (a phone's page laid
          // out wider than its screen is drawn smaller).
          const v = window.visualViewport;
          return [(x - v.offsetLeft) * v.scale, (y - v.offsetTop) * v.scale, b.bottom > p.bottom + 4 && off]; }
        """)
      if case .array(let point) = room, point.count == 3, point[2].bool == true,
        let x = point[0].double, let y = point[1].double
      {
        try await page.mouse.click(x: x, y: y)
        let focused = try await pane.evaluate("(p) => document.activeElement === p").bool
        #expect(focused == true, "a click in the empty room focuses the quote")
        try await page.keyboard.type(" Henry Bunbury.")
      } else {
        try await pane.fill("Bought of Sir Henry Bunbury.")
      }
      try await expect(pane).toHaveText("Bought of Sir Henry Bunbury.")

      // Its words picked as a form as any quote's, by a selection and "+
      // Form": never matched by the owner's name (user, 2026-11-03).
      let typedWords = quotes.first.locator(".quote-typed-word")
      try await expect(typedWords).toHaveCount(5)
      // All it holds is the quote: violet, the spaces between its words too,
      // as typed (user, 2026-11-03); no form till one is picked.
      try await expect(quotes.first.locator(".quote-typed-word.tei-highlight")).toHaveCount(5)
      try await expect(quotes.first.locator(".quote-typed-space.tei-highlight")).toHaveCount(4)
      try await expect(quotes.first.locator("[data-highlight='title']")).toHaveCount(0)
      try await page.addForm(
        in: source, from: ".quote-typed-word[data-typed-word='3']", to: ".quote-typed-word[data-typed-word='5']")
      try await expect(quotes.first.locator(".quote-typed-word[data-highlight='title']")).toHaveTexts(
        ["Sir", "Henry", "Bunbury."])
      // One strip (user, 2026-11-03): the spaces between its words filled,
      // its first word opening it and its last closing it.
      try await expect(quotes.first.locator(".quote-typed-space[data-quote-strip]")).toHaveCount(2)
      try await expect(quotes.first.locator("[data-quote-strip-start]")).toHaveText("Sir")
      try await expect(quotes.first.locator("[data-quote-strip-end]")).toHaveText("Bunbury.")

      // Posted as the copy's list: its claim the owner's row, its Source,
      // its form by place.
      let json = page.locator("input[name='outgoing-citations-json-4']")
      let posted = try await json.evaluate("(i) => i.value").string ?? ""
      #expect(posted.contains("\"claim\":\"formerOwners:"), "its claim the owner's row: \(posted)")
      #expect(posted.contains("\"source\":"), "a new card posts its Source: \(posted)")
      #expect(posted.contains("Bought of Sir Henry Bunbury."), "its quote: \(posted)")
      #expect(
        posted.contains(#""forms":[[[{"surface":"Sir","word":3},{"surface":"Henry","word":4},{"surface":"Bunbury.","word":5}]]]"#),
        "its form by place: \(posted)")
      // Typed over, a pick that no longer stands is let go, never moved.
      try await pane.fill("Bought of Sir H. Bunbury.")
      try await expect(quotes.first.locator("[data-highlight='title']")).toHaveCount(0)
      let retyped = try await json.evaluate("(i) => i.value").string ?? ""
      #expect(!retyped.contains("\"forms\""), "its stale form let go: \(retyped)")

      // "− Source" lets it go.
      let remove = card.locator(".quote-passage-actions .quote-passage-source-remove")
      try await expect(remove).toHaveText("Source")
      try await remove.click()
      try await expect(cards).toHaveCount(0)
      try await expect(json).toHaveValue("")
      try await page.expectNoOverflowButTrees()
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.expectNoErrors()
    }
  }

  /// A citation may cite a web page (user, 2026-11-03): a Source URL that
  /// is no IIIF manifest. Its Title and Language are prefilled from the
  /// page's own, its Class "Website", its Accessed today's, frozen; its Quote card the
  /// text-only reader, the quote typed as the page shows it. Posted as a web
  /// page's, kept on the citation itself.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aCopyCitesAWebPage(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    let html = Data("<!doctype html><html lang=\"en\"><head><title>Shakespeare Census</title></head><body><p>Found by Sir H. E. Bunbury at Barton, 1823.</p></body></html>".utf8)
    let fixture = try await FixtureServer(files: ["/sc/29/": .init(contentType: "text/html; charset=utf-8", body: html)])
    defer { fixture.stop() }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated(Self.form)
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.openHydrated(Self.form)

      try await page.locator("input[name='former-owner-item1-text-input']").fill("Sir Henry Bunbury")
      let view = page.locator(".outgoing-citations-view:has(#outgoing-citations-4)")
      try await view.locator(".outgoing-citations-actions .outgoing-citations-add").click()
      let card = view.locator(".outgoing-citations-list > .outgoing-citation").first
      let claim = card.locator(".outgoing-citation-claim")
      try await claim.locator(".dropdown-trigger").click()
      try await claim.locator(".dropdown-option[data-value^='formerOwners:']").filter(visible: true).first.click()

      let source = card.locator(".evidence-source-view")
      let accessed = source.locator(".quote-passage-accessed input")
      try await expect(accessed).toBeDisabled()
      try await expect(accessed).toHaveValue("")
      try await source.locator(".quote-passage-url input[type='url']").fill(fixture.baseURL + "/sc/29/")
      // Read as a web page: today's access date, its title, its Class.
      try await expect(source.locator(".quote-passage-fields-view"), timeout: .seconds(15))
        .toHaveAttribute("data-quote-website", "true")
      let today = try await page.evaluate(
        "new Date().toLocaleDateString('en-US', {month: 'long', day: 'numeric', year: 'numeric', timeZone: 'UTC'})"
      ).string ?? ""
      try await expect(accessed).toHaveValue(today)
      try await expect(source.locator("input[name$='-source-url-title']")).toHaveValue("Shakespeare Census")
      try await expect(source.locator("input[name$='-source-url-language']")).toHaveValue("eng")
      try await expect(source.locator("input[name$='-source-url-class']")).toHaveValue("website")
      // Its quote typed in its text-only reader, no images, at the text's
      // own size.
      let quotes = source.locator(".quote-passage-quotes > .quote-passage-quote")
      try await expect(quotes).toHaveCount(1)
      let pane = quotes.first.locator(".quote-passage-text .tei-page-text")
      try await expect(pane, timeout: .seconds(15)).toBeAttached()
      try await expect(quotes.first.locator(".artifact-canvas .image-view")).toHaveCount(0)
      try await pane.fill("Found by Sir H. E. Bunbury at Barton, 1823.")
      // Nothing marked till a person picks it: the name as printed.
      try await expect(quotes.first.locator("[data-highlight='title']")).toHaveCount(0)
      // Its reader's footer: XML, Reflow and fullscreen (user, 2026-11-03);
      // no header label for a page of no image. Reflow off, each typed
      // line one line as typed; on, its text runs on.
      let viewer = quotes.first.locator(".quote-passage-text .artifact-view")
      try await expect(viewer.locator(".artifact-footer .artifact-reflow-toggle")).toHaveCount(1)
      try await expect(viewer).toHaveAttribute("data-reflow", "false")
      let unwrapped = try await pane.evaluate("(p) => getComputedStyle(p).whiteSpace").string
      #expect(unwrapped == "pre", "Reflow off, never wrapped: \(unwrapped ?? "")")
      try await viewer.locator(".artifact-reflow-toggle button").click()
      try await expect(viewer).toHaveAttribute("data-reflow", "true")
      let wrapped = try await pane.evaluate("(p) => getComputedStyle(p).whiteSpace").string
      #expect(wrapped == "pre-wrap", "Reflow on, it runs on: \(wrapped ?? "")")
      try await viewer.locator(".artifact-reflow-toggle button").click()
      // Find reads the quote as typed (user, 2026-11-03).
      try await viewer.locator(".testament-find-button button").click()
      try await viewer.locator(".testament-find-input input").fill("Barton")
      try await expect(viewer.locator(".testament-find-count"), timeout: .seconds(10)).toHaveText("1 of 1")
      try await viewer.locator(".testament-find-button button").click()
      try await page.addForm(
        in: source, from: ".quote-typed-word[data-typed-word='3']", to: ".quote-typed-word[data-typed-word='6']")

      let json = page.locator("input[name='outgoing-citations-json-4']")
      let posted = try await json.evaluate("(i) => i.value").string ?? ""
      #expect(posted.contains(#"{"surface":"H.","word":4}"#), "its form by place: \(posted)")
      #expect(posted.contains("\"website\":true"), "posted as a web page's: \(posted)")
      #expect(posted.contains("\"sourceClass\":\"website\""), "its Class: \(posted)")
      #expect(posted.contains("Found by Sir H. E. Bunbury at Barton, 1823."), "its quote: \(posted)")
      #expect(!posted.contains("startImage"), "no images: \(posted)")

      // Its URL cleared: no web page, its Accessed empty again.
      try await source.locator(".quote-passage-url input[type='url']").fill("")
      try await expect(source.locator(".quote-passage-fields-view"), timeout: .seconds(15))
        .toHaveAttribute("data-quote-website", "false")
      try await expect(accessed).toHaveValue("")
      try await page.expectNoOverflowButTrees()
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.expectNoErrors()
    }
  }

  /// A web page's quote read: its URL a link to the page, its access date,
  /// the quote as typed in its text-only reader until its snapshot is made,
  /// its picked words magenta (its forms, never a name matched), and its
  /// page opened at the quote (a Text Fragment: a quote of more than eight
  /// words by its first four and its last four).
  @Test(arguments: [BrowserEngine.chrome])
  func aWebPagesQuoteOpensAtItself(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    let quote = #"{"forms":[[{"surface":"H.","word":4},{"surface":"E.","word":5},{"surface":"Bunbury","word":6}]],"text":"Found by Sir H. E. Bunbury at Barton, 1823.","website":{"accessed":"2026-11-03","class":"website","language":"eng","title":"Shakespeare Census","url":"https://web-tests.invalid/sc/29/"}}"#
    let address = "/mission-control/lexicographic/web-quote?card=head&quote="
      + (quote.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? quote)
    try await withPage(engine, gnorium) { page in
      try await page.goto(address)
      try await expect(page.locator(".datum-view").filter(hasText: "URL").locator("a")).toHaveAttribute(
        "href", "https://web-tests.invalid/sc/29/")
      try await expect(page.locator(".datum-view").filter(hasText: "Accessed")).toContainText("November 3, 2026")
      try await expect(page.locator(".quote-source-artifact .tei-page-text")).toContainText("Found by Sir H. E. Bunbury")
      // One form side by side: one strip, the spaces in it.
      try await expect(page.locator(".quote-source-artifact .tei-page-text [data-highlight='title']")).toHaveTexts(
        ["H. E. Bunbury"])
      try await expect(page.locator(".web-quote-links-page")).toHaveAttribute(
        "href", "https://web-tests.invalid/sc/29/#:~:text=Found%20by%20Sir%20H.,Bunbury%20at%20Barton%2C%201823.")
      try await expect(page.locator(".web-quote-links-archived")).toHaveCount(0)
    }
  }
}
