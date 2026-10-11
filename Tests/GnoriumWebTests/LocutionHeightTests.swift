import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Locution height", .serialized)
struct LocutionHeightTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aLongLocutionGrowsToItsContent(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin, submitted: true)
    let locution = UUID().uuidString.lowercased()
    func remove() {
      _ = try? TestAdmin.query("DELETE FROM locutions WHERE id = '\(locution)';")
      word.remove()
    }
    do {
      let user = try admin.column("id")
      let content = (1...100).map { "Paragraph \($0) keeps this long locution readable inside its own scrollport." }.joined(separator: "\n\n")
      _ = try TestAdmin.query("""
        INSERT INTO locutions (id, locutable_type, locutable_id, author_id, content, created_at)
        VALUES ('\(locution)', 'lexicographic_madrigal', '\(word.madrigalID.lowercased())', '\(user)', '\(content)', now());
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/madrigals/lexicographic/\(word.madrigalID)")
        let body = page.locator("#locution-\(locution.uppercased()) .locution-body")
        try await expect(body).toContainText("Paragraph 100")
        // No cap (user, 2026-10-12): the locution grows to its content, the
        // page the one scrollport, so nothing nested fights it for the wheel.
        #expect(try await body.evaluate("""
          el => {
            const style = getComputedStyle(el);
            return style.maxHeight === 'none' && el.scrollHeight <= el.clientHeight && el.clientHeight > 512;
          }
          """).bool == true, "The body is as tall as its words, with no scrollport of its own")
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      remove()
      try await admin.remove(after: error)
    }
    remove()
    try await admin.remove()
  }
}
