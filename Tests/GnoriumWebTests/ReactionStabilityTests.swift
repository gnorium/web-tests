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
      <!doctype html><html><head><meta charset="utf-8"><link rel="icon" href="data:,"><link rel="stylesheet" href="/reaction-picker.css"><style>
      :root{--spacing-4:4px;--border-width-base:1px;--border-color-subtle:rgb(185,185,185);--border-radius-base:12px;--background-color-base:white;--font-family-emoji:serif;--transition-duration-medium:250ms;--transition-timing-function-user:ease-out;--transition-property-fade:opacity}
      body { margin: 0; } .reactions-view { display:flex; flex-direction:column; gap:4px; }
      .reaction-picker-view { display:contents; }
      button { height:40px; } .reactions-chips button { height:32px; }
      </style></head><body><div style="height:900px">Locution above</div>
      <div class="reactions-view" data-reaction-id="fixture">
      <div class="reactions-controls"><div class="reaction-picker-view">
      <button class="reaction-picker-trigger" aria-controls="react-fixture-choices" aria-label="Add reaction">Add reaction</button>
      </div><button>Raw</button></div>
      <div class="reaction-picker-view"><div class="reaction-picker-choices" id="react-fixture-choices" hidden>
      <div class="reaction-picker-choices-content"><form action="/react/thumb" method="post"><button type="submit">👍</button></form></div>
      </div></div><div class="reactions-actions"><a href="#reply">Reply</a></div></div>
      <div style="height:1000px">Locution below</div><script src="/loader.js"></script></body></html>
      """
    let fragment = """
      <div class="reactions-view"><div class="reactions-chips"><span class="reactions-reaction">
      <form action="/react/thumb" method="post"><button class="reactions-emoji-button" aria-pressed="true">👍 1</button></form>
      </span></div></div>
      """
    let server = try await FixtureServer(files: [
      "/": .init(contentType: "text/html", body: Data(html.utf8)),
      "/reaction-picker.css": .init(contentType: "text/css", body: try Data(contentsOf: assets.appendingPathComponent("style-sheets/reaction-picker-view.css"))),
      "/loader.js": .init(contentType: "text/javascript", body: try Data(contentsOf: assets.appendingPathComponent("loader.js"))),
      "/client.wasm": .init(contentType: "application/wasm", body: try Data(contentsOf: assets.appendingPathComponent("client.wasm"))),
      "/react/thumb": .init(contentType: "text/html", body: Data(fragment.utf8)),
    ])
    defer { server.stop() }
    let configuration = BrowserTestConfiguration(baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(30))
    try await withPage(.chrome, configuration, viewport: .desktop) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      let motion = try await page.evaluate(#"""
        (async()=>{
          const trigger=document.querySelector('.reaction-picker-trigger'), panel=document.querySelector('.reaction-picker-choices'), content=panel.firstElementChild;
          const wait=ms=>new Promise(r=>setTimeout(r,ms));
          const sample=()=>({height:panel.getBoundingClientRect().height,border:getComputedStyle(panel).outlineWidth,opacity:Number(getComputedStyle(content).opacity)});
          trigger.click();await wait(100);const opening=sample();await wait(300);const full=sample();
          trigger.click();await wait(100);const closing=sample();await wait(300);const hidden=panel.hidden;
          trigger.click();await wait(60);trigger.click();await wait(50);trigger.click();await wait(400);
          const reopened=!panel.hidden && panel.classList.contains('reaction-picker-settled') && panel.getBoundingClientRect().height===full.height;trigger.click();await wait(400);
          return {opening,full,closing,hidden,reopened};
        })()
        """#, as: Motion.self)
      #expect(motion.opening.height > 0 && motion.opening.height < motion.full.height)
      #expect(motion.closing.height > 0 && motion.closing.height < motion.full.height)
      #expect(motion.opening.border == "1px" && motion.closing.border == "1px")
      #expect(motion.opening.opacity > 0 && motion.opening.opacity < 1)
      #expect(motion.closing.opacity > 0 && motion.closing.opacity < 1)
      #expect(motion.hidden && motion.reopened)
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
  struct Motion: Decodable {
    struct Sample: Decodable { let height: Double; let border: String; let opacity: Double }
    let opening: Sample; let full: Sample; let closing: Sample; let hidden: Bool; let reopened: Bool
  }
}
