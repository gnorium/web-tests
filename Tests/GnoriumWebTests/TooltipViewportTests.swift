import Testing
import WebTests
import WebTestsTesting

/// A tooltip's bubble stays inside the viewport: shifted back from the edge
/// it would cross, flipped to the end-aligned placement when shifting is not
/// enough, its arrow still at the trigger—and never a page scroll.
@Suite("Tooltip viewport containment", .serialized)
struct TooltipViewportTests {
  static let widths = [1440, 840, 375]

  @Test(arguments: [BrowserEngine.chrome], widths)
  func endPlacedIdentifierBubbleStaysInsideTheViewport(engine: BrowserEngine, width: Int) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: Viewport(width: width, height: 900)) { page in
      try await page.openHydrated("/mission-control/prompts/vignettes/compare?from=832FEFF0-9FD1-4711-86F9-AA1213C72996&to=CE0E6E42-ECF9-4BE8-A365-598219F30063")
      let triggers = page.locator(".vignette-identifier")
      try await expect(triggers).toHaveCount(2)
      // Left to right, then right to left, where a start-aligned bubble
      // grows from the trigger's other edge.
      for (direction, index) in [("ltr", 0), ("ltr", 1), ("rtl", 0), ("rtl", 1)] {
        _ = try await page.evaluate("document.querySelectorAll('.vignette-identity').forEach(side => side.dir = '\(direction)'); true", as: Bool.self)
        try await triggers.nth(index).hover()
        let bubble = page.locator(".tooltip-view[data-portal='true'][data-visible='true'] .tooltip-content")
        try await expect(bubble).toBeVisible()
        let report = try await page.evaluate("""
          (() => {
            const trigger = document.querySelectorAll('.vignette-identifier')[\(index)].getBoundingClientRect();
            const bubble = document.querySelector(".tooltip-view[data-portal='true'][data-visible='true'] .tooltip-content");
            const b = bubble.getBoundingClientRect();
            const arrow = getComputedStyle(bubble, '::after');
            const arrowX = b.left + parseFloat(arrow.left);
            const center = trigger.left + trigger.width / 2;
            // Inside the viewport less its scrollbar, which would cut it off.
            const root = document.documentElement;
            const fits = b.left >= 0 && b.right <= root.clientWidth && b.top >= 0 && b.bottom <= root.clientHeight;
            const noScroll = root.scrollWidth <= innerWidth && root.scrollWidth <= root.clientWidth;
            const aimed = Math.abs(arrowX - center) <= 1;
            const unwrapped = innerWidth < 768 || bubble.scrollWidth <= bubble.clientWidth && b.height < 2 * parseFloat(getComputedStyle(bubble).lineHeight) + 2 * parseFloat(getComputedStyle(bubble).paddingTop);
            return JSON.stringify({ fits, noScroll, aimed, unwrapped, left: b.left, right: b.right, clientWidth: root.clientWidth, scrollWidth: root.scrollWidth, arrowX, center });
          })()
          """, as: String.self)
        #expect(report.contains("\"fits\":true"), "\(report)")
        #expect(report.contains("\"noScroll\":true"), "\(report)")
        #expect(report.contains("\"aimed\":true"), "\(report)")
        #expect(report.contains("\"unwrapped\":true"), "\(report)")
        try await page.mouse.move(x: 0, y: 0)
        try await expect(triggers.nth(index)).toHaveAttribute("data-visible", "false")
      }
      // Before the hydration portals it, a bubble sits hidden in its
      // trigger, where it must not widen the page either.
      #expect(try await page.evaluate("""
        (() => {
          const trigger = document.querySelectorAll('.vignette-identifier')[1];
          const bubble = [...document.querySelectorAll(".tooltip-view[data-portal='true'] .tooltip-content")].find(b => b.textContent.trim().length === 36);
          const host = bubble.parentElement;
          trigger.appendChild(bubble);
          const width = document.documentElement.scrollWidth;
          host.appendChild(bubble);
          return width <= document.documentElement.clientWidth;
        })()
        """, as: Bool.self))
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }
}
