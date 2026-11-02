import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Evidence first (user, 2026-11-03): a copy's former owner carries its own
/// sources, the same Source everywhere. On Submit Testament an owner card
/// holds its Name, its Certainty, its Start and End cards stacked, its
/// sources, then one row, "+ Source" and "− Former owner"; "+ Former owner"
/// after every card. Each source is its Source accordion of its fields, its
/// Quote cards under it (each its artifact: a sourceless work's text-only
/// reader, its quote typed there), then "+ Quote" and "− Source". The
/// owner's row posts its sources in its JSON, each card's quote one of them.
@Suite("Former owner sources")
struct FormerOwnerSourcesTests {
  static let form = "/mission-control/submit/bibliographic/testament"

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func anOwnerCarriesItsSources(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated(Self.form)
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.openHydrated(Self.form)

      let owner = page.locator("[data-item-list='former-owner'] > [data-item-section='true']").first
      try await page.locator("input[name='former-owner-item1-text-input']").fill("Sir Henry Bunbury")
      // Its row: "+ Source", then "− Former owner" (hidden while alone);
      // the Start and End cards stacked.
      let row = owner.locator(":scope > .item-actions")
      try await expect(row.locator(".item-source-add-btn")).toHaveText("Source")
      try await expect(row.locator(".item-source-add-btn")).toHaveAttribute("aria-label", "Add source")
      let stacked = try await owner.evaluate(
        """
        (o) => { const s = o.querySelector('.form-items-period-start').getBoundingClientRect();
          const e = o.querySelector('.form-items-period-end').getBoundingClientRect();
          return e.top >= s.bottom - 0.5 && Math.abs(e.left - s.left) < 1; }
        """
      ).bool
      #expect(stacked == true, "Start over End, one column")

      // Two sources, each the one Source shape.
      try await row.locator(".item-source-add-btn").click()
      try await row.locator(".item-source-add-btn").click()
      let sources = owner.locator(":scope > .form-items-sources > .evidence-source-view")
      try await expect(sources).toHaveCount(2)
      let first = sources.first
      try await expect(first.locator(".source-accordion-view .accordion-title").first).toHaveText("Source")
      try await expect(first.locator(".quote-passage-record .origin-record-field-view"), timeout: .seconds(15))
        .toHaveCount(1)
      try await expect(first.locator(".quote-passage-actions .button-label")).toHaveTexts(["Quote", "Source"])
      let order = try await owner.evaluate(
        """
        (o) => { const fields = o.querySelector('.form-items-fields'), sources = o.querySelector('.form-items-sources'),
            row = o.querySelector(':scope > .item-actions');
          return !!(fields.compareDocumentPosition(sources) & Node.DOCUMENT_POSITION_FOLLOWING)
            && !!(sources.compareDocumentPosition(row) & Node.DOCUMENT_POSITION_FOLLOWING); }
        """
      ).bool
      #expect(order == true, "its fields, its sources, then its row")

      // A sourceless work: its text-only reader in its Quote card, the quote
      // typed there; "+ Quote" another card on the same source.
      try await first.locator("input[name$='-source-url-title']").fill("A Catalogue of the Library")
      let cards = first.locator(".quote-passage-quotes > .quote-passage-quote")
      try await expect(cards).toHaveCount(1)
      let pane = cards.first.locator(".quote-passage-text .tei-page-text")
      try await expect(pane, timeout: .seconds(15)).toBeAttached()
      try await pane.fill("Bought of Sir Henry Bunbury.")
      let quote = first.locator("input[name$='-quote']").first
      try await expect(quote).toHaveValue("Bought of Sir Henry Bunbury.")
      try await first.locator(".quote-passage-actions .quote-passage-quote-add").click()
      try await expect(cards).toHaveCount(2)
      let second = cards.nth(1).locator(".quote-passage-text .tei-page-text")
      try await expect(second, timeout: .seconds(15)).toBeAttached()
      try await second.fill("Sir Henry Bunbury his book.")
      try await expect(quote).toHaveValue("Bought of Sir Henry Bunbury.\n\nSir Henry Bunbury his book.")
      try await expect(cards.first.locator(".quote-passage-quote-remove")).toBeVisible()
      // Never the quote as text outside its artifact.
      try await expect(first.locator(".quote-passage-quote-text")).toHaveCount(0)

      // Posted in the owner's row.
      let json = page.locator("input[name='former-owner-json']")
      let posted = try await json.evaluate("(i) => i.value").string ?? ""
      #expect(posted.contains("\"evidence\":["), "the row posts its sources: \(posted)")
      #expect(posted.contains("Sir Henry Bunbury his book."), "each card's quote: \(posted)")

      // "− Quote" lets one go; "− Source" the other source.
      try await cards.nth(1).locator(".quote-passage-quote-remove").click()
      try await expect(cards).toHaveCount(1)
      try await expect(quote).toHaveValue("Bought of Sir Henry Bunbury.")
      try await sources.nth(1).locator(".quote-passage-actions .quote-passage-source-remove").click()
      try await expect(sources).toHaveCount(1)
      let after = try await json.evaluate("(i) => i.value").string ?? ""
      #expect(!after.contains("his book"), "the quote let go is gone: \(after)")
      // On a phone the form's outline scrolls, never its artifacts.
      if layout == .desktop { try await page.expectNoHorizontalOverflow() }
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.expectNoErrors()
    }
  }
}
