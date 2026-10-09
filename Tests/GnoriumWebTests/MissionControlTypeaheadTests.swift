import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A Mission Control list's people and models are comboboxes with a
/// server's typeahead (user, 2026-10-09): a row switched to Created by is a
/// combobox, its text 16px; typed text, case and diacritics aside, asks the
/// list's `…/created-by?q=` and shows what matches; the arrow keys and
/// Enter choose one, Escape closes the list, and Apply filters by it. The
/// Runs list, whose runs the machine creates ("gnorium") whatever the data.
/// Needs an admin, made for the test and removed after (see `TestAdmin`).
@Suite("Mission Control typeahead", .serialized)
struct MissionControlTypeaheadTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func createdBySuggestsAsItIsTyped(engine: BrowserEngine, layout: Layout) async throws {
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
      try await page.openHydrated("/mission-control/runs/bibliographic")
      try await page.expectNoErrors()
      try await page.locator(".filter-bar-add-btn").first.click()
      let row = page.locator(".filter-bar-row").last
      try await row.locator(".filter-bar-field-picker .dropdown-trigger").click()
      try await row.locator(".filter-bar-field-picker .dropdown-option[data-value='createdBy']").click()
      let field = row.locator("input[data-combobox-input='true']")
      try await expect(field).toBeVisible()
      let size = try await field.evaluate("(e) => getComputedStyle(e).fontSize").string
      #expect(size == "16px", "the combobox's text is 16px, as the bar's other fields: \(size ?? "")")

      // Typed in another case, with a diacritic: the server's suggestion.
      try await field.type("GNÓ")
      let suggestion = row.locator(".combobox-option[data-value='gnorium']")
      try await expect(suggestion).toBeVisible()
      // Escape closes the list; the arrow keys open it again, its
      // suggestions as the server matched them, and Enter takes the one
      // they are on.
      try await page.keyboard.press("Escape")
      try await expect(row.locator(".combobox-menu")).toHaveAttribute("data-open", "false")
      try await page.keyboard.press("ArrowDown")
      try await expect(row.locator(".combobox-menu")).toHaveAttribute("data-open", "true")
      try await expect(suggestion).toHaveAttribute("aria-selected", "true")
      try await page.keyboard.press("Enter")
      try await expect(field).toHaveValue("gnorium")
      try await expect(row.locator(".combobox-menu")).toHaveAttribute("data-open", "false")

      // Applied, the list filters by it, and the row holds it.
      try await page.locator(".filter-bar-apply").click()
      try await expect(page).toHaveURL("createdBy=gnorium") { url in
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
          .contains { $0.name == "createdBy" && $0.value == "gnorium" } == true
      }
      try await expect(page.locator("input[data-combobox-input='true']").first).toHaveValue("gnorium")
      try await page.expectNoHorizontalOverflow()
    }
  }
}
