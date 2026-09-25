import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The date filter on Mission Control's contributors page: Gnorium's own
/// calendar popover, by pointer, touch and keyboard. Needs an admin, made
/// for the test and removed after (see `TestAdmin`).
@Suite("Date picker", .serialized)
struct DatePickerTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func activeSinceDate(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let viewport = layout.viewport(for: engine)

    do {
      try await run(engine: engine, viewport: viewport, admin: admin)
    } catch {
      await admin.remove()
      throw error
    }
    await admin.remove()
  }

  private func run(engine: BrowserEngine, viewport: Viewport, admin: TestAdmin) async throws {
    try await withPage(engine, gnorium, viewport: viewport, cookies: [admin.cookie]) { page in
      try await page.openHydrated("/mission-control/contributors")
      try await expect(page, timeout: .seconds(10)).toHaveURL("/mission-control/contributors")

      // Pick the "Active since date" field in the first filter row.
      let row = page.locator(".filter-bar-row").first
      try await row.locator(".filter-bar-field-picker .dropdown-trigger").click()
      try await row.locator(".filter-bar-field-picker .dropdown-option").filter(hasText: "Active since date", exact: true).click()

      let picker = row.locator(".date-picker-view")
      let field = picker.locator(".date-picker-field input")
      let popover = picker.locator(".date-picker-popover")
      let value = picker.locator("input.date-picker-value")
      try await expect(picker).toBeVisible()
      try await expect(picker).toHaveAttribute("data-hydrated", "true")

      // Our field, not a native date input: nothing for the platform's
      // picker to open, and no keyboard asked for on a phone.
      try await expect(row.locator("input[type='date']")).toHaveCount(0)
      try await expect(field).toHaveAttribute("readonly")
      try await expect(field).toHaveAttribute("inputmode", "none")

      // Open it: a tap on a touch phone, a click otherwise.
      if viewport.touch { try await field.tap() } else { try await field.click() }
      try await expect(popover).toBeVisible()
      try await expect(popover).toHaveAttribute("data-open", "true")
      try await expect(field).toHaveAttribute("aria-expanded", "true")

      // As wide as the field, like a dropdown's menu, unless the field is
      // narrower than the popover's min-width (seven 40px days), which the
      // design keeps while the screen allows.
      let fieldBox = try #require(try await picker.boundingBox())
      let popoverBox = try #require(try await popover.boundingBox())
      let minWidth = try await popover.evaluate("(el) => parseFloat(getComputedStyle(el).minWidth) || 0").double ?? 0
      let expectedWidth = max(fieldBox.width, minWidth)
      #expect(
        abs(popoverBox.width - expectedWidth) < 1,
        "popover \(popoverBox) is not as wide as the field \(fieldBox) (min-width \(minWidth))")
      #expect(popoverBox.minX >= 0 && popoverBox.maxX <= Double(viewport.width), "the popover runs off screen: \(popoverBox)")

      // Keyboard: the focused day moves right a day; Enter picks it.
      let today = try #require(try await page.evaluate("document.activeElement?.getAttribute('data-date')").string)
      try await page.keyboard.press("ArrowRight")
      let tomorrow = try Self.day(after: today)
      let focused = try await page.evaluate("document.activeElement?.getAttribute('data-date')").string
      #expect(focused == tomorrow, "ArrowRight focused \(focused ?? "nothing"), not \(tomorrow)")
      try await page.keyboard.press("Enter")
      try await expect(value).toHaveValue(tomorrow)
      try await expect(field).not.toHaveValue("")

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

  /// The ISO day after `iso` (yyyy-mm-dd).
  static func day(after iso: String) throws -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    guard let date = formatter.date(from: iso) else { throw WebTestError("\(iso) is not a yyyy-mm-dd day.") }
    return formatter.string(from: date.addingTimeInterval(86_400))
  }
}
