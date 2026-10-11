import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The date picker's month and year shortcuts: the caption opens the year's
/// months, again the decade's years; a year picked goes back to its months,
/// a month to its days; Esc steps back a level. On an object list's Created
/// on filter, which needs no sign-in. Chrome only (headless).
@Suite("Date picker shortcuts", .serialized)
struct DatePickerShortcutsTests {
  static let list = "/mission-control/madrigals/bibliographic"

  @Test(arguments: Layout.allCases)
  func monthsAndYears(layout: Layout) async throws {
    let engine = BrowserEngine.chrome
    guard gnorium.engines.contains(engine) else { return }
    let viewport = layout.viewport(for: engine)
    try await withPage(engine, gnorium, viewport: viewport) { page in
      try await page.openHydrated(Self.list)
      let row = page.locator(".filter-bar-row").first
      try await row.locator(".filter-bar-field-picker .dropdown-trigger").click()
      try await row.locator(".filter-bar-field-picker .dropdown-option").filter(hasText: "Created on", exact: true).click()
      let picker = row.locator(".date-picker-view")
      let field = picker.locator(".date-picker-field input")
      let popover = picker.locator(".date-picker-popover")
      let caption = popover.locator(".date-picker-caption")
      let title = popover.locator(".date-picker-month-title")
      let days = popover.locator(".date-picker-grid")
      let periods = popover.locator(".date-picker-periods")
      let cells = periods.locator(".date-picker-period-cell")
      try await expect(picker).toHaveAttribute("data-hydrated", "true")

      func press(_ locator: Locator) async throws {
        if viewport.touch { try await locator.tap() } else { try await locator.click() }
      }
      func active(_ attribute: String) async throws -> String? {
        try await page.evaluate("document.activeElement?.getAttribute('\(attribute)')").string
      }

      try await press(field)
      try await expect(popover).toBeVisible()

      // The caption names the reader's month and says what it opens.
      let monthYear = try await page.evaluate(
        "new Date().toLocaleDateString('en-US', { month: 'long', year: 'numeric' })", as: String.self)
      let year = try await page.evaluate("new Date().getFullYear()", as: Int.self)
      let month = try await page.evaluate("new Date().getMonth() + 1", as: Int.self)
      let decade = year - year % 10
      try await expect(title).toHaveText(monthYear)
      try await expect(caption).toHaveAttribute("aria-label", "\(monthYear), choose month")
      try await expect(periods).toBeHidden()
      // The popover keeps one height on every grid (user, 2026-10-12).
      let dayHeight = try #require(try await popover.boundingBox()).height

      // The months: twelve, three to a row, this month current; the
      // arrows step a year.
      try await press(caption)
      try await expect(periods).toBeVisible()
      try await expect(days).toBeHidden()
      try await expect(title).toHaveText("\(year)")
      try await expect(caption).toHaveAttribute("aria-label", "\(year), choose year")
      try await expect(cells).toHaveCount(12)
      try await expect(periods.locator(".date-picker-period-view")).toHaveAttribute("role", "grid")
      try await expect(periods.locator("[aria-current='date']")).toHaveAttribute("data-value", "\(month)")
      try await expect(periods.locator("tr").first.locator(".date-picker-period-cell")).toHaveCount(3)
      let monthHeight = try #require(try await popover.boundingBox()).height
      #expect(abs(monthHeight - dayHeight) <= 1, "the months' popover is \(monthHeight) tall, the days' \(dayHeight)")
      try await shoot(page, "months", layout)
      try await press(popover.getByRole(.button, name: "Previous year"))
      try await expect(title).toHaveText("\(year - 1)")
      try await press(popover.getByRole(.button, name: "Next year"))
      try await expect(title).toHaveText("\(year)")

      // A month picked goes back to its days.
      try await press(cells.filter(hasText: "Mar", exact: true))
      try await expect(days).toBeVisible()
      try await expect(periods).toBeHidden()
      try await expect(title).toHaveText("March \(year)")
      try await expect(popover.getByRole(.button, name: "Previous month")).toBeVisible()

      // The years: the decade and a year either side, muted; the arrows
      // step a decade; the decade's caption opens nothing.
      try await press(caption)
      try await press(caption)
      try await expect(title).toHaveText("\(decade)–\(decade + 9)")
      try await expect(caption).toHaveAttribute("aria-disabled", "true")
      try await expect(cells).toHaveCount(12)
      try await expect(cells.first).toHaveAttribute("data-outside", "true")
      try await expect(cells.last).toHaveAttribute("data-outside", "true")
      try await expect(periods.locator("[aria-current='date']")).toHaveAttribute("data-value", "\(year)")
      let yearHeight = try #require(try await popover.boundingBox()).height
      #expect(abs(yearHeight - dayHeight) <= 1, "the years' popover is \(yearHeight) tall, the days' \(dayHeight)")
      try await shoot(page, "years", layout)
      try await press(popover.getByRole(.button, name: "Previous decade"))
      try await expect(title).toHaveText("\(decade - 10)–\(decade - 1)")

      // A year picked goes back to its months; a month, to its days.
      let pickedYear = decade - 5
      try await press(periods.locator("[data-value='\(pickedYear)']"))
      try await expect(title).toHaveText("\(pickedYear)")
      try await press(cells.filter(hasText: "Jun", exact: true))
      try await expect(title).toHaveText("June \(pickedYear)")

      // Keyboard: Enter on the caption opens the months, focus staying on
      // it; arrows move a cell, a row; Home and End the row's ends; Enter
      // picks.
      try await caption.press("Enter")
      try await expect(title).toHaveText("\(pickedYear)")
      try await expect(caption).toBeFocused()
      try await periods.locator("[tabindex='0']").focus()
      #expect(try await active("data-value") == "6", "the months open on June")
      try await page.keyboard.press("ArrowRight")
      #expect(try await active("data-value") == "7")
      try await page.keyboard.press("ArrowDown")
      #expect(try await active("data-value") == "10")
      try await page.keyboard.press("End")
      #expect(try await active("data-value") == "12")
      try await page.keyboard.press("Home")
      #expect(try await active("data-value") == "10")
      try await page.keyboard.press("ArrowUp")
      #expect(try await active("data-value") == "7")
      try await page.keyboard.press("ArrowLeft")
      #expect(try await active("data-value") == "6")
      // Past the edge, the next year.
      try await page.keyboard.press("ArrowUp")
      try await page.keyboard.press("ArrowUp")
      try await expect(title).toHaveText("\(pickedYear - 1)")
      #expect(try await active("data-value") == "12")
      let ringed = try await page.evaluate("document.activeElement?.matches(':focus-visible') ?? false", as: Bool.self)
      #expect(ringed, "the keyboard's cell wears no focus ring")
      try await page.keyboard.press("Enter")
      try await expect(days).toBeVisible()
      try await expect(title).toHaveText("December \(pickedYear - 1)")
      let day = try #require(try await active("data-date"))
      #expect(day.hasPrefix("\(pickedYear - 1)-12-"), "Enter left the focus on \(day)")

      // The years by keyboard: Right a year, Enter its months.
      try await caption.press("Enter")
      try await page.keyboard.press("Enter")
      let start = (pickedYear - 1) - (pickedYear - 1) % 10
      try await expect(title).toHaveText("\(start)–\(start + 9)")
      try await periods.locator("[tabindex='0']").focus()
      #expect(try await active("data-value") == "\(pickedYear - 1)")
      try await page.keyboard.press("ArrowRight")
      try await page.keyboard.press("Enter")
      try await expect(title).toHaveText("\(pickedYear)")
      #expect(try await active("data-value") == "12", "the months open on the focused month")

      // Esc steps back: months to days; years to months to days; then
      // closes.
      try await page.keyboard.press("Escape")
      try await expect(title).toHaveText("December \(pickedYear)")
      try await expect(popover).toBeVisible()
      try await caption.press("Enter")
      try await page.keyboard.press("Enter")
      try await expect(title).toHaveText("\(decade - 10)–\(decade - 1)")
      try await page.keyboard.press("Escape")
      try await expect(title).toHaveText("\(pickedYear)")
      try await page.keyboard.press("Escape")
      try await expect(title).toHaveText("December \(pickedYear)")
      try await expect(days).toBeVisible()
      try await page.keyboard.press("Escape")
      try await expect(popover).toBeHidden()

      // Reopened, it shows the days again.
      try await press(field)
      try await expect(days).toBeVisible()
      try await expect(periods).toBeHidden()
      try await expect(title).toHaveText(monthYear)

      try await page.expectNoErrors()
      try await page.expectNoHorizontalOverflow()
    }
  }

  /// Saves the popover's state when GNORIUM_SCREENSHOT_DIR names a folder.
  private func shoot(_ page: Page, _ name: String, _ layout: Layout) async throws {
    guard layout == .desktop, let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"]
    else { return }
    try await page.screenshot(to: URL(fileURLWithPath: directory).appendingPathComponent("datepicker-\(name).png"))
  }
}
