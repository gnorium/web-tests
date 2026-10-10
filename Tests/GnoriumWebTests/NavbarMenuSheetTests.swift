import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The navbar's "…" menu opens as a sheet under the navbar, never flush with
/// the screen's top: the sheet and its panel start at the navbar's bottom
/// (a pane sheet's zero top once overrode it in the shared style sheet).
/// The navbar's icon buttons are large (48) and plain (user, 2026-10-10):
/// no border, no ground, an 18px icon, a keyboard focus ring. The brand
/// scales with its slot, so the brand and three buttons fit at 320.
@Suite("Navbar menu sheet")
struct NavbarMenuSheetTests {
  @Test(arguments: enginesAndLayouts)
  func theSheetOpensBelowTheNavbar(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/")
      try await page.locator("[data-navbar-ellipsis]").filter(visible: true).first.click()
      try await expect(page.locator("#navbar-ellipsis-menu")).toHaveAttribute("data-state", "open")
      _ = try await page.evaluate(
        "Promise.all(document.getAnimations().filter(a => a.effect?.getTiming().iterations !== Infinity).map(a => a.finished.catch(() => null))).then(() => 1)", as: Int.self)
      let tops = try await page.evaluate(
        """
        (() => {
          const nav = document.querySelector('.navbar-view').getBoundingClientRect().bottom;
          const sheet = document.querySelector('#navbar-ellipsis-menu');
          return [nav, sheet.getBoundingClientRect().top, sheet.querySelector('.sheet-panel').getBoundingClientRect().top]
            .map(Math.round);
        })()
        """, as: [Int].self)
      #expect(tops[0] == 96, "the navbar is 96 tall: \(tops)")
      #expect(tops[1] == tops[0] && tops[2] == tops[0], "the sheet and its panel start under the navbar: \(tops)")
    }
  }

  @Test(arguments: enginesAndLayouts)
  func theIconButtonsAreLargeAndPlain(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/")
      let buttons = try await page.evaluate(
        """
        [...document.querySelectorAll('.navbar-right .button-view')].filter(b => b.getClientRects().length > 0)
          .map(b => { const r = b.getBoundingClientRect(); return [b.dataset.size, b.dataset.weight, Math.round(r.width), Math.round(r.height)].join(' ') })
        """, as: [String].self)
      #expect(!buttons.isEmpty)
      #expect(buttons.allSatisfy { $0 == "large plain 48 48" }, "\(buttons)")
      // Keyboard focus rings the plain button.
      // Reached from the keyboard: focus the one before it, then Tab.
      try await page.locator("[data-navbar-ellipsis] button").filter(visible: true).first.focus()
      try await page.keyboard.press("Shift+Tab")
      try await page.keyboard.press("Tab")
      let ring = try await page.evaluate(
        "(() => { const b = document.activeElement; if (!b.matches('[data-navbar-ellipsis] button')) return 'focus on ' + b.outerHTML.slice(0, 80); const s = getComputedStyle(b); return [s.outlineStyle, s.outlineWidth, s.backgroundColor, s.borderColor].join(' ') })()",
        as: String.self)
      #expect(ring.hasPrefix("solid 2px"), "focused: \(ring)")
      try await page.expectNoHorizontalOverflow()
    }
  }

  struct NavbarGeometry: Decodable {
    let scrollWidth: Double
    let clientWidth: Double
    let brandRight: Double
    let firstButtonLeft: Double
    let lastButtonRight: Double
    let viewportWidth: Double
    let buttons: [Double]
    let logo: Double
    let title: Double
  }

  /// A page with the brand and all three buttons: nothing overflows down to
  /// 320, every button is 48 and fully on screen, a gap parts the brand from
  /// the buttons, and the logo stays twice the wordmark's size.
  @Test
  func theBrandAndThreeButtonsFitAt320() async throws {
    guard gnorium.engines.contains(.chrome) else { return }
    try await withPage(.chrome, gnorium, viewport: .init(width: 320, height: 640)) { page in
      try await page.openHydrated("/biblio-records")
      for width in [1400, 768, 414, 375, 360, 320] {
        try await page.setViewport(width: width, height: 900)
        let g = try await page.evaluate(
          """
          (() => {
            const header = document.querySelector('.navbar-header');
            const rect = el => el.getBoundingClientRect();
            const buttons = [...document.querySelectorAll('.navbar-right .button-view')].filter(b => b.getClientRects().length > 0);
            return {scrollWidth: header.scrollWidth, clientWidth: header.clientWidth,
              brandRight: rect(document.querySelector('.navbar-brand')).right,
              firstButtonLeft: rect(buttons[0]).left, lastButtonRight: rect(buttons[buttons.length - 1]).right,
              viewportWidth: document.documentElement.clientWidth,
              buttons: buttons.flatMap(b => [rect(b).width, rect(b).height]),
              logo: rect(document.querySelector('.navbar-brand .logo-view')).height,
              title: parseFloat(getComputedStyle(document.querySelector('.navbar-brand .brand-title')).fontSize)};
          })()
          """, as: NavbarGeometry.self)
        #expect(g.scrollWidth <= g.clientWidth, "\(width): \(g)")
        #expect(g.buttons.count == 6 && g.buttons.allSatisfy { abs($0 - 48) < 0.5 }, "\(width): \(g.buttons)")
        #expect(g.firstButtonLeft - g.brandRight >= 8, "\(width): \(g)")
        #expect(g.lastButtonRight <= g.viewportWidth, "\(width): \(g)")
        #expect(abs(g.logo - 2 * g.title) < 0.5, "\(width): \(g)")
        #expect(g.title <= 32, "\(width): \(g)")
        try await page.expectNoHorizontalOverflow()
      }
    }
  }
}
