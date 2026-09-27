import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A title's forms belong to the nodes of a record's tree (user,
/// 2026-09-27): on Submit Testament, the edition's, in its Publication card,
/// never the work's; the same rows as Submit Sentiment's ("Form", "+ Add
/// form"), serialized in order for the record field, which matches them.
/// Nothing is submitted.
@Suite("Testament forms")
struct TestamentFormsTests {
  static let form = "/mission-control/submit/bibliographic/evidence-testament"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func theFormsAreTheEditions(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(Self.form)
        let form = page.locator(".submit-testament-form")
        let forms = form.locator("[data-item-list='title-form']")
        try await expect(forms).toHaveCount(1)
        // In the Publication card, not the work.
        let placed = try await forms.evaluate(
          """
          (group) => JSON.stringify({
            publication: !!group.closest("[data-as-namespace='publication'] .framed-accordion-view"),
            work: !!group.closest('.bibliographic-work-section'),
          })
          """
        ).string ?? "{}"
        struct Placed: Decodable { let publication: Bool; let work: Bool }
        let where_ = try JSONDecoder().decode(Placed.self, from: Data(placed.utf8))
        #expect(where_.publication, "the Form rows are not in the Publication card")
        #expect(!where_.work, "the Form rows are in the work")

        let rows = forms.locator("[data-item-section='true']:not([data-item-template] *)")
        try await expect(rows.first.locator(".text-input-input")).toHaveAttribute("placeholder", "Form")
        try await expect(forms.locator("[data-item-add-btn='true'] button")).toContainText("+ Add form")
        try await rows.first.locator(".text-input-input").fill("Poëms, by J. D.")
        try await forms.locator("[data-item-add-btn='true'] button").click()
        try await expect(rows).toHaveCount(2)
        try await rows.nth(1).locator(".text-input-input").fill("Poems by J.D.")
        // The record field asks again as the title changes, the forms
        // serialized with the form it posts.
        try await form.locator("input[name='title']").fill("Poems")
        try await expect(forms.locator(".title-form-json"), timeout: .seconds(10))
          .toHaveValue(#"[{"value":"Poëms, by J. D."},{"value":"Poems by J.D."}]"#)
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      await admin.remove()
      throw error
    }
    await admin.remove()
  }
}
