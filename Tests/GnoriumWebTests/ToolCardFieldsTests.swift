import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A tool card is fully transparent (user, 2026-10-07): every key of what
/// the model sent and received is a datum under its raw name, JSON parsed
/// into nested datums—never printed—in the JSON's own key order, and a
/// live card reads exactly as the recorded one. White is what the model
/// produces, gray what it is given (user, 2026-10-10): every card is a
/// plain white container, an argument datum is white, and a result, a
/// stub, the tools it is offered are gray boxes of gray datums—never a
/// depth's alternating tint. Markup it sent or read is code. Bookkeeping
/// blocks (usage, any unknown type) show nowhere, Raw included.
@Suite("Tool card fields", .serialized)
struct ToolCardFieldsTests {
  static let toolDefinitions =
    #"[{"type":"function","function":{"name":"read_conventions","description":"The exact recorded conventions tool.","parameters":{"type":"object","properties":{"section":{"type":"string","description":"Section as requested."}},"additionalProperties":false},"strict":true}},{"type":"function","function":{"name":"web_search","description":"Search the recorded web sources.","parameters":{"type":"object","properties":{"query":{"type":"string"}}}}},{"type":"function","function":{"name":"save_page","description":"Save this page with its original schema.","parameters":{"type":"object","properties":{"page":{"type":"integer"}}}}},{"type":"function","function":{"name":"write_tei","description":"Write the page's TEI.","parameters":{"type":"object","properties":{"tei":{"type":"string"}}}}}]"#

  static let conventions =
    #"{"ok": true, "tool": "read_conventions", "version": "3", "content": "Rule one.\nRule two."}"#
  static let search =
    #"{"ok": true, "tool": "web_search", "engine": "perplexity", "engine_name": "Perplexity", "searches": 1, "pages": [{"title": "Page", "url": "https://example.org/page"}, {"title": "Other", "url": "https://example.org/other"}]}"#
  static let saved =
    #"{"ok": true, "tool": "save_page", "saved": "1", "findings_count": 0, "note": null, "features": {"blank": ["blank"], "counts": {"lines": 0, "hands": 2}}, "findings": [{"kind": "gap", "flags": [false, true]}]}"#
  static let tei = (1...40).map { #"<p n="\#($0)">Line \#($0)</p>"# }.joined(separator: "\n")
  static let written = #"{"ok": true, "tool": "write_tei", "tei_len": 1200}"#
  static let stub =
    #"{"ok": true, "tool": "read_conventions", "compacted": true, "note": "Stubbed; call again."}"#
  static let usage =
    #"[{"stage":"explication","call_id":"model_1","provider":"DeepSeek","model":"deepseek-flash","input_tokens":23172,"output_tokens":1381,"reasoning_tokens":1241,"cost_usd":0.05463,"latency_ms":30312.5,"started_at":1,"finished_at":2}]"#

  /// Each datum of the card as `depth|label=value`, a group's value `{}`.
  static func signature(_ id: String) -> String {
    """
    (() => {
      const card = document.getElementById('\(id)').closest('.computorium-session-tool-call');
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

  struct Wrappers: Decodable {
    let count: Int
    let bare: Bool
    let flush: Bool
  }

  struct Grounds: Decodable {
    let thinking: Bool
    let argument: Bool
    let box: Bool
    let result: Bool
    let cardCount: Int
    let boxCount: Int
    let cardsOff: String
    let boxesOff: String
    let surfaces: Int
  }

  /// The labels under `selector`, in document order.
  static func labels(_ selector: String) -> String {
    "[...document.querySelectorAll('\(selector) .datum-label')].map(l => l.textContent.trim()).join(' ')"
  }

  static func blocks(prefix: String) -> [[String: String]] {
    [
      ["type": "tools", "content": toolDefinitions],
      ["type": "thinking", "content": String(repeating: "Thinking through the recorded page.\n\n", count: 80)],
      ["type": "usage", "content": usage],
      ["type": "tool", "name": "read_conventions", "arguments": "{}", "result": conventions, "status": "ok", "call_id": "\(prefix)rc"],
      ["type": "tool", "name": "web_search", "arguments": #"{"query": "sea"}"#, "result": search, "status": "ok", "call_id": "\(prefix)ws"],
      ["type": "tool", "name": "save_page", "arguments": #"{"page": 1}"#, "result": saved, "status": "ok", "call_id": "\(prefix)sp"],
      ["type": "tool", "name": "web_search", "arguments": #"{"query": "x"}"#, "result": #"{"ok": false, "error": "timed out"}"#, "status": "error", "call_id": "\(prefix)fx"],
      ["type": "draft", "content": #"{"bookkeeping": "never shown"}"#],
      [
        "type": "compaction", "mode": "micro", "micro": "1", "chars_before": "100", "chars_after": "60",
        "stubbed": "\(prefix)rc\tread_conventions\t{}\t40\t\(stub.utf8.count)\t\(stub)",
      ],
      ["type": "thinking", "content": "Writing the page."],
      [
        "type": "tool", "name": "write_tei",
        "arguments": String(decoding: try! JSONSerialization.data(withJSONObject: ["tei": tei]), as: UTF8.self),
        "result": written, "status": "ok", "call_id": "\(prefix)wt",
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
        #expect(try await page.evaluate("""
          (() => {
            const body = document.querySelector('.computorium-session-output-thinking-body');
            return getComputedStyle(body).maxHeight === '256px' && getComputedStyle(body).overflowY === 'auto'
              && body.clientHeight <= 256 && body.scrollHeight > body.clientHeight;
          })()
          """, as: Bool.self), "Thinking remains an inner 256px scrollport")
        let session = page.locator(".computorium-session-view")
        // The header's status chip keeps its own vocabulary: a submitted
        // antiphon's is green (user, 2026-10-10).
        #expect(try await page.evaluate("""
          (() => {
            const chip = document.querySelector('.computorium-core-header-status-chip')
            const probe = document.createElement('span'); document.body.append(probe)
            probe.style.color = 'var(--color-green)'; const green = getComputedStyle(probe).color; probe.remove()
            return chip.classList.contains('info-chip-green') && chip.textContent.trim() === 'Submitted'
              && getComputedStyle(chip.querySelector('.info-chip-text') || chip).color === green
          })()
          """, as: Bool.self), "The Submitted chip is green")
        // The tools the model is offered go with every request, so the
        // Tools card opens every round: before the first thinking, and
        // before the thinking and the text that follow a tool result.
        let tools = session.locator(".computorium-session-tools")
        try await expect(tools).toHaveCount(3)
        try await expect(tools.first.locator(".accordion-title")).toHaveText("Tools")
        #expect(try await page.evaluate(
          "!document.querySelector('.computorium-session-tools details').hasAttribute('open')", as: Bool.self),
          "The Tools card is collapsed by default, like a compaction card")
        try await tools.first.locator(".accordion-summary").first.click()
        try await expect(tools.first.locator(".tool-result-box-view")).toHaveCount(4)
        let toolsLabels = try await page.evaluate(
          "[...document.querySelector('.computorium-session-tools .tool-result-box-view').querySelectorAll('.datum-label')].map(l => l.textContent.trim()).join(' ')",
          as: String.self)
        #expect(
          toolsLabels == "name description parameters type properties section type description additionalProperties strict",
          "A tool's schema, every key in the JSON's own order: \(toolsLabels)")
        // The transcript's order: Tools, thinking, the calls, the
        // compaction, Tools, thinking, the write, Tools, the text.
        let orderJS = """
          [...document.querySelector('.computorium-session-output-content').querySelectorAll(
            '.computorium-session-tools, .computorium-session-output-thinking, .computorium-session-tool-call, .computorium-session-compaction, .computorium-session-output-rendered')]
            .map(e => e.className.replace('computorium-session-', '').split(' ')[0]).join(' ')
          """
        let order = try await page.evaluate(orderJS, as: String.self)
        #expect(order == "tools output-thinking tool-call tool-call tool-call tool-call compaction tools output-thinking tool-call tools output-rendered", "Stream order: \(order)")
        try await expect(session.locator(".computorium-session-tool-call-definition")).toHaveCount(0)
        // read_conventions: its content—the conventions—under `content`,
        // and every envelope key beside it, as the JSON wrote them.
        let conventions = page.locator("#computorium-session-tool-rc")
        try await conventions.locator(".accordion-summary").first.click()
        let signature = try await page.evaluate(Self.signature("computorium-session-tool-rc"), as: String.self)
        #expect(
          signature.hasPrefix("0|ok=true\n0|tool=read_conventions\n0|version=3\n0|content=Rule one.\nRule two."),
          "read_conventions shows every key in the JSON's order: \(signature)")
        // The card keeps the result as the model read it, then one line
        // down to the compaction that stubbed it; the stub itself, key by
        // key in one gray box, sits on the compaction card, where the
        // model received it (stream order is time order).
        #expect(signature.hasSuffix("0|content=Rule one.\nRule two."), "the call keeps only its original result: \(signature)")
        #expect(!signature.contains("compacted"), "the stub's keys are not repeated under the call: \(signature)")
        try await expect(conventions.locator(".computorium-session-tool-stub .link-view")).toHaveText("stubbed by microcompaction · 40 → 91 chars")
        try await expect(conventions.locator(".computorium-session-tool-stub .datum-view")).toHaveCount(0)
        try await expect(page.locator(".computorium-session-compaction-stubs li > .tool-result-box-view")).toHaveCount(1)
        try await expect(page.locator(".computorium-session-compaction-stubs li .link-view")).toHaveAttribute("href", "#computorium-session-tool-rc")
        let stubLabels = try await page.evaluate(Self.labels(".computorium-session-compaction-stubs"), as: String.self)
        #expect(stubLabels == "ok tool compacted note", "The compaction card shows every key of its stub, in order: \(stubLabels)")
        let gray = try await page.evaluate("""
          (() => {
            const box = document.querySelector('.computorium-session-compaction-stubs li > .tool-result-box-view');
            const result = document.querySelector('#computorium-session-tool-rc').closest('.computorium-session-tool-call').querySelector('.computorium-session-tool-call-result-box');
            return getComputedStyle(box).backgroundColor === getComputedStyle(result).backgroundColor
              && getComputedStyle(box).borderTopWidth === getComputedStyle(result).borderTopWidth;
          })()
          """, as: Bool.self)
        #expect(gray, "A stub sits on the same gray box a result does")
        // White sends, gray sees: the thinking card, every card, and an
        // argument datum on the page's base ground; the result box gray
        // and its datums the read-only field's gray; no card alternates
        // by depth (user, 2026-10-10).
        let grounds = try await page.evaluate("""
          (() => {
            const probe = document.createElement('span'); document.body.append(probe)
            const token = (name) => { probe.style.backgroundColor = 'var(--background-color-' + name + ')'; return getComputedStyle(probe).backgroundColor }
            const [white, seen, field] = [token('base'), token('neutral-subtle'), token('disabled')]; probe.remove()
            const bg = (el) => getComputedStyle(el).backgroundColor
            const cards = [...document.querySelectorAll('.computorium-session-output-thinking-rendered, .computorium-session-tool-call-rendered, .computorium-session-tools-rendered, .computorium-session-compaction-rendered')]
            const thinking = document.querySelector('.computorium-session-output-thinking-rendered')
            const argument = document.querySelector('#computorium-session-tool-ws .computorium-session-tool-call-args .datum-view > .datum-value')
            const resultBox = document.querySelector('#computorium-session-tool-ws .computorium-session-tool-call-result-box')
            const result = resultBox.querySelector('.datum-view > .datum-value')
            const boxes = [...document.querySelectorAll('.tool-result-box-view')]
            return {
              thinking: bg(thinking) === white, argument: bg(argument) === white,
              box: bg(resultBox) === seen, result: bg(result) === field && field !== white,
              cardCount: cards.length, boxCount: boxes.length,
              cardsOff: cards.filter(c => bg(c) !== white).map(c => c.className + '=' + bg(c)).join(','),
              boxesOff: boxes.filter(b => bg(b) !== seen).map(b => b.className + '=' + bg(b)).join(','),
              surfaces: document.querySelectorAll('.computorium-session-view .surface').length,
            }
          })()
          """, as: Grounds.self)
        #expect(grounds.thinking, "The thinking card is white: \(grounds)")
        #expect(grounds.argument, "An argument datum is white: \(grounds)")
        #expect(grounds.box && grounds.result, "A result box and its datums are gray: \(grounds)")
        #expect(grounds.cardCount >= 11 && grounds.cardsOff.isEmpty, "No card alternates: every card white: \(grounds)")
        #expect(grounds.boxCount >= 5 && grounds.boxesOff.isEmpty, "Every seen box gray: \(grounds)")
        #expect(grounds.surfaces == 0, "The transcript takes no depth tint: \(grounds)")
        // A card header's dot is its own vocabulary (never the roster's
        // marks): green for a call that came back, red for one that
        // failed, orange for a compaction (user, 2026-10-10).
        #expect(try await page.evaluate("""
          (() => {
            const probe = document.createElement('span'); document.body.append(probe)
            const tone = (name) => { probe.style.color = 'var(--color-' + name + ')'; return getComputedStyle(probe).color }
            const [green, red, orange] = [tone('green'), tone('red'), tone('orange')]; probe.remove()
            const color = (id) => getComputedStyle(document.getElementById(id).closest('.computorium-session-tool-call').querySelector('.computorium-session-tool-call-mark .icon-view')).color
            const compaction = getComputedStyle(document.querySelector('.computorium-session-compaction-mark .icon-view')).color
            return [color('computorium-session-tool-rc') === green, color('computorium-session-tool-fx') === red, compaction === orange].join(' ')
          })()
          """, as: String.self) == "true true true", "ok green, failed red, compaction orange")
        // The call's inputs and what came back stand 16 apart, further
        // than the 8 between the datums inside either (user, 2026-10-10).
        #expect(try await page.evaluate("""
          (() => {
            const card = document.querySelector('#computorium-session-tool-rc').closest('.computorium-session-tool-call');
            const content = card.querySelector('.accordion-content');
            const fields = card.querySelector('.computorium-session-tool-call-args');
            return getComputedStyle(content).rowGap + ' ' + (fields ? getComputedStyle(fields).rowGap : '8px');
          })()
          """, as: String.self) == "16px 8px", "Inputs and output 16 apart, datums 8")
        // A web search: its engine and pages under their own keys, one
        // nested group a page.
        let search = try await page.evaluate(Self.signature("computorium-session-tool-ws"), as: String.self)
        for line in [
          "0|query=sea", "0|engine=perplexity", "0|engine_name=Perplexity", "0|searches=1",
          "0|pages[0]={}", "1|title=Page", "1|url=https://example.org/page", "0|pages[1]={}", "1|title=Other",
        ] {
          #expect(search.contains(line), "web_search shows \(line): \(search)")
        }
        // Nested objects recurse; an array of plain values is its text;
        // zero is a number and false a boolean; no JSON is printed.
        let saved = try await page.evaluate(Self.signature("computorium-session-tool-sp"), as: String.self)
        for line in [
          "0|page=1", "0|findings_count=0", "0|note=null", "0|features={}", "1|blank=[\"blank\"]", "1|counts={}", "2|lines=0",
          "2|hands=2", "0|findings[0]={}", "1|kind=gap", "1|flags=[false, true]",
        ] {
          #expect(saved.contains(line), "save_page shows \(line): \(saved)")
        }
        #expect(saved.contains("2|lines=0\n2|hands=2"), "Nested keys keep the JSON's order: \(saved)")
        // Every value kind—string, number, boolean, null, array of plain
        // values—is the field's content directly: no wrapper inside the
        // value box. A multi-line string is plain mono text at the field's
        // inset, no box in the box; only markup is a code view, flush.
        let wrappers = try await page.evaluate("""
          (() => {
            const plain = [...document.querySelectorAll('#computorium-session-tool-sp .datum-view:not(.tool-field-group) > .datum-value')];
            const bare = plain.every(v => v.children.length === 1 && v.firstElementChild.classList.contains('datum-text') && v.firstElementChild.children.length === 0);
            const block = document.querySelector('#computorium-session-tool-rc .tool-field-block');
            const field = block.closest('.datum-value');
            const cs = getComputedStyle(block);
            const flush = cs.borderTopWidth === '0px' && cs.backgroundColor === 'rgba(0, 0, 0, 0)' && cs.paddingTop === '0px'
              && block.getBoundingClientRect().top - field.getBoundingClientRect().top <= 10
              && field.getBoundingClientRect().bottom - block.getBoundingClientRect().bottom <= 10;
            return { count: plain.length, bare, flush };
          })()
          """, as: Wrappers.self)
        #expect(wrappers.count >= 8 && wrappers.bare, "Plain values have no inner wrapper: \(wrappers)")
        #expect(wrappers.flush, "A multi-line value is mono text at the field's inset, no box: \(wrappers)")
        // Markup the model sent is code: colored XML, the full width of its
        // datum, capped at 256 and scrolled inside.
        let write = page.locator("#computorium-session-tool-wt")
        try await write.locator(".accordion-summary").first.click()
        let markup = try await page.evaluate("""
          (() => {
            const datum = document.querySelector('#computorium-session-tool-wt .computorium-session-tool-call-args .tool-field-markup');
            const code = datum.querySelector('.code-view');
            const value = datum.querySelector(':scope > .datum-value');
            return !!code.querySelector('.code-code.language-xml')
              && Math.abs(code.getBoundingClientRect().width - value.getBoundingClientRect().width) <= 2.5
              && getComputedStyle(code).maxHeight === '256px' && getComputedStyle(code).overflowY === 'auto'
              && code.clientHeight <= 256 && code.scrollHeight > code.clientHeight
              && code.querySelectorAll('.hljs-tag').length > 0
              && code.getBoundingClientRect().top - value.getBoundingClientRect().top <= 1.5
              && code.querySelector('.code-code').getBoundingClientRect().top - value.getBoundingClientRect().top <= 10
              && value.getBoundingClientRect().bottom - code.getBoundingClientRect().bottom <= 1.5;
          })()
          """, as: Bool.self)
        #expect(markup, "A tei argument is a CodeView: xml, full width, capped at 256")
        for text in [signature, search, saved] {
          #expect(!text.contains("={\"") && !text.contains("[{"), "No object is printed as JSON: \(text)")
        }
        // Bookkeeping the model never saw is nowhere: not between the
        // cards, not under Raw.
        let content = session.locator(".computorium-session-output-content")
        try await expect(content).not.toContainText("input_tokens")
        try await expect(content).not.toContainText("bookkeeping")
        try await expect(session.locator(".computorium-session-raw-toggle[data-toggle-hydrated='true']")).toHaveCount(1)
        try await session.locator(".computorium-session-raw-toggle button").click()
        try await expect(session.locator(".computorium-session-output-fieldset")).toHaveAttribute("data-raw-view", "true")
        try await expect(content).not.toContainText("input_tokens")
        try await expect(content).not.toContainText("bookkeeping")
        try await expect(session.locator(".computorium-session-tools-raw").first).toBeVisible()
        try await expect(session.locator(".computorium-session-tools-raw").first).toContainText("read_conventions")
        try await session.locator(".computorium-session-raw-toggle button").click()
        recorded = [signature, search, saved]
        try await page.expectNoHorizontalOverflow()

        // Live: the same stream frames render the same datums, the Tools
        // card at every round, and nothing for bookkeeping.
        let original = try await page.evaluate("fetch('\(antiphon)').then(r=>r.text())", as: String.self)
        let chunks = (Self.blocks(prefix: "live_") + [["type": "text", "content": "Done."]]).map { block -> String in
          var block: [String: Any] = block
          if block["type"] as? String != "tool", block["type"] as? String != "compaction" {
            block["text"] = block["content"]
          }
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
        try await expect(page.locator("#computorium-session-tool-live_wt")).toBeAttached()
        try await expect(page.locator("#computorium-session-tool-live_rc .computorium-session-tool-stub .link-view")).toBeAttached()
        try await expect(page.locator("#computorium-session-tool-live_rc .computorium-session-tool-stub .datum-view")).toHaveCount(0)
        var live: [String] = []
        for id in ["computorium-session-tool-live_rc", "computorium-session-tool-live_ws", "computorium-session-tool-live_sp"] {
          live.append(try await page.evaluate(Self.signature(id), as: String.self))
        }
        #expect(live == recorded, "A live card reads as the recorded one")
        let liveOrder = try await page.evaluate(orderJS, as: String.self)
        #expect(liveOrder == order, "The live transcript keeps the recorded order: \(liveOrder)")
        try await expect(page.locator(".computorium-session-tools .tool-result-box-view").first).toBeAttached()
        try await expect(page.locator("#computorium-session-tool-live_wt .tool-field-markup .code-code.language-xml")).toBeAttached()
        // Live cards take the same grounds as recorded ones.
        #expect(try await page.evaluate("""
          (() => {
            const probe = document.createElement('span'); document.body.append(probe)
            const token = (name) => { probe.style.backgroundColor = 'var(--background-color-' + name + ')'; return getComputedStyle(probe).backgroundColor }
            const [white, seen] = [token('base'), token('neutral-subtle')]; probe.remove()
            const bg = (el) => getComputedStyle(el).backgroundColor
            const cards = [...document.querySelectorAll('.computorium-session-output-thinking-rendered, .computorium-session-tool-call-rendered, .computorium-session-tools-rendered, .computorium-session-compaction-rendered')]
            const argument = document.querySelector('#computorium-session-tool-live_ws .computorium-session-tool-call-args .datum-view > .datum-value')
            const box = document.querySelector('#computorium-session-tool-live_ws .computorium-session-tool-call-result-box')
            return [cards.length >= 11, cards.every(c => bg(c) === white), bg(argument) === white, bg(box) === seen].join(' ')
          })()
          """, as: String.self) == "true true true true", "Live cards (11+) white, live argument white, live result box gray")
        try await expect(page.locator(".computorium-session-output-content")).not.toContainText("input_tokens")
        try await expect(page.locator(".computorium-session-output-content")).not.toContainText("bookkeeping")
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
