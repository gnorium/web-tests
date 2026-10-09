import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The home page's three links over the glyph field—Biblio-records, Graph,
/// Lexico-records—stand on one line at every width (user, 2026-10-09): at
/// 14px they fit a 375px phone; LinkView's 16px plain weight made them wrap.
@Suite("Home navigation links")
struct HomeNavLinksTests {
  @Test(arguments: enginesAndLayouts)
  func theThreeLinksStandOnOneLine(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/")
      let links = page.locator(".home-nav-links .nav-link")
      try await expect(links).toHaveCount(3)
      let tops = try await page.evaluate(
        "[...document.querySelectorAll('.home-nav-links .nav-link')].map(a => Math.round(a.getBoundingClientRect().top))",
        as: [Int].self)
      #expect(Set(tops).count == 1, "the links stand on one line: \(tops)")
      let size = try await page.evaluate(
        "getComputedStyle(document.querySelector('.home-nav-links .nav-link')).fontSize", as: String.self)
      #expect(size == "14px", "the links keep their 14px: \(size)")
    }
  }
}
