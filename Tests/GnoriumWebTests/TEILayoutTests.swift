import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A page read as the image sets it (user, 2026-09-27): every <lb/> a line
/// on a wide screen, never reflowed; each block's alignment and indent from
/// its rend; a page number and a running head set on one line a row, each
/// in its place; a right-aligned catchword at the right. On a phone the text
/// reflows: a block's lines run on as one paragraph, a break inside a word
/// joining it with no space. The page, from the Wikisource example the user
/// gave ("On the Goodness of the Supreme Being", 1756, p. 10), encoded as the
/// recognition now writes it.
@Suite("TEI layout", .serialized)
struct TEILayoutTests {
  static let tei = #"""
    <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt><title>t</title></titleStmt></fileDesc></teiHeader><text><body>
    <pb n="10" facs="https://example.org/iiif/web-tests/full/1300,/0/default.jpg"/>
    <fw type="pageNum" rend="align(left)">10</fw> <fw type="header" rend="align(center)">On the Goodness</fw>
    <lg><l rend="indent(1)"><s><w lemma="the" type="article">The</w> <w lemma="mighty" type="adjective">migh-<lb break="no"/>ty</w> <w lemma="power" type="noun">Power</w><lb/><w lemma="that" type="pronoun">that</w> <w lemma="form" type="verb">form'd</w> <w lemma="the" type="article">the</w> <w lemma="world" type="noun">world</w></s></l></lg>
    <fw type="catch" rend="align(right)">Here,</fw>
    </body></text></TEI>
    """#

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aPageIsSetAsTheImageSetsIt(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reading = try ScratchReading(owner: admin, tei: Self.tei)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(reading.path)
        let text = page.locator(".tei-page-text").first
        // The page number and the running head: one row, number at the start,
        // head in the middle.
        let row = text.locator(".tei-forme-row")
        try await expect(row).toHaveCount(1)
        try await expect(row.locator(".tei-forme-row-start .tei-line-forme-pageNumber")).toHaveText("10")
        try await expect(row.locator(".tei-forme-row-center .tei-line-forme-header")).toHaveText("On the Goodness")
        let number = try #require(try await row.locator(".tei-line-forme-pageNumber").boundingBox())
        let head = try #require(try await row.locator(".tei-line-forme-header").boundingBox())
        #expect(abs(number.y - head.y) < 4)
        #expect(number.x < head.x)
        // The catchword at the right.
        let catchword = text.locator(".tei-line-forme-catchword")
        try await expect(catchword).toHaveAttribute("data-rend", "align(right)")
        try await expect(catchword).toHaveCSS("text-align", "end")
        // The verse line's block, indented.
        let block = text.locator(".tei-block[data-rend='indent(1)']")
        try await expect(block).toHaveCount(1)
        let lines = block.locator(".tei-line")
        try await expect(lines).toHaveCount(3)
        let first = try #require(try await lines.nth(0).boundingBox())
        let second = try #require(try await lines.nth(1).boundingBox())
        switch layout {
        case .desktop:
          // One line to a line, as the image has them.
          try await expect(block).toHaveCSS("display", "flex")
          #expect(second.y > first.y + 4)
          try await expect(lines.nth(0)).toHaveText("The migh-")
          try await expect(lines.nth(1)).toHaveText("ty Power")
        case .phone:
          // Reflowed: the lines run on, the word broken inside joined.
          try await expect(block).toHaveCSS("display", "block")
          try await expect(lines.nth(0)).toHaveCSS("display", "inline")
          let flowed = try await block.innerText()
          #expect(flowed.contains("The migh-ty Power that form'd the world"))
        }
        let blockBox = try #require(try await block.boundingBox())
        let textBox = try #require(try await text.boundingBox())
        #expect(first.x >= blockBox.x)
        #expect(blockBox.x == textBox.x)
        try await expect(block).toHaveCSS("padding-inline-start", "24px")
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      reading.remove()
      await admin.remove()
      throw error
    }
    reading.remove()
    await admin.remove()
  }
}
