import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A testament's reader holds one image per page in its
/// viewer's image slot (user, 2026-09-28): only the page on screen is shown
/// and only its image holds tiles; an image paged away lets go of them, and
/// its transcript pages with it. The manifest and its pages' images are
/// served on this machine (`FixtureServer.threePageManifest`): the server
/// reads a source URL over https, or http to loopback for the tests, never a
/// data URL.
///
/// The page images are off until the reader asks for them (user,
/// 2026-09-29): the transcript takes the whole width and no image is
/// fetched; the header's Image switch (the image icon alone, distinct
/// from the pager's arrows, 2026-10-03) shows them, and the choice holds
/// across the reader's pages and the site's navigation for the browser
/// session (sessionStorage), and is off again in a new one.
@Suite("Images", .serialized)
struct ImageTests {
  /// The fixture's three pages' image services.
  static func services(_ fixture: FixtureServer) -> [String] { (1...3).map { "\(fixture.baseURL)/page-\($0)" } }

  static func tei(_ fixture: FixtureServer) -> String {
    """
    <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt><title>t</title></titleStmt></fileDesc></teiHeader><text><body>
    \(services(fixture).enumerated().map { #"<pb n="\#($0.offset + 1)" facs="\#($0.element)/full/1300,/0/default.jpg"/><p>Page \#($0.offset + 1).</p>"# }.joined(separator: "\n"))
    </body></text></TEI>
    """
  }

  /// Per image: whether it is shown, and how many tile images it holds.
  struct Image: Decodable { let service: String; let shown: Bool; let tiles: Int }

  static let imagesScript = """
    (viewer) => JSON.stringify([...viewer.querySelectorAll('.artifact-object .canvas-view')].map(s => ({
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
            // One line, never wrapped: every part of the pager on one row,
            // and the whole footer one row (user, 2026-10-12)—on a phone
            // (below 480px) its controls one step down, 32, else 40.
            const tops = [...pager.children].map((c) => Math.round(c.getBoundingClientRect().top));
            const middle = (e) => { const r = e.getBoundingClientRect(); return r.top + r.height / 2; };
            const parts = [...footer.querySelectorAll(':scope > .artifact-footer-start > *'), pager, full];
            const control = window.innerWidth < 480 ? 32 : 40;
            return pager.nextElementSibling === full && tops.every((t) => t === tops[0])
              && parts.every((e) => Math.abs(middle(e) - middle(pager)) < 1)
              && Math.round(p.height) === control
              && Math.round(f.height) === control + 17 && Math.abs(p.top + p.height / 2 - (b.top + b.height / 2)) < 1
              && p.right <= b.left && b.right <= f.right && footer.scrollWidth <= footer.clientWidth; }
          """).bool == true
        #expect(footerPager, "the pager sits in the footer, before fullscreen, and the footer fits one row")
        // The header row's controls fit without scrolling sideways.
        let rowFits = try await viewer.evaluate(
          "(viewer) => { const r = viewer.querySelector('.artifact-header-row'); return r.scrollWidth <= r.clientWidth; }"
        ).bool == true
        #expect(rowFits, "the header row needs more than its width")
        try await page.expectNoHorizontalOverflow()
        // Find is the search icon alone.
        // A toggle, as the image switch is: its button holds the name,
        // the viewer's short one (gnorium-web 23bd89d5c, 2026-10-13: the
        // viewer's tooltips shortened, as Overlay and XML).
        let find = viewer.locator(".testament-find-button button")
        try await expect(find).toHaveAccessibleName("Search")
        try await expect(find).toHaveText("")
        // Find and the image switch are the pager's medium chevrons'
        // size, 40, their icons' long edge the chevrons', 16 (icons are tight
        // to their glyph, 2026-10-01; an icon-only control on par with the
        // bars' 16px text takes its size, 2026-10-09): one row of medium
        // controls, 8 on every side of them, in a 56 bar (2026-10-10).
        let chevron = try #require(try await viewer.locator(".pagination-prev").first.boundingBox())
        let chevronIcon = try #require(try await viewer.locator(".pagination-prev svg").first.boundingBox())
        // On a phone every sized control is one step down (user,
        // 2026-10-12): small, 32, its icons 14, in a 48 bar.
        let control: Double = layout == .phone ? 32 : 40
        let glyph: Double = layout == .phone ? 14 : 16
        #expect(abs(chevron.height - control) < 1, "the pager's chevrons are \(control)")
        #expect(abs(max(chevronIcon.width, chevronIcon.height) - glyph) < 1, "the pager's chevrons are \(glyph)")
        #expect(abs(row.height - (control + 16)) < 1, "the header's row is \(control + 16)")
        for (name, control, icon) in [
          ("Find", find, find.locator("svg")),
          ("Image", toggle, toggle.locator("svg")),
        ] {
          let box = try #require(try await control.boundingBox())
          let iconBox = try #require(try await icon.boundingBox())
          #expect(abs(box.width - chevron.width) < 1 && abs(box.height - chevron.height) < 1, "\(name) is not the pager's size")
          #expect(
            abs(max(iconBox.width, iconBox.height) - max(chevronIcon.width, chevronIcon.height)) < 1,
            "\(name)'s icon is not the chevrons' size")
        }

        // Off: the transcript alone, the whole width, and no image asked for.
        // The switch is the image icon alone, named "Image".
        try await expect(toggle).toHaveAccessibleName("Image")
        try await expect(viewer.locator(".artifact-canvas-toggle .toggle-button-label")).toHaveCount(0)
        try await expect(toggle.locator("svg.image-icon-view")).toHaveCount(1)
        try await expect(toggle).toHaveAttribute("aria-pressed", "false")
        try await expect(viewer).toHaveAttribute("data-canvas-shown", "false")
        try await expect(object).toBeHidden()
        let container = try #require(try await viewer.locator(".artifact-viewer-container").boundingBox())
        let transcript = try #require(try await viewer.locator(".artifact-markup").boundingBox())
        #expect(abs(transcript.width - container.width) < 2, "the transcript takes the whole width")
        try await viewer.locator(".pagination-next").first.click()
        try await expect(viewer.locator(".artifact-markup .tei-page[data-active='true']"))
          .toHaveAttribute("data-service-id", services[1])
        #expect(try await page.evaluate(Self.imageRequestsScript(fixture)).double == 0, "an image was fetched while off")

        // On: the page on screen's image, beside the transcript.
        try await toggle.click()
        try await expect(toggle).toHaveAttribute("aria-pressed", "true")
        try await expect(object).toBeVisible()
        try await expect(viewer.locator(".artifact-object .canvas-view[data-active='true'] .canvas-tile-image").first)
          .toHaveCount(1)
        try await expect(viewer.locator(".artifact-object .canvas-view[data-active='true']"))
          .toHaveAttribute("data-service-id", services[1])

        // Across the reader's pages.
        try await viewer.locator(".pagination-next").first.click()
        try await expect(toggle).toHaveAttribute("aria-pressed", "true")
        try await expect(viewer.locator(".artifact-object .canvas-view[data-active='true']"))
          .toHaveAttribute("data-service-id", services[2])
        try await expect(viewer.locator(".artifact-object .canvas-view[data-active='true'] .canvas-tile-image").first)
          .toHaveCount(1)

        // Across navigation in the session.
        try await page.openHydrated(reading.path)
        let again = page.locator(".artifact-view").first
        try await expect(again).toHaveAttribute("data-artifact-hydrated", "true")
        try await expect(again.locator(".artifact-canvas-toggle button")).toHaveAttribute("aria-pressed", "true")
        try await expect(again.locator(".artifact-object")).toBeVisible()
        try await expect(again.locator(".artifact-object .canvas-view[data-active='true'] .canvas-tile-image").first)
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
        // Only the page on screen's canvas is drawn with the page; the
        // others as they are turned to (user, 2026-10-11).
        try await expect(viewer.locator(".artifact-object .canvas-view")).toHaveCount(1)
        try await expect(viewer.locator("#artifact-page-total")).toHaveText("3")
        // The page images, off by default, turned on.
        try await viewer.locator(".artifact-canvas-toggle button").click()

        func images() async throws -> [Image] {
          let json = try await viewer.evaluate(Self.imagesScript).string ?? "[]"
          return try JSONDecoder().decode([Image].self, from: Data(json.utf8))
        }
        func expectShown(_ index: Int) async throws {
          // The backdrop is drawn once the image service's format is probed.
          try await expect(viewer.locator(".artifact-object .canvas-view[data-active='true'] .canvas-tile-image").first)
            .toHaveCount(1)
          let read = try await images()
          let shown = read.filter(\.shown)
          #expect(shown.map(\.service) == [services[index]], "only page \(index + 1) is shown")
          #expect(shown.first.map { $0.tiles > 0 } == true, "the page on screen holds no tiles")
          for image in read where image.service != services[index] {
            #expect(image.tiles == 0, "\(image.service), off screen, holds tiles")
          }
          try await expect(
            viewer.locator(".artifact-markup .tei-page[data-active='true']")
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
