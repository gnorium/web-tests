import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A halftone's zones, edited in its Revise (user, 2026-10-24): the reader
/// already edits a page's TEI in raw and files it through Suggest; the zone
/// panel moves, splits, merges and sets aside zones by rewriting that same
/// code, so the page is marked edited as typing would mark it, and an edit
/// that cannot be made says so in red and changes nothing. Chrome, desktop.
@Suite("Zone edit", .serialized)
struct ZoneEditTests {
  static let page = """
    <TEI><facsimile><surface ulx="0" uly="0" lrx="1000" lry="1000">\
    <zone xml:id="z-L1" ulx="100" uly="100" lrx="900" lry="140"/>\
    <zone xml:id="z-L2" ulx="100" uly="150" lrx="900" lry="190"/>\
    </surface></facsimile><text><body><pb n="1"/><ab>\
    <lb facs="#z-L1"/>the quick brown fox jumps\
    <lb facs="#z-L2"/>over the lazy dog\
    </ab></body></text></TEI>
    """

  /// The code of the page on screen.
  static let code = "document.querySelector('.tei-page[data-active=\"true\"] .code-editor-input').value"

  /// The code of the page on screen set to `page`, as typing it would.
  static func typing(_ page: String) -> String {
    let literal = String(decoding: try! JSONSerialization.data(withJSONObject: [page]), as: UTF8.self)
    return """
      (() => {
        const area = document.querySelector('.tei-page[data-active="true"] .code-editor-input')
        area.value = \(literal)[0]
        area.dispatchEvent(new Event('input', { bubbles: true }))
        return area.value.length
      })()
      """
  }

  static func fields(_ page: Page, zone: String, _ more: [String: String] = [:]) async throws {
    try await page.locator("#zone-edit-zone").fill(zone)
    for (id, value) in more { try await page.locator("#zone-edit-\(id)").fill(value) }
  }

  @Test(arguments: [BrowserEngine.chrome])
  func zonesAreMovedSplitMergedAndSetAsideInTheCode(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch: ScratchOverture
    do { scratch = try ScratchOverture(owner: admin, sealed: true, calibrated: 4) }
    catch { try await admin.remove(after: error) }
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated("\(scratch.halftonePath)/revise")
        let viewer = page.locator(".revise-bibliographic-object .artifact-view")
        try await expect(viewer).toHaveAttribute("data-artifact-hydrated", "true")
        try await expect(page.locator(".zone-edit-view")).toHaveCount(1)
        _ = try await page.evaluate(Self.typing(Self.page), as: Int.self)

        // The zones on the page.
        try await page.locator("[data-zone-edit='list']").click()
        try await expect(page.locator(".zone-edit-done .zone-edit-message-text")).toHaveText("Zones on this page: z-L1, z-L2.")

        // Move: its four edges, nothing else.
        try await Self.fields(page, zone: "z-L2", ["left": "120", "top": "160", "right": "880", "bottom": "200"])
        try await page.locator("[data-zone-edit='move']").click()
        var code = try await page.evaluate(Self.code, as: String.self)
        #expect(code.contains(#"xml:id="z-L2" ulx="120" uly="160" lrx="880" lry="200""#), "Moved: \(code)")
        #expect(code.contains(#"xml:id="z-L1" ulx="100" uly="100" lrx="900" lry="140""#), "The other is as it was: \(code)")
        // The reader took it as an edit of the page.
        try await expect(page.locator(".tei-page[data-active='true']")).toHaveAttribute("data-edited", "true")

        // A move that cannot be made says why and changes nothing.
        try await Self.fields(page, zone: "z-L2", ["left": "500", "right": "400"])
        try await page.locator("[data-zone-edit='move']").click()
        try await expect(page.locator(".zone-edit-failed")).toBeVisible()
        try await expect(page.locator(".zone-edit-failed .zone-edit-message-text"))
          .toContainText("right edge must be right of its left edge")
        #expect(try await page.evaluate(Self.code, as: String.self) == code, "A refused edit changes nothing")

        // Split: two zones, the line's words divided by width.
        try await Self.fields(page, zone: "z-L1", ["split": "500"])
        try await page.locator("[data-zone-edit='split']").click()
        code = try await page.evaluate(Self.code, as: String.self)
        #expect(code.contains(#"xml:id="z-L1" ulx="100" uly="100" lrx="500" lry="140""#), "The left keeps the id: \(code)")
        #expect(code.contains(#"xml:id="z-L1-b" ulx="500" uly="100" lrx="900" lry="140""#), "The right is new: \(code)")
        #expect(code.contains(#"<lb facs="#z-L1-b"/>"#), "It has its line: \(code)")
        try await expect(page.locator(".zone-edit-done")).toBeVisible()

        // Merge it back: one zone, the text joined.
        try await Self.fields(page, zone: "z-L1", ["merge": "z-L1-b"])
        try await page.locator("[data-zone-edit='merge']").click()
        code = try await page.evaluate(Self.code, as: String.self)
        #expect(code.contains(#"xml:id="z-L1" ulx="100" uly="100" lrx="900" lry="140""#), "One zone again: \(code)")
        #expect(!code.contains("z-L1-b"), "The second is gone: \(code)")
        #expect(code.contains("the quick brown fox jumps"), "Its words are whole: \(code)")

        // Set aside: its zone and its line leave the page.
        try await Self.fields(page, zone: "z-L2")
        try await page.locator("[data-zone-edit='aside']").click()
        code = try await page.evaluate(Self.code, as: String.self)
        #expect(!code.contains("z-L2"), "Zone and line are gone: \(code)")
        #expect(!code.contains("over the lazy dog"), "Its text left with its line: \(code)")
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
