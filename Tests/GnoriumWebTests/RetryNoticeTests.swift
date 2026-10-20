import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A round's request sent again (user, 2026-10-17): the trace records it as
/// a `retry` event. A recorded transcript draws nothing for it (no
/// invented text either) and the round's Tools card once; live, it is a
/// transient blue alert until the resend's response arrives, and the
/// resend's reasoning opens a card of its own: each reasoning drawn once.
@Suite("Retry notice", .serialized)
struct RetryNoticeTests {
  struct Transcript: Decodable {
    let tools: Int
    let notices: [String]
    let blue: Int
    let thinking: [String]
    let running: Int
    let bracketed: Bool
  }

  /// The transcript as drawn: its Tools cards (the system turn's box
  /// included), its retry notices, its thinking cards' text.
  static let transcript = """
    (() => {
      const view = document.querySelector('.computorium-session-view')
      const content = view.querySelector('.computorium-session-output-content')
      const notices = [...content.querySelectorAll('.computorium-session-retry-notice')]
      const cards = [...content.querySelectorAll('.computorium-session-output-thinking')]
      return {
        tools: view.querySelectorAll('.computorium-session-tools').length,
        notices: notices.map(n => n.textContent.trim()),
        blue: notices.filter(n => n.classList.contains('alert-blue')).length,
        thinking: cards.map(c => c.querySelector('.markdown-view').textContent.trim()),
        running: content.querySelectorAll('.computorium-session-output-thinking-running').length,
        bracketed: view.textContent.includes('[the model answered nothing')
      }
    })()
    """

  @Test(arguments: [BrowserEngine.chrome])
  func aRetryIsATransientNoticeAndEachReasoningIsDrawnOnce(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphonID = UUID().uuidString.lowercased()
    let nocturneID = UUID().uuidString.lowercased()
    let name = "retry-notice-\(UUID().uuidString).html"
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
      let tools = #"[{"type":"function","function":{"name":"done","description":"Finish.","parameters":{"type":"object","properties":{}}}}]"#
      let recorded: [[String: String]] = [
        ["type": "tools", "content": tools],
        ["type": "thinking", "content": "The first reasoning."],
        ["type": "retry", "reason": "empty_response", "attempt": "2", "of": "3"],
        ["type": "thinking", "content": "The second reasoning."],
        ["type": "text", "content": "Done."],
      ]
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, image_service_ids_json, processing_status)
          VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO bibliographic_explication_nocturnes (id, submission_id, process, image, instance, provider, model, result, nocturne_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
          VALUES ('\(nocturneID)', (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'),
            'explication', '1', 1, 'fixture', 'fixture', 'passed', gen_random_uuid(), '\(antiphonID)', 1, now());
        \(try SessionTrace.append(recorded, table: "bibliographic_explication_nocturnes", id: nocturneID))
        COMMIT;
        """)
      let antiphon = "/mission-control/antiphons/bibliographic/\(antiphonID)"
      try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine), cookies: [admin.cookie]) { page in
        // Recorded: the round's Tools card once, nothing for the resend,
        // no bracketed text.
        try await page.openHydrated(antiphon)
        let drawn = try await page.evaluate(Self.transcript, as: Transcript.self)
        #expect(drawn.tools == 1, "One Tools card for the round: \(drawn)")
        #expect(drawn.notices.isEmpty, "No notice in a recorded transcript: \(drawn)")
        #expect(drawn.thinking == ["The first reasoning.", "The second reasoning."], "Each reasoning once: \(drawn)")
        #expect(!drawn.bracketed, "No invented text")

        // Live: a watch whose frames the test sends.
        let original = try await page.evaluate("fetch('\(antiphon)').then(r=>r.text())", as: String.self)
        let mock = """
          <script>
          window.EventSource=class {
            constructor(url) { this.handlers={}; setTimeout(()=>{ this.emit('start','{}'); window.__stream=this },0) }
            addEventListener(name,fn) { (this.handlers[name]??=[]).push(fn) }
            emit(name,data) { for (const fn of this.handlers[name]??[]) fn({data}) }
            close() {}
          };
          window.__emit=(o)=>window.__stream.emit('chunk',JSON.stringify(Object.assign({image:'1'},o)));
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
        let toolsJS = String(decoding: try JSONSerialization.data(withJSONObject: [tools]), as: UTF8.self)
        let waiting = try await page.evaluate("""
          (async () => {
            window.__emit({ type: 'tools', reset: '1', text: \(toolsJS)[0] })
            window.__emit({ type: 'thinking', text: 'The first ' })
            window.__emit({ type: 'thinking', append: '1', text: 'reasoning.' })
            await window.__frames()
            window.__emit({ type: 'retry', reason: 'stream_dropped', error: 'ReadTimeout', attempt: '2', of: '3' })
            await window.__frames()
            return \(Self.transcript)
          })()
          """, as: Transcript.self)
        #expect(waiting.notices == ["Stream dropped (ReadTimeout). Sent again (2 of 3)."], "One notice: \(waiting)")
        #expect(waiting.blue == 1, "Blue: \(waiting)")
        let live = try await page.evaluate("""
          (async () => {
            window.__emit({ type: 'thinking', text: 'The second ' })
            window.__emit({ type: 'thinking', append: '1', text: 'reasoning.' })
            await window.__frames()
            return \(Self.transcript)
          })()
          """, as: Transcript.self)
        #expect(live.tools == 1, "One Tools card for the round: \(live)")
        #expect(live.notices.isEmpty, "Gone once the response arrives: \(live)")
        #expect(live.thinking == ["The first reasoning.", "The second reasoning."], "Each reasoning once: \(live)")
        #expect(live.running == 1, "Only the resend's card is in flight: \(live)")
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
