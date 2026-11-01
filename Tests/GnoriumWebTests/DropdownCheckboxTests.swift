import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A multi-select dropdown's options are checkboxes, never radios: each
/// option's box is CheckboxView's, square (20px, the minimal radius, 4px).
/// On the solid blue row under the pointer the box inverts: unchecked, a
/// white edge on the blue; checked, white filled and edged with the tick in
/// the row's blue. Submit Testament's Origin relation is the dropdown here.
@Suite("Dropdown checkbox", .serialized)
struct DropdownCheckboxTests {
  @Test(arguments: gnorium.engines)
  func multiSelectOptionsAreSquareCheckboxes(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/submit/bibliographic/testament")
        let relation = page.locator(".submit-testament-form .origin-field-view [data-origin-row='true'] .dropdown-view").first
        try await relation.locator(".dropdown-trigger").click()
        try await expect(relation.locator(".dropdown-menu")).toHaveAttribute("data-open", "true")
        let option = relation.locator(".dropdown-option[data-value='abridgment_of']")
        let probe =
          "(b) => { const s = getComputedStyle(b); const r = b.getBoundingClientRect(); const t = getComputedStyle(b.querySelector('.dropdown-option-checkmark')); return [s.borderTopLeftRadius, s.borderBottomRightRadius, String(Math.round(r.width)), String(Math.round(r.height)), s.backgroundColor, s.borderTopColor, t.borderRightColor, getComputedStyle(b.closest('.dropdown-option')).backgroundColor].join('|') }"
        func box() async throws -> [String] {
          let text = try await option.locator(".dropdown-option-checkbox").evaluate(probe).string ?? ""
          return text.split(separator: "|").map(String.init)
        }
        // Unchecked, under the pointer: square, a white edge, no fill.
        try await option.hover()
        let unchecked = try await box()
        #expect(Array(unchecked.prefix(4)) == ["4px", "4px", "20", "20"], "a square 20px box with 4px corners, not \(unchecked)")
        #expect(unchecked.count == 8 && unchecked[4] == "rgba(0, 0, 0, 0)" && unchecked[5] == "rgb(255, 255, 255)",
          "unchecked on the blue row: transparent with a white edge, not \(unchecked)")
        // Checked, under the pointer: white filled and edged, the tick the row's blue.
        try await option.click()
        try await expect(option).toHaveAttribute("data-selected", "true")
        let checked = try await box()
        #expect(Array(checked.prefix(4)) == ["4px", "4px", "20", "20"], "a square 20px box with 4px corners, not \(checked)")
        #expect(checked.count == 8 && checked[4] == "rgb(255, 255, 255)" && checked[5] == checked[4] && checked[6] == checked[7],
          "checked on the blue row: white, its tick the row's blue, not \(checked)")
        // Away from the row: the house checkbox, blue filled with a white tick.
        try await relation.locator(".dropdown-option[data-value='translation_of']").hover()
        let resting = try await box()
        #expect(resting.count == 8 && resting[4] != "rgb(255, 255, 255)" && resting[6] == "rgb(255, 255, 255)",
          "checked on a white row: blue filled with a white tick, not \(resting)")
        #expect(Array(resting.prefix(2)) == ["4px", "4px"])
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }
}
