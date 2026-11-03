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

  /// One subject per amendment (user, 2026-11-03), never chosen: no
  /// radio; Submit with nothing changed is turned back above Submit; the
  /// first change—the work's fields here—freezes every testament, its
  /// handle and fields shut and the steppers offering nothing; undone,
  /// all open again.
  @Test(arguments: gnorium.engines, [Layout.desktop])
  func theFirstChangeIsTheOneSubject(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch = try ScratchWork(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("\(scratch.path)/amendments/new")
        try await expect(page.locator(".testament-choice-view")).toHaveCount(0)
        try await expect(page.locator("input[name='testament'][type='radio']")).toHaveCount(0)

        // Nothing changed: the server turns it back, on the form drawn again.
        try await page.locator(".action-gate-view button[type='submit']").first.click()
        let refusal = page.locator(".submit-amendment-refusal")
        try await expect(refusal, timeout: .seconds(15)).toContainText("Nothing was changed.")
        try await page.openHydrated("\(scratch.path)/amendments/new")

        let nodes = page.locator(".testament-outliner-node")
        let stepper = page.locator("#testament-outliner > .outliner-stepper-view[data-outliner-stepper-ready='true']")
        try await expect(stepper).toBeAttached()
        try await expect(nodes.first).toHaveAttribute("data-testament-frozen", "false")
        try await expect(stepper.locator(".outliner-stepper-add .outliner-stepper-button")).toBeEnabled()

        // The work edited: its own fields are the subject, every testament frozen.
        let work = page.locator(".submit-amendment-work")
        let title = work.locator("input[name='title']").first
        if !(try await title.isVisible()) {
          try await work.locator(".accordion-summary").first.click()
        }
        let original = try await title.inputValue()
        try await title.fill(original + " (edited)")
        try await expect(nodes.first).toHaveAttribute("data-testament-frozen", "true")
        try await expect(nodes.first.locator(".record-node-marker").first)
          .toHaveAttribute("data-outliner-immovable", "true")
        try await expect(stepper.locator(".outliner-stepper-add .outliner-stepper-button")).toBeDisabled()
        try await expect(stepper.locator(".outliner-stepper-remove .outliner-stepper-button")).toBeDisabled()
        try await expect(page.locator(".testament-outliner-hint[data-hint='edit']")).toHaveAttribute("data-visible", "true")

        // Undone: all open again.
        try await title.fill(original)
        try await expect(nodes.first).toHaveAttribute("data-testament-frozen", "false")
        try await expect(nodes.first.locator(".record-node-marker").first)
          .toHaveAttribute("data-outliner-immovable", "false")
        try await expect(stepper.locator(".outliner-stepper-add .outliner-stepper-button")).toBeEnabled()
      }
    } catch {
      scratch.remove()
      try await admin.remove(after: error)
    }
    scratch.remove()
    try await admin.remove()
  }
}
