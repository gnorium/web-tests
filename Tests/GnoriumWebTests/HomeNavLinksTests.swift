import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The home page's three links over the glyph field—Biblio-records, Graph,
/// Lexico-records—are 16px, the interface floor (user, 2026-10-10): on one
/// line where they fit, and on a phone one link a row, never wrapping into
/// a line and a half.
@Suite("Home navigation links")
struct HomeNavLinksTests {
  @Test(arguments: enginesAndLayouts)
  func theThreeLinksStandOnOneLineOrOneARow(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/")
      let links = page.locator(".home-nav-links .nav-link")
      try await expect(links).toHaveCount(3)
      let tops = try await page.evaluate(
        "[...document.querySelectorAll('.home-nav-links .nav-link')].map(a => Math.round(a.getBoundingClientRect().top))",
        as: [Int].self)
      if layout == .phone {
        #expect(Set(tops).count == 3, "on a phone, one link a row: \(tops)")
        #expect(tops == tops.sorted(), "in order, top to bottom: \(tops)")
      } else {
        #expect(Set(tops).count == 1, "the links stand on one line: \(tops)")
      }
      let size = try await page.evaluate(
        "getComputedStyle(document.querySelector('.home-nav-links .nav-link')).fontSize", as: String.self)
      #expect(size == "16px", "the links are 16px: \(size)")
    }
  }
}
