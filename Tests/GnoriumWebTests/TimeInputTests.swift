import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The time input on an object list's Created at filter (user, 2026-10-08):
/// a span of the day, Time start and Time end, each hours and minutes in a scrolling
/// column, in the date picker's popover—by keyboard, and by touch or
/// pointer. It submits one key (`?createdAt=09:00..17:30`), UTC, and narrows
/// the rows to that time of any day, as the Created at column shows it.
@Suite("Time input", .serialized)
struct TimeInputTests {
  static let list = "/mission-control/madrigals/bibliographic"
  /// ID, Title, Status, Created by, Created on, Created at.
  static let createdAtColumn = 6

  @Test(arguments: enginesAndLayouts)
  func createdAtSpan(engine: BrowserEngine, layout: Layout) async throws {
    let viewport = layout.viewport(for: engine)
    try await withPage(engine, gnorium, viewport: viewport) { page in
      try await page.openHydrated(Self.list)
      let row = page.locator(".filter-bar-row").first
      try await row.locator(".filter-bar-field-picker .dropdown-trigger").click()
      try await row.locator(".filter-bar-field-picker .dropdown-option").filter(hasText: "Created at", exact: true).click()

      let input = row.locator(".time-input-view")
      let field = input.locator(".time-input-field input")
      let popover = input.locator(".time-input-popover")
      let value = input.locator("input.time-input-value")
      try await expect(input).toHaveAttribute("data-hydrated", "true")
      try await expect(input).toHaveAttribute("data-range", "true")
      try await expect(field).toHaveAttribute("readonly")
      try await expect(field).toHaveAttribute("inputmode", "none")
      try await expect(field).toHaveAttribute("placeholder", "Created at")

      // Keyboard: Enter opens it on Time start's hours; ↓ sets an hour (the
      // minutes start at :00), Tab goes on to the next column, End to its
      // last value.
      try await field.press("Enter")
      try await expect(popover).toBeVisible()
      try await expect(field).toHaveAttribute("aria-expanded", "true")
      let focusedColumn = { () async throws -> String? in
        try await page.evaluate("document.activeElement?.closest('.time-input-column')?.getAttribute('aria-label')")
          .string
      }
      #expect(try await focusedColumn() == "Time start hours")
      try await page.keyboard.press("ArrowDown")
      try await expect(value).toHaveValue("01:00..")
      try await expect(field).toHaveValue("Since 01:00 UTC")
      try await page.keyboard.press("Tab")
      #expect(try await focusedColumn() == "Time start minutes")
      try await page.keyboard.press("ArrowDown")
      try await expect(value).toHaveValue("01:01..")
      try await page.keyboard.press("Tab")
      #expect(try await focusedColumn() == "Time end hours")
      try await page.keyboard.press("End")
      try await expect(value).toHaveValue("01:01..23:00")
      try await page.keyboard.press("Tab")
      try await page.keyboard.press("End")
      try await expect(value).toHaveValue("01:01..23:59")
      try await expect(field).toHaveValue("01:01–23:59 UTC")
      try await page.keyboard.press("Escape")
      try await expect(popover).toBeHidden()
      try await expect(field).toBeFocused()

      // Touch or pointer: a tap on an hour sets it.
      if viewport.touch { try await field.tap() } else { try await field.click() }
      try await expect(popover).toBeVisible()
      let popoverBox = try #require(try await popover.boundingBox())
      #expect(popoverBox.minX >= 0 && popoverBox.maxX <= Double(viewport.width), "the popover runs off screen: \(popoverBox)")
      let nine = popover.locator(".time-input-column[aria-label='Time start hours'] .time-input-option[data-value='9']")
      // Brought round in its column, as a finger scrolls it.
      _ = try await nine.evaluate("el => el.scrollIntoView({ block: 'nearest' })")
      if viewport.touch { try await nine.tap() } else { try await nine.click() }
      try await expect(value).toHaveValue("09:01..23:59")
      try await expect(nine).toHaveAttribute("aria-selected", "true")

      // Reset empties it; Done closes it.
      try await popover.getByRole(.button, name: "Reset").click()
      try await expect(value).toHaveValue("")
      try await expect(field).toHaveValue("")
      let five = popover.locator(".time-input-column[aria-label='Time end hours'] .time-input-option[data-value='5']")
      _ = try await nine.evaluate("el => el.scrollIntoView({ block: 'nearest' })")
      _ = try await five.evaluate("el => el.scrollIntoView({ block: 'nearest' })")
      if viewport.touch { try await nine.tap(); try await five.tap() } else { try await nine.click(); try await five.click() }
      try await expect(value).toHaveValue("09:00..05:00")
      try await popover.getByRole(.button, name: "Done").click()
      try await expect(popover).toBeHidden()

      // Applied: one key, and every row was created across midnight from
      // 09:00 to 05:00 UTC.
      try await page.locator(".filter-bar-apply").click()
      try await expect(page, timeout: .seconds(15)).toHaveURL("createdAt=09:00..05:00") { url in
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
          .contains { $0.name == "createdAt" && $0.value == "09:00..05:00" } ?? false
      }
      try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
      try await expect(page.locator(".filter-bar-value-input .time-input-field input")).toHaveValue("09:00–05:00 UTC")
      for minutes in try await Self.createdAtMinutes(page) {
        #expect(minutes >= 9 * 60 || minutes <= 5 * 60, "\(minutes / 60):\(minutes % 60) is outside 09:00–05:00")
      }

      // With Created on beside it, the time within those days.
      try await page.openHydrated("\(Self.list)?createdOn=-30d..&createdAt=12:00..12:59")
      for minutes in try await Self.createdAtMinutes(page) {
        #expect((12 * 60...12 * 60 + 59).contains(minutes), "\(minutes / 60):\(minutes % 60) is not in 12:00–12:59")
      }

      try await page.expectNoErrors()
      try await page.expectNoHorizontalOverflow()
    }
  }

  /// Every listed row's Created at ("4:31 PM", UTC) as minutes since midnight.
  static func createdAtMinutes(_ page: Page) async throws -> [Int] {
    try await page.evaluate(
      """
      [...document.querySelectorAll('.bibliographic-madrigals-table tbody tr td:nth-child(\(createdAtColumn))')]
        .map(td => td.textContent.trim().match(/^(\\d+):(\\d+) (AM|PM)$/))
        .filter(m => m)
        .map(m => (Number(m[1]) % 12 + (m[3] === 'PM' ? 12 : 0)) * 60 + Number(m[2]))
      """, as: [Int].self)
  }
}
