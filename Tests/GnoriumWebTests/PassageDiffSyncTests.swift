import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Passage diff scrolling", .serialized)
struct PassageDiffSyncTests {
  @Test(arguments: ["textarea", "prompt", "code", "artifact", "artifact-unwrapped"])
  func editorAndDiffTrackCorrespondingWrappedLines(kind: String) async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let assets = root.appendingPathComponent("gnorium-web/Public")
    let text = (1...40).map { "Line \($0): a deliberately long passage that wraps over several visual lines in the narrow editor." }.joined(separator: "\n")
    let rows = (1...40).map { index in
      let line = kind == "artifact-unwrapped" ? "Line \(index): a deliberately long passage that wraps over several visual lines in the narrow editor." : "Line \(index)"
      return "<div class='diff-row' data-diff-at='\(index)'><span class='diff-sign'>+</span><span class='diff-content'>\(line)</span></div>"
    }.joined()
    let codeLines = text.components(separatedBy: "\n").enumerated().map { index, line in
      "<span class='code-line'>\(line)\(index < 39 ? "\n" : "")</span>"
    }.joined()
    let source: String
    switch kind {
    case "prompt":
      source = "<div class='prompt-text-comparison'><fieldset><div class='prompt-text-body scrollport'><pre class='prompt-text-source'>\(text)</pre></div></fieldset><div class='diff-box'>\(rows)</div></div>"
    case "code":
      source = "<form data-revise-form><div class='field-diff-view'><div class='diff-field-input'><div class='code-editor-view'><div class='scrollport'><div style='overflow:auto'><code class='code-code' contenteditable='plaintext-only'>\(text)</code></div></div><textarea hidden>\(text)</textarea></div></div><div class='diff-box'>\(rows)</div></div></form>"
    case "artifact", "artifact-unwrapped":
      source = "<div class='testament-view'><div class='artifact-markup scrollport'><div class='tei-page' data-active='true'><div data-layer='markup'><code class='code-code'>\(codeLines)</code></div></div></div><div class='testament-diff' data-active='true'><div class='resemblance-diff-view diff-view'><div class='diff-box'><div class='diff-lines'>\(rows)</div></div></div></div></div>"
    default:
      source = "<form data-revise-form><div class='field-diff-view'><textarea>\(text)</textarea><div class='diff-box'>\(rows)</div></div></form>"
    }
    let diffCSS = try String(contentsOf: assets.appendingPathComponent("style-sheets/diff-view.css"), encoding: .utf8)
    let html = """
    <!doctype html><html><head><link rel='icon' href='data:,'><style>
    \(diffCSS)
    :root{--spacing-8:8px;--line-height-small-22:22px}
    body{margin:0} fieldset{margin:0;padding:0;border:0}
    textarea,.scrollport{width:280px;height:160px;overflow:auto;font:16px/22px monospace;padding:0;box-sizing:border-box;white-space:pre-wrap;overflow-wrap:break-word}
    pre,code{display:block;white-space:pre-wrap;font:inherit;overflow-wrap:inherit;margin:0}
    .code-line{display:block;padding-inline-start:36px} [data-layer=markup]{zoom:0.75}
    .diff-box{height:160px;overflow:auto;width:280px}.diff-row{height:30px}
    \(kind == "artifact-unwrapped" ? ".scrollport{height:820px} .code-code{white-space:pre} [data-layer=markup]{zoom:1} .diff-row{height:auto} .diff-content{white-space:pre-wrap}" : "")
    </style></head><body>\(source)<script src='/loader.js'></script></body></html>
    """
    let server = try await FixtureServer(files: [
      "/": .init(contentType: "text/html", body: Data(html.utf8)),
      "/loader.js": .init(contentType: "text/javascript", body: try Data(contentsOf: assets.appendingPathComponent("loader.js"))),
      "/client.wasm": .init(contentType: "application/wasm", body: try Data(contentsOf: assets.appendingPathComponent("client.wasm")))
    ])
    defer { server.stop() }
    let config = BrowserTestConfiguration(baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(30))
    try await withPage(.chrome, config, viewport: .desktop) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      try await expect(page.locator("[data-passage-pair]")).toHaveCount(1)
      let result = try await page.evaluate(#"""
      (async()=>{
        const area=document.querySelector('.scrollport') ?? document.querySelector('textarea'), box=document.querySelector('.diff-box');
        const frames=async()=>{for(let i=0;i<10;i++)await new Promise(requestAnimationFrame)};
        area.scrollTop=440;await frames();const editorDrives=box.scrollTop;
        box.scrollTop=600;await frames();const diffDrives=area.scrollTop;
        const values=[];for(let i=0;i<10;i++){await frames();values.push([area.scrollTop,box.scrollTop])}
        area.scrollTop=440;await frames();area.scrollTop=diffDrives;await frames();
        return {editorDrives,diffDrives,values,returned:box.scrollTop,tolerance:1+Math.max(1,(box.scrollHeight-box.clientHeight)/Math.max(1,area.scrollHeight-area.clientHeight))/2,windowY:window.scrollY};
      })()
      """#, as: Result.self)
      #expect(result.editorDrives > 0)
      #expect(result.diffDrives > (kind == "artifact-unwrapped" ? 0 : 440))
      #expect(result.windowY == 0)
      #expect(abs(result.returned - 600) <= result.tolerance, "a user can return to a previously matched position")
      for value in result.values { #expect(abs(value[0] - result.diffDrives) < 1); #expect(abs(value[1] - 600) < 1) }
      if kind == "artifact-unwrapped" {
        let endpoints = try await page.evaluate(#"""
        (async()=>{
          const source=document.querySelector('.scrollport'),box=document.querySelector('.diff-box');
          const frames=async()=>{for(let i=0;i<10;i++)await new Promise(requestAnimationFrame)};
          source.scrollTop=source.scrollHeight;await frames();
          const end=Math.abs(box.scrollTop-(box.scrollHeight-box.clientHeight))<1;
          box.scrollTop=0;await frames();const start=source.scrollTop===0;
          const nowrap=getComputedStyle(box.querySelector('.diff-content')).whiteSpace==='pre';
          document.querySelector('.code-code').style.whiteSpace='pre-wrap';await frames();
          const wrapped=box.dataset.passageWrap==='true';
          return [end,start,nowrap,wrapped];
        })()
        """#, as: [Bool].self)
        #expect(endpoints.allSatisfy { $0 }, "unequal viewports reach both ends together and follow Reflow")
      }
      try await page.expectNoErrors()
    }
  }
  struct Result: Decodable { let editorDrives: Double; let diffDrives: Double; let values: [[Double]]; let windowY: Double; let returned: Double; let tolerance: Double }
}
