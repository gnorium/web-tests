import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Testaments nest to any depth, as sentiments do (user, 2026-09-27): on
/// Submit Testament, the chosen record's chronicle tree takes the new
/// testament under an edition of its own level — an edition within an
/// edition — and refuses it under a manifest, in the chronicle tree's own
/// words (`TestamentShape.Fault`). Nothing is submitted. A throwaway admin
/// owns a scratch work (one edition and its manifest), removed after.
@Suite("Testament depth", .serialized)
struct TestamentDepthTests {
  static let form = "/mission-control/submit/bibliographic/evidence-testament"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func aNewEditionGoesUnderAnEditionNeverUnderAManifest(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    do {
      try await run(engine: engine, viewport: layout.viewport(for: engine), admin: admin, work: work)
    } catch {
      work.remove()
      await admin.remove()
      throw error
    }
    work.remove()
    await admin.remove()
  }

  private func run(engine: BrowserEngine, viewport: Viewport, admin: TestAdmin, work: ScratchWork) async throws {
    try await withPage(engine, gnorium, viewport: viewport, cookies: [admin.cookie]) { page in
      try await page.openHydrated(Self.form)
      let field = page.locator(".record-choice-field-view")
      let dropdown = field.locator(".dropdown-view")

      // The scratch work, found by typing and picked.
      try await dropdown.locator(".dropdown-trigger").click()
      try await dropdown.locator(".dropdown-search-input").fill(work.suffix)
      let results = dropdown.locator(".dropdown-options-list[data-dropdown-results='true']")
      try await expect(results.locator(".dropdown-option")).toHaveCount(1)
      try await results.locator(".dropdown-option[data-value='\(work.recordID)']").click()
      try await expect(field.locator("input[name='biblio-record']")).toHaveValue(work.recordID)

      // Its tree: its edition (1) and manifest (1.1); the new testament
      // after the edition (2).
      let tree = field.locator(".record-placement-view")
      try await expect(tree, timeout: .seconds(15)).toBeVisible()
      let new = tree.locator(".outliner-item[data-outliner-id='edition-new']")
      let number = new.locator(".record-placement-number").first
      try await expect(number).toHaveText("2")

      // Indented, it goes under the edition, after its manifest: an
      // edition within an edition. The arrangement posts it.
      try await new.locator(".outliner-handle").first.click()
      let indent = page.locator(".outliner-toolbar [data-outliner-action='indent']")
      try await expect(indent).toBeEnabled()
      try await indent.click()
      try await page.locator(".outliner-toolbar [data-outliner-action='done']").click()
      try await expect(number).toHaveText("1.2")
      let placement = try await field.locator("input[name='placement']").inputValue()
      #expect(placement.contains(#""edition-new":{"parent":"edition-"#), "\(placement)")

      // Under the manifest above it, it is refused, in the tree's words,
      // and stays where it was.
      let handle = new.locator(".outliner-handle").first
      try await handle.click()
      try await expect(indent).toBeDisabled()
      try await handle.press("ArrowRight")
      try await expect(tree.locator(".outliner-feedback .alert-content"))
        .toHaveText("Nothing can go under a manifest: its images attest it.")
      try await handle.press("Escape")
      try await expect(number).toHaveText("1.2")
    }
  }
}
