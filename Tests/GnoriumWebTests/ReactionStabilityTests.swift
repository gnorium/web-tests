import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Real WASM hydration with a local reaction response; no accounts or live data.
@Suite("Reaction stability")
struct ReactionStabilityTests {
  @Test
  func pickingAnEmojiUpdatesInPlaceAndKeepsTheControlRowStill() async throws {
    let workspace = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let assets = workspace.appendingPathComponent("gnorium-web/Public")
    guard FileManager.default.fileExists(atPath: assets.appendingPathComponent("client.wasm").path)
    else { try Test.cancel("Build the local client with make client first") }
    let html = """
      <!doctype html><html><head><meta charset="utf-8"><link rel="icon" href="data:,"><style>
      body { margin: 0; } .reactions-view { display:flex; flex-direction:column; gap:4px; }
      .reaction-picker-view { display:contents; } .reaction-picker-choices-content { display:flex; }
      button { height:40px; } .reactions-chips button { height:32px; }
      </style></head><body><div style="height:900px">Locution above</div>
      <div class="reactions-view" data-reaction-id="fixture">
      <div class="reaction-picker-view"><div class="reaction-picker-choices" id="react-fixture-choices" hidden>
      <div class="reaction-picker-choices-content"><form action="/react/thumb" method="post"><button type="submit">👍</button></form></div>
      </div></div><div class="reactions-controls"><div class="reaction-picker-view">
      <button class="reaction-picker-trigger" aria-controls="react-fixture-choices" aria-label="Add reaction">Add reaction</button>
      </div><button>Raw</button></div><div class="reactions-actions"><a href="#reply">Reply</a></div></div>
      <div style="height:1000px">Locution below</div><script src="/loader.js"></script></body></html>
      """
    let fragment = """
      <div class="reactions-view"><div class="reactions-chips"><span class="reactions-reaction">
      <form action="/react/thumb" method="post"><button class="reactions-emoji-button" aria-pressed="true">👍 1</button></form>
      </span></div></div>
      """
    let server = try await FixtureServer(files: [
      "/": .init(contentType: "text/html", body: Data(html.utf8)),
      "/loader.js": .init(contentType: "text/javascript", body: try Data(contentsOf: assets.appendingPathComponent("loader.js"))),
      "/client.wasm": .init(contentType: "application/wasm", body: try Data(contentsOf: assets.appendingPathComponent("client.wasm"))),
      "/react/thumb": .init(contentType: "text/html", body: Data(fragment.utf8)),
    ])
    defer { server.stop() }
    let configuration = BrowserTestConfiguration(baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(30))
    try await withPage(.chrome, configuration, viewport: .desktop) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      try await page.getByRole(.button, name: "Add reaction").click()
      try await expect(page.locator(".reaction-picker-choices")).toBeVisible()
      let before = try await page.evaluate("""
        (async () => {
          for(let i=0;i<30;i++) await new Promise(r=>requestAnimationFrame(r));
          return document.querySelector('.reactions-controls').getBoundingClientRect().top;
        })()
        """, as: Double.self)
      try await page.locator(".reaction-picker-choices button").click()
      try await expect(page.locator(".reactions-emoji-button")).toHaveText("👍 1")
      try await expect(page.locator(".reaction-picker-choices")).toBeHidden()
      try await expect(page).toHaveURL(server.baseURL + "/")
      let after = try await page.evaluate("document.querySelector('.reactions-controls').getBoundingClientRect().top", as: Double.self)
      #expect(abs(before - after) <= 1, "the control row does not jump when reacting")
      try await expect(page.getByRole(.link, name: "Reply")).toHaveCount(1)
      try await expect(page.getByRole(.button, name: "Raw")).toHaveCount(1)
      try await page.expectNoErrors()
    }
  }
}
