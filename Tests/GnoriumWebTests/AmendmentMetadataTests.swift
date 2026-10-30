import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Amendment metadata is edited directly: no field ticks.
@Suite("Amendment metadata", .serialized)
struct AmendmentMetadataTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func editingWithoutFieldTicks(engine: BrowserEngine, layout: Layout) async throws {
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

  /// An amendment names its one digitization (user, 2026-10-31): only the
  /// leaf has a radio; nothing selected refuses Submit with an alert above
  /// it; editing a parent's fields selects the one digitization
  /// under it, and its edit keeps the selection while it stands.
  @Test(arguments: gnorium.engines, [Layout.desktop])
  func selectingTheDigitization(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch = try ScratchWork(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("\(scratch.path)/amendments/new")
        let radios = page.locator(".testament-choice-view input[name='testament']")
        try await expect(radios).toHaveCount(1)
        let radio = radios.first
        try await expect(radio).toBeEnabled()
        try await expect(radio).toBeChecked(false)

        // Nothing selected: refused where it is, with the alert.
        let alert = page.locator(".testament-outliner-unchosen")
        try await expect(alert).toBeHidden()
        try await page.locator(".action-gate-view button[type='submit']").first.click()
        try await expect(alert).toBeVisible()
        try await expect(alert).toContainText("Select the digitization this amendment is about.")
        #expect(try await page.url().hasSuffix("/amendments/new"))

        // The work edited: its one digitization is selected, and the alert goes.
        let work = page.locator(".submit-amendment-work")
        let title = work.locator("input[name='title']").first
        if !(try await title.isVisible()) {
          try await work.locator(".accordion-summary").first.click()
        }
        let original = try await title.inputValue()
        try await title.fill(original + " (edited)")
        try await expect(radio).toBeChecked()
        try await expect(alert).toBeHidden()
        try await expect(radio).toHaveAttribute("form", "amendment-work")

        // Undone: still selected, still a radio.
        try await title.fill(original)
        try await expect(radio).toBeChecked()
        try await expect(radio).toBeEnabled()
      }
    } catch {
      scratch.remove()
      try await admin.remove(after: error)
    }
    scratch.remove()
    try await admin.remove()
  }
}
