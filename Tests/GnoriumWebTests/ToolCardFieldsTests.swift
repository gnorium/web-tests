import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A tool card is fully transparent (user, 2026-10-07): every key of what
/// the model sent and received is a datum under its raw name, JSON parsed
/// into nested datums—never printed—and a live card reads exactly as the
/// recorded one.
@Suite("Tool card fields", .serialized)
struct ToolCardFieldsTests {
  static let conventions =
    #"{"ok": true, "tool": "read_conventions", "version": "3", "content": "Rule one.\nRule two."}"#
  static let search =
    #"{"ok": true, "tool": "web_search", "engine": "perplexity", "engine_name": "Perplexity", "searches": 1, "pages": [{"title": "Page", "url": "https://example.org/page"}, {"title": "Other", "url": "https://example.org/other"}]}"#
  static let saved =
    #"{"ok": true, "tool": "save_page", "saved": "1", "findings_count": 0, "features": {"blank": ["blank"], "counts": {"lines": 0, "hands": 2}}, "findings": [{"kind": "gap", "flags": [false, true]}]}"#
  static let stub =
    #"{"ok": true, "tool": "read_conventions", "compacted": true, "note": "Stubbed; call again."}"#

  /// Each datum of the card as `depth|label=value`, a group's value `{}`.
  static func signature(_ id: String) -> String {
    """
    (() => {
      const card = document.getElementById('\(id)').closest('.session-tool-call');
      return [...card.querySelectorAll('.accordion-content .datum-view')].map(d => {
        let depth = 0;
        for (let p = d.parentElement; p && p !== card; p = p.parentElement) if (p.classList.contains('tool-field-group')) depth++;
        const label = d.querySelector(':scope > .datum-label').textContent.trim();
        const value = d.classList.contains('tool-field-group') ? '{}' : d.querySelector(':scope > .datum-value').textContent.trim();
        return depth + '|' + label + '=' + value;
      }).join('\\n');
    })()
    """
  }

  static func blocks(prefix: String) -> [[String: String]] {
    [
      ["type": "tool", "name": "read_conventions", "arguments": "{}", "result": conventions, "status": "ok", "call_id": "\(prefix)rc"],
      ["type": "tool", "name": "web_search", "arguments": #"{"query": "sea"}"#, "result": search, "status": "ok", "call_id": "\(prefix)ws"],
      ["type": "tool", "name": "save_page", "arguments": #"{"page": 1}"#, "result": saved, "status": "ok", "call_id": "\(prefix)sp"],
      [
        "type": "compaction", "mode": "micro", "micro": "1", "chars_before": "100", "chars_after": "60",
        "stubbed": "\(prefix)rc\tread_conventions\t{}\t40\t\(stub.utf8.count)\t\(stub)",
      ],
    ]
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func everyKeyIsADatumLiveAsRecorded(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphonID = UUID().uuidString.lowercased()
    let runID = UUID().uuidString.lowercased()
    let name = "tool-fields-live-\(UUID().uuidString).html"
    let file = URL(fileURLWithPath: "/Users/Madhavik/Downloads/Gnorium/gnorium-web/Public").appendingPathComponent(name)
    func cleanUp() {
      try? FileManager.default.removeItem(at: file)
      _ = try? TestAdmin.query(
        "DELETE FROM bibliographic_explication_stage_runs WHERE id='\(runID)'; DELETE FROM bibliographic_antiphons WHERE id='\(antiphonID)';")
      work.remove()
    }
    do {
      let user = try admin.column("id")
      let output = String(
        decoding: try JSONSerialization.data(
          withJSONObject: Self.blocks(prefix: "") + [["type": "text", "content": "Done."]]), as: UTF8.self)
        .replacingOccurrences(of: "'", with: "''")
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, canvas_service_ids_json, processing_status)
          VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO bibliographic_explication_stage_runs (id, submission_id, stage, canvas, attempt, provider, model, output, result, run_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
          VALUES ('\(runID)', (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'),
            'explication', '1', 1, 'DeepSeek', 'deepseek-flash', '\(output)', 'passed', gen_random_uuid(), '\(antiphonID)', 1200, now());
        COMMIT;
        """)
      let antiphon = "/mission-control/antiphons/bibliographic/\(antiphonID)"
      var recorded: [String] = []
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(antiphon)
        // read_conventions: its content—the conventions—under `content`,
        // and every envelope key beside it.
        let conventions = page.locator("#session-tool-rc")
        try await conventions.locator(".accordion-summary").first.click()
        let signature = try await page.evaluate(Self.signature("session-tool-rc"), as: String.self)
        for line in ["0|content=Rule one.\nRule two.", "0|ok=true", "0|tool=read_conventions", "0|version=3"] {
          #expect(signature.contains(line), "read_conventions shows \(line): \(signature)")
        }
        // Its stub, key by key, under the call and on the compaction card.
        #expect(signature.contains("0|note=Stubbed; call again."), "the stub's keys hang under the call: \(signature)")
        #expect(signature.contains("0|compacted=true"))
        let stubLabels = try await page.evaluate(
          "[...document.querySelectorAll('.session-compaction-stubs .datum-label')].map(l => l.textContent.trim()).join(' ')",
          as: String.self)
        #expect(stubLabels == "compacted note ok tool", "The compaction card shows every key of its stub: \(stubLabels)")
        // A web search: its engine and pages under their own keys, one
        // nested group a page.
        let search = try await page.evaluate(Self.signature("session-tool-ws"), as: String.self)
        for line in [
          "0|query=sea", "0|engine=perplexity", "0|engine_name=Perplexity", "0|searches=1",
          "0|pages[0]={}", "1|title=Page", "1|url=https://example.org/page", "0|pages[1]={}", "1|title=Other",
        ] {
          #expect(search.contains(line), "web_search shows \(line): \(search)")
        }
        // Nested objects recurse; an array of plain values is its text;
        // zero is a number and false a boolean; no JSON is printed.
        let saved = try await page.evaluate(Self.signature("session-tool-sp"), as: String.self)
        for line in [
          "0|page=1", "0|findings_count=0", "0|features={}", "1|blank=[\"blank\"]", "1|counts={}", "2|hands=2",
          "2|lines=0", "0|findings[0]={}", "1|flags=[false, true]", "1|kind=gap",
        ] {
          #expect(saved.contains(line), "save_page shows \(line): \(saved)")
        }
        for text in [signature, search, saved] {
          #expect(!text.contains("={\"") && !text.contains("[{"), "No object is printed as JSON: \(text)")
        }
        recorded = [signature, search, saved]
        try await page.expectNoHorizontalOverflow()

        // Live: the same calls streamed in render the same datums.
        let original = try await page.evaluate("fetch('\(antiphon)').then(r=>r.text())", as: String.self)
        let chunks = Self.blocks(prefix: "live_").map { block -> String in
          var block: [String: Any] = block
          block["canvas"] = "1"
          return String(decoding: try! JSONSerialization.data(withJSONObject: block), as: UTF8.self)
        }
        let chunksJS = String(decoding: try JSONSerialization.data(withJSONObject: chunks), as: UTF8.self)
        let mock = """
          <script>
          window.EventSource=class {
            constructor(url) { this.handlers={}; setTimeout(()=>{
              this.emit('start','{}');
              for (const chunk of \(chunksJS)) this.emit('chunk', chunk);
            },500); }
            addEventListener(name,fn) { (this.handlers[name]??=[]).push(fn); }
            emit(name,data) { for(const fn of this.handlers[name]??[])fn({data}); }
            close() {}
          };
          </script>
          """
        try original.replacingOccurrences(of: "<head>", with: "<head>" + mock)
          .replacingOccurrences(of: "data-auto-watch=\"0\"", with: "data-auto-watch=\"1\"")
          .write(to: file, atomically: true, encoding: .utf8)
        try await page.openHydrated("/\(name)")
        try await expect(page.locator("#session-tool-live_sp")).toBeAttached()
        try await expect(page.locator("#session-tool-live_rc .session-tool-stub")).toBeAttached()
        var live: [String] = []
        for id in ["session-tool-live_rc", "session-tool-live_ws", "session-tool-live_sp"] {
          live.append(try await page.evaluate(Self.signature(id), as: String.self))
        }
        #expect(live == recorded, "A live card reads as the recorded one")
        try await page.expectNoErrors()
      }
    } catch {
      cleanUp()
      try await admin.remove(after: error)
    }
    cleanUp()
    try await admin.remove()
  }
}
