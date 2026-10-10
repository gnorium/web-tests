import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A record lists no references (user, 2026-10-10): a record page, a
/// record version's page and a word's madrigal credit no sources—no
/// References, no Sources, no mark—and the version links to the madrigal
/// it was permitted from. Nothing scrolls sideways. A throwaway admin owns a scratch
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

  /// A word: its record, version and madrigal pages credit nothing.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWordCreditsNoSourcesAnywhere(engine: BrowserEngine, layout: Layout) async throws {
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

        // Its madrigal lists none either: no Sources section.
        try await page.openHydrated(madrigal)
        try await expect(page.locator("#object-sources, .sources-view, .reference-credit-view")).toHaveCount(0)
        #expect(!(try await page.locator("body").textContent()).contains("dictionary.example.org"))
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
