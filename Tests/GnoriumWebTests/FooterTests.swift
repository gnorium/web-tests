import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The footer's links sit in one wrapping row, spaced by the gap alone: no
/// "|" between them, in the markup or drawn by CSS.
@Suite("Footer")
struct FooterTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func linksWrapInOneRowWithoutSeparators(engine: BrowserEngine, layout: Layout) async throws {
    let viewport = layout.viewport(for: engine)
    try await withPage(engine, gnorium, viewport: viewport) { page in
      try await page.openHydrated("/")
      let nav = page.locator("footer .footer-nav")
      try await expect(nav).toBeVisible()
      try await expect(nav).toHaveCSS("display", "flex")
      try await expect(nav).toHaveCSS("flex-direction", "row")
      try await expect(nav).toHaveCSS("flex-wrap", "wrap")

      let text = try await nav.textContent()
      #expect(!text.contains("|"), "the footer's text has a | separator: \(text)")
      let drawn = try await nav.evaluate(
        """
        (nav) => [...nav.querySelectorAll('*')].flatMap((el) =>
          ['::before', '::after'].map((pseudo) => getComputedStyle(el, pseudo).content)
        ).filter((content) => content.includes('|'))
        """)
      #expect(drawn.array?.isEmpty ?? true, "CSS draws a | separator: \(drawn.jsonText)")

      let links = nav.locator("a")
      let count = try await links.count()
      try #require(count > 1)
      var boxes: [BoundingBox] = []
      for link in try await links.all() {
        boxes.append(try #require(try await link.boundingBox(), "a footer link is not visible"))
      }
      let navBox = try #require(try await nav.boundingBox())
      // Every link stays inside the row's width, wrapping rather than
      // running off the side.
      for box in boxes {
        #expect(box.maxX <= navBox.maxX + 0.5, "a footer link runs past the footer: \(box) in \(navBox)")
        #expect(box.maxX <= Double(viewport.width), "a footer link runs off screen: \(box)")
      }
      // In the wide layout, one row: every link on the same line.
      if layout == .desktop {
        let tops = Set(boxes.map { Int($0.minY.rounded()) })
        #expect(tops.count == 1, "the footer links sit on \(tops.count) lines at 1400 wide: \(boxes)")
      }
    }
  }
}
