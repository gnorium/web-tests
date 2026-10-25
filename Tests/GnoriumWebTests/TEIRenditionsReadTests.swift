import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A calibrated page as its base TEI sets it (gnorium-python
/// `calibration.base_tei`, user, 2026-10-25): every rendition its header
/// declares applied—a speech prefix's indent step, a centered run, a
/// running head's placement, a display line's letter-spacing, an explicit
/// vertical space—and the page REGULARIZED, read at its own size: never
/// drawn at the scan's whole width, though its frame declares the scans'
/// white around the text block (`margin:26.17em`, Hamlet Q1's). Shaped on
/// dev's Hamlet p. 14.
@Suite("TEI renditions read", .serialized)
struct TEIRenditionsReadTests {
  static let tei = #"""
    <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt><title>t</title></titleStmt></fileDesc><encodingDesc><tagsDecl><rendition xml:id="text-block" scheme="css" selector="text">font-size:85.59px;inline-size:26.50em;block-size:47.89em;margin:26.17em;max-inline-size:80.10em</rendition><rendition xml:id="size-6" scheme="css">font-size:1rem</rendition><rendition xml:id="leading-6" scheme="css">line-height:1.25rem</rendition><rendition xml:id="indent-1" scheme="css">text-indent:1.5rem</rendition><rendition xml:id="align-center-1" scheme="css">margin-inline-start:2em</rendition><rendition xml:id="fw-header" scheme="css">text-align:center</rendition><rendition xml:id="ls-0123456789-L9" scheme="css">letter-spacing:0.25em</rendition></tagsDecl></encodingDesc></teiHeader><text><body>
    <pb n="p. 14" facs="https://example.org/iiif/web-tests/full/1300,/0/default.jpg"/>
    <lb/><fw rendition="#fw-header" type="header">The Tragedye of Hamlet</fw>
    <ab rendition="#size-6 #leading-6"><lb/>Thou canst not then be false to any one,</ab>
    <ab rendition="#size-6 #leading-6 #indent-1"><lb/>Cor. What ist Ofelia he hath saide to you?</ab>
    <ab rendition="#size-6 #leading-6 #align-center-1" rend="align(center)"><lb/>Enter the Ghost.</ab>
    <space dim="vertical" quantity="2" unit="em"/>
    <ab rendition="#size-6 #leading-6 #ls-0123456789-L9"><lb/>FINIS</ab>
    </body></text></TEI>
    """#

  @Test(arguments: [BrowserEngine.chrome])
  func everyRenditionIsAppliedAndThePageReadAtItsSize(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reading = try ScratchReading(owner: admin, tei: Self.tei)
    do {
      try await withPage(engine, gnorium, viewport: .desktop) { page in
        try await page.openHydrated(reading.path)
        let text = page.locator(".tei-page-text").first
        let blocks = text.locator(".tei-block")
        try await expect(blocks).toHaveCount(4)
        // The running head in its role's placement: centered.
        try await expect(text.locator(".tei-line-forme-header")).toHaveCSS("text-align", "center")
        // The speech prefix's line indented by its step, 1.5 of the body's 16.
        let flush = try #require(try await blocks.nth(0).locator(".tei-line").first.boundingBox())
        try await expect(blocks.nth(1).locator(".tei-line").first).toHaveCSS("text-indent", "24px")
        let prefix = try #require(
          try await blocks.nth(1).locator(".tei-line").first.evaluate(
            "e => { const r = document.createRange(); r.selectNodeContents(e); return String(r.getClientRects()[0].left) }"
          ).string)
        #expect(abs((Double(prefix) ?? 0) - flush.x - 24) < 2, "the indented line starts 24 in")
        // The centered run: centered, its centering step's offset applied.
        try await expect(blocks.nth(2)).toHaveCSS("text-align", "center")
        try await expect(blocks.nth(2)).toHaveCSS("margin-inline-start", "32px")
        // The display line letter-spaced.
        try await expect(blocks.nth(3)).toHaveCSS("letter-spacing", "4px")
        // The explicit vertical space, 2em of the body.
        try await expect(text.locator(".tei-space")).toHaveCSS("height", "32px")
        // Regularized: the page's inset is the pane's own 16, never the
        // scan's 26.17em of white, and its type at the body's 16, drawn at
        // its own size (no zoom out to the scan's extent).
        try await expect(text).toHaveCSS("padding-top", "16px")
        try await expect(blocks.nth(0).locator(".tei-line").first).toHaveCSS("font-size", "16px")
        let drawn = try #require(
          try await text.evaluate("e => String(e.getBoundingClientRect().width / e.offsetWidth)").string)
        #expect(abs((Double(drawn) ?? 0) - 1) < 0.01, "the page is drawn at its own size")
      }
    } catch {
      reading.remove()
      try await admin.remove(after: error)
    }
    reading.remove()
    try await admin.remove()
  }
}
