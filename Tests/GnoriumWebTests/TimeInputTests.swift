import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The time input on an object list's Created at filter (user, 2026-10-08):
/// a span of the day on a 12-hour clock, as the tables read ("5:40 PM"),
/// Time start and Time end each an hour (1–12), minutes and AM/PM column, in
/// the date picker's popover—by keyboard, and by touch or pointer. The
/// reader picks and reads local times; the URL carries those wall-clock
/// times and the reader's IANA zone (`?createdAt=09:00..17:30[Asia/Kolkata]`),
/// since a time of day is not an instant. A span set in another zone reads
/// converted to the reader's clock. Run in India
/// (+05:30), New York (−04:00/−05:00) and Kathmandu (+05:45), by CDP time
/// zone emulation.
@Suite("Time input", .serialized)
struct TimeInputTests {
  static let list = "/mission-control/madrigals/bibliographic"
  /// ID, Title, Status, Created by, Created on, Created at.
  static let createdAtColumn = 6

  /// Per zone, a span picked there.
  static let spans: [(zone: String, start: (hour: Int, pm: Bool), end: (hour: Int, pm: Bool))] = [
    ("Asia/Kolkata", (4, false), (10, false)),
    ("America/New_York", (7, true), (11, true)),
    ("Asia/Kathmandu", (9, false), (5, true)),
  ]

  /// Each layout with each zone's span; Chrome only, which emulates a zone.
  static let cases: [(Layout, Int)] = Layout.allCases.flatMap { layout in spans.indices.map { (layout, $0) } }

  @Test(arguments: cases)
  func createdAtSpan(layout: Layout, span index: Int) async throws {
    let engine = BrowserEngine.chrome
    guard gnorium.engines.contains(engine) else { return }
    let span = Self.spans[index]
    let viewport = layout.viewport(for: engine)
    try await withPage(engine, gnorium, viewport: viewport) { page in
      try await page.setTimeZone(span.zone)
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

      // Keyboard: Enter opens it on Time start's hour; ↓ sets an hour (the
      // minutes start at :00, the half of the day at AM), Tab goes on to the
      // next column, End to its last value.
      try await field.press("Enter")
      try await expect(popover).toBeVisible()
      try await expect(field).toHaveAttribute("aria-expanded", "true")
      let focusedColumn = { () async throws -> String? in
        try await page.evaluate("document.activeElement?.closest('.time-input-column')?.getAttribute('aria-label')")
          .string
      }
      #expect(try await focusedColumn() == "Time start hour")
      try await page.keyboard.press("ArrowDown")  // 1 → 2
      let zone = try await page.evaluate("Intl.DateTimeFormat().resolvedOptions().timeZone", as: String.self)
      try await expect(value).toHaveValue("02:00..[\(zone)]")
      try await expect(field).toHaveValue("Since 2:00 AM")
      try await page.keyboard.press("Tab")
      #expect(try await focusedColumn() == "Time start minutes")
      try await page.keyboard.press("ArrowDown")
      try await expect(field).toHaveValue("Since 2:01 AM")
      try await page.keyboard.press("Tab")
      #expect(try await focusedColumn() == "Time start AM or PM")
      try await page.keyboard.press("End")
      try await expect(field).toHaveValue("Since 2:01 PM")
      try await page.keyboard.press("Tab")
      #expect(try await focusedColumn() == "Time end hour")
      try await page.keyboard.press("End")
      try await expect(field).toHaveValue("2:01 PM–12:00 AM")
      try await expect(value)
        .toHaveValue("14:01..00:00[\(zone)]")
      try await page.keyboard.press("Escape")
      try await expect(popover).toBeHidden()
      try await expect(field).toBeFocused()

      // Touch or pointer: Reset, then the zone's span, a tap an option.
      if viewport.touch { try await field.tap() } else { try await field.click() }
      try await expect(popover).toBeVisible()
      let popoverBox = try #require(try await popover.boundingBox())
      #expect(popoverBox.minX >= 0 && popoverBox.maxX <= Double(viewport.width), "the popover runs off screen: \(popoverBox)")
      // Always under the field, as a dropdown opens (user, 2026-10-10).
      let fieldBox = try #require(try await field.boundingBox())
      #expect(popoverBox.minY >= fieldBox.maxY, "the popover opens over the field: \(popoverBox), field \(fieldBox)")
      // Time start over Time end, one a row (user, 2026-10-10).
      let startBox = try #require(try await popover.locator(".time-input-parts > *").first.boundingBox())
      let endBox = try #require(try await popover.locator(".time-input-parts > *").last.boundingBox())
      #expect(startBox.maxY <= endBox.minY + 1, "Time start is not over Time end: \(startBox), \(endBox)")
      try await popover.getByRole(.button, name: "Reset").click()
      try await expect(value).toHaveValue("")
      try await expect(field).toHaveValue("")
      let option = { (part: String, unit: String, value: Int) in
        popover.locator(".time-input-column[aria-label='Time \(part) \(unit)'] .time-input-option[data-value='\(value)']")
      }
      for target in [
        option("start", "hour", span.start.hour), option("start", "AM or PM", span.start.pm ? 1 : 0),
        option("end", "hour", span.end.hour), option("end", "AM or PM", span.end.pm ? 1 : 0),
      ] {
        // Brought round in its column, as a finger scrolls it.
        _ = try await target.evaluate("el => el.scrollIntoView({ block: 'nearest' })")
        if viewport.touch { try await target.tap() } else { try await target.click() }
      }
      let start24 = span.start.hour % 12 + (span.start.pm ? 12 : 0)
      let end24 = span.end.hour % 12 + (span.end.pm ? 12 : 0)
      let two = { (value: Int) in value < 10 ? "0\(value)" : "\(value)" }
      let carried = "\(two(start24)):00..\(two(end24)):00[\(zone)]"
      try await expect(value).toHaveValue(carried)
      let words = "\(span.start.hour):00 \(span.start.pm ? "PM" : "AM")–\(span.end.hour):00 \(span.end.pm ? "PM" : "AM")"
      try await expect(field).toHaveValue(words)
      try await popover.getByRole(.button, name: "Done").click()
      try await expect(popover).toBeHidden()

      // Applied: one key, the wall-clock span and the reader's zone; the
      // field reads the reader's clock, no zone named; every row's Created
      // at, shown in the reader's clock, falls in the span.
      try await page.locator(".filter-bar-apply").click()
      try await expect(page, timeout: .seconds(15)).toHaveURL("createdAt=\(carried)") { url in
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
          .contains { $0.name == "createdAt" && $0.value == carried } ?? false
      }
      try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
      try await expect(page.locator(".filter-bar-value-input .time-input-field input")).toHaveValue(words)
      try await DateRangePickerTests.expectLocalCells(page)
      for minutes in try await Self.createdAtMinutes(page) {
        let inside = start24 <= end24
          ? minutes >= start24 * 60 && minutes <= end24 * 60 + 59
          : minutes >= start24 * 60 || minutes <= end24 * 60 + 59
        #expect(inside, "\(minutes / 60):\(minutes % 60) is outside \(words)")
      }

      // A span set in another zone reads converted to the reader's clock,
      // today's moment of each end; the URL keeps its zone.
      try await page.openHydrated("\(Self.list)?createdAt=09:00..17:30%5BAsia/Kolkata%5D")
      let expected = try await page.evaluate(
        """
        (() => {
          const now = new Date();
          const at = (h, m) => new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate(), h, m) - 330 * 60000)
            .toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' }).replace(/\\s+/g, ' ');
          return at(9, 0) + '–' + at(17, 30);
        })()
        """, as: String.self)
      try await expect(page.locator(".filter-bar-value-input .time-input-field input")).toHaveValue(expected)
      try await expect(page.locator(".filter-bar-value-input input.time-input-value"))
        .toHaveValue("09:00..17:30[Asia/Kolkata]")

      try await page.expectNoErrors()
      try await page.expectNoHorizontalOverflow()
    }
  }

  /// Every listed row's Created at ("4:31 PM", the reader's clock) as
  /// minutes since midnight.
  static func createdAtMinutes(_ page: Page) async throws -> [Int] {
    try await page.evaluate(
      """
      [...document.querySelectorAll('.bibliographic-madrigals-table tbody tr td:nth-child(\(createdAtColumn))')]
        .map(td => td.textContent.replace(/\\s+/g, ' ').trim().match(/^(\\d+):(\\d+) (AM|PM)$/))
        .filter(m => m)
        .map(m => (Number(m[1]) % 12 + (m[3] === 'PM' ? 12 : 0)) * 60 + Number(m[2]))
      """, as: [Int].self)
  }
}
