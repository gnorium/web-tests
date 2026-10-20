import Testing
import WebTests
import WebTestsTesting

/// Each week of the Watchtower's visitor charts says its dates and figure in
/// a real tooltip on its bar (user, 2026-10-20): shown on hover, on focus and
/// on a tap alike, never only in a native title. Desktop and phone, Chrome
/// headless.
@Suite("Visitors chart tooltips", .serialized)
struct VisitorsChartTooltipTests {
  static let shown = ".tooltip-view[data-portal='true'][data-visible='true'] .tooltip-content"

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWeeksFigureShowsOnHoverFocusAndTap(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/")
      let chart = page.locator(".watchtower-visitors-trend[data-metric='visitors']")
      let weeks = chart.locator(".watchtower-visitors-week")
      try await expect(weeks).toHaveCount(52)
      // No native title anywhere on the bars.
      try await expect(chart.locator("[title]")).toHaveCount(0)
      let last = weeks.last.locator(".watchtower-visitors-week-target")
      let label = try await last.getAttribute("aria-label") ?? ""
      #expect(label.contains(", so far): ") && label.hasSuffix(" visitors"), "\(label)")
      let bubble = page.locator(Self.shown)

      switch layout {
      case .desktop:
        try await last.hover()
        try await expect(bubble).toHaveText(label)
        try await page.mouse.move(x: 0, y: 0)
        try await expect(bubble).toHaveCount(0)
        // Focus, from the keyboard's side: the bar takes it and shows it.
        try await last.focus()
        try await expect(bubble).toHaveText(label)
        try await page.keyboard.press("Escape")
        try await expect(bubble).toHaveCount(0)
      case .phone:
        // A tap shows it and keeps it; a tap elsewhere closes it.
        try await last.tap()
        try await expect(bubble).toHaveText(label)
        try await page.locator("h1, h2").first.tap()
        try await expect(bubble).toHaveCount(0)
      }
      // The whole column is the target: as tall as the chart's bars.
      #expect(try await page.evaluate("""
        (() => {
          const target = document.querySelector(".watchtower-visitors-trend[data-metric='visitors'] .watchtower-visitors-week:last-child .watchtower-visitors-week-target");
          const bar = target.querySelector('.watchtower-visitors-week-bar');
          const t = target.getBoundingClientRect(), b = bar.getBoundingClientRect();
          return t.height >= b.height && t.height >= 64 && t.width > 0;
        })()
        """, as: Bool.self))
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }
}
