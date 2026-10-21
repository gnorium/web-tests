import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Submit Testament's fields reach the data it posts as they are filled
/// (user, 2026-10-21), never later: a list's JSON follows each keystroke,
/// opening a combobox by its arrow chooses nothing, and a required choice
/// stays chosen however it is clicked. Nothing is submitted. Needs an
/// admin, made for the test and removed after (see `TestAdmin`); Chrome,
/// phone and desktop.
@Suite("Submit Testament sync", .serialized)
struct SubmitTestamentSyncTests {
  static let form = "/mission-control/submit/bibliographic/testament"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func fieldsReachThePostedDataAsTheyAreFilled(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(Self.form)
        let form = page.locator(".submit-testament-form")

        // A voice's name is in the list's JSON while the field still has the
        // focus.
        let voices = form.locator("[data-item-list='work-voice']")
        let name = voices.locator(".text-input-input:not([data-item-template] *)").first
        try await name.click()
        try await name.type("Ada Lovelace")
        try await expect(name).toBeFocused()
        let json = try await page.evaluate(
          "document.querySelector(\"input[name='work-voice-json']\").value", as: String.self)
        #expect(json.contains("Ada Lovelace"), "The voice name is posted without leaving the field: \(json)")

        // A required choice stays chosen when it is clicked again.
        let language = form.locator(".dropdown-view:has(#work-language)")
        let value = form.locator("input[name='language']")
        try await language.locator(".dropdown-trigger").click()
        try await language.locator(".dropdown-option[data-value='eng']").click()
        try await expect(value).toHaveValue("eng")
        try await language.locator(".dropdown-trigger").click()
        try await language.locator(".dropdown-option[data-value='eng']").click()
        try await expect(value).toHaveValue("eng")

        // Opening a combobox by its arrow chooses nothing.
        let carrier = form.locator(".dropdown-view:has(#testament-carrier)")
        try await carrier.locator(".dropdown-trigger").click()
        try await carrier.locator(".dropdown-option[data-value='printed']").click()
        let provider = form.locator(".combobox-view:has(input[name='provider-dropdown'])")
        try await provider.locator(".combobox-toggle").click()
        try await expect(provider.getByRole(.combobox, name: "Provider")).toHaveAttribute("aria-expanded", "true")
        try await expect(provider.locator("input[name='provider-dropdown']")).toHaveValue("")
        try await expect(provider.getByRole(.combobox, name: "Provider")).toHaveValue("")
        try await page.expectNoErrors()
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }
}
