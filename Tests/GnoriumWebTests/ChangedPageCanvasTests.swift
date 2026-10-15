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
    try await expect(viewer.locator(".canvas-view[data-active='true'] .canvas-tile-image").first).toBeAttached()
    let rect = """
      (() => { const r = document.querySelector(".artifact-view .canvas-view[data-active='true'] .canvas-tile-compositor")
        .getBoundingClientRect(); return [r.left, r.top, r.width, r.height].join(','); })()
      """
    func box() async throws -> [Double] {
      try await page.evaluate(rect, as: String.self).split(separator: ",").compactMap { Double($0) }
    }
    let fitted = try await box()
    _ = try await page.evaluate(
      """
      (() => {
        const vp = document.querySelector(".artifact-view .canvas-view[data-active='true'] .canvas-viewport");
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
          (() => { const t = document.querySelector(".artifact-view .canvas-view[data-active='true'] .canvas-tile-compositor")
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
        try await expect(viewer.locator(".canvas-view[data-active='true'] .canvas-tile-image").first).toBeAttached()
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
          [...document.querySelectorAll(".artifact-view .canvas-view[data-active='true'] .canvas-tile-image")]
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
}
