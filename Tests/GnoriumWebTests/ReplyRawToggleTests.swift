import Foundation
import Testing
import WebTests
import WebTestsTesting

/// gnorium's reply in a locution, its session streaming live with a long
/// trace recorded (prod, 2026-10-18: a 1.3 MB Raw froze the page): its Raw
/// toggle pressed mid-stream shows Raw without a long task—the recorded
/// Raw fetched and parsed a part a task, its text read and colored a
/// frame's share at a time. The call and its Commit go through the real
/// routes with the workers stopped, as ArbitrationTests does; the session's
/// trace is seeded and its stream is the test's.
@Suite("Reply Raw toggle while streaming", .serialized)
struct ReplyRawToggleTests {
  static let sessions = "bibliographic_arbitration_sessions"

  /// A round's input as the template renders it: forty steps of a
  /// heading, prose and an XML block, each step's block long enough that a
  /// round is about 150 KB.
  static func prompt(_ round: Int) -> String {
    (0..<40).map { step in
      let lines = (0..<60).map { line in
        "<line n=\"\(round).\(step).\(line)\" type=\"x\">Text \(line) of step \(step) &amp; more words to read.</line>"
      }.joined(separator: "\n")
      return "### Step \(step) of round \(round)\n\nRead **page** \(step) and `write` it.\n\n```xml\n\(lines)\n```\n\n"
    }.joined()
  }

  /// The recorded trace: ten rounds of template input (about 1.5 MB in
  /// all), each with long reasoning, a reply and the template's output.
  static func trace() -> [[String: String]] {
    var blocks: [[String: String]] = [["type": "task_prompt_instance", "content": "Answer this query about the evidence."]]
    for round in 0..<10 {
      blocks.append(["type": "chat_template_input", "content": prompt(round)])
      blocks.append(["type": "thinking", "content": String(repeating: "Reasoning about round \(round) at length.\n\n", count: 400)])
      let reply = "Round \(round) reads as it should.\n\n```xml\n<p n=\"\(round)\">Answer.</p>\n```\n\n"
      blocks.append(["type": "text", "content": reply])
      blocks.append(["type": "chat_template_output", "content": reply, "end": "<｜end▁of▁sentence｜>"])
    }
    return blocks
  }

  /// The reply's watch, the test's: its frames a few every 8 ms once it
  /// starts—more rounds of input, reasoning a few words a frame, a reply,
  /// the template's output—to the reply's own session (`__label`). Every
  /// other stream stays the real one. Long tasks and long animation frames
  /// are recorded from the start.
  static func mock(replyID: String) -> String {
    """
    if (location.hash === '#reply-raw-test') {
      window.__longTasks = []
      try {
        new PerformanceObserver(list => { for (const e of list.getEntries()) window.__longTasks.push({ start: Math.round(e.startTime), duration: Math.round(e.duration) }) })
          .observe({ type: 'longtask', buffered: true })
      } catch (_) {}
      window.__longFrames = []
      try {
        new PerformanceObserver(list => {
          for (const f of list.getEntries()) {
            const end = f.startTime + f.duration
            window.__longFrames.push({
              start: Math.round(f.startTime), duration: Math.round(f.duration),
              callbacks: f.renderStart ? Math.round((f.styleAndLayoutStart || end) - f.renderStart) : 0,
              styleAndLayout: f.styleAndLayoutStart ? Math.round(end - f.styleAndLayoutStart) : 0,
              scripts: f.scripts.map(s => ({ invoker: s.invoker, source: (s.sourceURL || '').split('/').pop() + ':' + (s.sourceFunctionName || ''),
                duration: Math.round(s.duration), forcedStyleAndLayout: Math.round(s.forcedStyleAndLayoutDuration) })),
            })
          }
        }).observe({ type: 'long-animation-frame', buffered: true })
      } catch (_) {}
      const fence = (n) => '```xml\\n' + Array.from({ length: 12 }, (_, i) => '<line n="' + n + '.' + i + '">Live ' + i + '</line>').join('\\n') + '\\n```\\n\\n'
      const chunks = []
      for (let r = 0; r < 4; r++) {
        chunks.push({ type: 'chat_template_input', text: Array.from({ length: 20 }, (_, k) => '### Live step ' + k + '\\n\\n' + fence(r * 100 + k)).join('') })
        'Reasoning live, a few words at a time, about the page.\\n\\n'.repeat(40).match(/[\\s\\S]{1,8}/g)
          .forEach((text, i) => chunks.push(i === 0 ? { type: 'thinking', text } : { type: 'thinking', append: '1', text }))
        const reply = 'Live round ' + r + ' reads well.\\n\\n'
        chunks.push({ type: 'text', text: reply })
        chunks.push({ type: 'chat_template_output', text: reply, end: '<｜end▁of▁sentence｜>' })
      }
      window.__total = chunks.length
      window.__emitted = 0
      window.__label = () => document.querySelector('#locution-\(replyID.uppercased()) .computorium-session-view')
        ?.dataset.computoriumSessionImage ?? ''
      const Real = window.EventSource
      window.EventSource = class {
        constructor(url, options) {
          if (!String(url).includes('/arbitration/stream')) return new Real(url, options)
          this.handlers = {}
          setTimeout(() => {
            this.emit('start', '{"watch":true,"process":"arbitration"}')
            this.emit('chunk', JSON.stringify({ type: 'status', text: 'running', image: window.__label() }))
            const timer = setInterval(() => {
              for (let i = 0; i < 3 && window.__emitted < chunks.length; i++)
                this.emit('chunk', JSON.stringify(Object.assign({ image: window.__label() }, chunks[window.__emitted++])))
              if (window.__emitted >= chunks.length) clearInterval(timer)
            }, 8)
          }, 0)
        }
        addEventListener(name, fn) { (this.handlers[name] ??= []).push(fn) }
        emit(name, data) { for (const fn of this.handlers[name] ?? []) fn({ data }) }
        close() {}
      }
    }
    """
  }

  struct Press: Decodable {
    /// Raw showed (the toggle pressed, the Raw laid out, its steps gone).
    let shown: Bool
    let ms: Double
    let streaming: Bool
    /// The longest task from the press on, ms (0 for none over 50).
    let longest: Double
    let tasks: String
    let frames: String
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func replyRawShowsWithoutALongTask(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let stopped = try TestAdmin.query("""
      SELECT (NOT p.enabled OR NOT c.enabled)::text FROM computorium_worker_pool p
        CROSS JOIN computorium_services c WHERE p.singleton = true AND c.service = 'arbitration'
      """)
    guard stopped == "true" else {
      throw WebTestError("The reply fixture requires stopped dev workers so Commit cannot call a provider.")
    }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reading = try ScratchReading(owner: contributor, tei: ArbitrationTests.tei(fixture), sourceURL: fixture.baseURL + "/manifest.json")
    let objectID = reading.madrigalID
    let adminID = try admin.column("id")
    func remove() {
      _ = try? TestAdmin.query("""
        BEGIN;
        UPDATE prompt_vignettes SET committed_object_type = NULL, committed_object_id = NULL, committed_by_user_id = NULL,
          committed_at = NULL WHERE committed_by_user_id = '\(adminID)';
        DELETE FROM locutions WHERE locutable_type = 'bibliographic_madrigal' AND locutable_id = '\(objectID)' AND kind = 'reply';
        UPDATE locutions SET arbitration_session_id = NULL WHERE locutable_type = 'bibliographic_madrigal' AND locutable_id = '\(objectID)';
        \(SessionTrace.delete(table: Self.sessions, where: "locutable_type = 'bibliographic_madrigal' AND locutable_id = '\(objectID)'"))
        DELETE FROM bibliographic_arbitration_sessions WHERE locutable_type = 'bibliographic_madrigal' AND locutable_id = '\(objectID)';
        DELETE FROM locutions WHERE locutable_type = 'bibliographic_madrigal' AND locutable_id = '\(objectID)';
        COMMIT;
        """)
      reading.remove()
    }
    do {
      // The call: a contributor's, on the explicated page.
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated(reading.path + "?image=2")
        try await expect(page.locator(".prompt-previews-slot"), timeout: .seconds(20)).toHaveAttribute("aria-busy", "false")
        try await page.locator("#locution-thread-locution-body").fill("@gnorium What does the selected evidence support?")
        try await page.locator("#madrigal-images .roster-row").nth(0).locator("input").click()
        try await page.locator(".locution-thread-submit").click()
        try await expect(page.locator(".locution-call-page"), timeout: .seconds(15)).toHaveCount(1)
      }
      let callID = try TestAdmin.query("""
        SELECT id FROM locutions WHERE locutable_type = 'bibliographic_madrigal' AND locutable_id = '\(objectID)' AND kind = 'call'
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        // Committed: the session queued, its reply submitted with it.
        try await page.openHydrated(reading.path)
        try await page.locator("#locution-\(callID.uppercased()) .locution-commit").click()
        var sessionID = ""
        for _ in 0..<300 {
          sessionID = try TestAdmin.query(
            "SELECT id FROM bibliographic_arbitration_sessions WHERE call_locution_id = '\(callID)' AND result = 'queued'")
          if !sessionID.isEmpty { break }
          try await Task.sleep(for: .milliseconds(100))
        }
        guard UUID(uuidString: sessionID) != nil else { throw WebTestError("Commit did not create the waiting session.") }
        let replyID = try TestAdmin.query(
          "SELECT id FROM locutions WHERE arbitration_session_id = '\(sessionID)' AND kind = 'reply'")
        guard UUID(uuidString: replyID) != nil else { throw WebTestError("The Commit submitted no reply.") }
        // Running, its long trace recorded so far; held so the resumer
        // leaves it be.
        _ = try TestAdmin.query("""
          BEGIN;
          UPDATE bibliographic_arbitration_sessions SET result = 'running', error_message = NULL,
            held_by = 'web_tests', held_until = NOW() + interval '1 hour' WHERE id = '\(sessionID)';
          \(try SessionTrace.append(Self.trace(), table: Self.sessions, id: sessionID))
          UPDATE locutions SET call_status = 'running' WHERE id = '\(callID)';
          COMMIT;
          """)
        try await page.addInitScript(Self.mock(replyID: replyID))
        try await page.openHydrated(reading.path + "#reply-raw-test")
        let reply = "#locution-\(replyID.uppercased())"
        // Mid-stream: the watch a third through its frames.
        #expect(try await page.evaluate("""
          (async () => {
            for (let i = 0; i < 400 && !(window.__emitted > window.__total / 3); i++) await new Promise(r => setTimeout(r, 50))
            return window.__emitted > window.__total / 3 && window.__emitted < window.__total
          })()
          """, as: Bool.self), "The reply's stream is a third in and still going")
        // The reply's Raw toggle (its reactions row) pressed: Raw shows,
        // and no task from the press on runs long.
        let press = try await page.evaluate("""
          (async () => {
            const session = document.querySelector('\(reply) .computorium-session-view')
            const button = document.querySelector('\(reply) .computorium-session-markdown-toggle button')
            const streaming = window.__emitted < window.__total
            const shown = () => {
              const raw = session.querySelector('.chat-template-raw-view')
              return button.getAttribute('aria-pressed') === 'true' && session.dataset.rawView === 'true'
                && !!raw && raw.getBoundingClientRect().height > 0
            }
            const start = performance.now()
            button.click()
            while (!shown() && performance.now() - start < 30000) await new Promise(r => setTimeout(r, 20))
            const ms = performance.now() - start
            // The Raw on screen colored, the rest in idle time: a while
            // longer for any task that would run long after it shows.
            await new Promise(r => setTimeout(r, 1500))
            const tasks = window.__longTasks.filter(t => t.start + t.duration >= start)
            const frames = window.__longFrames.filter(f => tasks.some(t => t.start < f.start + f.duration && t.start + t.duration > f.start))
            return { shown: shown(), ms, streaming, longest: Math.max(0, ...tasks.map(t => t.duration)),
              tasks: JSON.stringify(tasks), frames: JSON.stringify(frames) }
          })()
          """, as: Press.self)
        #expect(press.streaming, "The press came while the reply streamed: \(press.ms)")
        #expect(press.shown, "Raw shows: \(press.ms) ms")
        // A freeze first (the page held for seconds), then the strict bound.
        #expect(press.longest <= 200, "No freeze: the longest task \(press.longest) ms; tasks \(press.tasks); frames \(press.frames)")
        #expect(press.tasks == "[]", "No long task (over 50 ms) from the press on: \(press.tasks); frames \(press.frames)")
        // Raw on screen is colored: the press came from a script, which leaves the page where it was (the Raw
        // below the fold), so the reader scrolls to it, and what comes on screen is colored within a few frames.
        #expect(try await page.evaluate("""
          (async () => {
            const raw = document.querySelector('\(reply) .chat-template-raw-view')
            raw.scrollIntoView({ block: 'center' })
            const colored = () => {
              let count = 0
              for (const name of ['code-tag', 'code-name', 'code-attr', 'code-value', 'code-entity', 'code-prefix', 'code-pi', 'code-cdata', 'code-comment'])
                for (const r of CSS.highlights.get(name) ?? []) {
                  if (!raw.contains(r.startContainer)) continue
                  const x = document.createRange(); x.setStart(r.startContainer, r.startOffset); x.setEnd(r.endContainer, r.endOffset)
                  const box = x.getBoundingClientRect()
                  if (box.height > 0 && box.bottom > 0 && box.top < innerHeight) count++
                }
              return count
            }
            for (let i = 0; i < 100 && colored() === 0; i++) await new Promise(r => requestAnimationFrame(r))
            return colored()
          })()
          """, as: Int.self) > 0, "Raw on screen is colored")
        try await page.expectNoErrors()
      }
    } catch {
      remove()
      try? await admin.remove()
      try await contributor.remove(after: error)
    }
    remove()
    try await admin.remove()
    try await contributor.remove()
  }
}
