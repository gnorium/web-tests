import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A testament's header has its own switch, never tied to the XML switch
/// (user, 2026-10-21): where there is a header, the footer's Header switch
/// stands right after the XML switch (or alone, where no page is explicated
/// and there is no XML switch), enabled, off by default. On, the header shows
/// as code alone (no rendered side) in a pane of its own at the top of the
/// markup's column, read-only on the code's gray, numbered from 1, whether
/// the XML is on or off; the XML switch neither enables nor clears it. The
/// page's XML never holds the header nor counts its lines on after it; a
/// Revise editor's numbers start at 1. No rendered header box anywhere. A
/// document with no header has no switch. A testament whose pages are
/// images alone shows its header in that column beside them while the switch
/// is on, the images the whole viewer while it is off. The header row's Image
/// and Search switches are drawn as the footer's are (subtle, gray).
/// A throwaway admin owns scratch works (dev has no model: rows made by SQL,
/// removed after).
@Suite("Testament header", .serialized)
struct TestamentHeaderTests {
  static let manifestPath = "/testament-header-manifest.json"
  static let service = "\(manifestPath)/page-1"
  /// Its header as Calibration writes one: each declaration on a line.
  static let header = """
    <teiHeader><fileDesc><titleStmt><title>Web tests header</title></titleStmt>
    <extent><measure unit="image" quantity="1"/></extent></fileDesc>
    <encodingDesc><tagsDecl>
    <rendition xml:id="size-1" scheme="css">font-size:0.8251rem</rendition>
    <rendition xml:id="size-2" scheme="css">font-size:1.0029rem</rendition>
    <rendition xml:id="leading-1" scheme="css">line-height:1.2857rem</rendition>
    </tagsDecl></encodingDesc>
    <revisionDesc><change when="2026-10-20" who="#gnorium">Calibrated.</change></revisionDesc></teiHeader>
    """
  static var headerLines: Int { header.split(separator: "\n", omittingEmptySubsequences: false).count }
  static let tei = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0">\(header)<text><body><pb n="1" facs="\(service)/full/1300,/0/default.jpg"/>\
    <p><s><w>The</w> <w>first</w> <w>page</w><pc>.</pc></s></p></body></text></TEI>
    """
  /// Calibrated, not yet explicated: the header, and no page read.
  static let calibrated = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0">\(header)<text><body></body></text></TEI>
    """

  struct State: Decodable {
    let hasXML: Bool
    /// The Header switch stands right after the XML switch.
    let afterXML: Bool
    let title: String
    let label: String
    let disabled: Bool
    let pressed: String
    /// The artifact's `data-header` and `data-raw`.
    let header: String
    let raw: String
    /// The header's pane shown, over the markup's.
    let shown: Bool
    let above: Bool
    let headerCount: Int
    let headerReset: String
    let headerGround: String
    let markupGround: String
    let headerEditable: Bool
    /// The page's code: its counter start, and whether it holds a header.
    let pageReset: String
    let pageHoldsHeader: Bool
    /// Headers drawn in a page's code, and rendered header boxes.
    let pageHeaders: Int
    let boxes: Int
    /// The images' pane and the viewer's body, wide.
    let objectWidth: Double
    let bodyWidth: Double
  }

  static func state(_ page: Page) async throws -> State {
    try await page.evaluate(
      """
      (() => {
        const view = document.querySelector('.artifact-view')
        const toggle = view.querySelector('.artifact-header-toggle')
        const button = toggle.querySelector('button')
        const xml = view.querySelector('.artifact-xml-toggle')
        const head = view.querySelector('.artifact-document-header')
        const box = view.querySelector('.artifact-markup-box')
        const markup = view.querySelector('.artifact-markup')
        const pane = view.querySelector(".tei-page[data-active='true'] .tei-page-raw[data-layer='markup']")
        const own = pane ? pane.querySelector(':scope > .code-view, :scope > form .code-view') : null
        const shown = !!head && getComputedStyle(head).display !== 'none' && head.getBoundingClientRect().height > 0
        const object = view.querySelector('.artifact-object')
        const body = view.querySelector('.artifact-viewer-container')
        return {
          hasXML: !!xml,
          afterXML: toggle.previousElementSibling?.classList.contains('artifact-xml-toggle') === true,
          title: toggle.getAttribute('title') || button.getAttribute('title') || '',
          label: button.getAttribute('aria-label') || '',
          disabled: button.disabled,
          pressed: button.getAttribute('aria-pressed') || '',
          header: view.getAttribute('data-header') || '',
          raw: view.getAttribute('data-raw') || '',
          shown,
          above: shown && (!box || head.getBoundingClientRect().bottom <= box.getBoundingClientRect().top + 1),
          headerCount: head ? head.querySelectorAll('.code-line').length : 0,
          headerReset: head ? getComputedStyle(head.querySelector('.code-code')).counterReset : '',
          headerGround: head ? getComputedStyle(head.querySelector('.code-view')).backgroundColor : '',
          markupGround: markup ? getComputedStyle(markup).backgroundColor : '',
          headerEditable: !!head?.querySelector('[contenteditable], textarea, input'),
          pageReset: own ? getComputedStyle(own.querySelector('.code-code')).counterReset : '',
          pageHoldsHeader: !!own && own.textContent.includes('teiHeader'),
          pageHeaders: document.querySelectorAll('.tei-page-header').length,
          boxes: document.querySelectorAll('.header-view, .header-entry-view').length,
          objectWidth: object ? object.getBoundingClientRect().width : 0,
          bodyWidth: body ? body.getBoundingClientRect().width : 0,
        }
      })()
      """, as: State.self)
  }

  /// The first reader's XML switched to `on` once it is hydrated (it wears
  /// `data-raw` then), whatever the session left it at.
  static func setXML(_ page: Page, _ on: Bool) async throws {
    let view = page.locator(".artifact-view").first
    var raw = ""
    for _ in 0..<50 {
      let read = try await page.evaluate("(() => document.querySelector('.artifact-view')?.getAttribute('data-raw') ?? '')()")
      raw = read.string ?? ""
      if !raw.isEmpty { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    if (raw == "true") != on {
      // The button's own click: a pointer click at a reader's bottom edge
      // landed on its code while the page scrolled under the pointer.
      _ = try await page.evaluate(
        "(() => { document.querySelector('.artifact-view .artifact-xml-toggle button').click(); return true })()")
    }
    try await expect(view).toHaveAttribute("data-raw", on ? "true" : "false")
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func theHeaderHasItsOwnSwitchAndPane(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let fixture = try await FixtureServer.manifest(at: Self.manifestPath)
    defer { fixture.stop() }
    let sourceURL = fixture.baseURL + Self.manifestPath
    var testament: ScratchTestament?
    var bare: ScratchTestament?
    var calibrated: ScratchTestament?
    var commit: ScratchCommit?
    func clean() async throws {
      commit?.remove()
      calibrated?.remove()
      bare?.remove()
      testament?.remove()
      try await admin.remove()
    }
    do {
      let scratch = try ScratchTestament(owner: admin, tei: Self.tei, sourceURL: sourceURL)
      testament = scratch
      let work = scratch.reading.work
      _ = try TestAdmin.query(
        """
        UPDATE biblio_record_versions SET metadata_json = jsonb_set(metadata_json::jsonb, '{sourceUrl}', '"\(sourceURL)"')::text
          WHERE biblio_record_id = '\(work.recordID.lowercased())';
        """)
      // A pending madrigal holding the same document, for its Revise page.
      let revising = try ScratchCommit(owner: admin)
      commit = revising
      let content = try String(
        decoding: JSONSerialization.data(
          withJSONObject: ["teiXml": Self.tei.replacingOccurrences(of: Self.service, with: "https://web-tests.invalid/iiif/p1")]),
        as: UTF8.self
      ).replacingOccurrences(of: "'", with: "''")
      _ = try TestAdmin.query(
        "UPDATE bibliographic_madrigals SET proposed_content_json = '\(content)' WHERE id = '\(revising.madrigalID)'")
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        // The record page's reader, fetched into its row.
        try await page.openHydrated(work.path)
        _ = try await page.evaluate(
          """
          (() => { document.querySelector("[data-reader-url*='\(scratch.versionID)' i]").closest('.record-row')
            .querySelector(':scope > .accordion-details > .accordion-summary').click(); return true; })()
          """)
        let view = page.locator(".artifact-view").first
        let toggle = view.locator(".artifact-header-toggle button")
        try await expect(toggle).toBeVisible()
        try await Self.setXML(page, false)

        // Off, enabled though the XML is off; right after the XML switch;
        // no box, nothing in a page's code.
        var state = try await Self.state(page)
        #expect(state.hasXML && state.afterXML, "the Header switch is not right after the XML switch")
        #expect(state.title == "Header")
        #expect(state.label == "Show the header")
        #expect(!state.disabled, "disabled while the XML is off")
        #expect(state.pressed == "false" && state.header == "false" && !state.shown)
        #expect(state.boxes == 0, "a rendered header box is drawn")
        #expect(state.pageHeaders == 0, "a header drawn in a page's code")

        // The header row's Image and Search switches drawn as the footer's.
        for name in [".testament-find-button", ".artifact-xml-toggle", ".artifact-header-toggle"] {
          try await expect(view.locator("\(name) .button-view").first).toHaveAttribute("data-weight", "subtle")
          try await expect(view.locator("\(name) .button-view").first).toHaveAttribute("data-color", "gray")
        }
        let canvas = view.locator(".artifact-canvas-toggle .button-view")
        if try await canvas.count() > 0 {
          try await expect(canvas.first).toHaveAttribute("data-weight", "subtle")
        }

        // Header on, XML off: the header's code alone over the rendered
        // page, on the gray, read-only, numbered from 1.
        try await toggle.click()
        state = try await Self.state(page)
        #expect(state.header == "true" && state.pressed == "true" && state.raw == "false", "header on: \(state)")
        #expect(state.shown && state.above, "the header's pane is not over the markup's: \(state)")
        #expect(state.headerCount == Self.headerLines, "the header has \(state.headerCount) lines")
        #expect(state.headerReset == "code-line 0")
        #expect(state.headerGround != state.markupGround, "the header is on the page's ground")
        #expect(!state.headerEditable)
        try await page.expectNoHorizontalOverflow()

        // XML on: the page's code beside it, numbered from 1, holding no
        // header; the header still on.
        try await Self.setXML(page, true)
        state = try await Self.state(page)
        #expect(state.header == "true" && state.shown && state.above, "XML on cleared the header: \(state)")
        #expect(state.pageReset == "code-line 0", "the page is numbered from \(state.pageReset)")
        #expect(!state.pageHoldsHeader, "the page's code holds the header")

        // XML off again: the header untouched, the switch still enabled.
        try await Self.setXML(page, false)
        try await expect(view).toHaveAttribute("data-header", "true")
        state = try await Self.state(page)
        #expect(state.shown && !state.disabled && state.pressed == "true", "XML off: \(state)")

        // Header off: the pane gone, the XML switch as it stood.
        try await toggle.click()
        try await expect(view).toHaveAttribute("data-header", "false")
        state = try await Self.state(page)
        #expect(!state.shown && state.raw == "false", "header off: \(state)")
        try await page.expectNoErrors()

        // Revise: the editor never holds the header nor counts on after it;
        // the header's pane over it, read-only.
        try await page.openHydrated("\(revising.madrigalPath)/revise")
        let reviseView = page.locator(".artifact-view").first
        try await Self.setXML(page, true)
        let value = try await page.evaluate(
          "(() => document.querySelector(\".tei-page[data-active='true'] .tei-page-edit textarea\").value)()",
          as: String.self)
        #expect(!value.contains("teiHeader"), "the editor holds the header: \(value.prefix(80))")
        try await reviseView.locator(".artifact-header-toggle button").click()
        state = try await Self.state(page)
        #expect(state.shown && state.above && !state.headerEditable, "revise: \(state)")
        let first = try await page.evaluate(
          "(() => document.querySelector(\".tei-page[data-active='true'] .tei-page-edit .code-gutter-lines > span\")?.textContent ?? '')()",
          as: String.self)
        #expect(first == "1", "the editor's first number is \(first) with the header on")
      }

      // A document that declares no header: no switch.
      let plain = try ScratchTestament(
        owner: admin,
        tei: #"<TEI><text><body><pb n="1" facs="\#(Self.service)/full/1300,/0/default.jpg"/><p>No header.</p></body></text></TEI>"#,
        sourceURL: sourceURL)
      bare = plain
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(plain.reading.path)
        try await expect(page.locator(".artifact-view .artifact-xml-toggle").first).toBeVisible()
        try await expect(page.locator(".artifact-header-toggle")).toHaveCount(0)
        try await expect(page.locator(".artifact-document-header")).toHaveCount(0)
      }

      // Calibrated, not yet explicated: no XML switch (there is no XML), the
      // Header switch alone; on, the header's column beside the images; off,
      // the images the whole viewer.
      let headerOnly = try ScratchTestament(owner: admin, tei: Self.calibrated, sourceURL: sourceURL)
      calibrated = headerOnly
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(headerOnly.reading.path)
        let view = page.locator(".artifact-view").first
        let toggle = view.locator(".artifact-header-toggle button")
        try await expect(toggle).toBeVisible()
        try await expect(view.locator(".artifact-xml-toggle")).toHaveCount(0)
        try await expect(view.locator(".artifact-markup")).toHaveCount(0)
        let frame = view.locator(".artifact-markup-frame[data-header-only='true']")
        try await expect(frame).toBeHidden()
        var state = try await Self.state(page)
        #expect(!state.hasXML && !state.disabled && state.pressed == "false" && !state.shown, "calibrated: \(state)")
        #expect(state.objectWidth >= state.bodyWidth - 1, "the images are not the whole viewer: \(state)")

        try await toggle.click()
        try await expect(view).toHaveAttribute("data-header", "true")
        try await expect(frame).toBeVisible()
        state = try await Self.state(page)
        #expect(state.shown && state.headerCount == Self.headerLines && !state.headerEditable, "calibrated, on: \(state)")
        #expect(state.headerReset == "code-line 0")
        try await page.expectNoHorizontalOverflow()

        try await toggle.click()
        try await expect(view).toHaveAttribute("data-header", "false")
        try await expect(frame).toBeHidden()
        state = try await Self.state(page)
        #expect(state.objectWidth >= state.bodyWidth - 1, "the images are not the whole viewer again: \(state)")
        try await page.expectNoErrors()
      }
      try await clean()
    } catch {
      try? await clean()
      throw error
    }
  }
}
