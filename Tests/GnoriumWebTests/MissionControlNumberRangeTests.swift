import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A Mission Control list's numbers filter by range (`?tokens=1000..5000`,
/// either end open): a row switched to Tokens or Cost is two number inputs,
/// Start and End, side by side in the row, 8 apart, whose typed ends make
/// the one value the bar submits; and Repeated, last, keeps rows whose
/// chosen column another row shares (`?repeated=objectID`). Applied, the
/// rows hold what was typed. Needs an admin, made for the test and removed
/// after (see `TestAdmin`).
@Suite("Mission Control number ranges", .serialized)
struct MissionControlNumberRangeTests {
  @Test(arguments: Layout.allCases)
  func ledgerRangesAndRepeated(layout: Layout) async throws {
    let engine = BrowserEngine.chrome
    guard gnorium.engines.contains(engine) else { return }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await run(engine: engine, viewport: layout.viewport(for: engine), admin: admin)
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }

  private func run(engine: BrowserEngine, viewport: Viewport, admin: TestAdmin) async throws {
    try await withPage(engine, gnorium, viewport: viewport, cookies: [admin.cookie]) { page in
      try await page.openHydrated("/mission-control/ledger/bibliographic")
      try await page.expectNoErrors()

      // Row 1 switched to Tokens: Start and End, a start typed.
      let first = page.locator(".filter-bar-row").first
      try await first.locator(".filter-bar-field-picker .dropdown-trigger").click()
      try await first.locator(".filter-bar-field-picker .dropdown-option[data-value='tokens']").click()
      let tokens = first.locator(".number-range-input-view")
      try await expect(tokens).toHaveAttribute("data-hydrated", "true")
      let start = tokens.locator(".number-range-input-start input")
      let end = tokens.locator(".number-range-input-end input")
      try await expect(start).toHaveAttribute("placeholder", "Start")
      try await expect(end).toHaveAttribute("placeholder", "End")
      try await expect(start).toHaveAttribute("aria-label", "Tokens start")
      let gap = try await tokens.locator(".number-range-input-ends").evaluate("(e) => getComputedStyle(e).columnGap")
        .string
      #expect(gap == "8px", "Start and End sit 8 apart: \(gap ?? "")")
      let startBox = try #require(try await start.boundingBox())
      let endBox = try #require(try await end.boundingBox())
      #expect(abs(startBox.y - endBox.y) < 1, "Start and End share a line")
      #expect(endBox.x > startBox.x + startBox.width, "End follows Start")
      try await start.fill("1000")
      try await expect(tokens.locator("input.number-range-input-value")).toHaveValue("1000..")

      // A row added for Cost, its end a decimal.
      try await page.locator(".filter-bar-add-btn").first.click()
      let second = page.locator(".filter-bar-row").last
      try await second.locator(".filter-bar-field-picker .dropdown-trigger").click()
      try await second.locator(".filter-bar-field-picker .dropdown-option[data-value='cost']").click()
      let cost = second.locator(".number-range-input-view")
      try await expect(cost).toHaveAttribute("data-hydrated", "true")
      try await cost.locator(".number-range-input-end input").fill("0.5")
      try await expect(cost.locator("input.number-range-input-value")).toHaveValue("..0.5")

      // And one for Repeated: Object ID.
      try await page.locator(".filter-bar-add-btn").first.click()
      let third = page.locator(".filter-bar-row").last
      try await third.locator(".filter-bar-field-picker .dropdown-trigger").click()
      try await third.locator(".filter-bar-field-picker .dropdown-option[data-value='repeated']").click()
      try await third.locator(".filter-bar-value-select .dropdown-trigger").click()
      try await third.locator(".filter-bar-value-select .dropdown-option[data-value='objectID']").click()

      try await page.locator(".filter-bar-apply").click()
      try await expect(page, timeout: .seconds(15)).toHaveURL("tokens, cost and repeated") { url in
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.contains { $0.name == "tokens" && $0.value == "1000.." }
          && items.contains { $0.name == "cost" && $0.value == "..0.5" }
          && items.contains { $0.name == "repeated" && $0.value == "objectID" }
      }
      try await page.expectNoErrors()
      // The rows hold what was applied, drawn by the server.
      let applied = page.locator(".filter-bar-row .number-range-input-view")
      try await expect(applied).toHaveCount(2)
      try await expect(applied.first.locator(".number-range-input-start input")).toHaveValue("1000")
      try await expect(applied.last.locator(".number-range-input-end input")).toHaveValue("0.5")
      try await expect(page.locator(".filter-bar-value-select input[type='hidden'][name='repeated']"))
        .toHaveValue("objectID")

      // A server-drawn range is bound too: its start cleared, it is open.
      let drawn = applied.first
      try await expect(drawn).toHaveAttribute("data-hydrated", "true")
      try await drawn.locator(".number-range-input-start input").fill("")
      try await drawn.locator(".number-range-input-end input").fill("5000")
      try await expect(drawn.locator("input.number-range-input-value")).toHaveValue("..5000")
    }
  }

  /// The Nocturnes list's Duration is typed in seconds; its rows come back
  /// from a link with the range and Repeated in force.
  @Test func nocturnesDurationAndRepeated() async throws {
    let engine = BrowserEngine.chrome
    guard gnorium.engines.contains(engine) else { return }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine), cookies: [admin.cookie]) {
        page in
        try await page.openHydrated(
          "/mission-control/nocturnes/bibliographic?duration=1.5..&cost=..0.25&repeated=resemblance")
        try await page.expectNoErrors()
        let ranges = page.locator(".filter-bar-row .number-range-input-view")
        try await expect(ranges).toHaveCount(2)
        try await expect(ranges.first.locator(".number-range-input-start input")).toHaveValue("1.5")
        try await expect(ranges.first.locator(".number-range-input-start input"))
          .toHaveAttribute("aria-label", "Duration start")
        try await expect(ranges.last.locator(".number-range-input-end input")).toHaveValue("0.25")
        try await expect(page.locator(".filter-bar-value-select input[type='hidden'][name='repeated']"))
          .toHaveValue("resemblance")
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }
}
