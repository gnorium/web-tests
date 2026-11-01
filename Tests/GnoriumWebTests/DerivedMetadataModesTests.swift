import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A lexico-record's derived Metadata (First attestation, Forms,
/// Pronunciation, Use, Related words) by form (user, 2026-11-01): Submit
/// Sentiment shows none of it, only what the submitter fills in; an
/// amendment, a frozen form, shows every field, an empty one its
/// placeholder (= its label), never "—". The record's own page, which
/// hides an empty one, is covered by the server's render tests.
@Suite("Derived metadata modes", .serialized)
struct DerivedMetadataModesTests {
  static let derived = ["Testament", "Place", "First user", "Date", "Hyphenation", "Rhymes", "Inflections"]

  @Test(arguments: gnorium.engines)
  func submitHidesFrozenFormsShowPlaceholders(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine), cookies: [admin.cookie]) {
        page in
        // Submit Sentiment: the typed identity only.
        try await page.openHydrated(SentimentFormTests.path)
        let submit = page.locator(".submit-sentiment-form .lexico-record-metadata-view")
        try await expect(submit).toHaveCount(1)
        try await expect(submit.locator("input[name='title']")).toBeVisible()
        try await expect(submit.locator(".metadata-group-view, .datum-view, .derived-forms-view")).toHaveCount(0)
        for label in Self.derived {
          try await expect(submit.locator("[placeholder='\(label)']")).toHaveCount(0)
        }
        // No dash in its fields (its Origin rows are their own field).
        let dashed = try await submit.evaluate(
          "(view) => [...view.children].some((c) => !c.matches('.origin-field-view') && c.textContent.includes('—'))"
        ).bool
        #expect(dashed == false)

        // An amendment: every derived field frozen, its placeholder.
        try await page.openHydrated("\(word.path)/amendments/new")
        let amendment = page.locator(".lexico-record-metadata-view").first
        try await expect(amendment.locator(".derived-forms-view")).toHaveCount(1)
        // Each field shows: its value as a datum, or empty, its placeholder.
        let labels = Self.derived.map { "'\($0)'" }.joined(separator: ", ")
        let missing = try await amendment.evaluate(
          """
          (view) => [\(labels)].filter((label) =>
            !view.querySelector(`input[disabled][placeholder='${label}']`)
              && ![...view.querySelectorAll('.datum-label')].some((l) => l.textContent.trim() === label)
          ).join(', ')
          """
        ).string
        #expect(missing == "", "missing: \(missing ?? "")")
        try await expect(amendment.locator("input[disabled][placeholder='Hyphenation']")).toHaveCount(1)
        #expect(try await amendment.evaluate("(view) => view.textContent.includes('—')").bool == false)
      }
    } catch {
      word.remove()
      try await admin.remove(after: error)
    }
    word.remove()
    try await admin.remove()
  }
}
