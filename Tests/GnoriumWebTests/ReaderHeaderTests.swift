import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A testament's reader has no title in its header (user, 2026-10-09): on a
/// biblio page the title is already the page's heading or its node's
/// description. The header is its controls alone—Raw, Find and the
/// semblance switch—on one row 40 tall with its 1 border, each control
/// small (32). Raw and Find need an ordinance, the semblance switch a page
/// image (user, 2026-10-09): the testament's manifest is served here
/// (`FixtureServer`), one canvas labeled "p1". The footer names the page on
/// screen by the manifest's canvas label, else its place in the sequence
/// (1, 2, 3): never the ordinance's own `pb n`. On every reader—a Disputorium object's, the record page's
/// and an overture's alike. A throwaway admin owns a scratch work with a
/// permitted testament, made by SQL and removed after.
@Suite("Reader header", .serialized)
struct ReaderHeaderTests {
  static let manifestPath = "/reader-header-manifest.json"
  /// The fixture manifest's one canvas (`FixtureServer.manifests`).
  static let service = "\(manifestPath)/page-1"
  /// Its page's `n` is no canvas label: the footer must not show it.
  static let tei = """
    <TEI><text><body><pb n="iv" facs="\(service)/full/1300,/0/default.jpg"/>\
    <p><s><w>The</w> <w>title</w> <w>page</w><pc>.</pc></s></p>\
    </body></text></TEI>
    """

  struct Header: Decodable {
    /// Any title left in the header.
    let titles: Int
    let raw: Bool
    let find: Bool
    let semblance: Bool
    /// The header's height, its border with it.
    let height: Double
    /// The tallest control in the header's row.
    let control: Double
    let label: String
    /// Every icon-only control's icon in the header and the footer, by its
    /// longer edge: on par with the bars' 16px text, each is 16.
    let icons: [Double]
    let total: String
    let zoom: Int
  }

  static func header(_ page: Page) async throws -> Header {
    try await page.evaluate(
      """
      (() => {
        const view = document.querySelector('.artifact-view')
        const row = view.querySelector('.artifact-header-row')
        const controls = [...row.querySelectorAll('button')].filter((b) => b.offsetParent)
        return {
          titles: view.querySelectorAll('#artifact-title, .artifact-title-block, .edge-fade-sheet-view').length,
          raw: !!row.querySelector('.artifact-code-toggle button')?.offsetParent,
          find: !!row.querySelector('.testament-find-button button')?.offsetParent,
          semblance: !!row.querySelector('.artifact-canvas-toggle button')?.offsetParent,
          height: view.querySelector(':scope > header').getBoundingClientRect().height,
          control: Math.max(0, ...controls.map((b) => b.getBoundingClientRect().height)),
          label: view.querySelector('.artifact-canvas-label').textContent.trim(),
          icons: [...view.querySelectorAll(':scope > header button svg, :scope > footer button svg')]
            .filter((svg) => svg.getBoundingClientRect().width > 0)
            .map((svg) => { const r = svg.getBoundingClientRect(); return Math.round(Math.max(r.width, r.height) * 10) / 10 }),
          total: view.querySelector('#artifact-page-total').textContent.trim(),
          zoom: view.querySelectorAll('.artifact-zoom-controls, #artifact-zoom-controls').length,
        }
      })()
      """, as: Header.self)
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func theHeaderHoldsTheControlsAndNoTitle(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let fixture = try await FixtureServer.manifest(at: Self.manifestPath)
    defer { fixture.stop() }
    let sourceURL = fixture.baseURL + Self.manifestPath
    var testament: ScratchTestament?
    func clean() async throws {
      testament?.remove()
      try await admin.remove()
    }
    do {
      let scratch = try ScratchTestament(owner: admin, tei: Self.tei, sourceURL: sourceURL)
      testament = scratch
      let work = scratch.reading.work
      // The record's versions name the served manifest too.
      _ = try TestAdmin.query(
        """
        UPDATE biblio_record_versions SET metadata_json = jsonb_set(metadata_json::jsonb, '{sourceUrl}', '"\(sourceURL)"')::text
          WHERE biblio_record_id = '\(work.recordID.lowercased())';
        """)
      let viewport = layout.viewport(for: engine)
      let folder = ProcessInfo.processInfo.environment["READER_HEADER_SCREENSHOTS"]
      let width = layout == .phone ? 375 : 1400
      func shoot(_ page: Page, _ name: String) async throws {
        guard let folder else { return }
        _ = try await page.evaluate(
          "(() => { document.querySelector('.artifact-view').scrollIntoView({ block: 'start' }); return true })()")
        try await page.screenshot(
          to: URL(fileURLWithPath: folder).appendingPathComponent("reader-\(name)-\(width).png"))
      }
      func check(_ header: Header, _ place: String) {
        #expect(header.titles == 0, "\(place): the header still has a title")
        #expect(header.raw, "\(place): no Raw switch")
        #expect(header.find, "\(place): no Find button")
        #expect(header.semblance, "\(place): no semblance switch")
        #expect(abs(header.height - 41) < 0.5, "\(place): the header is \(header.height) tall, not 41")
        #expect(abs(header.control - 32) < 0.5, "\(place): a control is \(header.control) tall, not 32")
        // The manifest's canvas label, never the page's pb n.
        #expect(header.label == "p1", "\(place): the footer names the page \(header.label)")
        #expect(!header.icons.isEmpty && header.icons.allSatisfy { abs($0 - 16) < 0.5 }, "\(place): icons \(header.icons), not 16")
        #expect(header.total == "1", "\(place): the pager's total is \(header.total)")
        #expect(header.zoom == 0, "\(place): an empty zoom slot is drawn")
      }
      try await withPage(engine, gnorium, viewport: viewport) { page in
        // As the server draws it, before any manifest is read: the pager
        // counts the ordinance's pages, never "of —".
        try await page.openHydrated(scratch.reading.path)
        let served = try await page.evaluate(
          """
          (async () => {
            const html = await (await fetch(location.href)).text()
            const doc = new DOMParser().parseFromString(html, 'text/html')
            return doc.querySelector('.artifact-view #artifact-page-total').textContent.trim()
          })()
          """)
        #expect(served == .string("1"), "the served pager's total is \(served), not the ordinance's 1 page")

        // A Disputorium object's reader.
        try await expect(page.locator(".artifact-view .artifact-header-row").first).toBeVisible()
        try await expect(page.locator(".artifact-view .artifact-canvas-label").first).toHaveText("p1")
        check(try await Self.header(page), "madrigal")
        try await shoot(page, "madrigal")
        try await page.expectNoHorizontalOverflow()

        // The record page's reader, fetched into its row.
        try await page.openHydrated(work.path)
        _ = try await page.evaluate(
          """
          (() => { document.querySelector("[data-reader-url*='\(scratch.versionID)' i]").closest('.record-row')
            .querySelector(':scope > .accordion-details > .accordion-summary').click(); return true; })()
          """)
        try await expect(page.locator(".artifact-view .artifact-canvas-label").first).toHaveText("p1")
        check(try await Self.header(page), "record page")
        try await shoot(page, "record")
        try await page.expectNoHorizontalOverflow()

        // The overture's reader: the work's testament, its ordinance the
        // newest its line has made.
        try await page.openHydrated("/mission-control/overtures/bibliographic/\(work.overtureID)")
        try await expect(page.locator(".artifact-view .artifact-header-row").first).toBeVisible()
        try await expect(page.locator(".artifact-view .artifact-canvas-label").first).toHaveText("p1")
        check(try await Self.header(page), "overture")
        try await shoot(page, "overture")
        try await page.expectNoHorizontalOverflow()

        // No page image (a source no manifest answers for): Raw and Find,
        // which need the ordinance, and no semblance switch, which needs a
        // semblance; the page named by its place.
        _ = try TestAdmin.query(
          """
          UPDATE biblio_record_versions SET metadata_json = jsonb_set(metadata_json::jsonb, '{sourceUrl}', '"https://example.org/web-tests-none"')::text
            WHERE biblio_record_id = '\(work.recordID.lowercased())';
          """)
        try await page.openHydrated(work.path)
        _ = try await page.evaluate(
          """
          (() => { document.querySelector("[data-reader-url*='\(scratch.versionID)' i]").closest('.record-row')
            .querySelector(':scope > .accordion-details > .accordion-summary').click(); return true; })()
          """)
        try await expect(page.locator(".artifact-view .artifact-canvas-label").first).toHaveText("1")
        let bare = try await Self.header(page)
        #expect(bare.raw && bare.find, "no page image: Raw and Find need only the ordinance")
        #expect(!bare.semblance, "no page image, yet a semblance switch")
      }
      try await clean()
    } catch {
      try? await clean()
      throw error
    }
  }
}
