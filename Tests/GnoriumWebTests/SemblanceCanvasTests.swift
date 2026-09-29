import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A testament's reader holds one semblance per page, each a canvas, in its
/// viewer's canvas slot (user, 2026-09-28): only the page on screen is shown
/// and only its canvas holds tiles; a canvas paged away lets go of them, and
/// its transcript pages with it. The manifest is a data URL, so no IIIF
/// server is asked for anything but the images, which need not load.
///
/// The page images are off until the reader asks for them (user,
/// 2026-09-29): the transcript takes the whole width and no image is
/// fetched; the header's Semblance switch (a left chevron) shows them, and the choice holds
/// across the reader's pages and the site's navigation for the browser
/// session (sessionStorage), and is off again in a new one.
@Suite("Semblance canvas", .serialized)
struct SemblanceCanvasTests {
  static let services = (1...3).map { "/web-tests-iiif/semblance-\($0)" }

  static let tei = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt><title>t</title></titleStmt></fileDesc></teiHeader><text><body>
    \(services.enumerated().map { #"<pb n="\#($0.offset + 1)" facs="\#($0.element)/full/1300,/0/default.jpg"/><p>Page \#($0.offset + 1).</p>"# }.joined(separator: "\n"))
    </body></text></TEI>
    """

  /// A IIIF v3 manifest of the three pages, as a data URL.
  static var manifestURL: String {
    let canvases = services.enumerated().map { index, service in
      #"{"type":"Canvas","width":1000,"height":1400,"label":{"none":["p\#(index + 1)"]},"items":[{"items":[{"body":{"id":"\#(service)/full/max/0/default.jpg","service":[{"id":"\#(service)"}]}}]}]}"#
    }
    let manifest = #"{"type":"Manifest","label":{"none":["Web tests"]},"items":[\#(canvases.joined(separator: ","))]}"#
    return "data:application/json,"
      + (manifest.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? manifest)
  }

  /// Per canvas: whether it is shown, and how many tile images it holds.
  struct Canvas: Decodable { let service: String; let shown: Bool; let tiles: Int }

  static let canvasesScript = """
    (viewer) => JSON.stringify([...viewer.querySelectorAll('.semblance-view')].map(s => ({
      service: s.dataset.serviceId,
      shown: getComputedStyle(s).display !== 'none',
      tiles: s.querySelectorAll('.canvas-view-tile-image').length,
    })))
    """

  /// The image requests made so far for the fixture's pages.
  static let imageRequestsScript = """
    performance.getEntriesByType('resource').filter(e => e.name.includes('/web-tests-iiif/')).length
    """

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func pageImagesAreOffUntilAskedForAndHoldForTheSession(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reading = try ScratchReading(owner: admin, tei: Self.tei)
    _ = try TestAdmin.query(
      """
      UPDATE bibliographic_evidences SET source_url = '\(Self.manifestURL)' WHERE title = '\(reading.work.title)';
      """)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(reading.path)
        let viewer = page.locator(".artifact-view").first
        try await expect(viewer).toHaveAttribute("data-artifact-hydrated", "true")
        try await expect(viewer.locator("#artifact-page-total")).toHaveText("3")
        let toggle = viewer.locator(".artifact-canvas-toggle button")
        let object = viewer.locator(".artifact-object")

        // The header is one row: the find bar, closed, takes no room.
        try await expect(viewer.locator(".artifact-header-bar")).toBeHidden()
        let header = try #require(try await viewer.locator(".artifact-header").boundingBox())
        let pager = try #require(try await viewer.locator(".artifact-page-nav").boundingBox())
        #expect(header.height < pager.height + 20, "the header holds more than its one row")
        // Find is the search icon alone.
        let find = viewer.locator(".testament-find-button")
        try await expect(find).toHaveAccessibleName("Find in this testament")
        try await expect(find).toHaveText("")

        // Off: the transcript alone, the whole width, and no image asked for.
        // The switch is the left chevron alone, named "Semblance".
        try await expect(toggle).toHaveAccessibleName("Semblance")
        try await expect(viewer.locator(".artifact-canvas-toggle .toggle-button-label")).toHaveCount(0)
        try await expect(toggle.locator("svg.previous-icon-view")).toHaveCount(1)
        try await expect(toggle).toHaveAttribute("aria-pressed", "false")
        try await expect(viewer).toHaveAttribute("data-canvas-shown", "false")
        try await expect(object).toBeHidden()
        let container = try #require(try await viewer.locator(".artifact-viewer-container").boundingBox())
        let transcript = try #require(try await viewer.locator(".artifact-transcript").boundingBox())
        #expect(abs(transcript.width - container.width) < 2, "the transcript takes the whole width")
        try await viewer.locator(".pagination-next").first.click()
        try await expect(viewer.locator(".artifact-transcript .tei-transcript[data-active='true']"))
          .toHaveAttribute("data-service-id", Self.services[1])
        #expect(try await page.evaluate(Self.imageRequestsScript).double == 0, "an image was fetched while off")

        // On: the page on screen's canvas, beside the transcript.
        try await toggle.click()
        try await expect(toggle).toHaveAttribute("aria-pressed", "true")
        try await expect(object).toBeVisible()
        try await expect(viewer.locator(".semblance-view[data-active='true'] .canvas-view-tile-image").first)
          .toHaveCount(1)
        try await expect(viewer.locator(".semblance-view[data-active='true']"))
          .toHaveAttribute("data-service-id", Self.services[1])

        // Across the reader's pages.
        try await viewer.locator(".pagination-next").first.click()
        try await expect(toggle).toHaveAttribute("aria-pressed", "true")
        try await expect(viewer.locator(".semblance-view[data-active='true']"))
          .toHaveAttribute("data-service-id", Self.services[2])
        try await expect(viewer.locator(".semblance-view[data-active='true'] .canvas-view-tile-image").first)
          .toHaveCount(1)

        // Across navigation in the session.
        try await page.openHydrated(reading.path)
        let again = page.locator(".artifact-view").first
        try await expect(again).toHaveAttribute("data-artifact-hydrated", "true")
        try await expect(again.locator(".artifact-canvas-toggle button")).toHaveAttribute("aria-pressed", "true")
        try await expect(again.locator(".artifact-object")).toBeVisible()
        try await expect(again.locator(".semblance-view[data-active='true'] .canvas-view-tile-image").first)
          .toHaveCount(1)
        try await page.expectNoHorizontalOverflow()
      }
      // A new session starts off, fetching nothing.
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(reading.path)
        let viewer = page.locator(".artifact-view").first
        try await expect(viewer).toHaveAttribute("data-artifact-hydrated", "true")
        try await expect(viewer.locator("#artifact-page-total")).toHaveText("3")
        try await expect(viewer.locator(".artifact-canvas-toggle button")).toHaveAttribute("aria-pressed", "false")
        try await expect(viewer.locator(".artifact-object")).toBeHidden()
        #expect(try await page.evaluate(Self.imageRequestsScript).double == 0, "an image was fetched while off")
      }
    } catch {
      reading.remove()
      try await admin.remove(after: error)
    }
    reading.remove()
    try await admin.remove()
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func onlyThePageOnScreenReadsItsImage(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reading = try ScratchReading(owner: admin, tei: Self.tei)
    _ = try TestAdmin.query(
      """
      UPDATE bibliographic_evidences SET source_url = '\(Self.manifestURL)' WHERE title = '\(reading.work.title)';
      """)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(reading.path)
        let viewer = page.locator(".artifact-view").first
        try await expect(viewer).toHaveAttribute("data-artifact-hydrated", "true")
        try await expect(viewer.locator(".semblance-view")).toHaveCount(3)
        try await expect(viewer.locator("#artifact-page-total")).toHaveText("3")
        // The page images, off by default, turned on.
        try await viewer.locator(".artifact-canvas-toggle button").click()

        func canvases() async throws -> [Canvas] {
          let json = try await viewer.evaluate(Self.canvasesScript).string ?? "[]"
          return try JSONDecoder().decode([Canvas].self, from: Data(json.utf8))
        }
        func expectShown(_ index: Int) async throws {
          // The backdrop is drawn once the image service's format is probed.
          try await expect(viewer.locator(".semblance-view[data-active='true'] .canvas-view-tile-image").first)
            .toHaveCount(1)
          let read = try await canvases()
          #expect(read.map(\.shown) == (0..<3).map { $0 == index }, "only page \(index + 1) is shown")
          #expect(read[index].tiles > 0, "the page on screen holds no tiles")
          for (other, canvas) in read.enumerated() where other != index {
            #expect(canvas.tiles == 0, "page \(other + 1), off screen, holds tiles")
          }
          try await expect(
            viewer.locator(".artifact-transcript .tei-transcript[data-active='true']")
          ).toHaveAttribute("data-service-id", Self.services[index])
        }

        try await expectShown(0)
        try await viewer.locator(".pagination-next").first.click()
        try await expectShown(1)
        try await viewer.locator(".pagination-next").first.click()
        try await expectShown(2)
        try await viewer.locator(".pagination-prev").first.click()
        try await expectShown(1)
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      reading.remove()
      try await admin.remove(after: error)
    }
    reading.remove()
    try await admin.remove()
  }
}
