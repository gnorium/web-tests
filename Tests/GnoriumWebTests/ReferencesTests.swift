import Foundation
import Testing
import WebTests
import WebTestsTesting

/// OED-style credits (user, 2026-09-28): a record page, and a record
/// version's page, credit no sources—no References, no list, no mark—and
/// the version links to the attribution object that does. The object
/// numbers each field's sources: its page's title (else host and path)
/// linked, its host. A fact with no fetched source is marked Unsourced.
/// Nothing scrolls sideways. A throwaway admin owns a scratch work whose
/// hallmark carries attributions, and a scratch word with research
/// references, made by SQL and removed after.
@Suite("References", .serialized)
struct ReferencesTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWorkIsCreditedOnItsHallmarkNotItsRecord(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin, references: true)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        let hallmark = "/mission-control/hallmarks/bibliographic/\(work.hallmarkID)"
        for path in [work.path, "\(work.path)/versions/\(work.versionID)"] {
          try await page.openHydrated(path)
          try await expect(page.locator("#record-references, #references, .sources-view")).toHaveCount(0)
          try await expect(page.locator(".field-references-view, .reference-credit-view")).toHaveCount(0)
          try await expect(page.locator(".reference-mark, .reference-marks-view")).toHaveCount(0)
          try await page.expectNoHorizontalOverflow()
          try await page.expectNoErrors()
        }
        // The version links to the hallmark that credits it (in its pedigree).
        try await expect(page.locator("a[href='\(hallmark)']")).not.toHaveCount(0)

        try await page.openHydrated(hallmark)
        // The record drawn as a tree (user, 2026-10-03): the work's fields in
        // its root's closed Metadata; under the title, its two sources,
        // numbered, in the order cited.
        let metadata = page.locator("#record-row-work #record-metadata-work")
        try await page.locator("#record-metadata-work > .accordion-summary").click()
        try await expect(metadata).toHaveAttribute("data-open-finished", "true")
        let title = page.locator("#work-work-field-references-title")
        try await expect(title).not.toHaveAttribute("open")
        try await page.locator("#work-work-field-references-title > .accordion-summary").click()
        try await expect(title).toHaveAttribute("data-open-finished", "true")
        let items = title.locator("ol.field-references-list > li")
        try await expect(items).toHaveCount(2)
        try await expect(items.nth(0).locator(".reference-credit-view-place a"))
          .toHaveAttribute("href", "https://catalogue.example.org/web-tests")
        try await expect(items.nth(0).locator(".reference-credit-view-source")).toHaveText("catalogue.example.org")
        try await expect(items.nth(1).locator(".reference-credit-view-place a"))
          .toHaveAttribute("href", "https://titles.example.org/web-tests")
        try await expect(items.nth(1).locator(".field-references-quote")).toHaveText(work.title)
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

  /// A word: its record and version pages credit nothing; its hallmark's
  /// Sources number each fact's, and the branch sentiment, which rests on
  /// nothing, is Unsourced.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWordIsCreditedOnItsHallmarkNotItsRecord(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        let hallmark = "/mission-control/hallmarks/lexicographic/\(word.hallmarkID)"
        for path in [word.path, "\(word.path)/versions/\(word.versionID)"] {
          try await page.openHydrated(path)
          try await expect(page.locator("#record-references, #references, .sources-view")).toHaveCount(0)
          try await expect(page.locator(".reference-credit-view")).toHaveCount(0)
          try await expect(page.locator("#record-row-s-1-1 .record-row-title sup")).toHaveCount(0)
          #expect(!(try await page.locator("body").textContent()).contains("dictionary.example.org"))
          try await page.expectNoHorizontalOverflow()
          try await page.expectNoErrors()
        }
        try await expect(page.locator("a[href='\(hallmark)']")).not.toHaveCount(0)

        try await page.openHydrated(hallmark)
        let sources = page.locator("#object-sources")
        try await expect(sources).not.toHaveAttribute("open")
        try await page.locator("#object-sources > .accordion-summary").click()
        try await expect(sources).toHaveAttribute("data-open-finished", "true")
        let fields = sources.locator(".sources-view-field")
        let title = fields.filter(hasText: "Title").first
        try await expect(title.locator("ol.sources-view-list > li")).toHaveCount(1)
        try await expect(title.locator(".reference-credit-view-place a"))
          .toHaveAttribute("href", "https://dictionary.example.org/web-tests")
        try await expect(title.locator(".reference-credit-view-source")).toHaveText("dictionary.example.org")
        let branch = fields.filter(hasText: "Sentiment 1").first
        try await expect(branch.locator(".info-chip-view")).toHaveText("Unsourced")
        let leaf = fields.filter(hasText: "Sentiment 1.1").first
        try await expect(leaf.locator(".reference-credit-view-place a"))
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
