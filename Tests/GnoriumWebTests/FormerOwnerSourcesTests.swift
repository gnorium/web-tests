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
      if layout == .desktop { try await page.expectNoHorizontalOverflow() }
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.expectNoErrors()
    }
  }
}
