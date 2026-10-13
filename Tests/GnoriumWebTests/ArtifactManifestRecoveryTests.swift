import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Artifact manifest recovery", .serialized)
struct ArtifactManifestRecoveryTests {
  @Test(arguments: [#"{"error":"Network error"}"#, #"{"canvases":[],"unread":true}"#])
  func imageButtonRecoversWithoutRefreshing(initial: String) async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let assets = root.appendingPathComponent("gnorium-web/Public")
    let html = #"""
      <!doctype html><html><head><meta charset="utf-8"><link rel="icon" href="data:,"><style>
      .artifact-view { display:flex; } .artifact-markup,.artifact-object { width:500px; height:400px; }
      .artifact-markup { overflow:auto; overflow-anchor:none; } [data-layer] { width:600px; height:1000px; }
      .artifact-view:not([data-canvas-confirmed='true']) .artifact-canvas-toggle { display:none; }
      </style><script>
      // Accelerate only manifest backoff. The fourth attempt remains observable
      // long enough to recover the source after the old three-retry limit.
      const timer = window.setTimeout.bind(window);
      window.setTimeout = (f,ms,...args) => timer(f,ms===30000?500:[4000,8000,16000].includes(ms)?ms/100:ms,...args);
      const fetchOriginal = window.fetch.bind(window); let attempts=0;
      window.fetch = async (...args) => {
        const response = await fetchOriginal(...args);
        if(args[0]==='/manifest') document.documentElement.dataset.manifestAttempts=String(++attempts);
        return response;
      };
      </script></head><body>
      <div class="artifact-view" data-manifest-url="/manifest">
      <div class="artifact-markup"><div class="tei-page" data-service-id="/scan"><div data-layer="rendering">Wording stays readable</div></div></div>
      <div class="artifact-object"></div><div class="artifact-canvas-toggle"><button>Images</button></div>
      </div><script src="/loader.js"></script></body></html>
      """#
    let server = try await FixtureServer(files: [
      "/": .init(contentType: "text/html", body: Data(html.utf8)),
      "/manifest": .init(contentType: "application/json", body: Data(initial.utf8)),
      "/loader.js": .init(contentType: "text/javascript", body: try Data(contentsOf: assets.appendingPathComponent("loader.js"))),
      "/client.wasm": .init(contentType: "application/wasm", body: try Data(contentsOf: assets.appendingPathComponent("client.wasm"))),
    ])
    defer { server.stop() }
    let configuration = BrowserTestConfiguration(baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(15))
    try await withPage(.chrome, configuration, viewport: .desktop) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      try await expect(page.locator("html")).toHaveAttribute("data-manifest-attempts", "4")
      try await expect(page.locator(".artifact-canvas-toggle")).toBeHidden()
      try await expect(page.locator(".tei-page")).toHaveAttribute("data-active", "true")
      server.serve(.init(contentType: "application/json", body: Data(#"{"canvases":[{"id":"/scan","w":1200,"h":2000}]}"#.utf8)), at: "/manifest")
      try await expect(page.locator(".artifact-canvas-toggle")).toBeVisible()
      try await expect(page.locator(".artifact-view")).toHaveAttribute("data-canvas-confirmed", "true")
      try await expect(page).toHaveURL(server.baseURL + "/")
      let attempts = try await page.evaluate("Number(document.documentElement.dataset.manifestAttempts)", as: Int.self)
      #expect(attempts >= 5, "recovery still works after the old retry limit")
      try await page.expectNoErrors()
    }
  }
}
