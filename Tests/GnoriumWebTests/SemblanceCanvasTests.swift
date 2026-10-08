import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A testament's reader holds one semblance per page, each a canvas, in its
/// viewer's canvas slot (user, 2026-09-28): only the page on screen is shown
/// and only its canvas holds tiles; a canvas paged away lets go of them, and
/// its transcript pages with it. The manifest and its pages' images are
/// served on this machine (`FixtureServer.threePageManifest`): the server
/// reads a source URL over https, or http to loopback for the tests, never a
/// data URL.
///
/// The page images are off until the reader asks for them (user,
/// 2026-09-29): the transcript takes the whole width and no image is
/// fetched; the header's Semblance switch (the image icon alone, distinct
/// from the pager's arrows, 2026-10-03) shows them, and the choice holds
/// across the reader's pages and the site's navigation for the browser
/// session (sessionStorage), and is off again in a new one.
@Suite("Semblance canvas", .serialized)
struct SemblanceCanvasTests {
  /// The fixture's three pages' image services.
  static func services(_ fixture: FixtureServer) -> [String] { (1...3).map { "\(fixture.baseURL)/page-\($0)" } }

  static func tei(_ fixture: FixtureServer) -> String {
    """
    <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt><title>t</title></titleStmt></fileDesc></teiHeader><text><body>
    \(services(fixture).enumerated().map { #"<pb n="\#($0.offset + 1)" facs="\#($0.element)/full/1300,/0/default.jpg"/><p>Page \#($0.offset + 1).</p>"# }.joined(separator: "\n"))
    </body></text></TEI>
    """
  }

  /// Per canvas: whether it is shown, and how many tile images it holds.
  struct Canvas: Decodable { let service: String; let shown: Bool; let tiles: Int }

  static let canvasesScript = """
    (viewer) => JSON.stringify([...viewer.querySelectorAll('.semblance-view')].map(s => ({
      service: s.dataset.serviceId,
      shown: getComputedStyle(s).display !== 'none',
      tiles: s.querySelectorAll('.canvas-tile-image').length,
    })))
    """

  /// The image requests made so far for the fixture's pages.
  static func imageRequestsScript(_ fixture: FixtureServer) -> String {
    "performance.getEntriesByType('resource').filter(e => e.name.startsWith('\(fixture.baseURL)/page-')).length"
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func pageImagesAreOffUntilAskedForAndHoldForTheSession(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let services = Self.services(fixture)
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reading = try ScratchReading(owner: admin, tei: Self.tei(fixture), sourceURL: fixture.baseURL + "/manifest.json")
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(reading.path)
        let viewer = page.locator(".artifact-view").first
        try await expect(viewer).toHaveAttribute("data-artifact-hydrated", "true")
        try await expect(viewer.locator("#artifact-page-total")).toHaveText("3")
        let toggle = viewer.locator(".artifact-canvas-toggle button")
        let object = viewer.locator(".artifact-object")

        // The header is one row, never wrapped (user, 2026-09-30): the find
        // bar, closed, takes no room, and a row too narrow for its controls
        // scrolls sideways, never the page.
        try await expect(viewer.locator(".artifact-header-bar")).toBeHidden()
        let header = try #require(try await viewer.locator(".artifact-header").boundingBox())
        let row = try #require(try await viewer.locator(".artifact-header-row").boundingBox())
        #expect(header.height < row.height + 2, "the header holds more than its one row")
        // The pager is in the footer, at every width, immediately before
        // fullscreen at the row's end (user, 2026-10-08): in the header it
        // pushed the row past a phone's width.
        try await expect(viewer.locator(".artifact-header .artifact-page-nav")).toHaveCount(0)
        let footerPager = try await viewer.evaluate(
          """
          (viewer) => { const footer = viewer.querySelector('.artifact-footer');
            const pager = footer.querySelector(':scope > .artifact-page-nav');
            const full = footer.querySelector(':scope > .artifact-fullscreen-button');
            const f = footer.getBoundingClientRect(), p = pager.getBoundingClientRect(),
              b = full.getBoundingClientRect();
            // One line, never wrapped: every part of the pager on one row.
            const tops = [...pager.children].map((c) => Math.round(c.getBoundingClientRect().top));
            return pager.nextElementSibling === full && tops.every((t) => t === tops[0])
              && Math.round(p.height) === 32
              && Math.round(f.height) === 41 && Math.abs(p.top + p.height / 2 - (b.top + b.height / 2)) < 1
              && p.right <= b.left && b.right <= f.right && footer.scrollWidth <= footer.clientWidth; }
          """).bool == true
        #expect(footerPager, "the pager sits in the footer, before fullscreen, and the footer fits")
        // The header row's controls fit without scrolling sideways.
        let rowFits = try await viewer.evaluate(
          "(viewer) => { const r = viewer.querySelector('.artifact-header-row'); return r.scrollWidth <= r.clientWidth; }"
        ).bool == true
        #expect(rowFits, "the header row needs more than its width")
        try await page.expectNoHorizontalOverflow()
        // Find is the search icon alone.
        // A toggle, as the semblance switch is: its button holds the name.
        let find = viewer.locator(".testament-find-button button")
        try await expect(find).toHaveAccessibleName("Find in this testament")
        try await expect(find).toHaveText("")
        // Find and the semblance switch are the pager's small chevrons' size,
        // 32, their icons' long edge the chevrons', 14 (icons are tight to
        // their glyph, 2026-10-01): one row of small controls in a 40 bar.
        let chevron = try #require(try await viewer.locator(".pagination-prev").first.boundingBox())
        let chevronIcon = try #require(try await viewer.locator(".pagination-prev svg").first.boundingBox())
        #expect(abs(chevron.height - 32) < 1, "the pager's chevrons are small, 32")
        #expect(abs(max(chevronIcon.width, chevronIcon.height) - 14) < 1, "the pager's chevrons are 14")
        #expect(abs(row.height - 40) < 1, "the header's row is 40")
        for (name, control, icon) in [
          ("Find", find, find.locator("svg")),
          ("Semblance", toggle, toggle.locator("svg")),
        ] {
          let box = try #require(try await control.boundingBox())
          let iconBox = try #require(try await icon.boundingBox())
          #expect(abs(box.width - chevron.width) < 1 && abs(box.height - chevron.height) < 1, "\(name) is not the pager's size")
          #expect(
            abs(max(iconBox.width, iconBox.height) - max(chevronIcon.width, chevronIcon.height)) < 1,
            "\(name)'s icon is not the chevrons' size")
        }

        // Off: the transcript alone, the whole width, and no image asked for.
        // The switch is the image icon alone, named "Semblance".
        try await expect(toggle).toHaveAccessibleName("Semblance")
        try await expect(viewer.locator(".artifact-canvas-toggle .toggle-button-label")).toHaveCount(0)
        try await expect(toggle.locator("svg.image-icon-view")).toHaveCount(1)
        try await expect(toggle).toHaveAttribute("aria-pressed", "false")
        try await expect(viewer).toHaveAttribute("data-canvas-shown", "false")
        try await expect(object).toBeHidden()
        let container = try #require(try await viewer.locator(".artifact-viewer-container").boundingBox())
        let transcript = try #require(try await viewer.locator(".artifact-transcript").boundingBox())
        #expect(abs(transcript.width - container.width) < 2, "the transcript takes the whole width")
        try await viewer.locator(".pagination-next").first.click()
        try await expect(viewer.locator(".artifact-transcript .tei-transcript[data-active='true']"))
          .toHaveAttribute("data-service-id", services[1])
        #expect(try await page.evaluate(Self.imageRequestsScript(fixture)).double == 0, "an image was fetched while off")

        // On: the page on screen's canvas, beside the transcript.
        try await toggle.click()
        try await expect(toggle).toHaveAttribute("aria-pressed", "true")
        try await expect(object).toBeVisible()
        try await expect(viewer.locator(".semblance-view[data-active='true'] .canvas-tile-image").first)
          .toHaveCount(1)
        try await expect(viewer.locator(".semblance-view[data-active='true']"))
          .toHaveAttribute("data-service-id", services[1])

        // Across the reader's pages.
        try await viewer.locator(".pagination-next").first.click()
        try await expect(toggle).toHaveAttribute("aria-pressed", "true")
        try await expect(viewer.locator(".semblance-view[data-active='true']"))
          .toHaveAttribute("data-service-id", services[2])
        try await expect(viewer.locator(".semblance-view[data-active='true'] .canvas-tile-image").first)
          .toHaveCount(1)

        // Across navigation in the session.
        try await page.openHydrated(reading.path)
        let again = page.locator(".artifact-view").first
        try await expect(again).toHaveAttribute("data-artifact-hydrated", "true")
        try await expect(again.locator(".artifact-canvas-toggle button")).toHaveAttribute("aria-pressed", "true")
        try await expect(again.locator(".artifact-object")).toBeVisible()
        try await expect(again.locator(".semblance-view[data-active='true'] .canvas-tile-image").first)
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
        #expect(try await page.evaluate(Self.imageRequestsScript(fixture)).double == 0, "an image was fetched while off")
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
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let services = Self.services(fixture)
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reading = try ScratchReading(owner: admin, tei: Self.tei(fixture), sourceURL: fixture.baseURL + "/manifest.json")
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
          try await expect(viewer.locator(".semblance-view[data-active='true'] .canvas-tile-image").first)
            .toHaveCount(1)
          let read = try await canvases()
          #expect(read.map(\.shown) == (0..<3).map { $0 == index }, "only page \(index + 1) is shown")
          #expect(read[index].tiles > 0, "the page on screen holds no tiles")
          for (other, canvas) in read.enumerated() where other != index {
            #expect(canvas.tiles == 0, "page \(other + 1), off screen, holds tiles")
          }
          try await expect(
            viewer.locator(".artifact-transcript .tei-transcript[data-active='true']")
          ).toHaveAttribute("data-service-id", services[index])
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
