import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A region's coordinates seen on the canvas while its markup is read or
/// edited in Raw (user, 2026-10-10): with the caret in a `bbox="x y w h"`
/// (the 0–1000 space over the whole image) on the Revise page, or the
/// pointer on an element whose `facs="#…"` names a zone in a read-only Raw,
/// the canvas pane draws the rectangle over the image, scaled to it; it
/// follows the value as it is typed and goes when the caret or the pointer
/// leaves. The witness's pages served on this machine
/// (`FixtureServer.threePageManifest`, 800 × 1100). Chrome, desktop.
@Suite("Markup regions", .serialized)
struct MarkupRegionTests {
  /// Where the canvas on screen draws its region, against where the box
  /// (0–1000) falls on the image as displayed, with its dimmed backdrop and
  /// the 0–1000 grid laid over the image (its 500 line at the image's
  /// midpoint): "none" when there is no region and no grid, "ok" within a
  /// pixel, else what is wrong.
  static let regionScript = """
    (box) => {
      const canvas = document.querySelector(".artifact-view .canvas-view[data-active='true']");
      const shown = (el) => !!el && !el.hidden && getComputedStyle(el).display !== 'none';
      const region = canvas && canvas.querySelector('.canvas-region');
      const dim = canvas && canvas.querySelector('.canvas-region-dim');
      const grid = canvas && canvas.querySelector('.canvas-grid');
      if (!shown(region)) return shown(grid) || shown(dim) ? 'grid or dim without a region' : 'none';
      if (!shown(dim)) return 'no dim';
      if (!shown(grid)) return 'no grid';
      const image = canvas.querySelector('.canvas-tile-compositor').getBoundingClientRect();
      const g = grid.getBoundingClientRect();
      const midpoint = g.left + g.width * 500 / 1000;
      if ([g.left - image.left, g.top - image.top, g.width - image.width, g.height - image.height,
        midpoint - (image.left + image.width / 2)].some((d) => Math.abs(d) > 1)) return 'grid off the image';
      if (!(grid.dataset.levels || '').split(' ').includes('100')) return 'no 100 lines: ' + grid.dataset.levels;
      const r = region.getBoundingClientRect();
      const want = [image.left + box[0] / 1000 * image.width, image.top + box[1] / 1000 * image.height,
        box[2] / 1000 * image.width, box[3] / 1000 * image.height];
      const got = [r.left, r.top, r.width, r.height];
      return want.every((w, i) => Math.abs(w - got[i]) <= 1) ? 'ok' : JSON.stringify({ want, got });
    }
    """

  /// A point of the image (0–1000) on screen.
  static func screenPoint(_ page: Page, _ x: Double, _ y: Double) async throws -> (x: Double, y: Double) {
    let at = (try await page.evaluate(
      """
      (() => {
        const image = document.querySelector(".artifact-view .canvas-view[data-active='true'] .canvas-tile-compositor")
          .getBoundingClientRect();
        return (image.left + \(x) / 1000 * image.width) + ',' + (image.top + \(y) / 1000 * image.height);
      })()
      """, as: String.self)).split(separator: ",").compactMap { Double($0) }
    return (at[0], at[1])
  }

  /// The editor's text.
  static let editorText =
    "document.querySelector(\".tei-page[data-active='true'] .tei-page-edit .code-code\").textContent"

  static func expectEditor(_ page: Page, contains needle: String, _ comment: Comment) async throws {
    var last = ""
    for _ in 0..<40 {
      last = try await page.evaluate(editorText, as: String.self)
      if last.contains(needle) { return }
      try await Task.sleep(for: .milliseconds(50))
    }
    Issue.record("\(comment.rawValue): \(last)")
  }

  /// The caret put in the editor's code, just after the first occurrence
  /// of `needle` (or `offset` bytes into it).
  static func caretScript(_ needle: String, offset: Int? = nil) -> String {
    """
    (() => {
      const code = document.querySelector(".tei-page[data-active='true'] .tei-page-edit .code-code");
      const walker = document.createTreeWalker(code, NodeFilter.SHOW_TEXT);
      code.focus();
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        const at = node.data.indexOf(\(String(reflecting: needle)));
        if (at < 0) continue;
        getSelection().collapse(node, at + \(offset.map(String.init) ?? "\(needle.utf16.count)"));
        return true;
      }
      return false;
    })()
    """
  }

  static func region(_ page: Page, _ box: [Int]) async throws -> String {
    try await page.evaluate("(\(regionScript))([\(box.map(String.init).joined(separator: ","))])", as: String.self)
  }

  /// Polls for a region state, the drawing following the caret a frame
  /// or two behind it.
  static func expectRegion(_ page: Page, _ box: [Int], _ want: String, _ comment: Comment) async throws {
    var last = ""
    for _ in 0..<40 {
      last = try await region(page, box)
      if last == want { return }
      try await Task.sleep(for: .milliseconds(50))
    }
    Issue.record("\(comment.rawValue): \(last)")
  }

  static func showCanvas(_ page: Page) async throws {
    let viewer = page.locator(".artifact-view").first
    try await expect(viewer).toHaveAttribute("data-artifact-hydrated", "true")
    if try await viewer.getAttribute("data-canvas-shown") != "true" {
      try await viewer.locator(".artifact-canvas-toggle button").click()
    }
    try await expect(viewer).toHaveAttribute("data-canvas-shown", "true")
    try await expect(viewer.locator(".canvas-view[data-active='true'] .canvas-tile-image").first).toBeAttached()
    try await page.locator(".artifact-raw-toggle").first.click()
  }

  @Test(arguments: [BrowserEngine.chrome])
  func theCaretInABboxDrawsItsRegionOnTheCanvas(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor, sourceURL: fixture.baseURL + "/manifest.json")
    do {
      _ = try TestAdmin.query(
        #"""
        UPDATE bibliographic_madrigals SET
          metadata_json = (metadata_json::jsonb || '{"provider":"folger_shakespeare_library"}'::jsonb)::text,
          proposed_content_json = '{"teiXml":"<TEI><text><body><pb n=\"1\" facs=\"\#(fixture.baseURL)/page-1/full/1300,/0/default.jpg\"/><p>Before</p><figure type=\"illustration\" bbox=\"120 340 760 380\"><figDesc>Woodcut.</figDesc></figure><p>After</p></body></text></TEI>"}'
        WHERE id = '\#(commit.madrigalID)'
        """#)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(commit.madrigalPath)/revise")
        try await Self.showCanvas(page)
        try await expect(page.locator(".tei-page-edit .code-code").first).toBeVisible()
        try await Self.expectRegion(page, [120, 340, 760, 380], "none", "No region before the caret is in one")

        // Inside the value: its rectangle, scaled to the image.
        #expect(try await page.evaluate(Self.caretScript("bbox=\"120 3"), as: Bool.self))
        try await Self.expectRegion(page, [120, 340, 760, 380], "ok", "The caret in the bbox draws it")

        // Typed over, it follows the value; a partial value draws nothing.
        #expect(try await page.evaluate(Self.caretScript("340 760", offset: 4), as: Bool.self))
        for _ in 0..<3 { try await page.keyboard.press("Delete") }
        try await Self.expectRegion(page, [120, 340, 760, 380], "none", "A partial bbox draws nothing")
        try await page.keyboard.insertText("500")
        try await Self.expectRegion(page, [120, 340, 500, 380], "ok", "The edited bbox redraws it")

        // In the figure's content, the figure's region; outside it, none.
        #expect(try await page.evaluate(Self.caretScript("Woodcut"), as: Bool.self))
        try await Self.expectRegion(page, [120, 340, 500, 380], "ok", "On the figure's content")
        #expect(try await page.evaluate(Self.caretScript("After"), as: Bool.self))
        try await Self.expectRegion(page, [120, 340, 500, 380], "none", "The caret left the figure")

        // Edited on the canvas: its bottom-right handle dragged to (800,
        // 900) writes the whole numbers into the bbox, the box following;
        // one undo takes the drag back whole.
        #expect(try await page.evaluate(Self.caretScript("bbox=\"120 3"), as: Bool.self))
        try await Self.expectRegion(page, [120, 340, 500, 380], "ok", "The caret back in the bbox")
        try await expect(page.locator(".canvas-view[data-active='true'] .canvas-crop-handle")).toHaveCount(4)
        let corner = try await Self.screenPoint(page, 620, 720)
        let target = try await Self.screenPoint(page, 800, 900)
        try await page.mouse.move(x: corner.x, y: corner.y)
        try await page.mouse.down(x: corner.x, y: corner.y)
        for step in 1...5 {
          let t = Double(step) / 5
          try await page.mouse.move(x: corner.x + (target.x - corner.x) * t, y: corner.y + (target.y - corner.y) * t)
        }
        try await Self.expectEditor(page, contains: "bbox=\"120 340 680 560\"", "Written live as it is dragged")
        try await page.mouse.up(x: target.x, y: target.y)
        try await Self.expectEditor(page, contains: "bbox=\"120 340 680 560\"", "The drag's end written")
        try await Self.expectRegion(page, [120, 340, 680, 560], "ok", "The box follows the drag")
        let posted = try await page.evaluate(
          "document.querySelector(\".tei-page[data-active='true'] .tei-page-edit textarea\").value",
          as: String.self)
        #expect(posted.contains("bbox=\"120 340 680 560\""), "The form posts the dragged value: \(posted)")
        // The editor's own undo (Chrome under automation runs no Cmd+Z).
        _ = try await page.evaluate("document.execCommand('undo')", as: Bool.self)
        try await Self.expectEditor(page, contains: "bbox=\"120 340 500 380\"", "One undo takes the drag back")

        // The arrows, the caret in the value: 1, with Shift 10; Alt resizes.
        #expect(try await page.evaluate(Self.caretScript("bbox=\"120 3"), as: Bool.self))
        try await page.keyboard.press("ArrowRight")
        try await Self.expectEditor(page, contains: "bbox=\"121 340 500 380\"", "ArrowRight nudges x by 1")
        try await page.keyboard.press("Shift+ArrowRight")
        try await Self.expectEditor(page, contains: "bbox=\"131 340 500 380\"", "Shift+ArrowRight nudges x by 10")
        try await page.keyboard.press("Alt+ArrowDown")
        try await Self.expectEditor(page, contains: "bbox=\"131 340 500 381\"", "Alt+ArrowDown grows h by 1")
        try await Self.expectRegion(page, [131, 340, 500, 381], "ok", "The box follows the keys")
      }
    } catch {
      commit.remove()
      try await contributor.remove(after: error)
    }
    commit.remove()
    try await contributor.remove()
  }

  @Test(arguments: [BrowserEngine.chrome])
  func thePointerOnAZonesElementInRawDrawsItsRegion(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor, sourceURL: fixture.baseURL + "/manifest.json")
    do {
      _ = try TestAdmin.query(
        #"""
        UPDATE bibliographic_madrigals SET
          metadata_json = (metadata_json::jsonb || '{"provider":"folger_shakespeare_library"}'::jsonb)::text,
          proposed_content_json = '{"teiXml":"<TEI><facsimile><surface n=\"1\" ulx=\"0\" uly=\"0\" lrx=\"1000\" lry=\"1000\"><zone xml:id=\"p1-z1\" ulx=\"100\" uly=\"200\" lrx=\"400\" lry=\"600\"/></surface></facsimile><text><body><pb n=\"1\" facs=\"\#(fixture.baseURL)/page-1/full/1300,/0/default.jpg\"/><p>Before</p><figure type=\"illustration\" facs=\"#p1-z1\"><figDesc>Woodcut.</figDesc></figure><p>After</p></body></text></TEI>"}'
        WHERE id = '\#(commit.madrigalID)'
        """#)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated(commit.madrigalPath)
        try await Self.showCanvas(page)
        let code = page.locator(".tei-page[data-active='true'] .tei-page-raw .code-code").first
        try await expect(code).toBeVisible()
        _ = try await code.evaluate("e => { e.scrollIntoView({block: 'center'}); return true }")
        // The middle of a word of the code, on screen.
        func point(_ needle: String) async throws -> (x: Double, y: Double) {
          let at = (try await code.evaluate(
            """
            (code) => {
              const walker = document.createTreeWalker(code, NodeFilter.SHOW_TEXT);
              for (let node = walker.nextNode(); node; node = walker.nextNode()) {
                const index = node.data.indexOf(\(String(reflecting: needle)));
                if (index < 0) continue;
                const range = document.createRange();
                range.setStart(node, index + 1);
                range.setEnd(node, index + 2);
                const r = range.getBoundingClientRect();
                return (r.left + r.width / 2) + ',' + (r.top + r.height / 2);
              }
              return '';
            }
            """
          ).string?.split(separator: ",") ?? []).compactMap { Double($0) }
          try #require(at.count == 2, "\(needle) is in the code")
          return (at[0], at[1])
        }
        let zone = [100, 200, 300, 400]
        try await Self.expectRegion(page, zone, "none", "No region before the pointer is on one")
        let figure = try await point("illustration")
        print("DEBUG", try await page.evaluate("(() => { const t = document.querySelector(\".tei-page[data-active='true']\"); const p = document.caretPositionFromPoint(\(figure.x), \(figure.y)); return JSON.stringify({zones: t.dataset.zones, node: p && p.offsetNode.textContent, off: p && p.offset, code: t.querySelector('.tei-page-raw .code-code').textContent.slice(0, 300)}) })()", as: String.self))
        try await page.mouse.move(x: figure.x, y: figure.y)
        try await Self.expectRegion(page, zone, "ok", "The pointer on the figure draws its zone")
        let after = try await point("After")
        try await page.mouse.move(x: after.x, y: after.y)
        try await Self.expectRegion(page, zone, "none", "The pointer left the figure")
        try await page.mouse.move(x: figure.x, y: figure.y)
        try await Self.expectRegion(page, zone, "ok", "Back on the figure")
        try await page.mouse.move(x: 2, y: 2)
        try await Self.expectRegion(page, zone, "none", "The pointer left the reader")

        // A selection in the facs keeps it on screen, the pointer elsewhere.
        _ = try await code.evaluate(
          """
          (code) => {
            const walker = document.createTreeWalker(code, NodeFilter.SHOW_TEXT);
            for (let node = walker.nextNode(); node; node = walker.nextNode()) {
              const at = node.data.indexOf('p1-z1');
              if (at >= 0) { getSelection().setBaseAndExtent(node, at, node, at + 2); return true; }
            }
            return false;
          }
          """)
        try await Self.expectRegion(page, zone, "ok", "A selection in the facs draws its zone")

        // The pointer's place on the image, in the 0–1000 space.
        // A whole screen pixel near (250, 600), and where it falls.
        let near = try await Self.screenPoint(page, 250, 600)
        let spot = (x: near.x.rounded(), y: near.y.rounded())
        let expected = try await page.evaluate(
          """
          (() => {
            const image = document.querySelector(".artifact-view .canvas-view[data-active='true'] .canvas-tile-compositor")
              .getBoundingClientRect();
            return Math.round((\(spot.x) - image.left) / image.width * 1000) + ', '
              + Math.round((\(spot.y) - image.top) / image.height * 1000);
          })()
          """, as: String.self)
        try await page.mouse.move(x: spot.x, y: spot.y)
        let readout = page.locator(".canvas-view[data-active='true'] .canvas-readout")
        try await expect(readout).toBeVisible()
        try await expect(readout).toHaveText(expected)

        // Finer levels as the image is enlarged: none of 1 at its fitted size;
        // zoomed in until 1 unit stands 4px apart, the 1s drawn.
        let grid = page.locator(".canvas-view[data-active='true'] .canvas-grid")
        let fitted = try await grid.getAttribute("data-levels") ?? ""
        #expect(!fitted.split(separator: " ").contains("1") && fitted.hasPrefix("100"), "Fitted levels: \(fitted)")
        _ = try await page.evaluate(
          """
          (() => {
            const vp = document.querySelector(".artifact-view .canvas-view[data-active='true'] .canvas-viewport");
            const r = vp.getBoundingClientRect();
            for (let i = 0; i < 60; i++) vp.dispatchEvent(new WheelEvent('wheel', { deltaY: -40, bubbles: true,
              cancelable: true, clientX: r.left + r.width / 2, clientY: r.top + r.height / 2 }));
            return true;
          })()
          """, as: Bool.self)
        let levels = try await page.evaluate(
          """
          (() => {
            const grid = document.querySelector(".artifact-view .canvas-view[data-active='true'] .canvas-grid");
            const image = document.querySelector(".artifact-view .canvas-view[data-active='true'] .canvas-tile-compositor")
              .getBoundingClientRect();
            return grid.dataset.levels + '|' + (Math.min(image.width, image.height) / 1000 >= 4);
          })()
          """, as: String.self)
        #expect(levels == "100 50 10 5 1|true", "Zoomed in, the 1-unit lines: \(levels)")
        // Fullscreen refits the image; the levels follow its spacing.
        try await page.locator("#artifact-fullscreen-btn").first.click()
        try await Task.sleep(for: .milliseconds(400))
        let full = try await page.evaluate(
          """
          (() => {
            const grid = document.querySelector(".artifact-view .canvas-view[data-active='true'] .canvas-grid");
            const image = document.querySelector(".artifact-view .canvas-view[data-active='true'] .canvas-tile-compositor")
              .getBoundingClientRect();
            const want = [100, 50, 10, 5, 1].filter((u) => Math.min(image.width, image.height) * u / 1000 >= 4);
            return grid.dataset.levels === want.join(' ') ? 'ok' : grid.dataset.levels + ' vs ' + want.join(' ');
          })()
          """, as: String.self)
        #expect(full == "ok", "Fullscreen levels: \(full)")
      }
    } catch {
      commit.remove()
      try await contributor.remove(after: error)
    }
    commit.remove()
    try await contributor.remove()
  }
}
