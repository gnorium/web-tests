import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A page changed at its source (user, 2026-10-11): the reader's image panel
/// shows the archived copy of the image the nocturne was sent—one plain image,
/// not IIIF tiles—and it zooms and pans exactly as the live canvas does. The
/// witness's pages served on this machine (`FixtureServer.threePageManifest`,
/// 800 × 1100), its archived copy beside them. Chrome, desktop.
@Suite("Changed page canvas", .serialized)
struct ChangedPageCanvasTests {
  /// The same wheel zoom and drag on the canvas on screen, as what they did
  /// to the image: its scale and where it moved, each to a tenth of a pixel.
  static func zoomAndPan(_ page: Page) async throws -> String {
    let viewer = page.locator(".artifact-view").first
    try await expect(viewer).toHaveAttribute("data-artifact-hydrated", "true")
    if try await viewer.getAttribute("data-canvas-shown") != "true" {
      try await viewer.locator(".artifact-canvas-toggle button").click()
    }
    try await expect(viewer).toHaveAttribute("data-canvas-shown", "true")
    try await expect(viewer.locator(".image-view[data-active='true'] .image-tile-image").first).toBeAttached()
    let rect = """
      (() => { const r = document.querySelector(".artifact-view .image-view[data-active='true'] .image-tile-compositor")
        .getBoundingClientRect(); return [r.left, r.top, r.width, r.height].join(','); })()
      """
    func box() async throws -> [Double] {
      try await page.evaluate(rect, as: String.self).split(separator: ",").compactMap { Double($0) }
    }
    let fitted = try await box()
    _ = try await page.evaluate(
      """
      (() => {
        const vp = document.querySelector(".artifact-view .image-view[data-active='true'] .image-viewport");
        const r = vp.getBoundingClientRect();
        for (let i = 0; i < 8; i++) vp.dispatchEvent(new WheelEvent('wheel', { deltaY: -40, bubbles: true,
          cancelable: true, clientX: r.left + r.width / 3, clientY: r.top + r.height / 3 }));
        return true;
      })()
      """, as: Bool.self)
    try await Task.sleep(for: .milliseconds(200))
    let zoomed = try await box()
    let center = (x: zoomed[0] + zoomed[2] / 2, y: zoomed[1] + zoomed[3] / 2)
    try await page.mouse.move(x: center.x, y: center.y)
    try await page.mouse.down(x: center.x, y: center.y)
    for step in 1...6 {
      try await page.mouse.move(x: center.x + Double(step) * 20, y: center.y + Double(step) * 12)
    }
    try await page.mouse.up(x: center.x + 120, y: center.y + 72)
    try await Task.sleep(for: .milliseconds(200))
    let panned = try await box()
    func f(_ v: Double) -> String { String(format: "%.1f", v) }
    return [
      f(zoomed[2] / fitted[2]), f(zoomed[0] - fitted[0]), f(zoomed[1] - fitted[1]),
      f(panned[0] - zoomed[0]), f(panned[1] - zoomed[1]), f(panned[2] - zoomed[2]),
    ].joined(separator: " ")
  }

  @Test(arguments: [BrowserEngine.chrome])
  func theArchivedCopyZoomsAndPansAsTheLiveCanvas(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let base = fixture.baseURL
    fixture.serve(
      .init(
        contentType: "image/svg+xml",
        body: Data(
          #"<svg xmlns="http://www.w3.org/2000/svg" width="800" height="1100"><rect width="800" height="1100" fill="ivory"/><text x="80" y="100">Archived copy</text></svg>"#
            .utf8)),
      at: "/web/20261011000000id_/page-1.jpg")
    let source = base + "/manifest.json"
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor, sourceURL: source)
    func unstage() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM testament_page_changes WHERE source_url = '\(source)';
        DELETE FROM wayback_saves WHERE url = '\(base)/page-1/full/max/0/default.jpg';
        COMMIT;
        """)
    }
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        // The live canvas first, its tiles from the image service.
        try await page.openHydrated(commit.madrigalPath)
        let live = try await Self.zoomAndPan(page)
        let scale = """
          (() => { const t = document.querySelector(".artifact-view .image-view[data-active='true'] .image-tile-compositor")
            .getAttribute('transform'); return Number(/scale\\(([\\d.]+)/.exec(t)[1]); })()
          """
        let liveZoom = try await page.evaluate(scale, as: Double.self)

        // Page 1 changed at its source, its full-size copy archived.
        _ = try TestAdmin.query(
          """
          BEGIN;
          INSERT INTO testament_page_changes (source_url, canvas_id, change, before, after, service_id)
            VALUES ('\(source)', '\(base)/canvas/1', 'image', 'a', 'b', '\(base)/page-1');
          INSERT INTO wayback_saves (url, sha256, kind, status, archive_url, archived_at)
            VALUES ('\(base)/page-1/full/max/0/default.jpg', 'a', 'full', 'saved',
              '\(base)/web/20261011000000/page-1.jpg', now());
          COMMIT;
          """)
        // Opened again, the archived copy follows the zoom the session
        // keeps from the live canvas.
        try await page.openHydrated(commit.madrigalPath)
        // The images shown as the session left them.
        let viewer = page.locator(".artifact-view").first
        try await expect(viewer).toHaveAttribute("data-canvas-shown", "true")
        try await expect(viewer.locator(".image-view[data-active='true'] .image-tile-image").first).toBeAttached()
        let keptZoom = try await page.evaluate(scale, as: Double.self)
        #expect(abs(keptZoom - liveZoom) < 1e-6, "the archived copy opens at the live canvas's zoom: \(keptZoom), \(liveZoom)")
        // Each opened at its fit: the session keeps the image's zoom
        // (artifact-core `ViewerZoom.imageKey`, so a reload opens where the
        // reader left it), which would open the archived copy zoomed in
        // already, as the live canvas was left.
        _ = try await page.evaluate("(() => { sessionStorage.removeItem('gnorium:artifact-zoom:image'); return 1 })()")
        try await page.openHydrated(commit.madrigalPath)
        let archived = try await Self.zoomAndPan(page)
        let after = try await page.evaluate(
          """
          [...document.querySelectorAll(".artifact-view .image-view[data-active='true'] .image-tile-image")]
            .map((i) => i.getAttribute('href')).join(' ')
          """, as: String.self)
        #expect(after.contains("/web/20261011000000id_/page-1.jpg"), "The archived copy is shown: \(after)")
        #expect(!after.contains("/page-1/"), "No IIIF tiles over the archived copy: \(after)")
        #expect(live == archived, "Zoom and pan: live \(live), archived \(archived)")
      }
      unstage()
      commit.remove()
      try await contributor.remove()
    } catch {
      unstage()
      commit.remove()
      try await contributor.remove(after: error)
    }
  }

  /// The images switch and the panes as the reader on screen shows them:
  /// `data-canvas-shown`; the switch disabled (`disabled`, `aria-disabled`)
  /// and pressed; its other attributes and its text (its label and
  /// tooltip); the image pane put away; the canvases on screen; the
  /// person's choice as the session keeps it; the text pane's width.
  struct Panes: Decodable, CustomStringConvertible {
    let shown: String
    let disabled: Bool
    let pressed: Bool
    let label: String
    let hidden: Bool
    let canvases: Int
    let kept: String?
    let width: Double

    var description: String {
      "shown \(shown), disabled \(disabled), pressed \(pressed), image pane hidden \(hidden), canvases \(canvases), "
        + "kept \(kept ?? "—"), width \(width), label \(label)"
    }
  }

  static func panes(_ page: Page) async throws -> Panes {
    try await page.evaluate(
      """
      (() => {
        const r = document.querySelector('.artifact-view'), wrap = r.querySelector('.artifact-canvas-toggle');
        const b = wrap.querySelector('button');
        return {
          shown: r.dataset.canvasShown,
          disabled: b.disabled && b.getAttribute('aria-disabled') === 'true',
          pressed: wrap.getAttribute('aria-pressed') === 'true' && b.getAttribute('aria-pressed') === 'true',
          label: [...b.attributes].filter((a) => !['disabled', 'aria-disabled', 'aria-pressed'].includes(a.name))
            .map((a) => a.name + '=' + a.value).join(' ') + '|' + b.textContent.trim(),
          hidden: getComputedStyle(r.querySelector('.artifact-object')).display === 'none',
          canvases: r.querySelectorAll('.image-view[data-active=true]').length,
          kept: sessionStorage.getItem('gnorium:artifact-page-images'),
          width: r.querySelector('.artifact-markup').getBoundingClientRect().width,
        };
      })()
      """, as: Panes.self)
  }

  /// The reader's own requests for addresses under `prefix` (one starting
  /// "/" on Gnorium's origin): its canvases' SVG images (`initiatorType`
  /// "image"—the notice's thumbnail of the image now is an HTML image, shown
  /// on purpose) and the images it fetches ahead (`loader.js`'s
  /// `__artifactPreloadImgs`).
  static func readerRequests(_ page: Page, _ prefix: String) async throws -> Int {
    try await page.evaluate(
      """
      (() => {
        const p = new URL('\(prefix)', location.href).href;
        return performance.getEntriesByType('resource').filter((e) => e.initiatorType === 'image' && e.name.startsWith(p)).length
          + (window.__artifactPreloadImgs || []).filter((i) => i.__url.startsWith(p)).length;
      })()
      """, as: Int.self)
  }

  /// The reader turned to the page at `index` (0-based), as a roster turns it.
  static func turn(_ page: Page, to index: Int) async throws {
    _ = try await page.evaluate(
      """
      (() => { document.querySelector('.artifact-view').dispatchEvent(new CustomEvent('artifact-show-canvas',
        { detail: '\(index)' })); return true })()
      """, as: Bool.self)
  }

  /// Whether `condition` holds within `seconds`.
  static func eventually(_ seconds: Double = 10, _ condition: () async throws -> Bool) async throws -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
      if try await condition() { return true }
      try await Task.sleep(for: .milliseconds(100))
    }
    return try await condition()
  }

  /// A changed page shows what its session was sent, never its image now
  /// (user, 2026-10-17): the archived copy; where it does not load at view
  /// time (the archive answers 404), or isn't archived at all
  /// (`"blank":true`), no image—Gnorium keeps no copy of a source's image:
  /// the text alone, the whole width, as with the images off, the images
  /// switch disabled (its label and tooltip kept) and reading off while
  /// that page is on screen. The person's choice is kept: a page with an
  /// image shows it as the switch was left. And the reader asks the live
  /// service for nothing of that page—no tile, no image fetched ahead from
  /// the pages beside it. Its source-change notice says what the image
  /// shows: the image that was sent, as archived, else none—updated in place
  /// where the archived copy fails to load. The witness's pages served on
  /// this machine (`FixtureServer.threePageManifest`). Chrome, desktop.
  @Test(arguments: [BrowserEngine.chrome])
  func aChangedPageShowsWhatWasSentOrItsTextAloneNeverItsImageNow(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let base = fixture.baseURL
    let source = base + "/manifest.json"
    let sent = "\(base)/page-1/full/!1300,1300/0/default.jpg"
    let full = "\(base)/page-1/full/max/0/default.jpg"
    // Archived; not served until the fixture is told to serve it (404).
    let archived = "\(base)/web/20261011000000id_/page-1.jpg"
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor, sourceURL: source)
    func unstage() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM testament_page_changes WHERE source_url = '\(source)';
        DELETE FROM wayback_saves WHERE url LIKE '\(base)/%';
        DELETE FROM sent_page_images WHERE source_url = '\(source)';
        COMMIT;
        """)
    }
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        let viewer = page.locator(".artifact-view").first
        let toggle = viewer.locator(".artifact-canvas-toggle button")
        let shownImage = viewer.locator(".image-view[data-active='true'] .image-tile-image[data-loaded='true']").first
        // Page 1's notice: its last sentence, what the image shows.
        let said = page.locator(".source-change-notice[data-service='\(base)/page-1'] .source-change-notice-reader").first
        // The live canvas first, the images switched on (the person's
        // choice, kept for the session): its tiles are the reader's own SVG
        // images, what is counted below.
        try await page.openHydrated(commit.madrigalPath)
        try await expect(viewer).toHaveAttribute("data-artifact-hydrated", "true")
        if try await viewer.getAttribute("data-canvas-shown") != "true" { try await toggle.click() }
        try await expect(viewer).toHaveAttribute("data-canvas-shown", "true")
        try await expect(shownImage).toBeAttached()
        #expect(try await Self.readerRequests(page, "\(base)/page-1/") > 0, "the live canvas's tiles are counted")

        // Page 1 changed at its source, its full-size copy archived—not
        // served: the text alone, the switch disabled, reading off.
        _ = try TestAdmin.query(
          """
          BEGIN;
          INSERT INTO testament_page_changes (source_url, canvas_id, change, before, after, service_id)
            VALUES ('\(source)', '\(base)/canvas/1', 'image', 'a', 'b', '\(base)/page-1');
          INSERT INTO sent_page_images (image_url, source_url, canvas_id, canvas_index, width, height, source_sha256, downloaded_at)
            VALUES ('\(sent)', '\(source)', '\(base)/canvas/1', 0, 800, 1100, 'a', now() - interval '1 hour');
          INSERT INTO wayback_saves (url, sha256, kind, status, archive_url, archived_at)
            VALUES ('\(full)', 'a', 'full', 'saved', '\(base)/web/20261011000000/page-1.jpg', now());
          COMMIT;
          """)
        try await page.openHydrated(commit.madrigalPath)
        try await expect(toggle).toHaveAttribute("aria-disabled", "true")
        // The notice no longer says the archived image is shown: it could
        // not be loaded.
        try await expect(said).toHaveText(
          "The archived image that was sent could not be loaded, so no image is shown.")
        try await Task.sleep(for: .milliseconds(600))
        let alone = try await Self.panes(page)
        #expect(
          alone.shown == "false" && alone.disabled && !alone.pressed && alone.hidden && alone.canvases == 0
            && alone.kept == "true",
          "the archived copy failed: the text alone, the switch disabled and off, the choice kept: \(alone)")
        #expect(try await Self.readerRequests(page, archived) > 0, "the archived copy asked for")
        #expect(try await Self.readerRequests(page, "/mission-control/sent-images/") == 0, "never a copy of our own")
        #expect(try await Self.readerRequests(page, "\(base)/page-1/") == 0, "never the image now")

        // A page with an image: shown as the switch was left, the switch
        // enabled, its label kept; the pages beside it fetched ahead, never
        // page 1's image now.
        try await Self.turn(page, to: 1)
        try await expect(viewer).toHaveAttribute("data-canvas-shown", "true")
        try await expect(shownImage).toBeAttached()
        let restored = try await Self.panes(page)
        #expect(
          !restored.disabled && restored.pressed && !restored.hidden && restored.canvases == 1 && restored.kept == "true",
          "an image again, as the switch was left: \(restored)")
        #expect(restored.label == alone.label, "the switch's label and tooltip kept")
        let ahead = try await Self.eventually { try await Self.readerRequests(page, "\(base)/page-3/") > 0 }
        #expect(ahead, "the page beside it fetched ahead")
        #expect(try await Self.readerRequests(page, "\(base)/page-1/") == 0, "never page 1's image now")
        // Page 1 with the images switched off by the person, then with them
        // on: the same text pane, the whole width.
        try await toggle.click()
        try await expect(viewer).toHaveAttribute("data-canvas-shown", "false")
        try await Self.turn(page, to: 0)
        try await Task.sleep(for: .milliseconds(600))
        let off = try await Self.panes(page)
        #expect(off.shown == "false" && off.disabled && off.kept == "false", "images off, by the person: \(off)")
        try await Self.turn(page, to: 1)
        try await expect(toggle).toBeEnabled()
        try await toggle.click()
        try await expect(viewer).toHaveAttribute("data-canvas-shown", "true")
        try await Self.turn(page, to: 0)
        try await expect(viewer).toHaveAttribute("data-canvas-shown", "false")
        try await Task.sleep(for: .milliseconds(600))
        let again = try await Self.panes(page)
        #expect(
          again.disabled && !again.pressed && again.hidden && again.canvases == 0 && again.kept == "true",
          "back on page 1: the text alone again, the choice kept: \(again)")
        #expect(abs(again.width - off.width) < 1, "the text the whole width, as with the images off: \(again), \(off)")

        // The archived copy served (saved again, should the view's recheck
        // have set it waiting): it is shown, and the notice says so.
        fixture.serve(
          .init(
            contentType: "image/svg+xml",
            body: Data(
              #"<svg xmlns="http://www.w3.org/2000/svg" width="800" height="1100"><rect width="800" height="1100" fill="ivory"/><text x="80" y="100">Archived copy</text></svg>"#
                .utf8)),
          at: "/web/20261011000000id_/page-1.jpg")
        _ = try TestAdmin.query("UPDATE wayback_saves SET status = 'saved' WHERE url = '\(full)'")
        try await page.openHydrated(commit.madrigalPath)
        try await expect(shownImage).toHaveAttribute("href", archived)
        try await expect(said).toHaveText("The image shown is the one that was sent, as archived.")
        #expect(try await Self.readerRequests(page, "\(base)/page-1/") == 0, "never the image now")

        // Not archived (`"blank":true`): the text alone at once, no copy
        // asked for, never the image now; page 2 as the switch was left.
        _ = try TestAdmin.query("DELETE FROM wayback_saves WHERE url = '\(full)'")
        try await page.openHydrated(commit.madrigalPath)
        try await expect(toggle).toHaveAttribute("aria-disabled", "true")
        try await expect(said).toHaveText("The image that was sent isn’t archived, so no image is shown.")
        try await Task.sleep(for: .milliseconds(600))
        let blank = try await Self.panes(page)
        #expect(
          blank.shown == "false" && blank.disabled && !blank.pressed && blank.hidden && blank.canvases == 0
            && blank.kept == "true",
          "not archived: the text alone: \(blank)")
        #expect(try await Self.readerRequests(page, archived) == 0, "no copy to ask for")
        #expect(try await Self.readerRequests(page, "\(base)/page-1/") == 0, "never the image now")
        try await Self.turn(page, to: 1)
        try await expect(viewer).toHaveAttribute("data-canvas-shown", "true")
        let imaged = try await Self.panes(page)
        #expect(!imaged.disabled && imaged.pressed && !imaged.hidden, "enabled on a page with an image: \(imaged)")
      }
      unstage()
      commit.remove()
      try await contributor.remove()
    } catch {
      unstage()
      commit.remove()
      try await contributor.remove(after: error)
    }
  }
}
