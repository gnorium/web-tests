import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The image never zooms out past its fit (user, 2026-11-01: Hamlet Q1's
/// front cover shrank to a thumbnail in an empty pane): wheeled or pinched
/// out as far as a reader likes, the whole image fits its pane exactly, one
/// side edge to edge. In a split pane, full screen and on a phone. Exercises
/// the real WASM reader with local assets; build with `make client` in
/// gnorium-web before running this suite.
@Suite("Artifact zoom fit", .serialized)
struct ArtifactZoomFitTests {
  struct Shown: Decodable {
    let zoom: Double
    let fit: Double
    /// The image's size on screen, and its pane's.
    let width: Double
    let height: Double
    let paneWidth: Double
    let paneHeight: Double
  }

  struct Pane: Sendable, CustomStringConvertible {
    let name: String
    let width: Int
    let height: Int
    let viewport: Viewport
    var description: String { name }
  }

  static let panes = [
    Pane(name: "split pane", width: 500, height: 600, viewport: .desktop),
    Pane(name: "full screen", width: 1400, height: 900, viewport: .desktop),
    Pane(name: "phone", width: 375, height: 600, viewport: .phone),
  ]

  static let scan = """
    <svg xmlns="http://www.w3.org/2000/svg" width="2820" height="3781" viewBox="0 0 100 100" preserveAspectRatio="none">\
    <rect width="100" height="100" fill="rgb(40,60,58)"/></svg>
    """

  static let shownScript = """
    () => {
      const v = document.querySelector('.frame-view[data-active="true"] .frame-viewport'), vb = v.getBoundingClientRect();
      const t = v.querySelector('.frame-tile-compositor').getAttribute('transform').match(/-?[\\d.]+(e-?\\d+)?/g).map(Number);
      return {zoom: t[2], fit: Math.min(vb.width / 2820, vb.height / 3781), width: 2820 * t[2], height: 3781 * t[2],
        paneWidth: vb.width, paneHeight: vb.height};
    }
    """

  static let gestures = """
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    const viewport = () => document.querySelector('.frame-view[data-active="true"] .frame-viewport');
    const wheel = (dy, fx, fy, ctrlKey) => {
      const v = viewport(), b = v.getBoundingClientRect();
      v.dispatchEvent(new WheelEvent('wheel', {deltaY: dy, ctrlKey, clientX: b.x + b.width * fx, clientY: b.y + b.height * fy, bubbles: true, cancelable: true}));
    };
    const run = async (n, dy, ctrlKey) => { for (let i = 0; i < n; i++) { wheel(dy, 0.4, 0.6, ctrlKey); await sleep(16); } };
    """

  @Test(arguments: panes)
  func theImageNeverZoomsOutPastItsFit(pane: Pane) async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let assets = root.appendingPathComponent("gnorium-web/Public")
    let wasm = ProcessInfo.processInfo.environment["ARTIFACT_TEST_WASM"]
      .map { URL(fileURLWithPath: $0) } ?? assets.appendingPathComponent("client.wasm")
    guard FileManager.default.fileExists(atPath: wasm.path),
      FileManager.default.fileExists(atPath: assets.appendingPathComponent("loader.js").path)
    else { try Test.cancel("Build gnorium-web's local client assets with make client first") }
    let css = try ["layout-view.css", "artifact-view.css", "frame-view.css"].map {
      try String(contentsOf: assets.appendingPathComponent("style-sheets/" + $0), encoding: .utf8)
    }.joined(separator: "\n")
    let w = pane.width, h = pane.height
    let html = """
      <!doctype html><html><head><meta name="viewport" content="width=device-width"><link rel="icon" href="data:,"><style>
      \(css)
      body { margin: 0; }
      .artifact-view { display: flex; flex-direction: column; width: \(w)px; height: \(h)px; border: 0; }
      .artifact-object { width: \(w)px; height: \(h)px; flex: none; display: flex; }
      .frame-view { width: \(w)px; height: \(h)px; }
      .frame-viewport { width: \(w)px; height: \(h)px; position: relative; overflow: hidden; }
      </style></head><body>
      <div class="artifact-view" data-manifest-url="/manifest">
        <div class="artifact-object"><div class="frame-view" data-service-id="/svc/1" data-active="true">
          <div class="frame-viewport"><div class="frame-spinner" data-visible="false"></div></div>
        </div></div>
      </div><script src="/loader.js"></script></body></html>
      """
    let info = #"{"@context":"http://iiif.io/api/image/3/context.json","id":"/svc/1","type":"ImageService3","protocol":"http://iiif.io/api/image","profile":"level2","width":2820,"height":3781,"tiles":[{"width":512,"height":512,"scaleFactors":[1,2,4,8,16,32]}]}"#
    let server = try await FixtureServer(files: [
      "/": .init(contentType: "text/html", body: Data(html.utf8)),
      "/loader.js": .init(contentType: "text/javascript", body: try Data(contentsOf: assets.appendingPathComponent("loader.js"))),
      "/client.wasm": .init(contentType: "application/wasm", body: try Data(contentsOf: wasm)),
      "/manifest": .init(contentType: "application/json", body: Data(#"{"canvases":[{"id":"/svc/1","w":2820,"h":3781,"l":"1"}]}"#.utf8)),
      "/svc/1/info.json": .init(contentType: "application/json", body: Data(info.utf8)),
      "/svc/1/*": .init(contentType: "image/svg+xml", body: Data(Self.scan.utf8)),
    ])
    defer { server.stop() }
    let config = BrowserTestConfiguration(baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(45))
    try await withPage(.chrome, config, viewport: pane.viewport) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      try await expect(page.locator(".frame-tile-image[data-loaded='true']").first).toBeAttached()
      func shown() async throws -> Shown { try await page.evaluate("(\(Self.shownScript))()", as: Shown.self) }
      func gesture(_ body: String) async throws {
        _ = try await page.evaluate("(async () => { \(Self.gestures) \(body); return 1 })()")
      }
      func expectFit(_ s: Shown, _ when: String) {
        #expect(abs(s.zoom - s.fit) <= s.fit * 1e-6, "\(pane) \(when): zoom \(s.zoom), its fit \(s.fit)")
        // The whole image in the pane, one side edge to edge.
        #expect(s.width <= s.paneWidth + 0.5 && s.height <= s.paneHeight + 0.5, "\(pane) \(when): \(s)")
        #expect(abs(s.width - s.paneWidth) <= 0.5 || abs(s.height - s.paneHeight) <= 0.5, "\(pane) \(when): \(s)")
      }
      expectFit(try await shown(), "opened")
      // Out from the fit: the wheel, then a pinch (a wheel with ctrlKey).
      try await gesture("await run(30, 40, false); await run(30, 40, true); await sleep(600)")
      expectFit(try await shown(), "wheeled and pinched out from the fit")
      // In, then far out again: it stops at the fit.
      try await gesture("await run(12, -40, false); await sleep(400)")
      let zoomedIn = try await shown()
      #expect(zoomedIn.zoom > zoomedIn.fit * 1.2, "\(pane): the wheel did not zoom in: \(zoomedIn)")
      try await gesture("await run(60, 40, false); await sleep(600)")
      expectFit(try await shown(), "zoomed in and back out")
    }
  }
}
