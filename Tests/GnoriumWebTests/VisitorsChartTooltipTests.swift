import Testing
import WebTests
import WebTestsTesting

/// Each week of the Watchtower's visitor charts says its dates and figure in
/// a real tooltip on its bar (user, 2026-10-20): shown on hover, on focus and
/// on a tap alike, never only in a native title. A week with no data has no
/// bar, no tooltip and no focus stop (user, 2026-10-21); a week with a real
/// zero keeps its zero-height bar and its "0 …" tooltip. Desktop and phone,
/// Chrome headless.
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
      // Every week of the three charts: known, a bar and its tooltip (a
      // zero's bar zero high, its label "0 …"); unknown, none of them.
      struct Weeks: Decodable {
        let unknownWithParts: [String]
        let knownWithoutParts: [String]
        let knownLabeledUnknown: [String]
        let zeroBarRaised: [String]
      }
      let weeksState = try await page.evaluate("""
        (() => {
          const out = { unknownWithParts: [], knownWithoutParts: [], knownLabeledUnknown: [], zeroBarRaised: [] }
          for (const week of document.querySelectorAll('.watchtower-visitors-week')) {
            const name = week.closest('.watchtower-visitors-trend').dataset.metric + ' ' + week.dataset.week
            const tooltip = week.querySelector('.tooltip-view, .watchtower-visitors-week-tooltip')
            const target = week.querySelector('.watchtower-visitors-week-target')
            const focusable = week.querySelector('[tabindex]')
            const rect = week.querySelector('.watchtower-visitors-week-bar rect')
            if (week.dataset.known !== 'true') {
              if (tooltip || target || focusable || rect) out.unknownWithParts.push(name)
              continue
            }
            if (!tooltip || !target || !rect || target.getAttribute('tabindex') !== '0') { out.knownWithoutParts.push(name); continue }
            const label = target.getAttribute('aria-label') || ''
            if (label.includes('): 0 ')) {
              if (rect.getBoundingClientRect().height > 0.5) out.zeroBarRaised.push(name)
            } else if (label.includes('): —')) {
              out.knownLabeledUnknown.push(name)
            }
          }
          return out
        })()
        """, as: Weeks.self)
      #expect(weeksState.unknownWithParts.isEmpty, "weeks with no data drawn as bars: \(weeksState.unknownWithParts)")
      #expect(weeksState.knownWithoutParts.isEmpty, "known weeks without a bar or tooltip: \(weeksState.knownWithoutParts)")
      #expect(weeksState.knownLabeledUnknown.isEmpty, "known weeks labeled unknown: \(weeksState.knownLabeledUnknown)")
      #expect(weeksState.zeroBarRaised.isEmpty, "zero weeks with a raised bar: \(weeksState.zeroBarRaised)")
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }
}
