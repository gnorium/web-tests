import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Unsetting a picked record takes back what its pick filled in and nobody
/// changed since, as a person would (a dropdown back to its placeholder, a
/// row the pick filled emptied); a field edited after the pick keeps its
/// value. Submit Testament's Biblio-record field. Nothing is submitted.
@Suite("Record unpick", .serialized)
struct RecordUnpickTests {
  static let form = "/mission-control/submit/bibliographic/evidence-testament"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func unsettingAPickTakesBackItsUntouchedValues(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(Self.form)
        let form = page.locator(".submit-testament-form")
        let field = form.locator(".record-choice-field-view")
        let dropdown = field.locator(".dropdown-view")
        let author = form.locator(
          "[data-item-list='work-voice'] [data-item-section='true']:not([data-item-template] *) .text-input-input")
        // Picked: its language, title, type and voice filled in.
        try await dropdown.locator(".dropdown-trigger").click()
        try await dropdown.locator(".dropdown-search-input").fill(work.suffix)
        try await dropdown.locator(
          ".dropdown-options-list[data-dropdown-results='true'] .dropdown-option[data-value='\(work.recordID)']"
        ).click()
        try await expect(form.locator("input[name='title']"), timeout: .seconds(15)).toHaveValue(work.title)
        try await expect(form.locator("#work-language")).toHaveValue("eng")
        try await expect(form.locator("#work-type")).toHaveValue("report")
        try await expect(author).toHaveCount(1)
        try await expect(author.first).toHaveValue(work.author)

        // One field edited: the pick still stands.
        try await form.locator("input[name='title']").fill("\(work.title), revised")
        try await Task.sleep(for: .milliseconds(900))
        try await expect(field.locator("input[name='biblio-record']")).toHaveValue(work.recordID)

        // Unset: the others go back as a person would clear them; the
        // edited title stays.
        try await dropdown.locator(".dropdown-trigger").click()
        try await dropdown.locator(".dropdown-option[data-value='\(work.recordID)']").first.click()
        try await expect(dropdown.locator(".dropdown-selected-text")).toHaveText("—")
        try await expect(form.locator("input[name='title']")).toHaveValue("\(work.title), revised")
        try await expect(form.locator("#work-language")).toHaveValue("")
        try await expect(form.locator("[data-dropdown-id='work-language'] .dropdown-selected-text")).toHaveText("Language")
        try await expect(form.locator("#work-type")).toHaveValue("")
        try await expect(form.locator("[data-dropdown-id='work-type'] .dropdown-selected-text")).toHaveText("Type")
        try await expect(author).toHaveCount(1)
        try await expect(author.first).toHaveValue("")

        // Picked again, then another value typed over the voice: unset, the
        // typed voice stays.
        try await dropdown.locator(".dropdown-trigger").click()
        try await dropdown.locator(".dropdown-search-input").fill(work.suffix)
        try await dropdown.locator(
          ".dropdown-options-list[data-dropdown-results='true'] .dropdown-option[data-value='\(work.recordID)']"
        ).click()
        try await expect(author.first, timeout: .seconds(15)).toHaveValue(work.author)
        try await expect(form.locator("#work-type")).toHaveValue("report")
        try await author.first.fill("Someone Else")
        try await Task.sleep(for: .milliseconds(900))
        try await dropdown.locator(".dropdown-trigger").click()
        try await dropdown.locator(".dropdown-option[data-value='\(work.recordID)']").first.click()
        try await expect(dropdown.locator(".dropdown-selected-text")).toHaveText("—")
        try await expect(author.first).toHaveValue("Someone Else")
        try await expect(form.locator("#work-type")).toHaveValue("")
      }
    } catch {
      work.remove()
      await admin.remove()
      throw error
    }
    work.remove()
    await admin.remove()
  }
}
