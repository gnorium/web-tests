import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A button group is one row where its buttons fit, and a column of buttons
/// each the row's full width only where they don't (`CrowdedRowHydration`
/// marks it `data-crowded`). The mark follows the room the row has, both
/// ways: squeezed, the group crowds; given its room back, it is one row
/// again, never stuck stretched.
@Suite("Button group crowding")
struct ButtonGroupCrowdingTests {
  @Test(arguments: [1440, 840, 600, 420, 320])
  func theGroupCrowdsOnlyWhileItsButtonsDoNotFit(width: Int) async throws {
    try await withPage(.chrome, gnorium, viewport: Viewport(width: width, height: 900)) { page in
      try await page.openHydrated("/")
      try await page.locator("[data-navbar-ellipsis]").filter(visible: true).first.click()
      try await expect(page.locator("#navbar-ellipsis-menu")).toHaveAttribute("data-state", "open")
      _ = try await page.evaluate(
        "Promise.all(document.getAnimations().filter(a => a.effect?.getTiming().iterations !== Infinity).map(a => a.finished.catch(() => null))).then(() => 1)", as: Int.self)
      // Each visible group: its mark, whether its buttons share one row, and
      // whether each is the row's full width.
      let state = """
        (() => [...document.querySelectorAll('#navbar-ellipsis-menu .button-group-view')]
          .filter(group => group.getClientRects().length > 0)
          .map(group => {
            const boxes = [...group.children].map(child => child.getBoundingClientRect());
            const oneRow = boxes.every(box => Math.round(box.top) === Math.round(boxes[0].top));
            const fullWidth = boxes.every(box => Math.abs(box.width - group.clientWidth) <= 1);
            return [group.dataset.crowded, oneRow ? 'one-row' : 'rows', fullWidth ? 'full-width' : 'own-width'].join(' ');
          }))()
        """
      let settled = "new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve(1))))"
      let before = try await page.evaluate(state, as: [String].self)
      #expect(!before.isEmpty, "the menu's color scheme and contrast groups are in view at \(width)")
      for group in before {
        #expect(group == "false one-row own-width" || group == "true rows full-width", "at \(width): \(group)")
      }
      // Squeezed far narrower than its buttons, every group crowds.
      _ = try await page.evaluate(
        "(document.querySelectorAll('#navbar-ellipsis-menu .button-group-view').forEach(group => group.style.width = '64px'), 1)",
        as: Int.self)
      _ = try await page.evaluate(settled, as: Int.self)
      let squeezed = try await page.evaluate(state, as: [String].self)
      #expect(squeezed.allSatisfy { $0 == "true rows full-width" }, "squeezed at \(width): \(squeezed)")
      // Its room given back, each is as it was: the mark is never sticky.
      _ = try await page.evaluate(
        "(document.querySelectorAll('#navbar-ellipsis-menu .button-group-view').forEach(group => group.style.width = ''), 1)",
        as: Int.self)
      _ = try await page.evaluate(settled, as: Int.self)
      let after = try await page.evaluate(state, as: [String].self)
      #expect(after == before, "room given back at \(width): \(after), was \(before)")
      try await page.expectNoErrors()
    }
  }
}
