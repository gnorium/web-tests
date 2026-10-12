import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A canvas photographed as an opening holds two pages, a `<pb/>` each
/// (user, 2026-10-12): with Reflow off its rendered text mirrors the spread,
/// each page a column of its own, the columns equally wide, in reading
/// order—left then right, right then left for a right-to-left script—so the
/// text pane looks like the image beside it. With Reflow on the pages run
/// one after the other.
@Suite("Spread layout", .serialized)
struct SpreadLayoutTests {
  static func tei(verso: String, recto: String, lang: String) -> String {
    #"""
    <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt><title>t</title></titleStmt></fileDesc></teiHeader><text xml:lang="\#(lang)"><body>
    <pb n="A1 verso" facs="https://example.org/iiif/web-tests-spread/full/1300,/0/default.jpg"/>
    <p><s><w>\#(verso)</w></s><lb/></p>
    <pb n="A2 recto"/>
    <p><s><w>\#(recto)</w></s><lb/></p>
    </body></text></TEI>
    """#
  }

  @Test(arguments: [BrowserEngine.chrome], [false, true])
  func aSpreadIsSetAsItsTwoPages(engine: BrowserEngine, rightToLeft: Bool) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let verso = rightToLeft ? "שמאל" : "Leftward"
    let recto = rightToLeft ? "ימין" : "Rightward"
    let reading = try ScratchReading(
      owner: admin, tei: Self.tei(verso: verso, recto: recto, lang: rightToLeft ? "heb" : "eng"))
    do {
      try await withPage(engine, gnorium, viewport: .desktop) { page in
        try await page.openHydrated(reading.path)
        let text = page.locator(".tei-page-text[data-layer='rendering']").first
        let spread = text.locator(".tei-spread")
        try await expect(spread).toHaveCount(1)
        try await expect(spread).toHaveAttribute("dir", rightToLeft ? "rtl" : "ltr")
        let pages = spread.locator(".tei-spread-page")
        try await expect(pages).toHaveCount(2)
        // Each page headed by its own label, its text under it.
        try await expect(pages.nth(0).locator(".tei-line-mark")).toHaveText("A1 verso")
        try await expect(pages.nth(1).locator(".tei-line-mark")).toHaveText("A2 recto")
        try await expect(pages.nth(0)).toContainText(verso)
        try await expect(pages.nth(1)).toContainText(recto)
        // Reflow off: side by side, equally wide, the first page on the
        // reading's leading side.
        let first = try #require(try await pages.nth(0).boundingBox())
        let second = try #require(try await pages.nth(1).boundingBox())
        #expect(abs(first.y - second.y) < 0.5, "the pages are not side by side")
        #expect(abs(first.width - second.width) < 0.5, "the columns differ: \(first.width) vs \(second.width)")
        // Each page's label on its first line, the two level.
        let firstLabel = try #require(try await pages.nth(0).locator(".tei-line-mark").boundingBox())
        let secondLabel = try #require(try await pages.nth(1).locator(".tei-line-mark").boundingBox())
        #expect(abs(firstLabel.y - secondLabel.y) < 0.5, "the labels stand at \(firstLabel.y) and \(secondLabel.y)")
        if rightToLeft {
          #expect(first.x > second.x + second.width - 0.5, "the first page is not on the right")
        } else {
          #expect(second.x > first.x + first.width - 0.5, "the first page is not on the left")
        }
        // Reflow on: one page after the other.
        try await page.locator(".artifact-reflow-toggle button").first.click()
        try await expect(page.locator("[data-reflow='true']").first).toHaveCount(1)
        let above = try #require(try await pages.nth(0).boundingBox())
        let below = try #require(try await pages.nth(1).boundingBox())
        #expect(below.y >= above.y + above.height - 0.5, "the reflowed pages are not one after the other")
        try await page.locator(".artifact-reflow-toggle button").first.click()
      }
    } catch {
      reading.remove()
      try await admin.remove(after: error)
    }
    reading.remove()
    try await admin.remove()
  }
}
