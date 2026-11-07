import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A quote typed against a source's frames (user, 2026-11-05) traces none of
/// them: nothing keeps its text on the image's part of the page. Beside its
/// frame its one line opens at its start, its first word at the pane's
/// edge, never scrolled to the image's middle; scrolled by the reader, it
/// stays where they put it, the frame unmoved.
@Suite("Typed quote beside frames", .serialized)
struct TypedQuoteFramesTests {
  static let quote =
    "Found by Sir H. E. Bunbury at Barton, 1823, in volume containing other quartos; probably belonged to his grandfather, Sir William Bunbury."

  /// The reader as a pending quote's is drawn (`TestamentView`
  /// `followsImages`, `typedText`): its page follows the frame on screen,
  /// the canvas slot the manifest's, its text one line as typed, the quote
  /// violet; Reflow in its footer, no Detach or Overlay.
  static func server() async throws -> FixtureServer {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let assets = root.appendingPathComponent("gnorium-web/Public")
    let css = try ["layout-view.css", "tei-view.css", "artifact-view.css", "frame-view.css"].map {
      try String(contentsOf: assets.appendingPathComponent("style-sheets/" + $0), encoding: .utf8)
    }.joined(separator: "\n")
    let html =
      "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><style>"
      + css + #"""
      body{margin:0}.artifact-view{width:100%;height:600px}.artifact-viewer-container{height:520px;flex:none}.tei-page-text{display:inline-block;white-space:pre;font-family:serif!important}</style><link rel="icon" href="data:,"></head><body><div class="artifact-view" data-manifest-url="/manifest" data-canvas-shown="true" data-markup-follows-canvas="true" data-typed-text="true" data-start-canvas="0"><div class="artifact-viewer-container"><div class="artifact-markup-viewport"><div class="artifact-markup-box"><div class="artifact-markup"><div class="tei-view"><div class="tei-page" data-service-id="" data-active="true"><div class="tei-page-text" data-layer="rendering"><span class="tei-highlight" data-highlight="sentence">
      """# + quote + #"""
      </span></div></div></div></div></div></div><div class="artifact-object"></div></div><footer class="artifact-footer"><div class="artifact-footer-start"><div class="artifact-reflow-toggle"><button>Reflow</button></div></div></footer></div><script src="/loader.js"></script></body></html>
      """#
    var files: [String: FixtureServer.File] = [
      "/": .init(contentType: "text/html", body: Data(html.utf8)),
      "/loader.js": .init(
        contentType: "text/javascript", body: try Data(contentsOf: assets.appendingPathComponent("loader.js"))),
      "/client.wasm": .init(
        contentType: "application/wasm", body: try Data(contentsOf: assets.appendingPathComponent("client.wasm"))),
      "/manifest": .init(
        contentType: "application/json",
        body: Data(#"{"canvases":[{"id":"/scan","w":1200,"h":2000,"imgs":["/scan.svg"]}]}"#.utf8)),
      "/scan.svg": .init(
        contentType: "image/svg+xml",
        body: Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="2000"/>"#.utf8)),
      "/fonts/noto-sans.woff2": .init(
        contentType: "font/woff2", body: try Data(contentsOf: assets.appendingPathComponent("fonts/noto-sans.woff2"))),
    ]
    // The built stylesheets the client asks for as it draws (`loader.js`).
    let sheets = assets.appendingPathComponent("style-sheets")
    for name in try FileManager.default.contentsOfDirectory(atPath: sheets.path)
    where name.hasSuffix(".css") || name.hasSuffix(".json") {
      files["/style-sheets/\(name)"] = .init(
        contentType: name.hasSuffix(".css") ? "text/css" : "application/json",
        body: try Data(contentsOf: sheets.appendingPathComponent(name)))
    }
    return try await FixtureServer(files: files)
  }

  @Test(arguments: [1440, 440])
  func aTypedQuoteOpensAtItsStart(width: Int) async throws {
    let server = try await Self.server()
    defer { server.stop() }
    let config = BrowserTestConfiguration(
      baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(30))
    try await withPage(.chrome, config, viewport: .init(width: width, height: 700)) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      // Its page follows the frame on screen, the frame drawn beside it.
      try await expect(page.locator(".tei-page")).toHaveAttribute("data-service-id", "/scan")
      try await expect(page.locator(".artifact-object [data-service-id='/scan']")).toHaveAttribute("data-active", "true")
      // Past a match's frame and its 400ms ease.
      try await page.evaluate("new Promise(resolve=>setTimeout(resolve,900))")
      let checks = try await page.evaluate(
        #"""
        (async()=>{
          const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms)),r=document.querySelector('.artifact-view');
          const pane=r.querySelector('.artifact-markup'),surface=()=>r.querySelector('.frame-tile-surface');
          const out=[];
          out.push(pane.scrollWidth>pane.clientWidth+40);
          out.push(pane.scrollLeft<=1);
          // Scrolled by the reader: it stays, and the frame does not follow.
          const before=surface()?.style.transform??'';
          pane.scrollLeft=120;
          await wait(400);
          out.push(Math.abs(pane.scrollLeft-120)<=1);
          out.push((surface()?.style.transform??'')===before);
          return out;
        })()
        """#, as: [Bool].self)
      let named = [
        "its line wider than its pane", "opened at its start, never matched to the frame",
        "scrolled by the reader, it stays", "the frame does not follow the text",
      ]
      #expect(checks.count == named.count, "\(checks)")
      for (check, name) in zip(checks, named) { #expect(check, "\(name)") }
      try await page.expectNoErrors()
    }
  }
}
