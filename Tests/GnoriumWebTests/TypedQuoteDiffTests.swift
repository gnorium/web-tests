import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A stored typed quote's reader in a diff (user, 2026-11-05), as
/// `PendingQuoteView` draws one: a quote by a Source URL whose frames are
/// "1"…"3", the quote on frame 2 (`data-markup-frames`), added (its Quote
/// card's `data-quote-state`), its page's code diffed as every line added
/// under its text pane (`TestamentView`'s slot under `.artifact-under-markup`).
///
/// - "the diff is not shown of the quote pane why? should be like trace":
///   under Raw its Diff box stands under its text pane as a traced page's
///   does, the pane ringed green.
/// - "on paging through it still shows pg 326's quote and diff why?": paged
///   to another frame, its pane is empty, with no ring and no diff; paged
///   back, all three again.
///
/// The client against the markup the server draws (artifact-core
/// `ArtifactView`, gnorium-web `TestamentView`, `QuoteSourceView`), its
/// built style sheets, a three-frame manifest. Chrome.
@Suite("Typed quote in a diff", .serialized)
struct TypedQuoteDiffTests {
  static let quote = "For Tragedy, his Richard the 2, Richard the 3, Henry the 4, King Iohn, Titus Andronicus and his Romeo and Iuliet."

  static func server() async throws -> FixtureServer {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let assets = root.appendingPathComponent("gnorium-web/Public")
    let css = try [
      "layout-view.css", "tei-view.css", "artifact-view.css", "frame-view.css", "code-view.css", "diff-view.css",
      "testament-view.css", "quote-source-view.css",
    ].map {
      try String(contentsOf: assets.appendingPathComponent("style-sheets/" + $0), encoding: .utf8)
    }.joined(separator: "\n")
    let code = "&lt;p&gt;" + quote + "&lt;/p&gt;"
    let html =
      "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><style>"
      + css + #"""
      body{margin:0}.testament-reader > .artifact-view{width:100%;height:600px}</style><link rel="icon" href="data:,"></head><body>
      <div class="quote-source-box"><fieldset class="quote-source-quote" data-quote-state="added"><div class="quote-source-artifact">
      <div class="testament-view" data-amendment-preview="" data-pages-url="" data-page-viewed-url=""><div class="testament-reader">
      <div class="artifact-view" data-manifest-url="/manifest" data-start-canvas="1" data-start-service="" data-canvas-shown="true" data-canvas-confirmed="false" data-markup-follows-canvas="true" data-markup-frames="2" data-markup-shown="true" data-typed-text="true" data-header="false">
      <div class="artifact-viewer-container"><div class="artifact-markup-viewport" data-header-only="false" data-sheet-host="true">
      <div class="artifact-markup-box"><div class="artifact-markup" id="artifact-markup"><div class="tei-view" data-editable="false">
      <div class="tei-page" id="tei-page-0" data-service-id="#page" data-active="true" data-has-markup="true">
      <div class="tei-page-text" data-layer="rendering"><div class="tei-text-block"><div class="tei-section"><div class="tei-block"><span class="tei-line"><span class="tei-highlight" data-highlight="sentence">
      """# + quote + #"""
      </span></span></div></div></div></div>
      <div class="tei-page-raw" data-layer="markup"><div class="code-view" data-lined="true"><code class="code-code"><span class="code-line" data-code-number="1">
      """# + code + #"""
      </span></code></div></div></div></div></div></div>
      <div class="artifact-under-markup"><div class="testament-diffs"><div class="testament-diff" data-service-id="#page" data-active="false" data-edited="true" data-translation-edited="false" data-page-state="added" data-translation-state="" data-kept="false">
      <div class="frame-diff-view" data-changed="true" data-well-formed="true"><div class="diff-view" data-shape="box" data-diff-mode="code"><div class="diff-box"><div class="diff-lines">
      <div class="diff-row" data-diff-line="inserted" data-diff-at="1"><span class="diff-sign">+</span><span class="diff-content">
      """# + code + #"""
      </span></div></div></div></div></div></div></div></div></div>
      <div class="artifact-object"></div></div>
      <footer class="artifact-footer"><div class="artifact-footer-start"><div class="artifact-xml-toggle"><button>XML</button></div><div class="artifact-reflow-toggle"><button>Reflow</button></div></div></footer>
      </div></div></div></div></fieldset></div><script src="/loader.js"></script></body></html>
      """#
    let canvases = (1...3).map { #"{"id":"/scan\#($0)","w":1200,"h":2000,"imgs":["/scan.svg"]}"# }.joined(separator: ",")
    var files: [String: FixtureServer.File] = [
      "/": .init(contentType: "text/html", body: Data(html.utf8)),
      "/loader.js": .init(
        contentType: "text/javascript", body: try Data(contentsOf: assets.appendingPathComponent("loader.js"))),
      "/client.wasm": .init(
        contentType: "application/wasm", body: try Data(contentsOf: assets.appendingPathComponent("client.wasm"))),
      "/manifest": .init(contentType: "application/json", body: Data(#"{"canvases":[\#(canvases)]}"#.utf8)),
      "/scan.svg": .init(
        contentType: "image/svg+xml",
        body: Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="2000"/>"#.utf8)),
    ]
    // The faces its style sheets draw it in: the page's serif, the code's
    // mono, the controls' sans.
    for font in ["noto-sans.woff2", "noto-sans-italic.woff2", "noto-sans-mono.woff2", "noto-serif.woff2", "noto-serif-italic.woff2"] {
      files["/fonts/" + font] = .init(
        contentType: "font/woff2", body: try Data(contentsOf: assets.appendingPathComponent("fonts/" + font)))
    }
    let sheets = assets.appendingPathComponent("style-sheets")
    for name in try FileManager.default.contentsOfDirectory(atPath: sheets.path)
    where name.hasSuffix(".css") || name.hasSuffix(".json") {
      files["/style-sheets/\(name)"] = .init(
        contentType: name.hasSuffix(".css") ? "text/css" : "application/json",
        body: try Data(contentsOf: sheets.appendingPathComponent(name)))
    }
    return try await FixtureServer(files: files)
  }

  /// What the reader shows: its page on screen (the frame it reads), the
  /// quote's text drawn (its page's layer on screen: its code under Raw,
  /// which puts its rendered text away, else that text), the pane's ring,
  /// its diff's zone and its rows.
  struct Shown: Decodable {
    let service: String
    let active: Int
    let markupShown: String
    let textShown: Bool
    let ring: String
    let zone: String
    let rows: Int
  }

  static let shown = """
    (() => {
      const view = document.querySelector('.artifact-view'), page = view.querySelector('.artifact-markup .tei-page');
      const box = view.querySelector('.artifact-markup-box'), s = getComputedStyle(box);
      const raw = view.querySelector(".artifact-xml-toggle[aria-pressed='true']");
      const text = page.querySelector(raw ? "[data-layer='markup']" : "[data-layer='rendering']");
      const rows = [...view.querySelectorAll(".testament-diff .diff-row")].filter((r) => r.getClientRects().length && r.getBoundingClientRect().height > 0);
      return { service: page.dataset.serviceId || '', active: view.querySelectorAll(".artifact-markup .tei-page[data-active='true']").length,
        markupShown: view.dataset.markupShown || '', textShown: !!text && text.getClientRects().length > 0 && text.getBoundingClientRect().height > 0,
        ring: s.outlineStyle === 'none' || s.outlineWidth === '0px' ? '' : s.outlineColor + ' ' + s.borderTopColor,
        zone: view.querySelector('.artifact-under-markup').dataset.shown || '', rows: rows.length };
    })()
    """

  static func toggle(_ page: Page, _ selector: String, _ on: Bool) async throws {
    _ = try await page.evaluate(
      """
      (() => { const w = document.querySelector('.artifact-view \(selector)'), b = w.querySelector('button'), v = '\(on)';
        w.setAttribute('aria-pressed', v); b.setAttribute('aria-pressed', v);
        w.dispatchEvent(new CustomEvent('toggle-button-update', { detail: v })); return true })()
      """)
  }

  /// Under Raw, the added quote's Diff box under its text pane, every line
  /// of its code added, the pane ringed green; Raw off, the zone put away.
  @Test(arguments: [1440, 440])
  func anAddedTypedQuoteShowsItsDiffUnderItsPane(width: Int) async throws {
    let server = try await Self.server()
    defer { server.stop() }
    let config = BrowserTestConfiguration(
      baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(30))
    try await withPage(.chrome, config, viewport: .init(width: width, height: 800)) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      // On its own frame (2, the reader's start), the page reads it.
      try await expect(page.locator(".artifact-markup .tei-page")).toHaveAttribute("data-service-id", "/scan2")
      try await Self.toggle(page, ".artifact-xml-toggle", true)
      try await expect(page.locator(".artifact-view")).toHaveAttribute("data-raw", "true")
      try await expect(page.locator(".artifact-under-markup")).toHaveAttribute("data-shown", "true")
      let rows = page.locator(".testament-diff[data-active='true'] .diff-row[data-diff-line='inserted']")
      try await expect(rows).toHaveCount(1)
      try await expect(rows.first).toBeVisible()
      try await expect(rows.first).toContainText("For Tragedy")
      let shown = try await page.evaluate(Self.shown, as: Shown.self)
      #expect(!shown.ring.isEmpty, "at \(width), the added quote's pane wears no ring: \(shown)")
      // Under the pane, in its column.
      let under = try await page.evaluate(
        """
        (() => { const pane = document.querySelector('.artifact-markup-box').getBoundingClientRect();
          const box = document.querySelector(".testament-diff[data-active='true'] .diff-box").getBoundingClientRect();
          return box.top >= pane.bottom - 1 && box.left >= pane.left - 2 && box.right <= pane.right + 2 })()
        """, as: Bool.self)
      #expect(under, "at \(width), the Diff box is not under the quote's text pane")
      try await Self.toggle(page, ".artifact-xml-toggle", false)
      try await expect(page.locator(".artifact-under-markup")).toHaveAttribute("data-shown", "false")
      try await expect(rows.first).toBeHidden()
      try await page.expectNoErrors()
    }
  }

  /// Paged to a frame that is not the quote's, its text pane is empty: no
  /// page active, no ring, no diff; paged back to its own, all three again.
  @Test(arguments: [1440, 440])
  func pagingAwayPutsTheQuoteItsRingAndItsDiffAway(width: Int) async throws {
    let server = try await Self.server()
    defer { server.stop() }
    let config = BrowserTestConfiguration(
      baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(30))
    try await withPage(.chrome, config, viewport: .init(width: width, height: 800)) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      try await expect(page.locator(".artifact-markup .tei-page")).toHaveAttribute("data-service-id", "/scan2")
      try await Self.toggle(page, ".artifact-xml-toggle", true)
      try await expect(page.locator(".artifact-under-markup")).toHaveAttribute("data-shown", "true")
      func turn(to service: String) async throws -> Shown {
        _ = try await page.evaluate(
          "(() => { document.querySelector('.artifact-view').dispatchEvent(new CustomEvent('artifact-show-service', { detail: '\(service)' })); return true })()")
        try await expect(page.locator(".artifact-markup .tei-page")).toHaveAttribute("data-service-id", service)
        try await Task.sleep(for: .milliseconds(300))
        return try await page.evaluate(Self.shown, as: Shown.self)
      }
      let own = try await page.evaluate(Self.shown, as: Shown.self)
      #expect(own.active == 1 && own.textShown && !own.ring.isEmpty && own.zone == "true" && own.rows == 1, "at \(width), on its frame: \(own)")
      for other in ["/scan3", "/scan1"] {
        let away = try await turn(to: other)
        #expect(away.active == 0, "at \(width), on \(other) a page is active: \(away)")
        #expect(away.markupShown == "false", "at \(width), on \(other) the reader says its markup shows: \(away)")
        #expect(!away.textShown, "at \(width), on \(other) the quote's text shows: \(away)")
        #expect(away.ring.isEmpty, "at \(width), on \(other) the pane is ringed: \(away)")
        #expect(away.zone == "false" && away.rows == 0, "at \(width), on \(other) its diff shows: \(away)")
        let back = try await turn(to: "/scan2")
        #expect(back.active == 1 && back.markupShown == "true" && back.textShown, "at \(width), back on its frame from \(other): \(back)")
        #expect(!back.ring.isEmpty, "at \(width), back on its frame from \(other), no ring: \(back)")
        #expect(back.zone == "true" && back.rows == 1, "at \(width), back on its frame from \(other), no diff: \(back)")
      }
      // Raw off, its text itself: on its frame alone.
      try await Self.toggle(page, ".artifact-xml-toggle", false)
      try await expect(page.locator(".artifact-under-markup")).toHaveAttribute("data-shown", "false")
      let read = try await page.evaluate(Self.shown, as: Shown.self)
      #expect(read.active == 1 && read.textShown, "at \(width), Raw off, on its frame: \(read)")
      let elsewhere = try await turn(to: "/scan3")
      #expect(elsewhere.active == 0 && !elsewhere.textShown, "at \(width), Raw off, on /scan3: \(elsewhere)")
      let again = try await turn(to: "/scan2")
      #expect(again.active == 1 && again.textShown, "at \(width), Raw off, back on its frame: \(again)")
      try await page.expectNoErrors()
    }
  }

  /// The same on a page the server draws: a scratch overture whose origin
  /// cites a quote typed on frame 2 of a three-frame source served here
  /// (`FixtureServer.threePageManifest`). Its reader opens on frame 2, its
  /// text there; turned to frame 3 its pane is empty; turned back, the
  /// quote again.
  @Test(arguments: [BrowserEngine.chrome])
  func aStoredTypedQuoteReadsOnItsOwnFrameAlone(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    var holder: ScratchOverture?
    do {
      let overture = try ScratchOverture(owner: admin, sealed: false)
      holder = overture
      let source = fixture.baseURL + "/manifest.json"
      let step = UUID().uuidString
      let origins =
        #"[{"id":"\#(step)","relations":["based_on"],"typed":{"title":"Web tests source","voices":[]},"origins":[],"#
        + #""outgoingCitations":[{"id":"\#(UUID().uuidString)","claims":[{"field":"origin","row":"\#(step)"}],"#
        + #""quotes":[{"id":"\#(UUID().uuidString)","anchors":[],"#
        + #""pending":{"sourceURL":"\#(source)","images":[2],"text":"The typedword stood on its frame","title":"Typed frames","language":"eng","class":"play"}}]}]}]"#
      _ = try TestAdmin.query(
        "UPDATE bibliographic_overtures SET origins_json = '\(origins)' WHERE id = '\(overture.overtureID)';")
      try await withPage(engine, gnorium, viewport: Viewport(width: 770, height: 923, deviceScaleFactor: 2), cookies: [admin.cookie]) { page in
        try await page.openHydrated(overture.path)
        let reader = page.locator(".pending-quote-view .artifact-view").first
        try await expect(reader, timeout: .seconds(15)).toBeAttached()
        try await expect(reader).toHaveAttribute("data-markup-frames", "2")
        _ = try await reader.evaluate("(e) => { e.scrollIntoView({ block: 'center' }); return true }")
        let pane = reader.locator(".artifact-markup .tei-page").first
        try await expect(pane, timeout: .seconds(15)).toHaveAttribute("data-service-id", fixture.baseURL + "/page-2")
        try await expect(pane).toHaveAttribute("data-active", "true")
        try await expect(reader.locator(".artifact-markup")).toContainText("typedword")
        func turn(_ control: String, to frame: Int) async throws {
          _ = try await reader.evaluate(
            "(e) => { e.querySelector('.artifact-page-nav .pagination-\(control)-container button').click(); return true }")
          try await expect(pane).toHaveAttribute("data-service-id", fixture.baseURL + "/page-\(frame)")
        }
        try await expect(reader).toHaveAttribute("data-pages-known", "true")
        try await turn("next", to: 3)
        try await expect(pane).toHaveAttribute("data-active", "false")
        try await expect(reader).toHaveAttribute("data-markup-shown", "false")
        try await expect(reader.locator(".artifact-markup [data-layer='rendering']").first).toBeHidden()
        try await turn("previous", to: 2)
        try await expect(pane).toHaveAttribute("data-active", "true")
        try await expect(reader).toHaveAttribute("data-markup-shown", "true")
        try await expect(reader.locator(".artifact-markup [data-layer='rendering']").first).toBeVisible()
        try await expect(reader.locator(".artifact-markup")).toContainText("typedword")
      }
    } catch {
      holder?.remove()
      try await admin.remove(after: error)
    }
    holder?.remove()
    try await admin.remove()
  }
}
