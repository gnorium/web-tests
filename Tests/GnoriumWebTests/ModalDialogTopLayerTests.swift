import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A dialog (`DialogView`, an attachment's lightbox among them) is a native
/// `<dialog>` opened with `showModal()`: the top layer holds it over
/// everything on the page, whatever stacking context it was drawn in—here an
/// accordion raised around it (z-index 2, as `:focus-within` raises one) under
/// a sticky sidebar, navbar and footer (z-index 100)—its backdrop the scrim and
/// the page behind inert (user, 2026-10-17: the Mission Control sidebar stayed
/// lit over a madrigal's lightbox). Escape, the backdrop and its close button
/// close it, a drag that only ends on the backdrop does not, and the chip that
/// opened it has the focus again. Runs the real WASM client against the
/// server's markup for a line chip, without a database. Build with
/// `make client` and `make styles` in gnorium-web first.
@Suite("Modal dialog top layer", .serialized)
struct ModalDialogTopLayerTests {
  struct Hit: Decodable {
    let sidebar: String
    let navbar: String
    let footer: String
    let page: String
    let shell: Bool
  }

  /// The server's markup for an image chip one line high and its lightbox
  /// (`ExpandableAttachmentView(.image, presentation: .line)` in
  /// `ModalDialogView`).
  static let chip = """
    <div class="expandable-attachment-view" data-kind="image" data-fallback-src="" data-presentation="line">\
    <button type="button" class="expandable-attachment-trigger expandable-attachment-image-trigger" aria-label="Expand current_image">\
    <img src="/page.svg" alt="current_image" loading="lazy" class="expandable-attachment-image-thumb"/>\
    <span class="expandable-attachment-name">current_image</span></button>\
    <div class="modal-dialog-view expandable-attachment-dialog-host" data-body-scrolls="false">\
    <dialog class="dialog-view modal-dialog expandable-attachment-dialog" aria-labelledby="dialog-title">\
    <div class="dialog-shell"><div class="dialog-header modal-dialog-header" data-default="true">\
    <div class="modal-dialog-header-text"><h2 class="dialog-header-title modal-dialog-title" id="dialog-title">current_image</h2>\
    <span class="expandable-attachment-image-size" aria-live="polite"></span></div>\
    <button type="button" class="button-view close-button-view dialog-close-button" aria-label="Close">×</button></div>\
    <div class="dialog-body"><div class="expandable-attachment-image-viewport">\
    <img src="/page.svg" alt="current_image" loading="lazy" class="expandable-attachment-image-canvas" draggable="false"/>\
    </div></div></div></dialog></div></div>
    """

  /// The page: a sticky navbar, sidebar and footer over the content, the
  /// chip inside an accordion raised above its neighbors, the stylesheets the
  /// server emits.
  static func html(css: String) -> String {
    """
    <!doctype html><html><head><meta charset="utf-8"><link rel="icon" href="data:,">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
    \(css)
    .bar { position: sticky; top: 0; z-index: 100; height: 64px; background: white }
    .frame { display: flex }
    .side { position: sticky; top: 64px; z-index: 100; width: 280px; height: calc(100dvh - 64px); background: white }
    main { flex: 1 }
    .raised { position: relative; z-index: 2; padding: 16px }
    .tall { height: 3000px }
    .foot { position: sticky; bottom: 0; z-index: 100; height: 48px; background: white }
    </style></head><body>
    <nav class="bar"><a id="bar-link" href="#bar">Gnorium</a></nav>
    <div class="frame">
    <aside class="side"><a id="side-link" href="#side">Madrigals</a></aside>
    <main><div class="raised">\(chip)</div><div class="tall"></div></main>
    </div>
    <footer class="foot"><a id="foot-link" href="#foot">Footer</a></footer>
    <script>
    window.dt = {
      dialog: () => document.querySelector('.dialog-view'),
      // What a point is over: "backdrop" for the dialog itself (its
      // ::backdrop), "shell" for what it holds, else the element's id or class.
      at(x, y) {
        const e = document.elementFromPoint(x, y), d = this.dialog();
        return !e ? '' : e === d ? 'backdrop' : d.contains(e) ? 'shell' : (e.id || String(e.className) || e.tagName)
      },
      // Points on the sticky sidebar, navbar and footer and on the page, each
      // outside the shell (16 from the screen's edges, 960 wide at most).
      points: { sidebar: [60, 400], navbar: [60, 32], footer: [60, 776], page: [1100, 400] },
      hits() { const p = this.points; return { sidebar: this.at(...p.sidebar), navbar: this.at(...p.navbar),
        footer: this.at(...p.footer), page: this.at(...p.page), shell: this.at(600, 400) === 'shell' } },
    };
    </script>
    <script src="/loader.js"></script></body></html>
    """
  }

  /// The local server's assets; a cancelled test where the client is not
  /// built.
  static func assets() throws -> (css: String, wasm: URL, loader: Data) {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let assets = root.appendingPathComponent("gnorium-web/Public")
    let wasm = ProcessInfo.processInfo.environment["ARTIFACT_TEST_WASM"]
      .map { URL(fileURLWithPath: $0) } ?? assets.appendingPathComponent("client.wasm")
    let sheets = ["layout-view", "dialog-view", "modal-dialog-view", "expandable-attachment-view"]
      .map { assets.appendingPathComponent("style-sheets/\($0).css") }
    guard FileManager.default.fileExists(atPath: wasm.path),
      FileManager.default.fileExists(atPath: assets.appendingPathComponent("loader.js").path),
      sheets.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) })
    else { try Test.cancel("Build gnorium-web's local client assets with make client and make styles first") }
    return (
      try sheets.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n"),
      wasm,
      try Data(contentsOf: assets.appendingPathComponent("loader.js"))
    )
  }

  /// The page served beside the real client, hydrated.
  static func withChipPage(_ body: @Sendable (Page) async throws -> Void) async throws {
    let assets = try assets()
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="1600"><rect width="1200" height="1600" fill="gainsboro"/></svg>"#
    let server = try await FixtureServer(files: [
      "/": .init(contentType: "text/html", body: Data(Self.html(css: assets.css).utf8)),
      "/loader.js": .init(contentType: "text/javascript", body: assets.loader),
      "/client.wasm": .init(contentType: "application/wasm", body: try Data(contentsOf: assets.wasm)),
      "/page.svg": .init(contentType: "image/svg+xml", body: Data(svg.utf8)),
    ])
    defer { server.stop() }
    let config = BrowserTestConfiguration(
      baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(30))
    try await withPage(.chrome, config, viewport: .init(width: 1200, height: 800)) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      try await expect(page.locator(".expandable-attachment-view")).toHaveAttribute("data-attachment-hydrated", "true")
      try await body(page)
    }
  }

  static func isOpen(_ page: Page) async throws -> Bool {
    try await page.evaluate("window.dt.dialog().matches(':modal')", as: Bool.self)
  }

  static func focusIsOnChip(_ page: Page) async throws -> Bool {
    try await page.evaluate(
      "!!document.activeElement && document.activeElement.classList.contains('expandable-attachment-image-trigger')",
      as: Bool.self)
  }

  static func point(_ page: Page, _ name: String) async throws -> (x: Double, y: Double) {
    let xy = try await page.evaluate("window.dt.points.\(name)", as: [Double].self)
    return (xy[0], xy[1])
  }

  @Test func theLightboxIsAboveEverythingAndThePageBehindIsInert() async throws {
    try await Self.withChipPage { page in
      // Closed, the points are on what they name.
      let before = try await page.evaluate("window.dt.hits()", as: Hit.self)
      #expect(before.sidebar == "side-link" || before.sidebar == "side", "the point is not on the sidebar: \(before.sidebar)")
      #expect(before.navbar == "bar" && before.footer == "foot", "the points are not on the bars: \(before)")

      let chip = page.locator(".expandable-attachment-image-trigger")
      try await chip.click()
      try await expect(page.locator(".dialog-view:modal")).toHaveCount(1)

      // Over the sticky sidebar, navbar and footer and the page: the backdrop;
      // over the shell, the shell.
      let hits = try await page.evaluate("window.dt.hits()", as: Hit.self)
      #expect(hits.sidebar == "backdrop", "the sidebar is over the backdrop: \(hits.sidebar)")
      #expect(hits.navbar == "backdrop", "the navbar is over the backdrop: \(hits.navbar)")
      #expect(hits.footer == "backdrop", "the footer is over the backdrop: \(hits.footer)")
      #expect(hits.page == "backdrop", "the page is over the backdrop: \(hits.page)")
      #expect(hits.shell, "the shell is not on top")

      // The scrim is the backdrop's, its color the token's; the page holds still.
      let scrim = try await page.evaluate(
        "getComputedStyle(window.dt.dialog(), '::backdrop').backgroundColor", as: String.self)
      #expect(scrim != "rgba(0, 0, 0, 0)" && !scrim.isEmpty, "the backdrop has no scrim: \(scrim)")
      #expect(try await page.evaluate("getComputedStyle(document.body).overflow", as: String.self) == "hidden")

      // Inert: nothing behind takes the focus, from a script or from Tab.
      let focused = try await page.evaluate(
        "(() => { document.getElementById('side-link').focus(); return document.activeElement.id })()", as: String.self)
      #expect(focused != "side-link", "the sidebar took the focus behind the dialog")
      for _ in 0..<4 {
        try await page.keyboard.press("Tab")
        let outside = try await page.evaluate(
          "!!document.activeElement && !!document.activeElement.closest('.side, .bar, .foot, .raised > .expandable-attachment-view > .expandable-attachment-trigger')",
          as: Bool.self)
        #expect(!outside, "Tab left the dialog")
      }

      // Escape closes it, and the chip has the focus again.
      try await page.keyboard.press("Escape")
      try await expect(page.locator(".dialog-view[open]")).toHaveCount(0)
      #expect(try await Self.focusIsOnChip(page), "the focus is not back on the chip")
      #expect(try await page.evaluate("getComputedStyle(document.body).overflow", as: String.self) == "visible")
    }
  }

  @Test func theBackdropClosesItButADragEndingOnItDoesNot() async throws {
    try await Self.withChipPage { page in
      let chip = page.locator(".expandable-attachment-image-trigger")
      try await chip.click()
      try await expect(page.locator(".dialog-view:modal")).toHaveCount(1)
      let sidebar = try await Self.point(page, "sidebar")
      let shell = (x: 600.0, y: 400.0)

      // A pan from the image that is let go over the backdrop.
      try await page.mouse.down(x: shell.x, y: shell.y)
      try await page.mouse.move(x: (shell.x + sidebar.x) / 2, y: shell.y)
      try await page.mouse.up(x: sidebar.x, y: sidebar.y)
      try await Task.sleep(for: .milliseconds(100))
      #expect(try await Self.isOpen(page), "a drag that ended on the backdrop closed it")

      // A press on the backdrop, over the sidebar.
      try await page.mouse.click(x: sidebar.x, y: sidebar.y)
      try await expect(page.locator(".dialog-view[open]")).toHaveCount(0)
      #expect(try await Self.focusIsOnChip(page), "the focus is not back on the chip")
      #expect(try await page.evaluate("location.hash", as: String.self) == "", "the press reached the sidebar")

      // Its close button.
      try await chip.click()
      try await expect(page.locator(".dialog-view:modal")).toHaveCount(1)
      try await page.locator(".dialog-close-button").click()
      try await expect(page.locator(".dialog-view[open]")).toHaveCount(0)
      #expect(try await Self.focusIsOnChip(page), "the focus is not back on the chip")
    }
  }
}
