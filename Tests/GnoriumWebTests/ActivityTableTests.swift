import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The dashboard's Activity table (user, 2026-10-20): Action, Object, ID,
/// Title, By, When. A revision is a Suggestion of a Revision, its id opening
/// it and its title the title of what it is filed on; never an act of the
/// object it is on.
@Suite("Activity table", .serialized)
struct ActivityTableTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aRevisionIsASuggestionOfARevision(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch: ScratchCommit
    do { scratch = try ScratchCommit(owner: admin) } catch { try await admin.remove(after: error) }
    do {
      let revisionID = try scratch.addOpenRevision()
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated("/mission-control")
        let table = page.locator(".mission-control-dashboard-recent-activity-table").first
        try await expect(table.locator("th[data-table-column-id]"))
          .toHaveTexts(["Action", "Object", "ID", "Title", "By", "When"])
        // The dashboard is recomputed every few seconds and pushed live.
        let id = table.locator("a[href*='/revisions/\(revisionID)' i]").first
        try await expect(id, timeout: .seconds(30)).toHaveCount(1)
        try await expect(id).toHaveText(revisionID.uppercased())
        let cells = try await page.evaluate("""
          (() => { const a = document.querySelector(".mission-control-dashboard-recent-activity-table a[href*='/revisions/\(revisionID)' i]");
            const row = a.closest('tr');
            return [...row.querySelectorAll('td')].slice(0, 4).map(td => td.innerText.trim()).join('|') })()
          """, as: String.self)
        #expect(cells == "Suggestion|Revision|\(revisionID.uppercased())|\(scratch.title)", "Row: \(cells)")
        try await expect(table).not.toContainText("Folksong")
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      scratch.remove()
      try await admin.remove(after: error)
    }
    scratch.remove()
    try await admin.remove()
  }
}
