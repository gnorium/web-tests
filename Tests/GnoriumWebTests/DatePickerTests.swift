import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The date filter on Mission Control's contributors page—Last active, a
/// range of days—in Gnorium's own calendar popover, by pointer, touch and
/// keyboard. Needs an admin, made for the test and removed after (see
/// `TestAdmin`).
@Suite("Date picker", .serialized)
struct DatePickerTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func lastActiveRange(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let viewport = layout.viewport(for: engine)

    do {
      try await run(engine: engine, viewport: viewport, admin: admin)
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }

  private func run(engine: BrowserEngine, viewport: Viewport, admin: TestAdmin) async throws {
    try await withPage(engine, gnorium, viewport: viewport, cookies: [admin.cookie]) { page in
      try await page.openHydrated("/mission-control/contributors")
      try await expect(page, timeout: .seconds(10)).toHaveURL("/mission-control/contributors")

      // Pick the "Last active" field in the first filter row.
      let row = page.locator(".filter-bar-row").first
      try await row.locator(".filter-bar-field-picker .dropdown-trigger").click()
      try await row.locator(".filter-bar-field-picker .dropdown-option").filter(hasText: "Last active", exact: true).click()

      let picker = row.locator(".date-picker-view")
      let field = picker.locator(".date-picker-field input")
      let popover = picker.locator(".date-picker-popover")
      let value = picker.locator("input.date-picker-value")
      try await expect(picker).toBeVisible()
      try await expect(picker).toHaveAttribute("data-hydrated", "true")
      try await expect(picker).toHaveAttribute("data-range", "true")

      // Our field, not a native date input: nothing for the platform's
      // picker to open, and no keyboard asked for on a phone. Its
      // placeholder is its label.
      try await expect(row.locator("input[type='date']")).toHaveCount(0)
      try await expect(field).toHaveAttribute("readonly")
      try await expect(field).toHaveAttribute("inputmode", "none")
      try await expect(field).toHaveAttribute("placeholder", "Last active")

      // Open it: a tap on a touch phone, a click otherwise.
      if viewport.touch { try await field.tap() } else { try await field.click() }
      try await expect(popover).toBeVisible()
      try await expect(popover).toHaveAttribute("data-open", "true")
      try await expect(field).toHaveAttribute("aria-expanded", "true")
      let popoverBox = try #require(try await popover.boundingBox())
      #expect(popoverBox.minX >= 0 && popoverBox.maxX <= Double(viewport.width), "the popover runs off screen: \(popoverBox)")
      #expect(popoverBox.minY >= 0, "the popover runs off the top: \(popoverBox)")

      // Keyboard: the focused day is today, the reader's; right a day and
      // Enter starts the range there, open at its end; right again and
      // Enter closes it. The value is the UTC instants that bound those
      // local days, the end the next day's first moment.
      let today = try #require(try await page.evaluate("document.activeElement?.getAttribute('data-date')").string)
      #expect(today == (try await Self.localToday(page)), "the calendar opens on the reader's today: \(today)")
      try await page.keyboard.press("ArrowRight")
      let tomorrow = try Self.day(after: today)
      let focused = try await page.evaluate("document.activeElement?.getAttribute('data-date')").string
      #expect(focused == tomorrow, "ArrowRight focused \(focused ?? "nothing"), not \(tomorrow)")
      try await page.keyboard.press("Enter")
      try await expect(value).toHaveValue("\(try await Self.instant(page, startOf: tomorrow))..")
      let tomorrowWords = try #require(Self.words(tomorrow))
      try await expect(field).toHaveValue("Since \(tomorrowWords)")
      try await page.keyboard.press("ArrowRight")
      try await page.keyboard.press("Enter")
      let after = try Self.day(after: tomorrow)
      let afterNext = try Self.day(after: after)
      try await expect(value).toHaveValue(
        "\(try await Self.instant(page, startOf: tomorrow))..\(try await Self.instant(page, startOf: afterNext))")
      try await expect(popover.locator(".date-picker-month-day[aria-selected='true']")).toHaveCount(2)

      // Reset empties the field and keeps the calendar open.
      try await popover.getByRole(.button, name: "Reset").click()
      try await expect(value).toHaveValue("")
      try await expect(field).toHaveValue("")
      try await expect(popover).toHaveAttribute("data-open", "true")

      // Done closes it and gives focus back to the field.
      try await popover.getByRole(.button, name: "Done").click()
      try await expect(popover).toHaveAttribute("data-open", "false")
      try await expect(popover).toBeHidden()
      try await expect(field).toBeFocused()

      // Enter reopens it from the field; Esc closes it again.
      try await field.press("Enter")
      try await expect(popover).toBeVisible()
      try await page.keyboard.press("Escape")
      try await expect(popover).toBeHidden()
      try await expect(field).toHaveAttribute("aria-expanded", "false")

      try await page.expectNoErrors()
      try await page.expectNoHorizontalOverflow()
    }
  }

  static func formatter(_ format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = format
    return formatter
  }

  /// The ISO day after `iso` (yyyy-mm-dd).
  static func day(after iso: String) throws -> String {
    let formatter = formatter("yyyy-MM-dd")
    guard let date = formatter.date(from: iso) else { throw WebTestError("\(iso) is not a yyyy-mm-dd day.") }
    return formatter.string(from: date.addingTimeInterval(86_400))
  }

  /// The page's today, its reader's zone, yyyy-mm-dd.
  static func localToday(_ page: Page) async throws -> String {
    try await page.evaluate(
      "(() => { const d = new Date(); return [d.getFullYear(), String(d.getMonth() + 1).padStart(2, '0'), String(d.getDate()).padStart(2, '0')].join('-'); })()",
      as: String.self)
  }

  /// The local day `offset` days from the page's today, yyyy-mm-dd.
  static func localDay(_ page: Page, _ offset: Int) async throws -> String {
    var day = try await localToday(page)
    let formatter = formatter("yyyy-MM-dd")
    if let date = formatter.date(from: day) {
      day = formatter.string(from: date.addingTimeInterval(Double(offset) * 86_400))
    }
    return day
  }

  /// The UTC instant a local day (yyyy-mm-dd) begins in the page's zone, as
  /// a range's bound: `2026-09-30T18:30Z` for Oct 1 in India.
  static func instant(_ page: Page, startOf day: String) async throws -> String {
    try await page.evaluate(
      "((iso) => { const [y, m, d] = iso.split('-').map(Number); return new Date(y, m - 1, d).toISOString().slice(0, 16) + 'Z'; })('\(day)')",
      as: String.self)
  }

  /// "Oct 9, 2026" for `2026-10-09`, as the field and the "on" columns read.
  static func words(_ iso: String) -> String? {
    formatter("yyyy-MM-dd").date(from: iso).map { formatter("MMM d, yyyy").string(from: $0) }
  }
}
