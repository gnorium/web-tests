import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The navbar's "…" menu opens as a sheet under the navbar, never flush with
/// the screen's top: the sheet and its panel start at the navbar's bottom
/// (a pane sheet's zero top once overrode it in the shared style sheet).
/// The navbar's icon buttons are medium (40) and plain, page furniture as
/// the pager's chevrons (user, 2026-10-10): no border, no ground, a
/// keyboard focus ring; they fit on the navbar's row at every width.
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
  func theIconButtonsAreMediumAndPlain(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/")
      let buttons = try await page.evaluate(
        """
        [...document.querySelectorAll('.navbar-right .button-view')].filter(b => b.getClientRects().length > 0)
          .map(b => { const r = b.getBoundingClientRect(); return [b.dataset.size, b.dataset.weight, Math.round(r.width), Math.round(r.height)].join(' ') })
        """, as: [String].self)
      #expect(!buttons.isEmpty)
      #expect(buttons.allSatisfy { $0 == "medium plain 40 40" }, "\(buttons)")
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
}
