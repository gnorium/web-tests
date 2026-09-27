import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The Reference Sources page, linked from the footer: two tabs,
/// Bibliographic and Lexicographic, drawn alike (the sources under their
/// language's name, then "Open data"), the records list's filter bar with a
/// language filter
/// (English where it is entered, every language once the filter is cleared
/// as any filter is, kept in the query), each group a plain list, and a
/// search per group (Query, Source, Search, one column) that opens the
/// chosen source's search for the query in a new tab. `window.open` is stubbed to record what would open,
/// so no test reaches another site.
@Suite("Reference sources", .serialized)
struct ReferenceSourcesTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func thePageListsTheSourcesAndSearchesThem(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/reference-sources?language=eng")
      try await expect(page.locator("footer .footer-nav a[href='/reference-sources?language=eng']"))
        .toHaveText("Reference Sources")
      try await expect(page.locator(".page-heading")).toHaveText("Reference Sources")
      // Entered: the bibliographic sources, in English, then the open data.
      try await expect(page.locator("#bibliographic .reference-sources-group")).toHaveCount(2)
      try await expect(page.locator("#reference-sources-bibliographic-eng h3")).toHaveText("English")
      try await expect(page.locator("#reference-sources-bibliographic-open h3")).toHaveText("Open data")
      try await expect(page.locator("#lexicographic")).toHaveCount(0)
      // The Lexicographic tab keeps the language, in the query.
      try await page.locator(".reference-sources-tabs a").filter(hasText: "Lexicographic").click()
      try await expect(page.locator("#lexicographic .reference-sources-group")).toHaveCount(2)
      try await expect(page.locator("#reference-sources-lexicographic-eng h3")).toHaveText("English")
      try await expect(page.locator("#reference-sources-lexicographic-open h3")).toHaveText("Open data")
      try await expect(page.locator("#reference-sources-lexicographic-open .reference-sources-source").nth(0))
        .toContainText("English Wiktionary")
      #expect(try await page.url().hasSuffix("/reference-sources?kind=lexicographic&language=eng"))
      // The filter cleared as any filter is — its value picked again, then
      // Apply: every language, every Wiktionary edition.
      try await page.openHydrated("/reference-sources?kind=lexicographic&language=eng")
      let filter = page.locator(".filter-bar-view")
      try await filter.locator(".filter-bar-value-select .dropdown-trigger").click()
      try await filter.locator(".filter-bar-value-select .dropdown-option").filter(hasText: "English", exact: true).click()
      try await filter.locator(".filter-bar-apply").click()
      try await expect(page.locator("#lexicographic .reference-sources-group")).toHaveCount(13)
      try await expect(
        page.locator("#reference-sources-lexicographic-open .reference-sources-source").filter(hasText: "French Wiktionary")
      ).toHaveCount(1)
      // As the records list reads a cleared filter: the language empty.
      let cleared = URLComponents(string: try await page.url())?.queryItems ?? []
      #expect(cleared.contains(URLQueryItem(name: "kind", value: "lexicographic")))
      #expect(cleared.first { $0.name == "language" }?.value ?? "" == "", "\(cleared)")
      try await page.openHydrated("/reference-sources?kind=lexicographic&language=eng")

      // English's sources, in the registry's order, each its name linked
      // home, the OED noted as by subscription.
      let english = page.locator("#reference-sources-lexicographic-eng")
      let sources = english.locator(".reference-sources-source")
      try await expect(sources).toHaveCount(3)
      try await expect(sources.nth(0).locator("a")).toHaveAttribute("href", "https://www.oed.com/")
      try await expect(sources.nth(0)).toContainText("(subscription)")
      try await expect(sources.nth(1)).not.toContainText("(subscription)")
      try await expect(sources.nth(2).locator("a")).toHaveAttribute("href", "https://www.merriam-webster.com/")
      try await expect(english.locator(".reference-sources-search label").first).toContainText("Query")

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
      #expect(try await page.url().hasSuffix("/reference-sources?kind=lexicographic&language=eng"))

      _ = try await page.evaluate("window.__opened = []")

      // Another, chosen; the term encoded, Enter submitting.
      try await search.locator(".dropdown-trigger").click()
      try await search.locator(".dropdown-option").filter(hasText: "Middle English Dictionary", exact: true).click()
      let term = search.locator("input[name='q']")
      try await term.fill("ice cream")
      try await term.press("Enter")
      #expect(
        try await opened() == [
          "https://quod.lib.umich.edu/m/middle-english-dictionary/dictionary?utf8=%E2%9C%93&search_field=hnf&q=ice%20cream",
          "_blank",
        ])

      _ = try await page.evaluate("window.__opened = []")

      // The open data's English Wiktionary searches the English edition.
      let open = page.locator("#reference-sources-lexicographic-open .reference-sources-search")
      try await open.locator("input[name='q']").fill("computer")
      try await open.locator("button[type='submit']").click()
      #expect(try await opened() == ["https://en.wiktionary.org/wiki/Special:Search?search=computer", "_blank"])

      // One column: the term, then the source, then the button, each below
      // the one before.
      let tops = try await page.evaluate(
        "[...document.querySelectorAll('#reference-sources-lexicographic-eng .reference-sources-search > *')].map((el) => el.getBoundingClientRect().top)",
        as: [Double].self)
      #expect(tops.count == 3 && tops[0] < tops[1] && tops[1] < tops[2])

      // A catalog: a title with a diacritic.
      try await page.openHydrated("/reference-sources?language=eng")
      _ = try await page.evaluate("window.open = (url, target) => { window.__opened = [url, target]; return null; }")
      let national = page.locator("#reference-sources-bibliographic-eng .reference-sources-search")
      try await national.locator(".dropdown-trigger").click()
      try await national.locator(".dropdown-option").filter(hasText: "British Library", exact: true).click()
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
