import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The Reference Sources page, linked from the footer: the dictionaries by
/// language and the catalogs by kind, each a plain list, and a search per
/// group that opens the chosen source's search for the typed term in a new
/// tab. `window.open` is stubbed to record what would open, so no test
/// reaches another site.
@Suite("Reference sources", .serialized)
struct ReferenceSourcesTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func thePageListsTheSourcesAndSearchesThem(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/reference-sources")
      try await expect(page.locator("footer .footer-nav a[href='/reference-sources']")).toHaveText("Reference Sources")
      try await expect(page.locator(".page-heading")).toHaveText("Reference Sources")

      // English's dictionaries, in the registry's order, each its name
      // linked home, the OED noted as by subscription.
      let english = page.locator("#reference-sources-dictionaries-eng")
      try await expect(english.locator("h3")).toHaveText("English")
      let sources = english.locator(".reference-sources-source")
      try await expect(sources).toHaveCount(3)
      try await expect(sources.nth(0).locator("a")).toHaveAttribute("href", "https://www.oed.com/")
      try await expect(sources.nth(0)).toContainText("(subscription)")
      try await expect(sources.nth(1)).not.toContainText("(subscription)")
      try await expect(sources.nth(2).locator("a")).toHaveAttribute("href", "https://www.merriam-webster.com/")
      try await expect(page.locator("#reference-sources-dictionaries-every-language .reference-sources-source"))
        .toHaveCount(2)
      try await expect(page.locator("#reference-sources-catalogs-national h3")).toHaveText("National libraries")

      // Nothing opens anywhere: what would, is recorded.
      _ = try await page.evaluate("window.open = (url, target) => { window.__opened = [url, target]; return null; }")
      /// What was opened, once something was (up to five seconds).
      func opened() async throws -> [String] {
        for _ in 0..<50 {
          let seen = try await page.evaluate("window.__opened || []", as: [String].self)
          if !seen.isEmpty { return seen }
          try await Task.sleep(nanoseconds: 100_000_000)
        }
        return []
      }

      // The first dictionary, as it stands chosen.
      let search = english.locator(".reference-sources-search")
      try await search.locator("input[name='q']").fill("computer")
      try await search.locator("button[type='submit']").click()
      #expect(try await opened() == ["https://www.oed.com/search/dictionary/?scope=Entries&q=computer", "_blank"])
      #expect(try await page.url().hasSuffix("/reference-sources"))

      _ = try await page.evaluate("window.__opened = []")

      // Another, chosen; the term encoded, Enter submitting.
      try await search.locator(".dropdown-trigger").click()
      try await search.locator(".dropdown-option").filter(hasText: "Merriam-Webster", exact: true).click()
      let term = search.locator("input[name='q']")
      try await term.fill("ice cream")
      try await term.press("Enter")
      #expect(try await opened() == ["https://www.merriam-webster.com/dictionary/ice%20cream", "_blank"])

      _ = try await page.evaluate("window.__opened = []")

      // A catalog: a title with a diacritic.
      let national = page.locator("#reference-sources-catalogs-national .reference-sources-search")
      try await national.locator("input[name='q']").fill("Straße")
      try await national.locator("button[type='submit']").click()
      #expect(try await opened() == ["https://catalogue.bl.uk/nde/search?query=Stra%C3%9Fe&vid=44BL_MAIN:BLL01_NDE", "_blank"])

      // No term, nothing opens.
      _ = try await page.evaluate("window.__opened = []")
      try await national.locator("input[name='q']").fill("")
      try await national.locator("button[type='submit']").click()
      try await Task.sleep(nanoseconds: 500_000_000)
      #expect(try await page.evaluate("window.__opened.length", as: Int.self) == 0)

      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }
}
