import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Amendment metadata remains editable after field-formulation ticks are retired.
@Suite("Amendment metadata", .serialized)
struct AmendmentFormulationTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func editingWithoutFormulationTicks(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch = try ScratchWork(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("\(scratch.path)/amendments/new")
        let work = page.locator(".submit-amendment-work")
        let title = work.locator("input[name='title']").first
        if !(try await title.isVisible()) {
          try await work.locator(".accordion-summary").first.click()
        }
        try await expect(title).toBeVisible()
        let original = try await title.inputValue()
        try await title.fill(original + " (edited)")
        try await expect(title).toHaveValue(original + " (edited)")
        try await expect(page.locator("input[name='attribute[]']")).toHaveCount(0)
        try await expect(page.locator(".selectable-field-view")).toHaveCount(0)
        try await title.fill(original)
        try await expect(title).toHaveValue(original)
      }
    } catch {
      scratch.remove()
      try await admin.remove(after: error)
    }
    scratch.remove()
    try await admin.remove()
  }
}
