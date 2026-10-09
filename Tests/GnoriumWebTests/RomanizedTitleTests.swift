import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A record whose title is in another script has a Romanized title (user,
/// 2026-10-09): an information field in its Metadata, right after the
/// title, disabled (written by the model at explication and checked against
/// ICU's transliteration, never typed); the Title search finds the record
/// by its romanization, accents and case aside; a Latin title has no such
/// field, and nothing shows in the list's rows. A Devanagari scratch word
/// under a throwaway admin, removed after; Chrome, phone and desktop.
@Suite("Romanized title", .serialized)
struct RomanizedTitleTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aDevanagariTitleShowsAndIsFoundByItsRomanization(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let suffix = String(UUID().uuidString.prefix(6).lowercased())
    // A unique Devanagari title, its romanization the conventional one.
    let word = try ScratchWord(owner: admin, language: "hin", title: "रामायण\(suffix)", romanizedTitle: "Ramayan \(suffix)")
    let latin = try ScratchWord(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(word.path)
        try await page.expectNoErrors()
        let metadata = page.locator("#record-metadata")
        try await metadata.locator(".accordion-summary").first.click()
        // The field, after the title, disabled, holding the romanization.
        let field = metadata.locator("input[name='romanizedTitle']")
        try await expect(field).toBeVisible()
        try await expect(field).toHaveValue("Ramayan \(suffix)")
        try await expect(field).toBeDisabled()
        try await expect(metadata.locator(".datum-view").filter(hasText: "Title").first).toBeVisible()
        try await page.expectNoHorizontalOverflow()

        // The Title search, by the romanization in another case: the word.
        try await page.openHydrated("/lexico-records")
        if layout == .phone {
          try await page.locator(".sidebar-menu-btn").click()
        }
        let form = page.locator("[data-records-search='true']").filter(visible: true).first
        try await form.locator(".search-bar-input").fill("RAMAYAN \(suffix)")
        try await expect(page.locator(".records-count-view")).toHaveText("1 lexico-record")
        let rows = page.locator(".records-results-view tbody a[href^='/lexico-records/']")
        try await expect(rows).toHaveCount(1)
        try await expect(rows.first).toHaveText(word.title)
        // Nothing of the romanization in the row.
        try await expect(page.locator(".records-results-view tbody").getByText("Ramayan", exact: false)).toHaveCount(0)

        // A Latin title has no Romanized title field.
        try await page.openHydrated(latin.path)
        let own = page.locator("#record-metadata")
        try await own.locator(".accordion-summary").first.click()
        try await expect(own.locator(".datum-view").filter(hasText: "Title").first).toBeVisible()
        try await expect(own.locator("input[name='romanizedTitle']")).toHaveCount(0)
      }
    } catch {
      word.remove()
      latin.remove()
      try await admin.remove(after: error)
    }
    word.remove()
    latin.remove()
    try await admin.remove()
  }
}
