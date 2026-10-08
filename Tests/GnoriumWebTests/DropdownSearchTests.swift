import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A dropdown's search box is the site's search box (user, 2026-10-08): a
/// `search-input-view` whose placeholder is "Search", no ellipsis. The
/// dropdown drives it: typed into, it narrows the options; the arrow keys
/// and Enter choose one; closed, it is emptied; a long query fades at rest.
/// The field picker of Mission Control's contributors filter bar. Needs an
/// admin, made for the test and removed after (see `TestAdmin`).
@Suite("Dropdown search", .serialized)
struct DropdownSearchTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func theSearchBoxIsTheSearchInput(engine: BrowserEngine, layout: Layout) async throws {
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
      try await page.openHydrated("/mission-control/contributors")
      let picker = page.locator(".filter-bar-row").first.locator(".filter-bar-field-picker")
      let box = picker.locator(".dropdown-search-input")
      let input = box.locator(".search-input")
      let visible = picker.locator(".dropdown-option[data-hidden='false']")

      // The site's search box, its placeholder the label: "Search".
      try await expect(picker.locator(".search-input-view.dropdown-search-input")).toHaveCount(1)
      try await expect(input).toHaveAttribute("placeholder", "Search")
      try await expect(input).toHaveAttribute("data-edge-fade", "true")

      // Open, a letter typed lands in the box and narrows the options.
      try await picker.locator(".dropdown-trigger").click()
      try await expect(picker.locator(".dropdown-menu")).toHaveAttribute("data-open", "true")
      let all = try await visible.count()
      try await page.keyboard.press("a")
      try await expect(input).toBeFocused()
      try await expect(input).toHaveValue("a")
      try await page.keyboard.type("ctive since d")
      try await expect(visible).toHaveCount(1)
      #expect(all > 1)

      // The arrow keys and Enter choose it; the box is emptied as it closes.
      try await page.keyboard.press("ArrowDown")
      try await page.keyboard.press("Enter")
      try await expect(picker.locator(".dropdown-selected-text")).toHaveText("Active since date")
      try await expect(picker.locator(".dropdown-menu")).toHaveAttribute("data-open", "false")
      try await expect(input).toHaveValue("")

      // A query longer than the box fades at its end once the box is left.
      try await picker.locator(".dropdown-trigger").click()
      try await input.fill(String(repeating: "overflowing ", count: 12))
      _ = try await input.evaluate("(el) => el.blur()")
      try await expect(input).toHaveAttribute("data-overflowing", "true")
      try await expect(input).toHaveAttribute("data-overflowing-end", "true")
      let fade = try await box.locator(".search-input-wrapper")
        .evaluate("(el) => getComputedStyle(el, '::after').opacity").string
      #expect(fade == "1")
    }
  }
}
