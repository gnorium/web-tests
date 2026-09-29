import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A record page's testament tree is the shared tree whose nodes are
/// accordions (user, 2026-09-30): a row's own chevron is its collapse
/// control, so the tree draws no toggle of its own and keeps no toggle
/// column: a top row starts where the tree does, and a row under it one
/// step in. Closing a row hides the rows under it with its body; opening it
/// shows them again. The fixture work holds an edition and its manifest.
@Suite("Record tree", .serialized)
struct RecordTreeTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aRowsOwnChevronCollapsesTheRowsUnderIt(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(work.path)
        let tree = page.locator(".outliner-view").first
        let edition = tree.locator(".outliner-item[data-outliner-id^='edition-']").first
        let manifest = tree.locator(".outliner-item[data-outliner-id^='manifest-']").first
        try await expect(edition).toHaveAttribute("data-outliner-accordion", "true")
        try await expect(tree.locator(".outliner-toggle")).toHaveCount(0)
        try await expect(manifest).toBeVisible()

        // No toggle column: the top row starts where the tree's list does,
        // and the row under it a step (24px) further in.
        let list = try #require(try await tree.locator(".outliner-scroll > .outliner-list").boundingBox())
        let top = try #require(try await edition.locator(":scope > .outliner-row > .outliner-node").boundingBox())
        let under = try #require(try await manifest.locator(":scope > .outliner-row > .outliner-node").boundingBox())
        #expect(abs(top.x - list.x) < 1, "the top row keeps a toggle column's room")
        #expect(abs(under.x - top.x - 24) < 1, "the row under it is not one step in")

        // The row's own chevron: closed, the rows under it go with its body.
        let summary = edition.locator(":scope > .outliner-row > .outliner-node .accordion-summary").first
        try await summary.click()
        try await expect(edition).toHaveAttribute("data-outliner-collapsed", "true")
        try await expect(manifest).toBeHidden()
        try await summary.click()
        try await expect(edition).toHaveAttribute("data-outliner-collapsed", "false")
        try await expect(manifest).toBeVisible()
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      work.remove()
      try await admin.remove(after: error)
    }
    work.remove()
    try await admin.remove()
  }
}
