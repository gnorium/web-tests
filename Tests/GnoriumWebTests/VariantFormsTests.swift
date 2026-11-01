import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Forms are submitted, not only derived (user, 2026-11-01): a record's
/// Forms field, right after its title, is an add-able list on both sides.
/// With none, one frozen Forms field; "+ Form" stamps a row (legend
/// "Form": its Form and a Source box, Source › Images › Quote, no Role),
/// "+ Source" another box, "− Form" takes the row away; the list is written
/// into forms-json as the server reads it. Nothing is submitted.
@Suite("Variant forms")
struct VariantFormsTests {
  static let forms: [(path: String, scope: String)] = [
    ("/mission-control/submit/lexicographic/sentiment", "record-"),
    ("/mission-control/submit/bibliographic/testament", "work-"),
  ]

  @Test(arguments: gnorium.engines, Layout.allCases)
  func aFormIsAddedWithItsSourceBoxes(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      for form in Self.forms {
        try await page.openHydrated(form.path)
        let field = page.locator("#\(form.scope)forms.variant-forms-field-view")
        try await expect(field).toHaveCount(1)
        let empty = field.locator(".variant-forms-empty input[disabled][placeholder='Forms']")
        try await expect(empty).toBeVisible()
        let add = field.locator(".variant-forms-add-btn")
        try await expect(add).toHaveText("Form")
        try await expect(add).toHaveAttribute("aria-label", "Add form")

        // "+ Form": a row, its legend singular, the frozen field gone.
        try await add.click()
        let rows = field.locator(".variant-forms-list > .variant-form")
        try await expect(rows).toHaveCount(1)
        try await expect(empty).toBeHidden()
        let row = rows.first
        try await expect(row.locator(".form-item-legend").first).toHaveText("Form")
        let key = try await row.getAttribute("data-variant-form-key") ?? ""
        try await expect(row.locator(".origin-quote-field-view")).toHaveCount(1)
        try await expect(row.locator("[name$='-role']")).toHaveCount(0)
        try await row.locator("input[name='\(key)-form']").fill("Hamlette")
        let box = row.locator(".origin-quote-field-view").first
        let quote = try await box.getAttribute("data-origin-quote-key") ?? ""
        try await box.locator("input[name='\(quote)-source-url']").fill("https://example.org/hamlet/manifest.json")
        try await box.locator("input[name='\(quote)-start-image']").fill("3")
        try await box.locator("textarea[name='\(quote)-quote']").fill("The Tragedie of Hamlette.")
        let json = try await field.evaluate(
          "(f) => f.querySelector(\"input[name='forms-json']\").value"
        ).string ?? ""
        #expect(json.contains("\"form\":\"Hamlette\""), Comment(rawValue: json))
        #expect(json.contains("\"sourceURL\":\"https://example.org/hamlet/manifest.json\""), Comment(rawValue: json))
        #expect(json.contains("\"images\":[3]"), Comment(rawValue: json))
        #expect(json.contains("\"quote\":\"The Tragedie of Hamlette.\""), Comment(rawValue: json))

        // "+ Source": a second box, each "− Source" shown.
        try await row.locator(".variant-form-add-quote-btn").click()
        try await expect(row.locator(".origin-quote-field-view")).toHaveCount(2)
        // Each box's record field asked for as it is stamped (its Source):
        // the row settles before it is removed.
        try await expect(row.locator(".quote-passage-record .origin-record-field-view"), timeout: .seconds(15))
          .toHaveCount(2)
        try await expect(row.locator(".origin-quote-remove-btn").first).toBeVisible()
        try await page.expectNoHorizontalOverflow()

        // "− Form": the row goes, the frozen field is back, the list empty.
        try await row.locator(".variant-form-remove-btn").click()
        try await expect(rows).toHaveCount(0)
        try await expect(empty).toBeVisible()
        try await expect(field.locator("input[name='forms-json']")).toHaveValue("[]")
        try await page.expectNoErrors()
      }
    }
  }
}
