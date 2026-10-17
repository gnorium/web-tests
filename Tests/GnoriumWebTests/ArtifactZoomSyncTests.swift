import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Exercises the real WASM reader with local assets, without a database.
/// Build with `make client` in gnorium-web before running this suite.
@Suite("Artifact zoom sync", .serialized)
struct ArtifactZoomSyncTests {
  @Test(arguments: [250, 600])
  func zoomAndScrollStayAtTheLatestGesture(width: Int) async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let assets = root.appendingPathComponent("gnorium-web/Public")
    let wasm = ProcessInfo.processInfo.environment["ARTIFACT_TEST_WASM"]
      .map { URL(fileURLWithPath: $0) } ?? assets.appendingPathComponent("client.wasm")
    guard FileManager.default.fileExists(atPath: wasm.path),
      FileManager.default.fileExists(atPath: assets.appendingPathComponent("loader.js").path)
    else { try Test.cancel("Build gnorium-web's local client assets with make client first") }
    let css = try ["layout-view.css", "tei-view.css", "artifact-view.css"].map {
      try String(contentsOf: assets.appendingPathComponent("style-sheets/" + $0), encoding: .utf8)
    }.joined(separator: "\n")
    let html = """
      <!doctype html><html><head><link rel="icon" href="data:,"><style>
      \(css)
      body { margin: 0; }
      .artifact-view { display: flex; flex-direction: row; gap: 0; padding: 0; border: 0; width: 1000px; }
      .artifact-view .artifact-markup, .artifact-view .artifact-object { width: 500px; height: 400px; flex: none; }
      .tei-view .tei-line { font-family: serif; }
      .artifact-markup { overflow: auto; overflow-anchor: none; }
      [data-layer] { width: \(width)px; height: 1000px; }
      .canvas-viewport { width: 500px; height: 400px; position: relative; overflow: hidden; }
      .canvas-tile-surface { position: absolute; inset: 0; width: 100%; height: 100%; }
      </style></head><body>
      <div class="artifact-view" data-manifest-url="/manifest">
        <div class="artifact-xml-toggle" style="display:none"><button></button></div>
        <div class="artifact-reflow-toggle" style="display:none"><button></button></div>
        <div class="artifact-detach-toggle" style="display:none"><button></button></div>
        <div class="artifact-markup"><div class="tei-view"><div class="tei-page" data-service-id="/scan">
          <div class="tei-page-text" data-layer="rendering"><div class="tei-section">
            <span class="tei-line">Wording</span><span class="tei-line">Second printed line</span>
            <span class="tei-line">Third printed line</span>
          </div></div>
          <div data-layer="markup"><div class="code-view"><pre class="code-code">&lt;pb n="1"/&gt;</pre></div></div>
        </div></div></div>
        <div class="artifact-object"><div class="canvas-view" data-service-id="/scan">
          <div class="canvas-viewport"><div class="canvas-spinner"></div></div>
        </div></div>
      </div><script src="/loader.js"></script></body></html>
      """
    let server = try await FixtureServer(files: [
      "/": .init(contentType: "text/html", body: Data(html.utf8)),
      "/loader.js": .init(contentType: "text/javascript", body: try Data(contentsOf: assets.appendingPathComponent("loader.js"))),
      "/client.wasm": .init(contentType: "application/wasm", body: try Data(contentsOf: wasm)),
      "/manifest": .init(contentType: "application/json", body: Data(#"{"canvases":[{"id":"/scan","w":1200,"h":2000,"imgs":["/scan.svg"]}]}"#.utf8)),
      "/scan.svg": .init(contentType: "image/svg+xml", body: Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="2000"><rect width="1200" height="2000" fill="white"/></svg>"#.utf8)),
    ])
    defer { server.stop() }
    let config = BrowserTestConfiguration(baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(30))
    try await withPage(.chrome, config, viewport: .desktop) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      try await expect(page.locator(".tei-page")).toHaveAttribute("data-active", "true")
      // Read zoom and pan from the actual rendered layers, frame by frame.
      let results = try await page.evaluate(#"""
        (async () => {
          const pane = document.querySelector('.artifact-markup');
          const layer = pane.querySelector('[data-layer]');
          const image = document.querySelector('.canvas-viewport');
          const frame = () => new Promise(resolve => requestAnimationFrame(resolve));
          const settle = async () => { for (let i = 0; i < 12; i++) await frame(); };
          const wheel = (el, deltaY = -40) => {
            const b = el.getBoundingClientRect();
            el.dispatchEvent(new WheelEvent('wheel', {deltaY, clientX: b.x + 250, clientY: b.y + 350, bubbles: true, cancelable: true}));
          };
          const state = () => {
            const b = layer.getBoundingClientRect(), p = pane.getBoundingClientRect();
            const t = document.querySelector('.canvas-tile-compositor').getAttribute('transform');
            const v = t.match(/[-\d.]+/g).map(Number);
            return [Number(layer.dataset.zoom), pane.scrollLeft, pane.scrollTop,
                    (p.x + pane.clientWidth / 2 - b.x) / b.width,
                    (p.y + pane.clientHeight / 2 - b.y) / b.height,
                    v[2], (250 - v[0]) / (1200 * v[2]), (200 - v[1]) / (2000 * v[2])];
          };
          await settle();
          // Cross actual size repeatedly. A zoom changes the scale, never
          // the printed page's dimensions or the relative line positions.
          const shape = () => {
            const b = layer.getBoundingClientRect();
            const z = Number(layer.dataset.zoom);
            const text = layer.firstElementChild?.getBoundingClientRect();
            return [b.width / z, b.height / z, text ? text.height / z : 0];
          };
          const initial = state();
          const pairedFit = initial[0] / (initial[5] / 0.2);
          const natural = shape();
          const shapes = [];
          for (let cycle = 0; cycle < 3; cycle++) {
            for (let i = 0; i < 8; i++) { wheel(pane, 40); await settle(); shapes.push(shape()); }
            for (let i = 0; i < 8; i++) { wheel(pane); await settle(); shapes.push(shape()); }
          }
          for (const size of shapes) {
            for (let i = 0; i < size.length; i++) {
              if (Math.abs(size[i] - natural[i]) > 0.2) throw new Error('page geometry changes during zoom: ' + JSON.stringify({natural,size}));
            }
          }
          // Reset to a predictable scrolled state after the repeated cycle.
          for (let i = 0; i < 12; i++) { wheel(pane, 40); await settle(); }
          await settle();
          for (let i = 0; i < 5; i++) { wheel(pane); await settle(); }
          pane.scrollTop = 500;
          await settle();
          const before = state();
          // Content arriving and repeated layout measurement must preserve pan.
          const samples = [];
          for (let i = 0; i < 12; i++) {
            layer.appendChild(document.createComment('layout'));
            await frame(); samples.push(state());
          }
          await settle();
          const after = state();
          // Opposing queued updates in one frame: wording is the latest input.
          const expectedTextZoom = after[0] * 1.2;
          wheel(image, 40); wheel(pane);
          await settle();
          const wordingWins = state();
          // Then switch the controlling pane: image is the latest input.
          const expectedImageZoom = wordingWins[5] * 1.2;
          wheel(pane, 40); wheel(image);
          await settle();
          const imageWins = state();
          return {before, after, samples, pairedFit, expectedTextZoom, wordingWins, expectedImageZoom, imageWins};
        })()
        """#, as: Results.self)
      #expect(results.before[2] > 100, "fixture reached a scrolled page")
      for sample in results.samples + [results.after] {
        #expect(abs(sample[0] - results.before[0]) < 0.001)
        #expect(abs(sample[1] - results.before[1]) <= 1)
        #expect(abs(sample[2] - results.before[2]) <= 1, "layout measurement must not reset scroll")
        #expect(abs(sample[5] - results.before[5]) < 0.001)
        #expect(abs(sample[7] - results.before[7]) < 0.001)
      }
      #expect(abs(results.wordingWins[0] - results.expectedTextZoom) < 0.001, "latest wording gesture wins")
      #expect(abs(results.imageWins[5] - results.expectedImageZoom) < 0.001, "latest image gesture wins")
      for state in [results.wordingWins, results.imageWins] {
        #expect(abs(state[0] / results.pairedFit - state[5] / 0.2) < 0.01, "zoom stays synchronized with the stable page frame")
        #expect(abs(state[4] - state[7]) < 0.005, "vertical position stays synchronized")
      }
      let modes = try await page.evaluate(#"""
        (async () => {
          const root = document.querySelector('.artifact-view');
          const pane = root.querySelector('.artifact-markup');
          const rendering = pane.querySelector('[data-layer="rendering"]');
          const settle = async () => { for(let i=0;i<12;i++) await new Promise(r=>requestAnimationFrame(r)); };
          const toggle = async (name,value) => {
            root.querySelector(name).dispatchEvent(new CustomEvent('toggle-button-update',{detail:value?'true':'false'}));
            await settle();
          };
          await toggle('.artifact-xml-toggle', true);
          const code = pane.querySelector('[data-layer="markup"]');
          const raw = getComputedStyle(rendering).display === 'none'
            && code.dataset.zoom === '1' && getComputedStyle(code).zoom === '1';
          await toggle('.artifact-xml-toggle', false);
          const rendered = pane.querySelector('[data-page-scale]') !== null && rendering.getBoundingClientRect().height > 0;
          await toggle('.artifact-reflow-toggle', true);
          const reflow = pane.querySelector('[data-page-scale]') === null && getComputedStyle(rendering).transform === 'none';
          await toggle('.artifact-reflow-toggle', false);
          const restored = pane.querySelector('[data-page-scale]') !== null && rendering.getBoundingClientRect().height > 0;
          const wait = ms => new Promise(resolve=>setTimeout(resolve,ms));
          await toggle('.artifact-detach-toggle', false); await wait(500);
          const imageZoom = () => Number(root.querySelector('.canvas-tile-compositor').getAttribute('transform').match(/[-\d.]+/g)[2]);
          const baseline = Number(rendering.dataset.zoom);
          const pairedRatio = baseline/imageZoom();
          await toggle('.artifact-detach-toggle', true);
          const wheel = () => {
            const b=pane.getBoundingClientRect();
            pane.dispatchEvent(new WheelEvent('wheel',{deltaY:-40,clientX:b.x+250,clientY:b.y+200,bubbles:true,cancelable:true}));
          };
          wheel(); await settle(); const enlarged = Number(rendering.dataset.zoom);
          root.querySelector('.artifact-detach-toggle').dispatchEvent(new CustomEvent('toggle-button-update',{detail:'false'}));
          await wait(90); const middle=Number(rendering.dataset.zoom);
          await wait(500); const matched=Number(rendering.dataset.zoom);
          const animated=enlarged>middle && middle>matched && Math.abs(matched-baseline)<.005;
          await toggle('.artifact-detach-toggle', true); wheel(); await settle();
          root.querySelector('.artifact-detach-toggle').dispatchEvent(new CustomEvent('toggle-button-update',{detail:'false'}));
          await wait(90); wheel(); await settle();const readerZoom=Number(rendering.dataset.zoom);
          await wait(500);const cancelled=Math.abs(Number(rendering.dataset.zoom)-readerZoom)<.005 && Math.abs(imageZoom()-readerZoom/pairedRatio)<.005;
          return [raw,rendered,reflow,restored,animated,cancelled];
        })()
        """#, as: [Bool].self)
      #expect(modes.allSatisfy { $0 }, "Raw and Reflow leave and restore the scaled frame correctly")
      try await page.expectNoErrors()
    }
  }

  private struct Results: Decodable {
    let before: [Double]
    let after: [Double]
    let samples: [[Double]]
    let pairedFit: Double
    let expectedTextZoom: Double
    let wordingWins: [Double]
    let expectedImageZoom: Double
    let imageWins: [Double]
  }
}
