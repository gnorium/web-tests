import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Ticking fields for attribution on the Submit Amendment form: a box
/// before every field and every row, ticked by editing the field, drawn
/// blue when ticked and unedited. Nothing is submitted. Needs a signed-in
/// account, made for the test and removed after (see `TestAdmin`).
@Suite("Amendment attribution", .serialized)
struct AmendmentAttributionTests {
  /// The Bosworth–Toller record, kept on the dev database.
  static let form =
    "/biblio-records/ang/an-anglo-saxon-dictionary/joseph-bosworth-and-thomas-northcote-toller/amendments/new"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func tickingFields(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await run(engine: engine, viewport: layout.viewport(for: engine), admin: admin)
    } catch {
      await admin.remove()
      throw error
    }
    await admin.remove()
  }

  private func run(engine: BrowserEngine, viewport: Viewport, admin: TestAdmin) async throws {
    try await withPage(engine, gnorium, viewport: viewport, cookies: [admin.cookie]) { page in
      try await page.openHydrated(Self.form)
      let work = page.locator(".submit-amendment-work")
      let title = work.locator(".attribute-field-view[data-attribute-key='title']")
      let titleBox = title.locator(".attribute-field-view-checkbox .checkbox-input")
      let titleInput = title.locator(".text-input-input")
      let script = work.locator(".attribute-field-view[data-attribute-key='script']")
      let scriptBox = script.locator(".attribute-field-view-checkbox .checkbox-input")

      // A real input per field and per row, unticked.
      try await expect(titleBox).toHaveAttribute("name", "attribute[]")
      try await expect(titleBox).toBeChecked(false)
      try await expect(work.locator(".attribute-field-view[data-attribute-key='author[1]']:not([data-item-template] *)")).toHaveCount(1)

      // The work's fields sit in its Metadata accordion: open it if shut.
      if !(try await titleInput.isVisible()) {
        try await work.locator(".accordion-summary").first.click()
      }
      try await expect(titleInput).toBeVisible()

      // Editing a field ticks it; undoing the edit unticks it again.
      let before = try await titleInput.inputValue()
      try await titleInput.fill(before + " (edited)")
      try await expect(titleBox).toBeChecked()
      try await titleInput.fill(before)
      try await expect(titleBox).toBeChecked(false)

      // An unedited field can be ticked by hand, and its control is drawn
      // blue, border and ring.
      try await scriptBox.check()
      let trigger = script.locator(".dropdown-trigger")
      let ring = try await trigger.evaluate("(el) => getComputedStyle(el).boxShadow").string ?? ""
      let blue = try await page.evaluate(
        "getComputedStyle(document.documentElement).getPropertyValue('--border-color-blue').trim()"
      ).string ?? ""
      #expect(!blue.isEmpty)
      #expect(ring.contains("1px"), "the ticked field's control has no ring: \(ring)")
      try await scriptBox.uncheck()
      try await expect(scriptBox).toBeChecked(false)
    }
  }
}
