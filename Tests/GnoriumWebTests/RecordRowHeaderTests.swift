import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A record row whose value wraps keeps its controls on its FIRST line
/// (user, 2026-11-01): the accordion's controls (its chevron) stand as one
/// group one line high at the header's top, beside the number and the info
/// icon, never centered on the wrapped block.
@Suite("Record row header", .serialized)
struct RecordRowHeaderTests {
  struct Tops: Decodable {
    let lines: Double
    let number: Double
    let info: Double
    let chevron: Double
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWrappedHeadersControlsStandOnItsFirstLine(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(word.path)
        let row = page.locator(".record-row-view:has(.record-row-uuid)").first
        try await expect(row).toBeVisible()
        // A value long enough to wrap at every width.
        let tops = try await page.evaluate(
          """
          (() => {
            const row = document.querySelector('.record-row-view:has(.record-row-uuid)')
            const summary = row.querySelector('.accordion-summary')
            const title = summary.querySelector('.record-row-title')
            title.textContent = 'The London bookseller and publisher John Trundell, who printed the first quarto '
              + 'of Hamlet with Nicholas Ling in 1603, and whose shop stood at the sign of the Barbican.'
            const top = el => el.getBoundingClientRect().top
            return {
              lines: Math.round(title.getBoundingClientRect().height / parseFloat(getComputedStyle(title).lineHeight)),
              number: top(summary.querySelector('.record-row-number')),
              info: top(summary.querySelector('.record-row-uuid svg')),
              chevron: top(summary.querySelector('.accordion-expand-icon svg'))
            }
          })()
          """, as: Tops.self)
        #expect(tops.lines >= 2, "the value does not wrap: \(tops.lines) line")
        #expect(abs(tops.info - tops.number) < 1, "info icon \(tops.info) vs number \(tops.number)")
        #expect(abs(tops.chevron - tops.number) < 1, "chevron \(tops.chevron) vs number \(tops.number)")
        #expect(abs(tops.chevron - tops.info) < 1, "chevron \(tops.chevron) vs info icon \(tops.info)")
      }
    } catch {
      word.remove()
      try await admin.remove(after: error)
    }
    word.remove()
    try await admin.remove()
  }
}
