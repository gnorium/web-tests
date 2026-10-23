import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A session's context bar (user, 2026-10-21): "6% used  67.1k / 1M" and a
/// bar of what the latest call read, by kind; its popover's first line, each
/// kind, the free space and the totals in aligned columns—as recorded, and
/// on as a watch's usage and context frames arrive; one Context row where no
/// call said the kinds; only what is known, never a row of "—"; before a
/// call the bar "—" and no popover. The ⓘ says no usage.
@Suite("Context bar", .serialized)
struct ContextBarTests {
  /// The bar's state, the popover's emptiness and display, its first line,
  /// the bar's words, two kinds' rows, Context's, the free space's, two
  /// segments' widths and the totals (the popover is portaled to <body>
  /// once bound): one line, " | " between; a hidden row "hidden".
  static let bar = """
    (() => { const b = document.querySelector('.session-context-bar-view');
      const d = document.querySelector('.session-context-bar-details');
      const row = k => { const r = d.querySelector(`.session-context-bar-row[data-category="${k}"]`);
        return r.hidden ? 'hidden' : r.querySelector('.session-context-bar-count').textContent + ' '
          + r.querySelector('.session-context-bar-share').textContent };
      const seg = k => b.querySelector(`.session-context-bar-segment[data-category="${k}"]`).getAttribute('width');
      const sum = d.querySelector('.session-context-bar-summary');
      return [b.dataset.context, d.dataset.empty, getComputedStyle(d.parentElement).display,
        sum.hidden ? 'hidden' : sum.textContent, b.querySelector('.session-context-bar-percent').textContent,
        b.querySelector('.session-context-bar-tokens').textContent, row('tools'), row('tool_outputs'), row('context'),
        row('free'), seg('tool_outputs'), seg('context'),
        [...d.querySelectorAll('.session-context-bar-totals > .session-context-bar-row')]
          .map(r => r.hidden ? 'hidden' : r.querySelector('.session-context-bar-total').textContent).join(' ')
      ].join(' | ') })()
    """

  /// Opened by a click: the popover shows, its rows a grid whose numbers
  /// end on one edge; the bar a 40px box after Raw and the ⓘ, exactly as
  /// wide as the popover, its right edge at the popover's (user,
  /// 2026-10-21).
  static let opened = """
    (async () => { const b = document.querySelector('.session-context-bar-view');
      b.querySelector('.session-context-bar-meter').click();
      await new Promise(r => requestAnimationFrame(() => setTimeout(r, 300)));
      const d = document.querySelector('.session-context-bar-details');
      const bubble = getComputedStyle(d.parentElement);
      const ends = [...d.querySelectorAll('.session-context-bar-row:not([hidden]) .session-context-bar-count')]
        .map(e => Math.round(e.getBoundingClientRect().right));
      const row = b.closest('.computorium-session-controls-start');
      const order = [...row.children].map(e => e.classList.contains('session-context-bar-view') ? 'bar'
        : e.querySelector('.computorium-session-markdown-toggle') || e.classList.contains('computorium-session-markdown-toggle') ? 'raw'
        : e.querySelector('.computorium-session-byline-words') ? 'info' : 'other');
      const meter = b.querySelector('.session-context-bar-meter').getBoundingClientRect();
      const box = d.parentElement.getBoundingClientRect();
      const fitted = Math.abs(meter.width - box.width) <= 1 && Math.abs(meter.right - box.right) <= 1
        ? 'fitted' : `unfit ${meter.left}–${meter.right} / ${box.left}–${box.right}`;
      return [bubble.visibility, getComputedStyle(d.querySelector('.session-context-bar-breakdown')).display,
        new Set(ends).size === 1 ? 'aligned' : 'ragged',
        Math.round(meter.height),
        order.join(' '), fitted].join(' | ') })()
    """

  /// A call's context block as `session_context` writes it: every value a
  /// string; the kinds sum to 63,748, the chat template's 3,315 the rest of
  /// the 67,063 read.
  static let kinds: [String: String] = [
    "window": "1048576", "used": "67063", "system_prompt": "1200", "task_prompt": "900", "tools": "3100",
    "images": "2048", "thinking": "12000", "tool_inputs": "500", "tool_outputs": "41000", "text": "3000",
    "autocompaction_summaries": "0", "chat_template": "3315",
  ]

  @Test(arguments: [BrowserEngine.chrome])
  func theBarSaysTheContextByKindAndGoesOnLive(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphonID = UUID().uuidString.lowercased()
    let nocturneID = UUID().uuidString.lowercased()
    let name = "context-bar-\(UUID().uuidString).html"
    let file = URL(fileURLWithPath: "/Users/Madhavik/Downloads/Gnorium/gnorium-web/Public").appendingPathComponent(name)
    func cleanUp() {
      try? FileManager.default.removeItem(at: file)
      _ = try? TestAdmin.query(
        SessionTrace.delete(table: "bibliographic_explication_nocturne_instances", where: "id='\(nocturneID)'")
          + "DELETE FROM bibliographic_explication_nocturnes WHERE id IN (SELECT nocturne_id FROM bibliographic_explication_nocturne_instances WHERE id='\(nocturneID)'); DELETE FROM bibliographic_antiphons WHERE id='\(antiphonID)';")
      work.remove()
    }
    do {
      let user = try admin.column("id")
      // As `SessionStream` records a call: its usage, as JSON, under `content`.
      let call = #"[{"purpose":"explication","provider":"deepseek","model":"deepseek-flash","input_tokens":67063,"output_tokens":845,"reasoning_tokens":512,"context_tokens":1048576,"latency_ms":1,"started_at":1,"finished_at":2}]"#
      let recorded: [[String: String]] = [
        ["type": "thinking", "content": "Reading."],
        ["type": "usage", "content": call],
        ["type": "context"].merging(Self.kinds) { $1 },
        ["type": "text", "content": "Done."],
      ]
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, image_service_ids_json, processing_status)
          VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO bibliographic_explication_nocturnes (id, bibliographic_antiphon_id, submission_id, process, image, instance_count)
         VALUES (md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid, '\(antiphonID)', (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'), 'explication', '1', 1)
         ON CONFLICT (id) DO UPDATE SET instance_count = bibliographic_explication_nocturnes.instance_count + 1;
        INSERT INTO bibliographic_explication_nocturne_instances (id, nocturne_id, submission_id, process, image, instance, provider, model, result, nocturne_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
        VALUES ('\(nocturneID)', md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid, (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'), 'explication', '1', 1, 'fixture', 'fixture', 'passed', gen_random_uuid(), '\(antiphonID)', 1, now());
        \(try SessionTrace.append(recorded, table: "bibliographic_explication_nocturne_instances", id: nocturneID))
        COMMIT;
        """)
      let antiphon = "/mission-control/antiphons/bibliographic/\(antiphonID)"
      try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine), cookies: [admin.cookie]) { page in
        // Recorded: the trace's one call, by kind; its cached input unknown.
        try await page.openHydrated(antiphon)
        #expect(
          try await page.evaluate(Self.bar, as: String.self)
            == "window | false | block | 6% used · 67.1k of 1M tokens | 6% used | 67.1k / 1M | 3.1k 0.3% | 41k 3.9% | hidden | 981.5k 93.6% | 39 | 0 | 67,063 hidden 845 512")
        #expect(try await page.evaluate(Self.opened, as: String.self) == "visible | grid | aligned | 40 | raw info bar | fitted")
        #expect(
          try await page.evaluate(
            "document.querySelector('.computorium-session-byline-words').textContent.includes('context')",
            as: Bool.self) == false,
          "The ⓘ says no usage")

        // Live: a watch whose frames the test sends, from the trace's start.
        let original = try await page.evaluate("fetch('\(antiphon)').then(r=>r.text())", as: String.self)
        let mock = """
          <script>
          window.EventSource=class {
            constructor(url) { this.handlers={}; setTimeout(()=>{ this.emit('start','{}'); window.__stream=this },0) }
            addEventListener(name,fn) { (this.handlers[name]??=[]).push(fn) }
            emit(name,data) { for (const fn of this.handlers[name]??[]) fn({data}) }
            close() {}
          };
          window.__emit=(o)=>window.__stream.emit('chunk',JSON.stringify(Object.assign({image:'1',image_index:-1},o)));
          window.__frames=()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(()=>setTimeout(r,50))));
          </script>
          """
        try original.replacingOccurrences(of: "<head>", with: "<head>" + mock)
          .replacingOccurrences(of: "data-auto-watch=\"0\"", with: "data-auto-watch=\"1\"")
          .replacingOccurrences(of: #"data-trace-resume="[^"]*""#, with: #"data-trace-resume="""#, options: .regularExpression)
          .write(to: file, atomically: true, encoding: .utf8)
        try await page.openHydrated("/\(name)")
        #expect(try await page.evaluate("""
          (async () => { for (let i = 0; i < 50 && !window.__stream; i++) await new Promise(r => setTimeout(r, 100)); return !!window.__stream })()
          """, as: Bool.self), "The watch is attached")
        let lines = try await page.evaluate("""
          (async () => {
            const lines = []
            // A new session: nothing called yet.
            window.__emit({ type: 'reset', text: '' })
            await window.__frames()
            lines.push(\(Self.bar))
            // The trace from its start: its first round's usage first.
            window.__emit({ type: 'thinking', reset: '1', text: 'Reading.' })
            window.__emit({ type: 'usage', input_tokens: 1200, output_tokens: 300, reasoning_tokens: 120,
              context_input_tokens: 1200, context_tokens: 1048576 })
            await window.__frames()
            lines.push(\(Self.bar))
            // The next round's: the context is its input, the tokens summed.
            window.__emit({ type: 'usage', input_tokens: 67063, cached_tokens: 50000, output_tokens: 845,
              reasoning_tokens: 512, context_input_tokens: 67063, context_tokens: 1048576 })
            await window.__frames()
            lines.push(\(Self.bar))
            // What it read, by kind: the Context segment gives way to them.
            window.__emit({ type: 'context', window: 1048576, used: 67063, system_prompt: 1200, tools: 3100,
              task_prompt: 900, images: 2048, thinking: 12000, tool_inputs: 500, tool_outputs: 41000,
              text: 3000, autocompaction_summaries: 0, chat_template: 3315 })
            await window.__frames()
            lines.push(\(Self.bar))
            // A search: its tokens, the context as it was.
            window.__emit({ type: 'usage', input_tokens: 0, output_tokens: 0 })
            await window.__frames()
            lines.push(\(Self.bar))
            return lines
          })()
          """, as: [String].self)
        #expect(lines == [
          "none | true | none | hidden | — used | — / — | hidden | hidden | hidden | hidden | 0 | 0 | hidden hidden hidden hidden",
          "window | false | block | 0% used · 1.2k of 1M tokens | 0% used | 1.2k / 1M | hidden | hidden | 1.2k 0.1% | 1M 99.9% | 0 | 1 | 1,200 hidden 300 120",
          "window | false | block | 6% used · 67.1k of 1M tokens | 6% used | 67.1k / 1M | hidden | hidden | 67.1k 6.4% | 981.5k 93.6% | 0 | 63 | 68,263 50,000 1,145 632",
          "window | false | block | 6% used · 67.1k of 1M tokens | 6% used | 67.1k / 1M | 3.1k 0.3% | 41k 3.9% | hidden | 981.5k 93.6% | 39 | 0 | 68,263 50,000 1,145 632",
          "window | false | block | 6% used · 67.1k of 1M tokens | 6% used | 67.1k / 1M | 3.1k 0.3% | 41k 3.9% | hidden | 981.5k 93.6% | 39 | 0 | 68,263 50,000 1,145 632",
        ], "\(lines)")
        #expect(
          try await page.evaluate(
            "document.querySelector('.computorium-session-view').dataset.contextUsage", as: String.self)
            == "67063 1048576 68263 50000 1145 632 1200 3100 900 2048 12000 500 41000 3000 0 3315")
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
