import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A shadow is elevation alone (user, 2026-10-09): only what floats above
/// the page casts one—a dropdown's, a combobox's and a menu's panel, a
/// popover, a tooltip, the search panel, the outline's drag preview and
/// toolbar. Nothing on the page does: no card lifted on hover, no chip, no
/// toggle's grip, no alert, no badge, no key hint, no ring. A shadow is a
/// design token, never a hand-written value: a panel's `--box-shadow-medium`,
/// the outline's dragged and floating layers' `--box-shadow-large`. Every
/// rule of every sheet a page loads is read, its hover and focus states with
/// them.
@Suite("Elevation shadows")
struct ElevationShadowsTests {
  static let floating = [
    "dropdown-menu", "combobox-menu", "menu-button-menu", "menu-list", "popover", "tooltip-content",
    "search-bar-dropdown", "outliner-drag-preview", "outliner-toolbar",
  ]

  @Test(arguments: [BrowserEngine.chrome])
  func onlyFloatingLayersCastShadows(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: .desktop) { page in
      for path in ["/", "/lexico-records", "/biblio-records", "/auth/sign-in", "/mission-control/overtures/bibliographic", "/mission-control/folksongs/bibliographic"] {
        try await page.openHydrated(path)
        let floating = Self.floating.map { "'\($0)'" }.joined(separator: ",")
        let grounded = try await page.evaluate(
          """
          (() => {
            const floating = [\(floating)];
            const out = [];
            const walk = (rules) => {
              for (const rule of rules) {
                if (rule.cssRules) walk(rule.cssRules);
                const shadow = rule.style && rule.style.getPropertyValue('box-shadow');
                if (!shadow || shadow.trim() === 'none') continue;
                if (!floating.some((name) => rule.selectorText.includes(name))) {
                  out.push(rule.selectorText);
                } else if (!/^var\\(--box-shadow-(medium|large)\\)( !important)?$/.test(shadow.trim())) {
                  out.push(`${rule.selectorText}: ${shadow} is not a shadow token`);
                }
              }
            };
            for (const sheet of document.styleSheets) {
              try { walk(sheet.cssRules); } catch (e) {}
            }
            return out;
          })()
          """)
        #expect(grounded.array?.isEmpty ?? true, "\(path): a shadow on the page, not a floating layer, or not a token: \(grounded.jsonText)")
      }
    }
  }
}
