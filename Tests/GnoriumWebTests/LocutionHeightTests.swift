import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Locution height", .serialized)
struct LocutionHeightTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func longLocutionScrollsInside512Pixels(engine: BrowserEngine, layout: Layout) async throws {
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
        #expect(try await body.evaluate("""
          el => {
            const style = getComputedStyle(el);
            const before = window.scrollY;
            el.scrollTop = el.scrollHeight;
            return style.maxHeight === '512px' && style.overflowY === 'auto'
              && el.clientHeight === 512 && el.scrollHeight > 512
              && el.scrollTop > 0 && window.scrollY === before;
          }
          """).bool == true, "The body is a 512px scrollport and scrolling it does not scroll the page")
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
