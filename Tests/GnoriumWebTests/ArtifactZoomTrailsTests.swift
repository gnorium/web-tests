import CoreGraphics
import Foundation
import ImageIO
import Testing
import WebTests
import WebTestsTesting

/// Zooming the scan in, panning it to an edge and zooming it back out leaves
/// nothing of the earlier views behind (user report, Safari, 2026-10-17:
/// thin strips of the page's edge at many places across the empty margin
/// beside the image). Exercises the real WASM reader with local assets, with
/// the reader's own styles and without a database. Build with `make client`
/// in gnorium-web before running this suite.
@Suite("Artifact zoom trails", .serialized)
struct ArtifactZoomTrailsTests {
  struct Moment: Decodable {
    let name: String
    let zoom: Double
    /// The image's rectangle in the window (left, top, right, bottom), and
    /// its viewport's.
    let image: [Double]
    let viewport: [Double]
    /// Every image on the surface that is not inside the image's rectangle.
    let outside: [String]
    /// How many region tiles and whole images are on the surface.
    let tiles: Int
    let wholes: Int
    let windowHeight: Double
  }

  /// The scan: cream, with a dark band down each edge, so that an edge left
  /// behind is as visible as a book's spine.
  static let scan = """
    <svg xmlns="http://www.w3.org/2000/svg" width="2820" height="3781" viewBox="0 0 100 100" preserveAspectRatio="none">\
    <rect width="100" height="100" fill="rgb(216,207,174)"/>\
    <rect width="3" height="100" fill="rgb(90,58,26)"/><rect x="97" width="3" height="100" fill="rgb(90,58,26)"/></svg>
    """

  /// What the surface holds, read from where each image is on the window.
  static let momentScript = """
    (name) => {
      const v = document.querySelector('.image-view[data-active="true"] .image-viewport'), vb = v.getBoundingClientRect();
      const g = v.querySelector('.image-tile-compositor');
      const t = g.getAttribute('transform').match(/-?[\\d.]+(e-?\\d+)?/g).map(Number);
      const image = [vb.left + t[0], vb.top + t[1], vb.left + t[0] + 2820 * t[2], vb.top + t[1] + 3781 * t[2]];
      const outside = [];
      let tiles = 0, wholes = 0;
      for (const i of v.querySelectorAll('.image-tile-image')) {
        const href = i.getAttribute('href') || '';
        if (/\\/\\d+,\\d+,\\d+,\\d+\\//.test(href)) tiles++; else wholes++;
        const r = i.getBoundingClientRect();
        if (r.width === 0) continue;
        if (r.left < image[0] - 1.01 || r.top < image[1] - 1.01 || r.right > image[2] + 1.01 || r.bottom > image[3] + 1.01) {
          outside.push(href.replace(/^.*\\/svc\\/\\d+\\//, '') + ' ' + [r.left, r.top, r.right, r.bottom].map(Math.round).join(','));
        }
      }
      return {name, zoom: t[2], image, viewport: [vb.left, vb.top, vb.right, vb.bottom], outside, tiles, wholes, windowHeight: innerHeight};
    }
    """

  /// A reader's gestures: the wheel zooming about a point, a drag panning.
  static let gestures = """
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    const viewport = () => document.querySelector('.image-view[data-active="true"] .image-viewport');
    const wheel = (dy, fx, fy) => {
      const v = viewport(), b = v.getBoundingClientRect();
      v.dispatchEvent(new WheelEvent('wheel', {deltaY: dy, clientX: b.x + b.width * fx, clientY: b.y + b.height * fy, bubbles: true, cancelable: true}));
    };
    const run = async (n, dy, fx, fy) => { for (let i = 0; i < n; i++) { wheel(dy, fx, fy); await sleep(16); } };
    const drag = async (dx, dy) => {
      const v = viewport(), b = v.getBoundingClientRect(), x0 = b.x + b.width / 2, y0 = b.y + b.height / 2;
      v.dispatchEvent(new MouseEvent('mousedown', {clientX: x0, clientY: y0, bubbles: true, cancelable: true}));
      for (let i = 1; i <= 20; i++) {
        window.dispatchEvent(new MouseEvent('mousemove', {clientX: x0 + dx * i / 20, clientY: y0 + dy * i / 20, bubbles: true}));
        await sleep(16);
      }
      window.dispatchEvent(new MouseEvent('mouseup', {clientX: x0 + dx, clientY: y0 + dy, bubbles: true}));
    };
    """

  @Test func nothingIsLeftBesideTheImageAfterZoomingInAndOut() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let assets = root.appendingPathComponent("gnorium-web/Public")
    let wasm = ProcessInfo.processInfo.environment["ARTIFACT_TEST_WASM"]
      .map { URL(fileURLWithPath: $0) } ?? assets.appendingPathComponent("client.wasm")
    guard FileManager.default.fileExists(atPath: wasm.path),
      FileManager.default.fileExists(atPath: assets.appendingPathComponent("loader.js").path)
    else { try Test.cancel("Build gnorium-web's local client assets with make client first") }
    let css = try ["layout-view.css", "artifact-view.css", "image-view.css"].map {
      try String(contentsOf: assets.appendingPathComponent("style-sheets/" + $0), encoding: .utf8)
    }.joined(separator: "\n")
    // The reader's styles as they are, the viewport only given its size.
    let html = """
      <!doctype html><html><head><link rel="icon" href="data:,"><style>
      \(css)
      body { margin: 0; }
      .artifact-view { display: flex; flex-direction: column; width: 1000px; height: 600px; border: 0; }
      .artifact-object { width: 1000px; height: 600px; flex: none; display: flex; }
      .image-view { width: 1000px; height: 600px; }
      .image-viewport { width: 1000px; height: 600px; position: relative; overflow: hidden; }
      </style></head><body>
      <div class="artifact-view" data-manifest-url="/manifest">
        <div class="artifact-object"><div class="image-view" data-service-id="/svc/1" data-active="true">
          <div class="image-viewport"><div class="image-spinner" data-visible="false"></div></div>
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
    try await withPage(.chrome, config, viewport: .desktop) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      try await expect(page.locator(".image-tile-image[data-loaded='true']").first).toBeAttached()
      func moment(_ name: String) async throws -> Moment {
        try await page.evaluate("(\(Self.momentScript))('\(name)')", as: Moment.self)
      }
      func gesture(_ body: String) async throws {
        _ = try await page.evaluate("(async () => { \(Self.gestures) \(body); return 1 })()")
      }
      // In to the actual size about a point, panned to the page's top left, out in turns, then to the fit.
      try await gesture("await run(16, -40, 0.7, 0.3); await sleep(1500)")
      let zoomedIn = try await moment("zoomed in")
      try await gesture("await drag(2000, 2000); await sleep(800)")
      let panned = try await moment("panned to the corner")
      try await gesture(
        """
        for (let k = 0; k < 3; k++) {
          await run(8, 40, 0.2, 0.15); await sleep(500);
          await run(4, -40, 0.2, 0.15); await sleep(500);
        }
        await run(24, 40, 0.2, 0.15); await sleep(2500)
        """)
      let atFit = try await moment("back at the fit")
      for shown in [zoomedIn, panned, atFit] {
        #expect(shown.outside.isEmpty, "\(shown.name): images beside the image's rectangle \(shown.image): \(shown.outside)")
      }
      // The tiles of the levels left are gone once a whole image shows what they showed.
      #expect(atFit.tiles == 0, "tiles of an earlier level are still on the surface at the fit: \(atFit.tiles)")
      #expect(atFit.wholes <= 3, "the surface holds the image's copies of earlier levels: \(atFit.wholes)")
      // And the margins beside the image are one colour.
      let scale = try await page.evaluate("window.devicePixelRatio", as: Double.self)
      let png = try await page.screenshot()
      let result = try #require(Self.marginsAreUniform(png, scale: scale, moment: atFit), "the screenshot could not be read")
      #expect(result.checked > 1000, "the margins beside the image were not read: \(result.checked) pixels")
      #expect(result.off == 0, "pixels of something other than the background beside the image: \(result.off) of \(result.checked), first \(result.sample)")
    }
  }

  /// The pixels of the viewport beside the image (its rectangle, and a
  /// couple of pixels about it, left out, as are the viewport's own edges)
  /// against the colour of its empty corner.
  static func marginsAreUniform(_ png: Data, scale: Double, moment: Moment) -> (checked: Int, off: Int, sample: String)? {
    guard let source = CGImageSourceCreateWithData(png as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    let width = image.width
    let height = image.height
    var buffer = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = buffer.withUnsafeMutableBytes { bytes -> Bool in
      guard
        let context = CGContext(
          data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return nil }
    func pixel(_ x: Int, _ y: Int) -> [Int] {
      let at = (y * width + x) * 4
      return [Int(buffer[at]), Int(buffer[at + 1]), Int(buffer[at + 2])]
    }
    let inset = 16.0
    let top = moment.viewport[1] + inset
    let bottom = min(moment.viewport[3], moment.windowHeight) - inset
    let corner = pixel(Int((moment.viewport[0] + inset) * scale), Int(top * scale))
    var checked = 0
    var off = 0
    var sample = ""
    let beside: [(Double, Double)] = [
      (moment.viewport[0] + inset, moment.image[0] - 2), (moment.image[2] + 2, moment.viewport[2] - inset),
    ]
    for (left, right) in beside where right > left {
      for y in Int(top * scale)..<min(height, Int(bottom * scale)) {
        for x in Int(left * scale)..<min(width, Int(right * scale)) {
          checked += 1
          let value = pixel(x, y)
          if zip(value, corner).contains(where: { abs($0 - $1) > 8 }) {
            off += 1
            if sample.isEmpty { sample = "(\(x), \(y)) \(value) against \(corner)" }
          }
        }
      }
    }
    return (checked, off, sample)
  }
}
