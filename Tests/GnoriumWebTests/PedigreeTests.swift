import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A Pedigree can run to tens of thousands of rows (a large work's line):
/// its rows are capped at `size256` tall, as a thinking block is
/// (`capHeight`, HeightCap.swift), and scroll inside, so the page does not
/// grow with it. A throwaway admin owns a scratch line of 60 overtures, made
/// by SQL and removed after.
@Suite("Pedigree", .serialized)
struct PedigreeTests {
  struct Box: Decodable {
    let maxHeight: String
    let overflowY: String
    let clientHeight: Double
    let scrollHeight: Double
    let scrolled: Double
    let groups: Int
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aLongPedigreeScrollsInsideItsCap(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let line = try ScratchLine(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(line.path)
        try await page.locator("#pedigree-rows > .accordion-summary").click()
        try await expect(page.locator("#pedigree-rows")).toHaveAttribute("data-open-finished", "true")
        let box = try await page.evaluate(
          """
          (() => {
            const rows = document.querySelector('#pedigree-rows .pedigree-rows')
            const style = getComputedStyle(rows)
            rows.scrollTop = 100
            return {
              maxHeight: style.maxHeight,
              overflowY: style.overflowY,
              clientHeight: rows.clientHeight,
              scrollHeight: rows.scrollHeight,
              scrolled: rows.scrollTop,
              groups: rows.querySelectorAll('.pedigree-group').length,
            }
          })()
          """, as: Box.self)
        // Instance, overture, and an antiphon and a notation per link.
        #expect(box.groups == 122)
        #expect(box.maxHeight == "256px")
        #expect(box.overflowY == "auto")
        #expect(box.clientHeight <= 256)
        #expect(box.scrollHeight > box.clientHeight * 4, "the rows are not taller than their cap")
        #expect(box.scrolled == 100, "the rows do not scroll inside")
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      line.remove()
      try await admin.remove(after: error)
    }
    line.remove()
    try await admin.remove()
  }
}
