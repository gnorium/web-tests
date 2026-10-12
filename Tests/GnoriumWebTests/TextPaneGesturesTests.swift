import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The text pane is handled as the image pane is (user, 2026-10-12): the
/// wheel zooms it about the pointer and never scrolls the page; a drag from
/// blank space pans it, a drag from its text selects it, and a click on a
/// word still opens its gloss. A throwaway admin owns a scratch testament with one long line,
/// wider than the pane, made by SQL and removed after.
@Suite("Text pane gestures", .serialized)
struct TextPaneGesturesTests {
  static let service = "https://example.org/iiif/webtests-gestures"
  static let tei = """
    <TEI><text><body><pb n="1" facs="\(service)/full/1300,/0/default.jpg"/>\
    <p><s>\((1...60).map { "<w>word\($0)</w>" }.joined(separator: " "))</s></p>\
    </body></text></TEI>
    """

  struct Pane: Decodable {
    let zoom: String?
    let left: Double
    let top: Double
    let selection: String
    let pageY: Double
  }

  static let state = """
    (() => { const m = document.querySelector('.artifact-markup'); const l = m.querySelector('.tei-page[data-active="true"] [data-layer="rendering"]');
      return { zoom: l.dataset.zoom || null, left: m.scrollLeft, top: m.scrollTop, selection: String(window.getSelection()), pageY: window.scrollY } })()
    """

  @Test(arguments: [BrowserEngine.chrome])
  func theTextPaneZoomsAndPansAsTheImageDoes(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    var testament: ScratchTestament?
    do {
      let scratch = try ScratchTestament(owner: admin, tei: Self.tei)
      testament = scratch
      try await withPage(engine, gnorium, viewport: .desktop) { page in
        try await page.openHydrated(scratch.reading.work.path)
        _ = try await page.evaluate(
          """
          (() => { sessionStorage.clear(); document.querySelector("[data-reader-url*='\(scratch.versionID)' i]").closest('.record-row')
            .querySelector(':scope > .accordion-details > .accordion-summary').click(); return true; })()
          """)
        let pane = page.locator(".artifact-markup").first
        try await expect(pane.locator(".tei-word").first).toHaveText("word1")
        _ = try await page.evaluate("(() => { document.querySelector('.artifact-markup').scrollIntoView({block: 'center'}); return 1 })()")
        try await Task.sleep(for: .milliseconds(400))
        let box = try #require(try await pane.boundingBox())
        let before = try await page.evaluate(Self.state, as: Pane.self)
        #expect(before.zoom == "1", "the text opens at its actual size")

        // A plain wheel zooms out, about the pointer, and the page stays put.
        _ = try await page.evaluate(
          """
          (() => { const m = document.querySelector('.artifact-markup'); const r = m.getBoundingClientRect();
            for (let i = 0; i < 3; i++) m.dispatchEvent(new WheelEvent('wheel', {deltaY: 40, clientX: r.x + r.width / 2, clientY: r.y + r.height / 2, bubbles: true, cancelable: true}));
            return 1 })()
          """)
        try await Task.sleep(for: .milliseconds(300))
        let zoomed = try await page.evaluate(Self.state, as: Pane.self)
        #expect(Double(zoomed.zoom ?? "1") ?? 1 < 1, "the wheel did not zoom the text: \(zoomed.zoom ?? "—")")
        #expect(zoomed.pageY == before.pageY, "the wheel scrolled the page")

        // Back at its actual size it overflows: a drag from the blank space
        // under the line pans it, and selects nothing.
        _ = try await page.evaluate("(() => { document.querySelector('.artifact-markup').dispatchEvent(new KeyboardEvent('keydown', {key: '0', bubbles: true})); return 1 })()")
        try await Task.sleep(for: .milliseconds(300))
        let start = try await page.evaluate(Self.state, as: Pane.self)
        // Between the line's foot and the pane's (or the window's) bottom.
        let lineBox = try #require(try await pane.locator(".tei-line").first.boundingBox())
        let viewportHeight = try await page.evaluate("innerHeight", as: Double.self)
        let blank = (lineBox.y + lineBox.height + min(box.y + box.height, viewportHeight)) / 2
        try await page.mouse.down(x: box.x + box.width * 3 / 4, y: blank)
        try await page.mouse.move(x: box.x + box.width / 2, y: blank)
        try await page.mouse.up(x: box.x + box.width / 4, y: blank)
        let panned = try await page.evaluate(Self.state, as: Pane.self)
        #expect(panned.left > start.left, "the drag did not pan the text: \(start.left) → \(panned.left)")
        #expect(panned.selection.isEmpty, "the drag selected text")
        try await expect(page.locator(".artifact-markup .gloss-sheet[data-state='open']")).toHaveCount(0)

        // A drag from the text selects it, and pans nothing.
        let line = lineBox.y + lineBox.height / 2
        try await page.mouse.down(x: box.x + box.width / 4, y: line)
        try await page.mouse.move(x: box.x + box.width / 2, y: line)
        try await page.mouse.up(x: box.x + box.width * 3 / 4, y: line)
        let selected = try await page.evaluate(Self.state, as: Pane.self)
        #expect(!selected.selection.isEmpty, "a drag from the text selected nothing")
        #expect(selected.left == panned.left, "a drag from the text panned it")

        // A click on a word still opens its gloss.
        _ = try await page.evaluate("(() => { window.getSelection().removeAllRanges(); return 1 })()")
        let word = pane.locator(".tei-word").filter(hasText: "word2").first
        try await word.click()
        try await expect(page.locator(".artifact-markup .gloss-sheet")).toHaveAttribute("data-state", "open")
        try await page.expectNoErrors()
      }
      testament?.remove()
      try await admin.remove()
    } catch {
      testament?.remove()
      try await admin.remove(after: error)
    }
  }
}
