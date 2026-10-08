import Foundation
import Testing
import WebTests
import WebTestsTesting

/// OED-style credits (user, 2026-09-28): a record page, and a record
/// version's page, credit no sources—no References, no list, no mark—and
/// the version links to the madrigal it was permitted from. A word's
/// madrigal numbers each fact's sources: its page's title (else host and
/// path) linked, its host. A fact with no fetched source is marked
/// Unsourced. Nothing scrolls sideways. A throwaway admin owns a scratch
/// work and a scratch word with research references, made by SQL and
/// removed after.
@Suite("References", .serialized)
struct ReferencesTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWorkCreditsNoSourcesOnItsRecord(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        let madrigal = "/mission-control/madrigals/bibliographic/\(work.madrigalID)"
        for path in [work.path, "\(work.path)/vignettes/\(work.versionID)"] {
          try await page.openHydrated(path)
          try await expect(page.locator("#record-references, #references, .sources-view")).toHaveCount(0)
          try await expect(page.locator(".reference-credit-view")).toHaveCount(0)
          try await expect(page.locator(".reference-mark, .reference-marks-view")).toHaveCount(0)
          try await page.expectNoHorizontalOverflow()
          try await page.expectNoErrors()
        }
        // The version links to the madrigal it was permitted from (in its
        // pedigree).
        try await expect(page.locator("a[href='\(madrigal)']")).not.toHaveCount(0)
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      work.remove()
      try await admin.remove(after: error)
    }
    work.remove()
    try await admin.remove()
  }

  /// A word: its record and version pages credit nothing; its madrigal's
  /// Sources number each fact's, and the branch sentiment, which rests on
  /// nothing, is Unsourced.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWordIsCreditedOnItsMadrigalNotItsRecord(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        let madrigal = "/mission-control/madrigals/lexicographic/\(word.madrigalID)"
        for path in [word.path, "\(word.path)/vignettes/\(word.versionID)"] {
          try await page.openHydrated(path)
          try await expect(page.locator("#record-references, #references, .sources-view")).toHaveCount(0)
          try await expect(page.locator(".reference-credit-view")).toHaveCount(0)
          try await expect(page.locator("#record-row-s-1-1 .record-row-title sup")).toHaveCount(0)
          #expect(!(try await page.locator("body").textContent()).contains("dictionary.example.org"))
          try await page.expectNoHorizontalOverflow()
          try await page.expectNoErrors()
        }
        try await expect(page.locator("a[href='\(madrigal)']")).not.toHaveCount(0)

        try await page.openHydrated(madrigal)
        let sources = page.locator("#object-sources")
        try await expect(sources).not.toHaveAttribute("open")
        try await page.locator("#object-sources > .accordion-summary").click()
        try await expect(sources).toHaveAttribute("data-open-finished", "true")
        let fields = sources.locator(".sources-field")
        let title = fields.filter(hasText: "Title").first
        try await expect(title.locator("ol.sources-list > li")).toHaveCount(1)
        try await expect(title.locator(".reference-credit-place a"))
          .toHaveAttribute("href", "https://dictionary.example.org/web-tests")
        try await expect(title.locator(".reference-credit-source")).toHaveText("dictionary.example.org")
        let branch = fields.filter(hasText: "Sentiment 1").first
        try await expect(branch.locator(".info-chip-view")).toHaveText("Unsourced")
        let leaf = fields.filter(hasText: "Sentiment 1.1").first
        try await expect(leaf.locator(".reference-credit-place a"))
          .toHaveAttribute("href", "https://senses.example.org/web-tests")
        try await expect(leaf.locator(".info-chip-view")).toHaveCount(0)
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      word.remove()
      try await admin.remove(after: error)
    }
    word.remove()
    try await admin.remove()
  }
}
