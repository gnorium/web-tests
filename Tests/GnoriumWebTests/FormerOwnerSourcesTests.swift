import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Evidence first (user, 2026-11-03): a node's claims rest on its
/// Outgoing citations, one accordion a node under its Note. On Submit
/// Testament a copy's "+ Citation" stamps a card: its Claim (the copy's
/// fields, and each former owner by name as it is typed), its Source, its
/// Quote cards (a sourceless work's text-only reader, its quote typed
/// there), then "+ Quote" and "− Citation". The copy's list posts as JSON,
/// each new card its claim and its Source.
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
      let pane = quotes.first.locator(".quote-passage-text .tei-page-text")
      try await expect(pane, timeout: .seconds(15)).toBeAttached()
      try await pane.fill("Bought of Sir Henry Bunbury.")

      // Posted as the copy's list: its claim the owner's row, its Source.
      let json = page.locator("input[name='outgoing-citations-json-4']")
      let posted = try await json.evaluate("(i) => i.value").string ?? ""
      #expect(posted.contains("\"claim\":\"formerOwners:"), "its claim the owner's row: \(posted)")
      #expect(posted.contains("\"source\":"), "a new card posts its Source: \(posted)")
      #expect(posted.contains("Bought of Sir Henry Bunbury."), "its quote: \(posted)")

      // "− Citation" lets it go.
      let remove = card.locator(".quote-passage-actions .quote-passage-source-remove")
      try await expect(remove).toHaveText("Citation")
      try await remove.click()
      try await expect(cards).toHaveCount(0)
      try await expect(json).toHaveValue("")
      try await page.expectNoHorizontalOverflow()
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

      let json = page.locator("input[name='outgoing-citations-json-4']")
      let posted = try await json.evaluate("(i) => i.value").string ?? ""
      #expect(posted.contains("\"website\":true"), "posted as a web page's: \(posted)")
      #expect(posted.contains("\"sourceClass\":\"website\""), "its Class: \(posted)")
      #expect(posted.contains("Found by Sir H. E. Bunbury at Barton, 1823."), "its quote: \(posted)")
      #expect(!posted.contains("startImage"), "no images: \(posted)")

      // Its URL cleared: no web page, its Accessed empty again.
      try await source.locator(".quote-passage-url input[type='url']").fill("")
      try await expect(source.locator(".quote-passage-fields-view"), timeout: .seconds(15))
        .toHaveAttribute("data-quote-website", "false")
      try await expect(accessed).toHaveValue("")
      try await page.expectNoHorizontalOverflow()
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.expectNoErrors()
    }
  }

  /// A web page's quote read: its URL a link to the page, its access date,
  /// the quote as typed in its text-only reader until its snapshot is made,
  /// and its page opened at the quote (a Text Fragment: a quote of more
  /// than eight words by its first four and its last four).
  @Test(arguments: [BrowserEngine.chrome])
  func aWebPagesQuoteOpensAtItself(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    let quote = #"{"claim":"Sir Henry Bunbury","text":"Found by Sir H. E. Bunbury at Barton, 1823.","website":{"accessed":"2026-11-03","class":"website","language":"eng","title":"Shakespeare Census","url":"https://web-tests.invalid/sc/29/"}}"#
    let address = "/mission-control/lexicographic/web-quote?card=head&quote="
      + (quote.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? quote)
    try await withPage(engine, gnorium) { page in
      try await page.goto(address)
      try await expect(page.locator(".datum-view").filter(hasText: "URL").locator("a")).toHaveAttribute(
        "href", "https://web-tests.invalid/sc/29/")
      try await expect(page.locator(".datum-view").filter(hasText: "Accessed")).toContainText("November 3, 2026")
      try await expect(page.locator(".quote-source-artifact .tei-page-text")).toContainText("Found by Sir H. E. Bunbury")
      try await expect(page.locator(".web-quote-links-page")).toHaveAttribute(
        "href", "https://web-tests.invalid/sc/29/#:~:text=Found%20by%20Sir%20H.,Bunbury%20at%20Barton%2C%201823.")
      try await expect(page.locator(".web-quote-links-archived")).toHaveCount(0)
    }
  }
}
