import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Prompt Markdown layout", .serialized)
struct PromptMarkdownLayoutTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func renderedReadingAndExactRawSource(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    guard let path = ProcessInfo.processInfo.environment["GNORIUM_PROMPT_FIXTURE_PATH"],
      FileManager.default.fileExists(atPath: path) else {
      try Test.cancel("Export the native prompt fixture with GNORIUM_PROMPT_FIXTURE_PATH first.")
    }
    let html = try Data(contentsOf: URL(fileURLWithPath: path))
    // Serve on the app's origin so the real WASM client can load without CORS.
    let name = "prompt-layout-\(UUID().uuidString).html"
    let publicFile = URL(fileURLWithPath: "/Users/Madhavik/Downloads/Gnorium/gnorium-web/Public").appendingPathComponent(name)
    try html.write(to: publicFile)
    defer { try? FileManager.default.removeItem(at: publicFile) }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/\(name)")
      let view = page.locator(".prompt-text-view").first
      let rendered = view.locator(".prompt-text-rendered")
      let source = view.locator(".prompt-text-source")
      try await expect(rendered).toBeVisible()
      try await expect(source).toBeHidden()
      try await expect(rendered.locator("strong")).toHaveText("selected")
      try await expect(rendered.locator("pre code")).toContainText("{page}")
      let original = try await source.textContent()
      #expect(original.contains("**selected**"))
      let geometry = try await page.evaluate("""
        (() => {
          const content = document.querySelector('.mission-control-prompt-content');
          const sections = [...content.querySelectorAll(':scope > .prompt-section')];
          const crumbs = [...document.querySelectorAll('.breadcrumb-label, .breadcrumb-current')].map(e => e.textContent.trim());
          const expected = ['Mission Control', 'Prompts', 'Bibliographic', 'Bibliographic Explication'];
          let index = -1;
          const ordered = expected.every(label => { index = crumbs.indexOf(label, index + 1); return index >= 0; });
          return getComputedStyle(content).gap === '24px'
            && sections.length === 2
            && sections.every(s => getComputedStyle(s).gap === '16px')
            && ordered
            && document.querySelectorAll('.prompt-text-body script').length === 0;
        })()
        """, as: Bool.self)
      #expect(geometry)
      // The rendered prose on Raw's 16 on 22 (user, 2026-10-14): switching
      // never changes the size or the leading; inline code follows the prose.
      let sizes = try await page.evaluate("""
        (() => {
          const view = document.querySelector('.prompt-text-view');
          const size = e => { const s = getComputedStyle(e); return s.fontSize + '/' + s.lineHeight; };
          const prose = [...view.querySelectorAll('.prompt-text-rendered, .prompt-text-rendered p')].map(size);
          const code = [...view.querySelectorAll('.prompt-text-rendered p code')].map(e => getComputedStyle(e).fontSize);
          return JSON.stringify({ prose: [...new Set(prose)], code: [...new Set(code)],
            raw: size(view.querySelector('.prompt-text-source')),
            h2: size(view.querySelector('.prompt-text-rendered h2')),
            label: size(view.querySelector('.prompt-text-rendered .code-block-lang')) });
        })()
        """, as: String.self)
      #expect(sizes == #"{"prose":["16px/22px"],"code":["16px"],"raw":"16px/22px","h2":"20px/30px","label":"16px/22px"}"#, "Prompt prose at 16 on 22: \(sizes)")
      try await view.locator(".prompt-text-markdown-toggle button").click()
      try await expect(source).toBeVisible()
      try await expect(rendered).toBeHidden()
      #expect(try await source.textContent() == original, "Switching never rewrites source")
      try await view.locator(".prompt-text-markdown-toggle button").click()
      try await expect(rendered).toBeVisible()
      #expect(try await source.textContent() == original)
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }

  /// A process's prompt read rendered sets its lines as Raw does (user,
  /// 2026-10-14): Raw's 16/22 leading, blocks one Raw line apart (the blank
  /// line between them), a list's items none.
  @Test(arguments: [BrowserEngine.chrome])
  func renderedPromptKeepsTheSourcesLeading(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: .desktop) { page in
      try await page.openHydrated("/mission-control/prompts/bibliographic/explication")
      let view = page.locator(".prompt-text-view").first
      try await expect(view.locator(".prompt-text-rendered")).toBeVisible()
      let metrics = try await page.evaluate("""
        (() => {
          const view = document.querySelector('.prompt-text-view');
          const rendered = view.querySelector('.prompt-text-rendered');
          const list = rendered.querySelector('ul, ol');
          const p = rendered.querySelector('p');
          const s = getComputedStyle(rendered);
          return JSON.stringify({ leading: getComputedStyle(p).lineHeight, gap: s.rowGap,
            list: list ? getComputedStyle(list).rowGap : '0px',
            raw: getComputedStyle(view.querySelector('.prompt-text-source')).lineHeight });
        })()
        """, as: String.self)
      #expect(metrics == #"{"leading":"22px","gap":"22px","list":"0px","raw":"22px"}"#, "rendered prompt metrics: \(metrics)")
      try await page.expectNoErrors()
    }
  }
}
