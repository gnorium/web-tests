import Foundation
import Network
import Testing
import WebTests
import WebTestsTesting

/// The reader against an image host that has gone bad, as the Internet
/// Archive's IIIF did for one book (user report, 2026-10-17): every region
/// request hangs and is answered 504 a minute on, the whole image answers
/// at some widths and hangs at others. Exercises the real WASM reader with
/// local assets, without a database. Build with `make client` in
/// gnorium-web before running this suite.
@Suite("Artifact degraded host", .serialized)
struct ArtifactDegradedHostTests {
  /// An image host that misbehaves on demand, and counts what it is asked.
  final class DegradedHost: @unchecked Sendable {
    struct Request: Sendable {
      let path: String
      let startedAt: Date
      var heldFor: TimeInterval?
      var answered: Bool
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "web-tests.degraded-host")
    private let lock = NSLock()
    private var requests: [Request] = []
    private(set) var port: UInt16 = 0
    /// Widths of the whole image that never answer.
    var hungWidths: Set<Int> = []
    /// What a region request gets: hang (a 504 a minute on) or an answer.
    var regionsHang = true

    var baseURL: String { "http://127.0.0.1:\(port)" }

    init() async throws {
      let parameters = NWParameters.tcp
      parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
      listener = try NWListener(using: parameters)
      listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
      let listener = self.listener
      port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, any Error>) in
        let box = Once()
        listener.stateUpdateHandler = { state in
          switch state {
          case .ready: if box.claim() { continuation.resume(returning: listener.port?.rawValue ?? 0) }
          case .failed(let error): if box.claim() { continuation.resume(throwing: error) }
          default: break
          }
        }
        listener.start(queue: queue)
      }
    }

    func stop() { listener.cancel() }

    var seen: [Request] {
      lock.lock()
      defer { lock.unlock() }
      return requests
    }

    private func serve(_ connection: NWConnection) {
      connection.start(queue: queue)
      connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self] data, _, _, _ in
        let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
        let target = request.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init) ?? "/"
        let path = String(target.split(separator: "?", maxSplits: 1).first ?? "/")
        lock.lock()
        requests.append(Request(path: path, startedAt: Date(), heldFor: nil, answered: false))
        let index = requests.count - 1
        lock.unlock()
        // The client abandons a request: the connection closes, which a read
        // sees as its end.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [self] _, _, isComplete, error in
          if isComplete || error != nil { release(index, answered: false) }
        }
        let isRegion = path.range(of: #"/\d+,\d+,\d+,\d+/"#, options: .regularExpression) != nil
        let width = path.range(of: #"/full/(\d+),/"#, options: .regularExpression)
          .flatMap { Int(path[$0].split(separator: "/")[1].dropLast()) }
        if path.hasSuffix("/info.json") {
          reply(connection, index, 200, "application/json", Data(Self.info(base: baseURL, path: path).utf8), after: 0.2)
        } else if isRegion && regionsHang {
          // Held until the client gives up, or a minute on, a 504.
          queue.asyncAfter(deadline: .now() + 60) { [self] in
            reply(connection, index, 504, "text/html", Data("<h1>504</h1>".utf8), after: 0)
          }
        } else if let width, hungWidths.contains(width) {
          queue.asyncAfter(deadline: .now() + 60) { [self] in
            reply(connection, index, 504, "text/html", Data("<h1>504</h1>".utf8), after: 0)
          }
        } else {
          let size = width ?? 512
          let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="\#(size)" height="\#(size * 4 / 3)"><rect width="100%" height="100%" fill="rgb(204,204,221)"/></svg>"#
          reply(connection, index, 200, "image/svg+xml", Data(svg.utf8), after: 0.3)
        }
      }
    }

    private func reply(_ connection: NWConnection, _ index: Int, _ status: Int, _ type: String, _ body: Data, after: TimeInterval) {
      queue.asyncAfter(deadline: .now() + after) { [self] in
        guard !isReleased(index) else { return }
        var head = "HTTP/1.1 \(status) X\r\nContent-Type: \(type)\r\nAccess-Control-Allow-Origin: *\r\n"
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { [self] _ in
          release(index, answered: true)
          connection.cancel()
        })
      }
    }

    private func isReleased(_ index: Int) -> Bool {
      lock.lock()
      defer { lock.unlock() }
      return requests[index].heldFor != nil
    }

    private func release(_ index: Int, answered: Bool) {
      lock.lock()
      defer { lock.unlock() }
      guard requests[index].heldFor == nil else { return }
      requests[index].heldFor = Date().timeIntervalSince(requests[index].startedAt)
      requests[index].answered = answered
    }

    private static func info(base: String, path: String) -> String {
      let service = String(path.dropLast("/info.json".count))
      return #"{"@context":"http://iiif.io/api/image/3/context.json","id":"\#(base)\#(service)","type":"ImageService3","protocol":"http://iiif.io/api/image","profile":"level2","width":2820,"height":3781,"tiles":[{"width":512,"height":512,"scaleFactors":[1,2,4,8,16,32]}]}"#
    }

    private final class Once: @unchecked Sendable {
      private let lock = NSLock()
      private var done = false
      func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
      }
    }
  }

  struct Outcome: Decodable {
    let best: Int
    let tiles: Int
    let loadedTiles: Int
    let zoom: Double
    let spinner: String
  }

  /// The page: the real reader over one canvas of the bad host.
  static func page(root: URL, host: DegradedHost) async throws -> (server: FixtureServer, wasm: URL)? {
    let assets = root.appendingPathComponent("gnorium-web/Public")
    let wasm = ProcessInfo.processInfo.environment["ARTIFACT_TEST_WASM"]
      .map { URL(fileURLWithPath: $0) } ?? assets.appendingPathComponent("client.wasm")
    guard FileManager.default.fileExists(atPath: wasm.path),
      FileManager.default.fileExists(atPath: assets.appendingPathComponent("loader.js").path)
    else { return nil }
    let css = try ["layout-view.css", "artifact-view.css", "image-view.css"].map {
      try String(contentsOf: assets.appendingPathComponent("style-sheets/" + $0), encoding: .utf8)
    }.joined(separator: "\n")
    let service = "\(host.baseURL)/svc/1"
    let html = """
      <!doctype html><html><head><link rel="icon" href="data:,"><style>
      \(css)
      body { margin: 0; }
      .artifact-view { display: flex; flex-direction: column; width: 1000px; height: 820px; }
      .artifact-object { width: 1000px; height: 800px; flex: none; display: flex; }
      .image-view { width: 1000px; height: 800px; }
      .image-viewport { width: 1000px; height: 800px; position: relative; overflow: hidden; }
      .image-tile-surface { position: absolute; inset: 0; width: 100%; height: 100%; }
      </style></head><body>
      <div class="artifact-view" data-manifest-url="/manifest">
        <div class="artifact-object"><div class="image-view" data-service-id="\(service)" data-active="true">
          <div class="image-viewport"><div class="image-spinner" data-visible="false"></div></div>
        </div></div>
      </div><script src="/loader.js"></script></body></html>
      """
    let server = try await FixtureServer(files: [
      "/": .init(contentType: "text/html", body: Data(html.utf8)),
      "/loader.js": .init(contentType: "text/javascript", body: try Data(contentsOf: assets.appendingPathComponent("loader.js"))),
      "/client.wasm": .init(contentType: "application/wasm", body: try Data(contentsOf: wasm)),
      "/manifest": .init(
        contentType: "application/json",
        body: Data(#"{"canvases":[{"id":"\#(service)","w":2820,"h":3781,"l":"1"}]}"#.utf8)),
    ])
    return (server, wasm)
  }

  /// What the page shows of the image: the widest image loaded across the
  /// whole of it, read from the address each image was asked for.
  static let outcomeScript = """
    (() => {
      const v = document.querySelector('.image-view[data-active="true"] .image-viewport');
      const images = [...v.querySelectorAll('.image-tile-image')];
      let best = 0, tiles = 0, loadedTiles = 0;
      for (const i of images) {
        const href = i.getAttribute('href') || '', loaded = i.getAttribute('data-loaded') === 'true';
        let m;
        if ((m = href.match(/\\/full\\/(\\d+),/))) { if (loaded) best = Math.max(best, Number(m[1])); }
        else if (/\\/\\d+,\\d+,\\d+,\\d+\\//.test(href)) { tiles++; if (loaded) loadedTiles++; }
      }
      const zoom = Number(v.querySelector('.image-tile-compositor').getAttribute('transform').match(/-?[\\d.]+/g)[2]);
      return {best, tiles, loadedTiles, zoom, spinner: v.querySelector('.image-spinner').dataset.visible};
    })()
    """

  @Test func tilesThatHangDoNotStarveTheReaderAndTheWholeImageStandsIn() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let host = try await DegradedHost()
    defer { host.stop() }
    // Every region hangs, as on the Archive; whole images answer.
    host.regionsHang = true
    guard let (server, _) = try await Self.page(root: root, host: host) else {
      try Test.cancel("Build gnorium-web's local client assets with make client first")
    }
    defer { server.stop() }
    let config = BrowserTestConfiguration(baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(45))
    try await withPage(.chrome, config, viewport: .desktop) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      // The first copies are on screen.
      try await expect(page.locator(".image-view[data-active='true'] .image-tile-image[data-loaded='true']").first).toBeAttached()
      // Zoomed in to the actual size, where tiles are what the image asks for.
      _ = try await page.evaluate(
        """
        (async () => {
          const v = document.querySelector('.image-viewport'), b = v.getBoundingClientRect();
          for (let i = 0; i < 14; i++) {
            v.dispatchEvent(new WheelEvent('wheel', {deltaY: -40, clientX: b.x + 500, clientY: b.y + 400, bubbles: true, cancelable: true}));
            await new Promise(r => setTimeout(r, 16));
          }
          return 1;
        })()
        """)
      func isRegion(_ request: DegradedHost.Request) -> Bool {
        request.path.range(of: #"/\d+,\d+,\d+,\d+/"#, options: .regularExpression) != nil
      }
      // Tiles the host has never answered go one at a time—the one that
      // tests it—while the whole image at its full width stands in: the
      // image is sharp at once, the region hangs alone.
      var outcome = Outcome(best: 0, tiles: 0, loadedTiles: 0, zoom: 0, spinner: "")
      let deadline = Date().addingTimeInterval(20)
      while Date() < deadline {
        outcome = try await page.evaluate(Self.outcomeScript, as: Outcome.self)
        if outcome.best == 2820 { break }
        try await Task.sleep(for: .milliseconds(250))
      }
      #expect(outcome.best == 2820, "the whole image stands in at the width the zoom shows: \(outcome)")
      #expect(outcome.loadedTiles == 0, "no tile arrived from a host that hangs them")
      #expect(outcome.spinner == "false")
      // More of the same view: still the one region out, no other asked for.
      for _ in 0..<6 {
        _ = try await page.evaluate(
          """
          (() => { const v = document.querySelector('.image-viewport'), b = v.getBoundingClientRect();
            v.dispatchEvent(new WheelEvent('wheel', {deltaY: 40, clientX: b.x + 500, clientY: b.y + 400, bubbles: true, cancelable: true}));
            v.dispatchEvent(new WheelEvent('wheel', {deltaY: -40, clientX: b.x + 500, clientY: b.y + 400, bubbles: true, cancelable: true})); return 1 })()
          """)
        try await Task.sleep(for: .milliseconds(400))
      }
      let regions = host.seen.filter(isRegion)
      #expect(regions.count == 1, "one region tests the host, the rest wait for its answer: \(regions.map(\.path))")
      #expect(regions.allSatisfy { $0.heldFor == nil }, "the test is let run to its end, never cut")
      // Nothing the reader asked for was a region but that one, or the image's max.
      #expect(!host.seen.contains { $0.path.contains("/max/") }, "no max asked for")
    }
  }
}
