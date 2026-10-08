import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The date range picker on an object list's Created on filter (user,
/// 2026-10-08): presets beside the calendar, as Google Analytics, Stripe,
/// Grafana and Datadog lay theirs out—above it on a phone. A preset selects
/// its days and stays relative in the URL (`?createdOn=-7d..`); two days
/// picked make a fixed range (`2026-10-01..2026-10-08`). Each narrows the
/// rows to their UTC days, as the Created on column shows them.
@Suite("Date range picker", .serialized)
struct DateRangePickerTests {
  static let list = "/mission-control/madrigals/bibliographic"
  /// The column the filter asks of: ID, Title, Status, Created by, Created on.
  static let createdOnColumn = 5

  @Test(arguments: enginesAndLayouts)
  func presetsAndFixedRanges(engine: BrowserEngine, layout: Layout) async throws {
    let viewport = layout.viewport(for: engine)
    try await withPage(engine, gnorium, viewport: viewport) { page in
      try await page.openHydrated(Self.list)

      // The bar's fields in the table's column order, the creation three
      // last, and no "since".
      let row = page.locator(".filter-bar-row").first
      let fields = try await row.locator(".filter-bar-field-picker .dropdown-option").allTextContents()
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      #expect(fields == ["ID", "Title", "Status", "Created by", "Created on", "Created at"], "fields: \(fields)")

      try await row.locator(".filter-bar-field-picker .dropdown-trigger").click()
      try await row.locator(".filter-bar-field-picker .dropdown-option").filter(hasText: "Created on", exact: true).click()
      let picker = row.locator(".date-picker-view")
      let field = picker.locator(".date-picker-field input")
      let popover = picker.locator(".date-picker-popover")
      let value = picker.locator("input.date-picker-value")
      try await expect(picker).toHaveAttribute("data-hydrated", "true")
      try await expect(field).toHaveAttribute("placeholder", "Created on")

      if viewport.touch { try await field.tap() } else { try await field.click() }
      try await expect(popover).toBeVisible()

      // The presets, beside the calendar—or above it on a phone.
      let presets = popover.locator(".date-picker-preset")
      let labels = try await presets.allTextContents().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      #expect(labels == ["Today", "Last 7 days", "Last 30 days", "Last 90 days"], "presets: \(labels)")
      let presetsBox = try #require(try await popover.locator(".date-picker-presets").boundingBox())
      let gridBox = try #require(try await popover.locator(".date-picker-grid").boundingBox())
      if layout == .phone {
        #expect(presetsBox.maxY <= gridBox.minY + 1, "presets above the calendar on a phone")
      } else {
        #expect(presetsBox.maxX <= gridBox.minX + 1, "presets left of the calendar")
      }
      let popoverBox = try #require(try await popover.boundingBox())
      #expect(popoverBox.minX >= 0 && popoverBox.maxX <= Double(viewport.width), "the popover runs off screen: \(popoverBox)")

      // A preset selects its days, through today, and stays relative.
      let lastWeek = presets.filter(hasText: "Last 7 days", exact: true)
      if viewport.touch { try await lastWeek.tap() } else { try await lastWeek.click() }
      try await expect(value).toHaveValue("-7d..")
      try await expect(field).toHaveValue("Last 7 days")
      try await expect(lastWeek).toHaveAttribute("aria-pressed", "true")
      // Its ends read in the Date start and Date end fields, named as a
      // year range's are.
      try await expect(popover.locator(".date-picker-start input")).toHaveAttribute("placeholder", "Date start")
      try await expect(popover.locator(".date-picker-end input"))
        .toHaveValue(try #require(DatePickerTests.words(DatePickerTests.utcDay(0))))
      try await expect(popover.locator(".date-picker-start input"))
        .toHaveValue(try #require(DatePickerTests.words(DatePickerTests.utcDay(-6))))
      let today = DatePickerTests.utcDay(0)
      try await expect(popover.locator(".date-picker-month-day[data-date='\(today)']"))
        .toHaveAttribute("aria-selected", "true")

      // Applied, the URL keeps it relative, the field reads it, and every
      // row was created in the last seven UTC days.
      try await popover.getByRole(.button, name: "Done").click()
      try await page.locator(".filter-bar-apply").click()
      try await expect(page, timeout: .seconds(15)).toHaveURL("createdOn=-7d..") { url in
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
          .contains { $0.name == "createdOn" && $0.value == "-7d.." } ?? false
      }
      try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
      try await expect(page.locator(".filter-bar-value-input .date-picker-field input")).toHaveValue("Last 7 days")
      let week = (0..<7).compactMap { DatePickerTests.words(DatePickerTests.utcDay(-$0)) }
      for day in try await Self.createdOnCells(page) {
        #expect(week.contains(day), "\(day) is not in the last seven days")
      }

      // Two days picked make a fixed range: yesterday through today.
      let applied = page.locator(".filter-bar-value-input.date-picker-view")
      let appliedField = applied.locator(".date-picker-field input")
      if viewport.touch { try await appliedField.tap() } else { try await appliedField.click() }
      let yesterday = DatePickerTests.utcDay(-1)
      for day in [yesterday, today] {
        let cell = applied.locator(".date-picker-month-day[data-date='\(day)']")
        if try await cell.count() == 0 {
          // Yesterday was last month: page back to it.
          try await applied.getByRole(.button, name: "Previous month").click()
        }
        if viewport.touch { try await cell.first.tap() } else { try await cell.first.click() }
      }
      try await expect(applied.locator("input.date-picker-value")).toHaveValue("\(yesterday)..\(today)")
      try await expect(applied.locator(".date-picker-preset[aria-pressed='true']")).toHaveCount(0)
      try await page.keyboard.press("Escape")
      try await page.locator(".filter-bar-apply").click()
      try await expect(page, timeout: .seconds(15)).toHaveURL("createdOn=\(yesterday)..\(today)") { url in
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
          .contains { $0.name == "createdOn" && $0.value == "\(yesterday)..\(today)" } ?? false
      }
      let twoDays = [yesterday, today].compactMap(DatePickerTests.words)
      for day in try await Self.createdOnCells(page) {
        #expect(twoDays.contains(day), "\(day) is not yesterday or today")
      }

      // A range no row falls in lists none.
      try await page.openHydrated("\(Self.list)?createdOn=2000-01-01..2000-01-02")
      try await expect(page.locator(".mission-control-objects-table-empty")).toBeVisible()
      try await expect(page.locator(".filter-bar-value-input .date-picker-field input"))
        .toHaveValue("Jan 1–2, 2000")

      try await page.expectNoErrors()
      try await page.expectNoHorizontalOverflow()
    }
  }

  /// Every listed row's Created on, as shown.
  static func createdOnCells(_ page: Page) async throws -> [String] {
    try await page.evaluate(
      """
      [...document.querySelectorAll('.bibliographic-madrigals-table tbody tr td:nth-child(\(createdOnColumn))')]
        .map(td => td.textContent.trim())
      """, as: [String].self)
  }
}
