import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A halftone's zones, edited in its Revise (user, 2026-10-24): the reader
/// already edits a page's TEI in raw and files it through Suggest; the zone
/// panel drags, splits, merges and sets aside zones on the page's image by rewriting that same
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

  /// The stage's zone `id`, and its box on the page as the code writes it.
  static func zone(_ page: Page, _ id: String) -> Locator { page.locator(".zone-edit-zone[data-zone='\(id)']") }

  /// A drag from `from` to `to`, both fractions of the layer (0...1).
  static func drag(_ page: Page, from: (Double, Double), to: (Double, Double)) async throws {
    let box = try await page.evaluate(
      "(() => { const r = document.querySelector('.zone-edit-layer').getBoundingClientRect(); return [r.left, r.top, r.width, r.height] })()",
      as: [Double].self)
    func point(_ f: (Double, Double)) -> (Double, Double) { (box[0] + box[2] * f.0, box[1] + box[3] * f.1) }
    let a = point(from), b = point(to)
    try await page.mouse.down(x: a.0, y: a.1)
    for step in 1...6 {
      let t = Double(step) / 6
      try await page.mouse.move(x: a.0 + (b.0 - a.0) * t, y: a.1 + (b.1 - a.1) * t)
    }
    try await page.mouse.up(x: b.0, y: b.1)
  }

  @Test(arguments: [BrowserEngine.chrome])
  func zonesAreDraggedSplitMergedAndSetAsideOnThePage(engine: BrowserEngine) async throws {
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

        // The zones are drawn over the page, one box each.
        try await expect(page.locator(".zone-edit-zone")).toHaveCount(2)

        // Click selects; drag moves: the code's box changes, nothing else.
        try await Self.zone(page, "z-L2").click()
        try await expect(Self.zone(page, "z-L2")).toHaveAttribute("data-selected", "true")
        try await Self.drag(page, from: (0.5, 0.17), to: (0.5, 0.27))
        var code = try await page.evaluate(Self.code, as: String.self)
        #expect(!code.contains(#"xml:id="z-L2" ulx="100" uly="150" lrx="900" lry="190""#), "Moved: \(code)")
        #expect(code.contains(#"xml:id="z-L1" ulx="100" uly="100" lrx="900" lry="140""#), "The other is as it was: \(code)")
        try await expect(page.locator(".tei-page[data-active='true']")).toHaveAttribute("data-edited", "true")

        // A corner resizes.
        let before = code
        try await Self.drag(page, from: (0.9, 0.27), to: (0.8, 0.3))
        code = try await page.evaluate(Self.code, as: String.self)
        #expect(code != before, "Resized: \(code)")

        // Split: select one, press Split, click inside it.
        try await Self.zone(page, "z-L1").click()
        try await page.locator("[data-zone-edit='split']").click()
        try await expect(page.locator(".zone-edit-done")).toBeVisible()
        try await Self.zone(page, "z-L1").click()
        code = try await page.evaluate(Self.code, as: String.self)
        #expect(code.contains(#"xml:id="z-L1-b""#), "A new zone on the right: \(code)")
        #expect(code.contains(#"<lb facs="#z-L1-b"/>"#), "It has its line: \(code)")

        // Merge needs two: refused with one, done with two.
        try await page.locator("[data-zone-edit='merge']").click()
        try await expect(page.locator(".zone-edit-failed")).toBeVisible()
        try await Self.zone(page, "z-L1").click()
        try await page.keyboard.down("Shift")
        try await Self.zone(page, "z-L1-b").click()
        try await page.keyboard.up("Shift")
        try await page.locator("[data-zone-edit='merge']").click()
        code = try await page.evaluate(Self.code, as: String.self)
        #expect(!code.contains("z-L1-b"), "One zone again: \(code)")
        #expect(code.contains("the quick brown fox jumps"), "Its words are whole: \(code)")

        // Set aside: the selected zone and its line leave the page.
        try await Self.zone(page, "z-L2").click()
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
