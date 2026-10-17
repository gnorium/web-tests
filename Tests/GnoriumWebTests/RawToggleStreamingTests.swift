import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The Raw toggle is instant mid-stream (user, 2026-10-17): one toggle
/// button, Raw when pressed, Markdown when not. While a session streams—its
/// chat template's Raw growing by turns, its reply a token at a time with
/// code blocks in it—each press of that one toggle shows the other view
/// within two animation frames, no task on the main thread runs long (the
/// standard 50 ms long-task threshold), and the code on screen is already
/// colored when it shows. Scrolling through either view never shows a code
/// block uncolored: what comes near the screen is colored before it gets
/// there, and the rest in idle time. Once the stream ends, Raw's last runs
/// are colored exactly as a recorded Raw's.
@Suite("Raw toggle while streaming", .serialized)
struct RawToggleStreamingTests {
  struct Toggle: Decodable {
    /// The view the press turns to shows, the other is gone, and the
    /// toggle's pressed state says which.
    let changed: Bool
    /// The session has one Raw toggle, never a pair of buttons.
    let single: Bool
    /// Animation frames it took to show.
    let frames: Int
    let ms: Double
    /// The stream was still going when it was pressed.
    let streaming: Bool
  }

  struct Coverage: Decodable {
    /// Whether any of it is on screen.
    let inView: Bool
    /// Raw: its lines on screen holding markup, and the colored stretches
    /// starting on screen. Markdown: its code blocks on screen, and those
    /// highlighted.
    let wanted: Int
    let colored: Int
    let detail: String
  }

  struct Exactness: Decodable {
    let exact: Bool
    let live: [String]
    let fresh: [String]
  }

  struct Scroll: Decodable {
    let steps: Int
    let failures: [String]
  }

  /// The page's watch, mocked: the session's frames, a few every 8 ms,
  /// built here—six calls, each the template's input (forty steps of
  /// headings, prose and XML blocks), its reply a few characters a frame
  /// (paragraphs and XML blocks), then the template's output. Long tasks are
  /// recorded from the start.
  static let mock = """
    <script>
    window.__longTasks = [];
    try {
      new PerformanceObserver(list => { for (const e of list.getEntries()) window.__longTasks.push({ start: e.startTime, duration: e.duration }) })
        .observe({ type: 'longtask', buffered: true });
    } catch (_) {}
    (() => {
      const fence = (n) => '```xml\\n' + Array.from({ length: 12 }, (_, i) => '<line n="' + n + '.' + i + '" type="x">Text ' + i + ' &amp; more</line>').join('\\n') + '\\n```\\n\\n';
      const prompt = (r) => '### Round ' + r + '\\n\\n' + Array.from({ length: 40 }, (_, k) => '### Step ' + k + '\\n\\nRead **page** ' + k + ' and `write` it.\\n\\n' + fence(r * 1000 + k)).join('');
      const chunks = [];
      for (let r = 0; r < 6; r++) {
        chunks.push({ type: 'chat_template_input', text: prompt(r) });
        const reply = Array.from({ length: 8 }, (_, k) => 'Paragraph ' + k + ' of round ' + r + ', with a few words.\\n\\n' + fence(r * 100 + k)).join('');
        reply.match(/[\\s\\S]{1,6}/g).forEach((text, i) => chunks.push(i === 0 ? { type: 'text', text } : { type: 'text', append: '1', text }));
        chunks.push({ type: 'chat_template_output', text: reply, end: '<｜end▁of▁sentence｜>' });
      }
      window.__total = chunks.length;
      window.__emitted = 0;
      window.__done = false;
      window.EventSource = class {
        constructor(url) {
          this.handlers = {};
          setTimeout(() => {
            this.emit('start', '{}');
            const timer = setInterval(() => {
              for (let i = 0; i < 3 && window.__emitted < chunks.length; i++) {
                this.emit('chunk', JSON.stringify(Object.assign({ resemblance: '1' }, chunks[window.__emitted++])));
              }
              if (window.__emitted >= chunks.length) {
                clearInterval(timer);
                // The session ends: its last run is complete.
                this.emit('done', JSON.stringify({ status: 'succeeded' }));
                window.__done = true;
              }
            }, 8);
          }, 0);
        }
        addEventListener(name, fn) { (this.handlers[name] ??= []).push(fn) }
        emit(name, data) { for (const fn of this.handlers[name] ?? []) fn({ data }) }
        close() {}
      };
    })();
    window.__frame = () => new Promise(r => requestAnimationFrame(r));
    window.__session = () => document.querySelector('.computorium-session-view');
    window.__shown = (el) => !!el && el.getBoundingClientRect().height > 0;
    // Press the session's one Raw toggle (pressed: Raw; not: Markdown) and
    // count the frames until the view it turns to shows. `raw` is the view
    // the press is expected to turn to.
    window.__pressRawToggle = async (raw) => {
      const session = window.__session();
      const streaming = !window.__done;
      const toggles = session.querySelectorAll('.computorium-session-markdown-toggle');
      const single = toggles.length === 1 && toggles[0].querySelectorAll('button').length === 1;
      const button = toggles[0].querySelector('button');
      const shows = () => {
        const rawView = session.querySelector('.chat-template-raw-view');
        const markdown = session.querySelector('.computorium-session-output-rendered');
        const pressed = button.getAttribute('aria-pressed') === 'true';
        return raw ? pressed && window.__shown(rawView) && !window.__shown(markdown)
          : !pressed && window.__shown(markdown) && !window.__shown(rawView);
      };
      const before = performance.now();
      button.click();
      let frames = 0;
      while (!shows() && frames < 2) { await window.__frame(); frames++; }
      const changed = shows();
      // Painted: the frame that shows it.
      await window.__frame();
      return { changed, single, frames, ms: performance.now() - before, streaming };
    };
    // The text of a highlight's range, live or static.
    window.__text = (r) => { const x = document.createRange(); x.setStart(r.startContainer, r.startOffset); x.setEnd(r.endContainer, r.endOffset); return x.toString() };
    window.__caret = (x, y) => {
      if (document.caretPositionFromPoint) { const p = document.caretPositionFromPoint(x, y); return p && { node: p.offsetNode, offset: p.offset } }
      const r = document.caretRangeFromPoint(x, y); return r && { node: r.startContainer, offset: r.startOffset };
    };
    // Raw's lines on screen holding markup, and its colored stretches
    // starting on screen: one at least a line.
    window.__rawCoverage = () => {
      const raw = window.__session().querySelector('.chat-template-raw-view');
      if (!window.__shown(raw)) return { inView: false, wanted: 0, colored: 0, detail: 'hidden' };
      const rect = raw.getBoundingClientRect();
      const top = Math.max(rect.top, 0) + 4, bottom = Math.min(rect.bottom, innerHeight) - 4;
      if (bottom <= top) return { inView: false, wanted: 0, colored: 0, detail: 'off screen' };
      const x = Math.max(rect.left, 0) + 40;
      const a = window.__caret(x, top), b = window.__caret(x, bottom);
      if (!a || !b || !raw.contains(a.node) || !raw.contains(b.node)) return { inView: true, wanted: 1, colored: 0, detail: 'no caret in Raw' };
      const visible = document.createRange();
      visible.setStart(a.node, a.offset);
      visible.setEnd(b.node, b.offset);
      const lines = visible.toString().split('\\n');
      // A line cut at the screen's edges is not counted.
      const wanted = lines.slice(1, -1).filter(l => l.includes('<line')).length;
      let colored = 0;
      for (const name of ['code-tag', 'code-name', 'code-attr', 'code-value', 'code-entity', 'code-prefix', 'code-pi', 'code-cdata', 'code-comment']) {
        for (const r of CSS.highlights.get(name) ?? []) {
          if (raw.contains(r.startContainer) && visible.comparePoint(r.startContainer, r.startOffset) === 0) colored++;
        }
      }
      return { inView: true, wanted, colored, detail: lines.length + ' lines' };
    };
    // The reply's code blocks on screen, and those highlighted.
    window.__markdownCoverage = (committedOnly) => {
      const session = window.__session();
      const blocks = [...session.querySelectorAll('.computorium-session-output-rendered ' + (committedOnly ? '[data-md-committed] ' : '') + 'pre code')]
        .filter(code => { const r = code.getBoundingClientRect(); return r.height > 0 && r.bottom > 0 && r.top < innerHeight });
      const plain = blocks.filter(code => !code.hasAttribute('data-highlighted'));
      return { inView: blocks.length > 0, wanted: blocks.length, colored: blocks.length - plain.length,
        detail: plain.map(code => code.textContent.slice(0, 40)).join(' | ') };
    };
    // Each of Raw's last two runs (the last reply, complete when the end
    // token's run began; the end token's, complete when the stream ended)
    // colored exactly: its stretches, by kind and place in the run, the same
    // as a copy of the run alone gets, colored whole from a fresh start (a
    // recorded Raw's coloring). Both are painted whole first (idle time).
    window.__stretches = (container) => {
      const out = [];
      for (const name of ['code-tag', 'code-name', 'code-attr', 'code-value', 'code-entity', 'code-prefix', 'code-pi', 'code-cdata', 'code-comment']) {
        for (const r of CSS.highlights.get(name) ?? []) {
          if (!container.contains(r.startContainer)) continue;
          const before = document.createRange();
          before.setStart(container, 0);
          before.setEnd(r.startContainer, r.startOffset);
          out.push(name + ':' + before.toString().length + '+' + window.__text(r).length);
        }
      }
      return out.sort();
    };
    window.__lastRunsExact = async () => {
      const raw = window.__session().querySelector('.chat-template-raw-view');
      const runs = [...raw.children].slice(-2);
      const probes = runs.map(run => {
        const probe = document.createElement('pre');
        probe.setAttribute('data-code-syntax', 'chat-template');
        probe.append(run.cloneNode(true));
        document.body.append(probe);
        return probe;
      });
      // Colored as any Raw first shown is (`CodeHydration`, after a click).
      document.body.click();
      let live = [], fresh = [];
      for (let i = 0; i < 100; i++) {
        await new Promise(r => setTimeout(r, 50));
        live = runs.map(run => window.__stretches(run).join(' '));
        fresh = probes.map(probe => window.__stretches(probe).join(' '));
        if (live.every((l, k) => l === fresh[k]) && live[0].length > 0) break;
      }
      probes.forEach(probe => probe.remove());
      // The reply's run holds XML: colored; the end token's may hold none.
      return { exact: live.every((l, k) => l === fresh[k]) && live[0].length > 0, live, fresh };
    };
    // Raw's nodes per run (elements, then text nodes), for a long task's
    // report: what style recalculation and layout walk when Raw shows.
    window.__rawNodes = () => {
      const raw = window.__session().querySelector('.chat-template-raw-view');
      if (!raw) return 'no Raw';
      const runs = [...raw.children].map(run => {
        const walker = document.createTreeWalker(run, NodeFilter.SHOW_TEXT);
        let texts = 0;
        while (walker.nextNode()) texts++;
        return (run.getElementsByTagName('*').length + 1) + '/' + texts;
      });
      return runs.length + ' runs, elements/texts each: ' + runs.join(' ');
    };
    // Through the page from its top, most of a screen a step: at each, the
    // view's code on screen colored, a frame after the scroll.
    window.__scrollThrough = async (raw) => {
      const failures = [];
      let steps = 0;
      window.scrollTo(0, 0);
      await window.__frame();
      for (let y = 0; y <= document.documentElement.scrollHeight; y += Math.round(innerHeight * 0.8)) {
        window.scrollTo(0, y);
        await window.__frame();
        await window.__frame();
        steps++;
        const c = raw ? window.__rawCoverage() : window.__markdownCoverage(false);
        if (c.inView && c.colored < (raw ? Math.max(c.wanted, 1) : c.wanted)) failures.push(y + ': ' + JSON.stringify(c));
      }
      return { steps, failures };
    };
    </script>
    """

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func toggleIsInstantMidStream(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphonID = UUID().uuidString.lowercased()
    let nocturneID = UUID().uuidString.lowercased()
    let name = "raw-toggle-streaming-\(UUID().uuidString).html"
    let file = URL(fileURLWithPath: "/Users/Madhavik/Downloads/Gnorium/gnorium-web/Public").appendingPathComponent(name)
    func cleanUp() {
      try? FileManager.default.removeItem(at: file)
      _ = try? TestAdmin.query(
        SessionTrace.delete(table: "bibliographic_explication_nocturnes", where: "id='\(nocturneID)'")
          + "DELETE FROM bibliographic_explication_nocturnes WHERE id='\(nocturneID)'; DELETE FROM bibliographic_antiphons WHERE id='\(antiphonID)';")
      work.remove()
    }
    do {
      let user = try admin.column("id")
      let recorded: [[String: String]] = [["type": "text", "content": "Preparing the Raw toggle fixture."]]
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, resemblance_service_ids_json, processing_status)
          VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO bibliographic_explication_nocturnes (id, submission_id, process, resemblance, instance, provider, model, result, nocturne_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
          VALUES ('\(nocturneID)', (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'),
            'explication', '1', 1, 'fixture', 'fixture', 'passed', gen_random_uuid(), '\(antiphonID)', 1, now());
        \(try SessionTrace.append(recorded, table: "bibliographic_explication_nocturnes", id: nocturneID))
        COMMIT;
        """)
      let antiphon = "/mission-control/antiphons/bibliographic/\(antiphonID)"
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(antiphon)
        let original = try await page.evaluate("fetch('\(antiphon)').then(r=>r.text())", as: String.self)
        try original.replacingOccurrences(of: "<head>", with: "<head>" + Self.mock)
          .replacingOccurrences(of: "data-auto-watch=\"0\"", with: "data-auto-watch=\"1\"")
          .replacingOccurrences(of: #"data-trace-resume="[^"]*""#, with: #"data-trace-resume="""#, options: .regularExpression)
          .write(to: file, atomically: true, encoding: .utf8)
        try await page.openHydrated("/\(name)")

        // Mid-stream: the toggle shows once the template's first input has
        // come, and the reply is a few rounds in.
        #expect(try await page.evaluate("""
          (async () => {
            for (let i = 0; i < 300 && !(window.__emitted > window.__total * 0.35 && document.querySelector('.computorium-session-markdown-toggle button')); i++)
              await new Promise(r => setTimeout(r, 50));
            return !window.__done && window.__emitted > window.__total * 0.35
          })()
          """, as: Bool.self), "The stream is a third in and still going")
        let start = try await page.evaluate("performance.now()", as: Double.self)

        // The one toggle pressed four times: Raw, Markdown, Raw, Markdown,
        // each within two frames, mid-stream.
        for (index, raw) in [true, false, true, false].enumerated() {
            let toggle = try await page.evaluate("window.__pressRawToggle(\(raw))", as: Toggle.self)
          #expect(toggle.single, "One Raw toggle button: \(toggle)")
          #expect(toggle.streaming, "Press \(index + 1) came while the stream was going: \(toggle)")
          #expect(toggle.changed && toggle.frames <= 2, "Press \(index + 1) turns to \(raw ? "Raw" : "Markdown") within two frames: \(toggle)")
          if raw {
            // Raw's code on screen colored in the frame that shows it.
            let coverage = try await page.evaluate("window.__rawCoverage()", as: Coverage.self)
            #expect(coverage.inView && coverage.colored >= max(coverage.wanted, 1), "Raw on screen is colored as it shows: \(coverage)")
          } else {
            let coverage = try await page.evaluate("window.__markdownCoverage(true)", as: Coverage.self)
            #expect(coverage.colored == coverage.wanted, "The reply's code on screen is highlighted as it shows: \(coverage)")
          }
          _ = try await page.evaluate("new Promise(r => setTimeout(() => r(true), 300))")
        }
        let long = try await page.evaluate(
          "JSON.stringify(window.__longTasks.filter(t => t.start + t.duration >= \(start)))", as: String.self)
        let nodes = try await page.evaluate("window.__rawNodes()", as: String.self)
        #expect(long == "[]", "No long task (over 50 ms) while toggling Raw mid-stream: \(long); Raw: \(nodes)")

        // The stream ended: through the whole page in Raw, then in Markdown,
        // no code on screen is ever plain.
        #expect(try await page.evaluate("""
          (async () => { for (let i = 0; i < 600 && !window.__done; i++) await new Promise(r => setTimeout(r, 50)); await window.__frame(); return window.__done })()
          """, as: Bool.self), "The stream ends")
        let toRaw = try await page.evaluate("window.__pressRawToggle(true)", as: Toggle.self)
        #expect(toRaw.changed, "The Raw toggle pressed, Raw shows: \(toRaw)")
        // Its last runs, complete, colored exactly as a recorded Raw's.
        let exact = try await page.evaluate("window.__lastRunsExact()", as: Exactness.self)
        #expect(exact.exact, "Raw's last runs are colored exactly once complete: \(exact)")
        let rawScroll = try await page.evaluate("window.__scrollThrough(true)", as: Scroll.self)
        #expect(rawScroll.steps > 3 && rawScroll.failures.isEmpty, "Raw is colored wherever it is scrolled to: \(rawScroll)")
        let toMarkdown = try await page.evaluate("window.__pressRawToggle(false)", as: Toggle.self)
        #expect(toMarkdown.changed, "The Raw toggle released, Markdown shows: \(toMarkdown)")
        let markdownScroll = try await page.evaluate("window.__scrollThrough(false)", as: Scroll.self)
        #expect(
          markdownScroll.steps > 3 && markdownScroll.failures.isEmpty,
          "The reply's code is highlighted wherever it is scrolled to: \(markdownScroll)")
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
