import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A Quote card's XML numbers its lines 1, 2, 3… (user, 2026-11-05: on
/// Submit Testament, a new citation's Quote switched to XML read 0 on every
/// line). A reader's code lines are laid out only as they come into view
/// (`content-visibility: auto`, which contains each line's style), so a
/// counter run across the lines never reached a line's number: each line
/// carries its own (`data-code-number`), which its `::before` shows, and
/// keeps it as the quote typed is written into it. Signed out, Chrome
/// headless.
@Suite("Quote XML numbers")
struct QuoteXMLNumbersTests {
  struct Lines: Decodable {
    let count: Int
    let numbers: [String]
    let before: [String]
  }

  /// The code lines of `card`'s XML: how many, each one's number, and what
  /// each one's `::before` shows.
  static func lines(_ card: Locator) async throws -> Lines {
    let read = try await card.locator(".tei-page-raw[data-layer='markup'] .code-view[data-lined='true']").first.evaluate(
      """
      (code) => {
        const lines = [...code.querySelectorAll('.code-line')]
        return JSON.stringify({
          count: lines.length,
          numbers: lines.map((line) => line.getAttribute('data-code-number') || ''),
          before: lines.map((line) => getComputedStyle(line, '::before').content),
        })
      }
      """)
    return try JSONDecoder().decode(Lines.self, from: Data((read.string ?? "{}").utf8))
  }

  static func expectNumbered(_ lines: Lines, _ moment: String) {
    #expect(lines.count > 0, "\(moment): the XML has no lines")
    #expect(lines.numbers == (0..<lines.count).map { String($0 + 1) }, "\(moment): \(lines.numbers)")
    for (index, shown) in lines.before.enumerated() {
      // Its own number, as the cascade gives it: the attribute it reads,
      // or the number itself; never a counter.
      #expect(
        shown == "attr(data-code-number)" || shown == "\"\(index + 1)\"",
        "\(moment): line \(index + 1) shows \(shown)")
    }
  }

  @Test(arguments: [BrowserEngine.chrome])
  func aNewCitationsQuoteNumbersItsXMLFromOne(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium) { page in
      let form = "/mission-control/submit/bibliographic/testament"
      try await page.openHydrated(form)
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.openHydrated(form)

      // Outgoing citations › + Citation, on the work.
      let view = page.locator(".outgoing-citations-view:has(#outgoing-citations-0)").first
      let add = view.locator(".outgoing-citations-actions .outgoing-citations-add").first
      if !(try await add.isVisible()) {
        try await view.locator(".accordion-summary").first.click()
      }
      try await add.click()
      let citations = view.locator(".outgoing-citations-list > .outgoing-citation")
      try await expect(citations).toHaveCount(1)
      // A sourceless work: its Quote card's text-only reader.
      let source = citations.first.locator(".evidence-source-view")
      try await source.locator("input[name$='-source-url-title']").fill("Web tests numbered work")
      let card = source.locator(".quote-passage-quotes > .quote-passage-quote").first
      try await expect(card.locator(".quote-passage-text .tei-page-text"), timeout: .seconds(15)).toBeAttached()

      // XML on, by the button's own click.
      let viewer = card.locator(".artifact-view").first
      _ = try await card.locator(".artifact-xml-toggle button").first.evaluate("(button) => { button.click(); return true }")
      try await expect(viewer).toHaveAttribute("data-raw", "true")
      try await expect(card.locator(".tei-page-raw[data-layer='markup'] .code-line").first).toBeVisible()
      Self.expectNumbered(try await Self.lines(card), "XML on")

      // The quote typed is written into its line: the numbers stay.
      _ = try await card.locator(".artifact-xml-toggle button").first.evaluate("(button) => { button.click(); return true }")
      try await expect(viewer).toHaveAttribute("data-raw", "false")
      try await card.locator(".quote-passage-text .tei-page-text").fill("A numbered quote.")
      _ = try await card.locator(".artifact-xml-toggle button").first.evaluate("(button) => { button.click(); return true }")
      try await expect(viewer).toHaveAttribute("data-raw", "true")
      try await expect(card.locator(".tei-page-raw[data-layer='markup'] .code-code")).toContainText("A numbered quote.")
      Self.expectNumbered(try await Self.lines(card), "typed")

      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.expectNoErrors()
    }
  }
}
