import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A record's vignette shows its level as the record's page does (user,
/// 2026-10-20): the same level view in its sidebar, the mark and the word,
/// and no status line under the vignette's title. The work's vignette is
/// explicated: a disc beside "Explicated"; the word's counts its sentiments
/// per level instead (a lexico-record has no single level). On a phone the sidebar is
/// reached through the menu. Nothing scrolls sideways. Chrome headless.
@Suite("Vignette level", .serialized)
struct VignetteLevelTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWorksVignetteShowsItsLevelInTheSidebar(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await Self.expectLevel(page, path: "\(work.path)/vignettes/\(work.versionID)", layout: layout)
      }
    } catch {
      work.remove()
      try await admin.remove(after: error)
    }
    work.remove()
    try await admin.remove()
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWordsVignetteShowsItsLevelInTheSidebar(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await Self.expectCounts(page, path: "\(word.path)/vignettes/\(word.versionID)", layout: layout)
      }
    } catch {
      word.remove()
      try await admin.remove(after: error)
    }
    word.remove()
    try await admin.remove()
  }

  /// A word's vignette has no single level (user, 2026-10-20): its
  /// sentiments counted per level, as its record's page counts them—the
  /// scratch word's branch and leaf both explicated, a disc beside "2
  /// explicated".
  static func expectCounts(_ page: Page, path: String, layout: Layout) async throws {
    try await page.openHydrated(path)
    try await expect(page.locator(".layout-content-area .record-status-view")).toHaveCount(0)
    if layout == .phone {
      try await page.locator("[aria-label='Open menu']").filter(visible: true).first.click()
    }
    let counts = page.locator(".record-sidebar-view .record-level-counts-view").filter(visible: true).first
    try await expect(counts).toBeVisible()
    try await expect(counts.locator(".record-level-counts-level")).toHaveTexts(["2 explicated"])
    try await expect(counts.locator(".record-level-counts-level .icon-view")).toHaveCount(1)
    try await expect(page.locator(".record-sidebar-view .record-level-view")).toHaveCount(0)
    try await page.expectNoHorizontalOverflow()
    try await page.expectNoErrors()
  }

  static func expectLevel(_ page: Page, path: String, layout: Layout) async throws {
    try await page.openHydrated(path)
    // No status line in the main column.
    try await expect(page.locator(".layout-content-area .record-status-view")).toHaveCount(0)
    if layout == .phone {
      try await page.locator("[aria-label='Open menu']").filter(visible: true).first.click()
    }
    let level = page.locator(".record-sidebar-view .record-level-view").filter(visible: true).first
    try await expect(level).toBeVisible()
    try await expect(level.locator(".record-level-level")).toHaveText("Explicated")
    try await expect(level.locator(".record-level-level .icon-view")).toHaveCount(1)
    try await expect(level.locator(".record-level-partial")).toHaveCount(0)
    try await page.expectNoHorizontalOverflow()
    try await page.expectNoErrors()
  }
}
