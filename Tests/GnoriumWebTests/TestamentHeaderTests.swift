import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A testament's header lives in its artifact's XML pane (user,
/// 2026-10-20): where its document declares a `<teiHeader>`, the footer's
/// Header switch stands right of the XML switch, off by default, enabled
/// only while the XML shows (XML off puts it off); on, the header's lines
/// head the page's code, read-only on the code's gray, numbered 1, 2, 3 and
/// the page's lines counted on after them; off, the page's lines are
/// numbered from 1. Never editable, in Revise too. No rendered header box
/// anywhere. A document declaring no header has no switch. The header row's
/// Image and Search switches are drawn as the footer's are (subtle, gray).
/// A throwaway admin owns a scratch work with a permitted testament whose
/// madrigal TEI declares a header (dev has no model: rows made by SQL,
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

  struct State: Decodable {
    /// The Header switch stands right after the XML switch.
    let besideXML: Bool
    let title: String
    let label: String
    let disabled: Bool
    let pressed: String
    /// The artifact's `data-header`.
    let header: String
    /// The header's lines shown, above the page's code.
    let shown: Bool
    let above: Bool
    let headerCount: Int
    /// The page's code's counter start and the header's.
    let pageReset: String
    let headerReset: String
    let headerGround: String
    let pageGround: String
    let headerEditable: Bool
    let boxes: Int
  }

  static func state(_ page: Page) async throws -> State {
    try await page.evaluate(
      """
      (() => {
        const view = document.querySelector('.artifact-view')
        const toggle = view.querySelector('.artifact-header-toggle')
        const button = toggle.querySelector('button')
        const pane = view.querySelector(".tei-page[data-active='true'] .tei-page-raw[data-layer='markup']")
        const head = pane.querySelector('.tei-page-header')
        const own = pane.querySelector(':scope > .code-view, :scope > form .code-view')
        const shown = getComputedStyle(head).display !== 'none' && head.getBoundingClientRect().height > 0
        return {
          besideXML: toggle.previousElementSibling?.classList.contains('artifact-xml-toggle') === true,
          title: toggle.getAttribute('title') || button.getAttribute('title') || '',
          label: button.getAttribute('aria-label') || '',
          disabled: button.disabled,
          pressed: button.getAttribute('aria-pressed') || '',
          header: view.getAttribute('data-header') || '',
          shown,
          above: shown && head.getBoundingClientRect().bottom <= own.getBoundingClientRect().top + 1,
          headerCount: head.querySelectorAll('.code-line').length,
          pageReset: getComputedStyle(own.querySelector('.code-code')).counterReset,
          headerReset: getComputedStyle(head.querySelector('.code-code')).counterReset,
          headerGround: getComputedStyle(head.querySelector('.code-view')).backgroundColor,
          pageGround: getComputedStyle(own).backgroundColor,
          headerEditable: !!head.querySelector('[contenteditable], textarea, input'),
          boxes: document.querySelectorAll('.header-view, .header-entry-view').length,
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
  func theHeaderHeadsTheXMLPaneUnderItsSwitch(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let fixture = try await FixtureServer.manifest(at: Self.manifestPath)
    defer { fixture.stop() }
    let sourceURL = fixture.baseURL + Self.manifestPath
    var testament: ScratchTestament?
    var bare: ScratchTestament?
    var commit: ScratchCommit?
    func clean() async throws {
      commit?.remove()
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

        // Off, disabled while the XML is off; right of the XML switch; no box.
        var state = try await Self.state(page)
        #expect(state.besideXML, "the Header switch is not right of the XML switch")
        #expect(state.title == "Header")
        #expect(state.label == "Show the header")
        #expect(state.disabled, "enabled while the XML is off")
        #expect(state.pressed == "false")
        #expect(state.boxes == 0, "a rendered header box is drawn")

        // The header row's Image and Search switches drawn as the footer's.
        for name in [".testament-find-button", ".artifact-xml-toggle"] {
          try await expect(view.locator("\(name) .button-view").first).toHaveAttribute("data-weight", "subtle")
          try await expect(view.locator("\(name) .button-view").first).toHaveAttribute("data-color", "gray")
        }
        let canvas = view.locator(".artifact-canvas-toggle .button-view")
        if try await canvas.count() > 0 {
          try await expect(canvas.first).toHaveAttribute("data-weight", "subtle")
        }

        // XML on: the switch enabled, still off; the page numbered from 1.
        try await Self.setXML(page, true)
        state = try await Self.state(page)
        #expect(!state.disabled, "disabled while the XML shows")
        #expect(!state.shown, "the header shows with its switch off")
        #expect(state.pageReset == "code-line 0", "the page is numbered from \(state.pageReset)")

        // Header on: its lines over the page's, on the gray, read-only;
        // numbered from 1, the page's on after them.
        try await toggle.click()
        state = try await Self.state(page)
        #expect(state.header == "true" && state.pressed == "true")
        #expect(state.shown && state.above, "the header's lines are not over the page's: \(state)")
        #expect(state.headerCount == Self.headerLines, "the header has \(state.headerCount) lines")
        #expect(state.headerReset == "code-line 0")
        #expect(state.pageReset == "code-line \(Self.headerLines)", "the page's lines start after \(state.pageReset)")
        #expect(state.headerGround != state.pageGround, "the header is on the page's ground")
        #expect(!state.headerEditable)
        try await page.expectNoHorizontalOverflow()

        // XML off: the header off with it, the switch disabled.
        try await Self.setXML(page, false)
        try await expect(view).toHaveAttribute("data-raw", "false")
        try await expect(view).toHaveAttribute("data-header", "false")
        state = try await Self.state(page)
        #expect(state.disabled && state.pressed == "false" && state.header == "false", "XML off: \(state)")
        try await page.expectNoErrors()

        // Revise: the editor never holds the header; it is drawn over it,
        // read-only, the editor's numbers counted on after it.
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
        #expect(first == "\(Self.headerLines + 1)", "the editor's first number is \(first)")
        try await reviseView.locator(".artifact-header-toggle button").click()
        let again = try await page.evaluate(
          "(() => document.querySelector(\".tei-page[data-active='true'] .tei-page-edit .code-gutter-lines > span\")?.textContent ?? '')()",
          as: String.self)
        #expect(again == "1", "the editor's first number is \(again) with the header off")
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
        try await expect(page.locator(".tei-page-header")).toHaveCount(0)
      }
      try await clean()
    } catch {
      try? await clean()
      throw error
    }
  }
}
