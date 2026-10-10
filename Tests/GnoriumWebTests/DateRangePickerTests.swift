import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The date range picker on an object list's Created on filter (user,
/// 2026-10-08): presets beside the calendar, as Google Analytics, Stripe,
/// Grafana and Datadog lay theirs out—above it on a phone. The UI shows the
/// reader's local days; the URL carries UTC. A preset stays relative
/// (`?createdOn=-7d..`) and counts the reader's days, read from the `tz`
/// cookie the client sets; two days picked make a fixed range, the UTC
/// instants that bound those local days. Run in India (+05:30) and New York
/// (−04:00), by CDP time zone emulation, so a local day is never a UTC one.
@Suite("Date range picker", .serialized)
struct DateRangePickerTests {
  static let list = "/mission-control/madrigals/bibliographic"
  /// The column the filter asks of: ID, Title, Status, Created by, Created on.
  static let createdOnColumn = 5
  /// Each layout in each zone; Chrome only, which emulates a zone.
  static let cases: [(Layout, String)] = Layout.allCases.flatMap { layout in
    ["Asia/Kolkata", "America/New_York", "Asia/Kathmandu"].map { (layout, $0) }
  }

  @Test(arguments: cases)
  func presetsAndFixedRanges(layout: Layout, zone: String) async throws {
    let engine = BrowserEngine.chrome
    guard gnorium.engines.contains(engine) else { return }
    let viewport = layout.viewport(for: engine)
    try await withPage(engine, gnorium, viewport: viewport) { page in
      try await page.setTimeZone(zone)
      try await page.openHydrated(Self.list)
      // A plain page view sets no cookie.
      let before = try await page.evaluate("document.cookie", as: String.self)
      #expect(!before.contains("tz="), "a plain view set the tz cookie: \(before)")

      // Every Created on cell is the reader's day of its moment.
      try await Self.expectLocalCells(page)

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

      // Exactly the field's width, as a dropdown's menu (user, 2026-10-10).
      let popoverBox = try #require(try await popover.boundingBox())
      let fieldBox = try #require(try await field.boundingBox())
      #expect(popoverBox.minX >= 0 && popoverBox.maxX <= Double(viewport.width), "the popover runs off screen: \(popoverBox)")
      #expect(
        abs(popoverBox.minX - fieldBox.minX) <= 1 && abs(popoverBox.width - fieldBox.width) <= 1,
        "the popover is not the field's width: \(popoverBox), field \(fieldBox)")

      // The presets beside the calendar, or above it, one a row, in a
      // popover narrower than 480 (user, 2026-10-10). The days stay 32 wide.
      let presets = popover.locator(".date-picker-preset")
      let labels = try await presets.allTextContents().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      #expect(labels == ["Today", "Last 7 days", "Last 30 days", "Last 90 days"], "presets: \(labels)")
      let presetsBox = try #require(try await popover.locator(".date-picker-presets").boundingBox())
      let gridBox = try #require(try await popover.locator(".date-picker-grid").boundingBox())
      if popoverBox.width < 480 {
        #expect(presetsBox.maxY <= gridBox.minY + 1, "presets above the calendar in a narrow popover")
        let firstPreset = try #require(try await presets.first.boundingBox())
        let secondPreset = try #require(try await presets.nth(1).boundingBox())
        #expect(firstPreset.maxY <= secondPreset.minY + 1, "presets side by side: \(firstPreset), \(secondPreset)")
      } else {
        #expect(presetsBox.maxX <= gridBox.minX + 1, "presets left of the calendar")
      }
      #expect(gridBox.maxX <= popoverBox.maxX + 1, "the calendar overflows the popover: \(gridBox), \(popoverBox)")
      let dayBox = try #require(try await popover.locator(".date-picker-month-day").first.boundingBox())
      #expect(dayBox.width >= 32 - 0.5, "a day narrower than 32: \(dayBox)")
      // Date start over Date end, one field a row (user, 2026-10-10).
      let startBox = try #require(try await popover.locator(".date-picker-ends > *").first.boundingBox())
      let endBox = try #require(try await popover.locator(".date-picker-ends > *").last.boundingBox())
      #expect(startBox.maxY <= endBox.minY + 1, "Date start is not over Date end: \(startBox), \(endBox)")

      // A preset selects its days, through the reader's today, and stays
      // relative.
      let today = try await DatePickerTests.localToday(page)
      let lastWeek = presets.filter(hasText: "Last 7 days", exact: true)
      if viewport.touch { try await lastWeek.tap() } else { try await lastWeek.click() }
      try await expect(value).toHaveValue("-7d..")
      try await expect(field).toHaveValue("Last 7 days")
      try await expect(lastWeek).toHaveAttribute("aria-pressed", "true")
      // Filtering by date tells the server the reader's zone. (Chrome may
      // name India's zone by its older alias, Asia/Calcutta.)
      let cookie = try await page.evaluate("document.cookie", as: String.self)
      let resolved = try await page.evaluate("Intl.DateTimeFormat().resolvedOptions().timeZone", as: String.self)
      #expect(cookie.contains("tz=\(resolved)"), "the tz cookie: \(cookie), the browser's zone \(resolved) (\(zone))")
      try await expect(popover.locator(".date-picker-month-day[data-date='\(today)']"))
        .toHaveAttribute("aria-selected", "true")
      // Its ends read in the Date start and Date end fields, named as a
      // year range's are.
      try await expect(popover.locator(".date-picker-start input")).toHaveAttribute("placeholder", "Date start")
      try await expect(popover.locator(".date-picker-end input")).toHaveValue(try #require(DatePickerTests.words(today)))
      try await expect(popover.locator(".date-picker-start input"))
        .toHaveValue(try #require(DatePickerTests.words(try await DatePickerTests.localDay(page, -6))))

      // Applied, the URL keeps it relative, the field reads it, and every
      // row was created in the reader's last seven days.
      try await popover.getByRole(.button, name: "Done").click()
      try await page.locator(".filter-bar-apply").click()
      try await expect(page, timeout: .seconds(15)).toHaveURL("createdOn=-7d..") { url in
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
          .contains { $0.name == "createdOn" && $0.value == "-7d.." } ?? false
      }
      try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
      try await expect(page.locator(".filter-bar-value-input .date-picker-field input")).toHaveValue("Last 7 days")
      var week: [String] = []
      for offset in 0..<7 {
        if let words = DatePickerTests.words(try await DatePickerTests.localDay(page, -offset)) { week.append(words) }
      }
      for day in try await Self.createdOnCells(page) {
        #expect(week.contains(day), "\(day) is not in the reader's last seven days")
      }

      // Two days picked make a fixed range: yesterday through today, the
      // UTC instants that bound them, the end the next day's first moment.
      let applied = page.locator(".filter-bar-value-input.date-picker-view")
      let appliedField = applied.locator(".date-picker-field input")
      if viewport.touch { try await appliedField.tap() } else { try await appliedField.click() }
      let yesterday = try await DatePickerTests.localDay(page, -1)
      for day in [yesterday, today] {
        let cell = applied.locator(".date-picker-month-day[data-date='\(day)']")
        if try await cell.count() == 0 {
          // Yesterday was last month: page back to it.
          try await applied.getByRole(.button, name: "Previous month").click()
        }
        if viewport.touch { try await cell.first.tap() } else { try await cell.first.click() }
      }
      let tomorrow = try DatePickerTests.day(after: today)
      let fixed =
        "\(try await DatePickerTests.instant(page, startOf: yesterday))..\(try await DatePickerTests.instant(page, startOf: tomorrow))"
      try await expect(applied.locator("input.date-picker-value")).toHaveValue(fixed)
      try await expect(applied.locator(".date-picker-preset[aria-pressed='true']")).toHaveCount(0)
      try await page.keyboard.press("Escape")
      try await page.locator(".filter-bar-apply").click()
      try await expect(page, timeout: .seconds(15)).toHaveURL("createdOn=\(fixed)") { url in
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
          .contains { $0.name == "createdOn" && $0.value == fixed } ?? false
      }
      try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
      let twoDays = [yesterday, today].compactMap(DatePickerTests.words)
      let shownRange = try await page.locator(".filter-bar-value-input .date-picker-field input").inputValue()
      #expect(shownRange.contains("–"), "the field reads the local days: \(shownRange)")
      for day in try await Self.createdOnCells(page) {
        #expect(twoDays.contains(day), "\(day) is not the reader's yesterday or today")
      }

      // A range no row falls in lists none, and reads the reader's days.
      try await page.openHydrated(
        "\(Self.list)?createdOn=\(try await DatePickerTests.instant(page, startOf: "2000-01-01"))..\(try await DatePickerTests.instant(page, startOf: "2000-01-03"))")
      try await expect(page.locator(".mission-control-objects-table-empty")).toBeVisible()
      try await expect(page.locator(".filter-bar-value-input .date-picker-field input")).toHaveValue("Jan 1–2, 2000")

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

  /// The "on" and "at" cells read their moment in the reader's zone, as the
  /// browser's own formatter puts it ("Oct 8, 2026", "5:40 PM").
  static func expectLocalCells(_ page: Page) async throws {
    let mismatches = try await page.evaluate(
      """
      [...document.querySelectorAll('time.local-time-view[data-format="date"], time.local-time-view[data-format="time"]')]
        .map(t => {
          const d = new Date(t.getAttribute('datetime'));
          const want = t.dataset.format === 'date'
            ? d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
            : d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
          const got = t.textContent.replace(/\\s+/g, ' ').trim();
          return got === want.replace(/\\s+/g, ' ') ? null : got + ' ≠ ' + want;
        })
        .filter(x => x)
      """, as: [String].self)
    #expect(mismatches.isEmpty, "cells not in the reader's zone: \(mismatches.prefix(3))")
  }
}
