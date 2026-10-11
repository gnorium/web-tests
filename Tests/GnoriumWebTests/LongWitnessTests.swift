import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A long book reads by what is shown, never by its length (user,
/// 2026-10-11): the reader draws the page on screen and the pages either
/// side, fetching each as it is turned to; the Evidence roster is one
/// continuous list drawing only the rows in view; ticks are the items',
/// kept whether their rows are drawn or not, and post as roster positions
/// in ranges.
@Suite("Long witness", .serialized)
struct LongWitnessTests {
  static let pages = 300

  /// A madrigal of `pages` blank pages but one, the 299th, whose text a
  /// search finds: the blank ones unexplicated, so each may be ticked.
  static func tei() -> String {
    let tei = "<TEI><text><body>"
      + (1...pages).map {
        "<pb n=\"\($0)\" facs=\"https://web-tests.invalid/iiif/p\($0)/full/max/0/default.jpg\"/>"
          + ($0 == 299 ? "<p>A needle.</p>" : "")
      }.joined()
      + "</body></text></TEI>"
    return String(decoding: try! JSONSerialization.data(withJSONObject: ["teiXml": tei]), as: UTF8.self)
      .replacingOccurrences(of: "'", with: "''")
  }

  @Test(arguments: [BrowserEngine.chrome])
  func aLongMadrigalDrawsWhatIsShown(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch: ScratchCommit
    do { scratch = try ScratchCommit(owner: admin) } catch { try await admin.remove(after: error) }
    do {
      _ = try TestAdmin.query(
        "UPDATE bibliographic_madrigals SET proposed_content_json = '\(Self.tei())' WHERE id = '\(scratch.madrigalID)'")
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated(scratch.madrigalPath + "?resemblance=150")
        let viewer = page.locator(".madrigal-object .artifact-view")
        try await expect(viewer.locator("#artifact-page-total")).toHaveText("\(Self.pages)")
        // The page on screen, and the four either side fetched ahead.
        try await expect(viewer.locator(".artifact-markup .tei-page[data-active='true']"))
          .toHaveAttribute("data-page-index", "150")
        try await expect(viewer.locator(".artifact-markup .tei-page"), timeout: .seconds(10)).toHaveCount(9)
        // Turned, the next page is shown, the one past the window fetched
        // and the far one let go.
        try await viewer.locator(".pagination-next").first.click()
        try await expect(viewer.locator(".artifact-markup .tei-page[data-active='true']"))
          .toHaveAttribute("data-page-index", "151")
        try await expect(viewer.locator(".artifact-markup .tei-page[data-page-index='155']")).toHaveCount(1)
        try await expect(viewer.locator(".artifact-markup .tei-page[data-page-index='146']")).toHaveCount(0)

        // The roster follows, and draws only rows around what is in view.
        let roster = page.locator("#madrigal-resemblances").first
        try await expect(roster.locator(".roster-row-selected")).toHaveAttribute("data-position", "151")
        let drawn = try await roster.locator(".roster-row").count()
        #expect(drawn < 80, "the roster drew \(drawn) rows")

        // A tick is the item's, out of view or in it.
        let ticked = page.locator("#commit-form input[name='ticked']")
        try await roster.locator(".roster-row[data-position='151'] .checkbox-input").check()
        try await expect(ticked).toHaveAttribute("value", "151")
        try await roster.locator(".roster-row[data-position='152'] .checkbox-input").check()
        try await expect(ticked).toHaveAttribute("value", "151-152")
        // The list scrolled to its start: row 0 drawn and ticked, row 152 let go.
        _ = try await page.evaluate("""
          (() => { const list = document.querySelector('#madrigal-resemblances .roster-options-list');
            list.querySelector('.roster-row').scrollIntoView(); window.scrollTo(0, 0);
            let s = list.parentElement; while (s) { s.scrollTop = 0; s = s.parentElement; } return true })()
          """, as: Bool.self)
        try await roster.locator(".roster-row[data-position='0'] .checkbox-input").check()
        try await expect(ticked).toHaveAttribute("value", "0,151-152")
        try await expect(roster.locator(".roster-row[data-position='152']")).toHaveCount(0)
        // Back to the selected row: its tick stands.
        _ = try await roster.locator(".roster-row-selected").evaluate("(el) => { el.scrollIntoView({ block: 'center' }); return true }")
        try await expect(roster.locator(".roster-row[data-position='152'] .checkbox-input")).toBeChecked()

        // Search filters the items, not the rows drawn.
        let search = roster.locator(".roster-search-input .search-input")
        try await search.fill("299")
        try await expect(roster.locator(".roster-row")).toHaveCount(1)
        try await expect(roster.locator(".roster-row")).toHaveAttribute("data-position", "298")
        try await search.fill("")

        // Find searches the whole book on the server: its pages listed, a
        // page found turned to.
        try await viewer.locator(".testament-find-button button").click()
        try await viewer.locator(".testament-find-input input").fill("needle")
        let result = viewer.locator(".testament-find-result")
        try await expect(result.first, timeout: .seconds(10)).toHaveAttribute("data-page-index", "298")
        try await result.first.click()
        try await expect(viewer.locator(".artifact-markup .tei-page[data-active='true']"), timeout: .seconds(10))
          .toHaveAttribute("data-page-index", "298")
        try await viewer.locator(".testament-find-button button").click()

        // Commit posts the ranges.
        #expect(try await page.evaluate(CommitTests.interceptScript, as: Bool.self))
        try await page.locator(".commit-trigger").click()
        let posted = try #require(try await CommitTests.posted(page))
        #expect(posted.ticked == "0,151-152")
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
