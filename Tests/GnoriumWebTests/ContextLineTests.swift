import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A session's context line (user, 2026-10-18): its footer says "context
/// 67,063 of 1,048,576, input …, output … (thinking …)"—the latest call's input over the
/// window it ran against, and the calls summed—as recorded, and on as a
/// watch's usage frames arrive; "—" before a call.
@Suite("Context line", .serialized)
struct ContextLineTests {
  static let footer = """
    document.querySelector('.computorium-session-footer-meta').textContent.trim()
    """

  @Test(arguments: [BrowserEngine.chrome])
  func theFooterSaysTheContextAndGoesOnLive(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphonID = UUID().uuidString.lowercased()
    let nocturneID = UUID().uuidString.lowercased()
    let name = "context-line-\(UUID().uuidString).html"
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
      // As `SessionStream` records a call: its usage, as JSON, under `content`.
      let call = #"[{"purpose":"explication","provider":"deepseek","model":"deepseek-flash","input_tokens":67063,"output_tokens":845,"reasoning_tokens":512,"context_tokens":1048576,"latency_ms":1,"started_at":1,"finished_at":2}]"#
      let recorded: [[String: String]] = [
        ["type": "thinking", "content": "Reading."],
        ["type": "usage", "content": call],
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
        // Recorded: the trace's one call.
        try await page.openHydrated(antiphon)
        #expect(
          try await page.evaluate(Self.footer, as: String.self)
            == "context 67,063 of 1,048,576, input 67,063, output 845 (thinking 512)")

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
            lines.push(\(Self.footer))
            // The trace from its start: its first round's usage first.
            window.__emit({ type: 'thinking', reset: '1', text: 'Reading.' })
            window.__emit({ type: 'usage', input_tokens: 1200, output_tokens: 300, reasoning_tokens: 120,
              context_input_tokens: 1200, context_tokens: 1048576 })
            await window.__frames()
            lines.push(\(Self.footer))
            // The next round's: the context is its input, the tokens summed.
            window.__emit({ type: 'usage', input_tokens: 67063, output_tokens: 845, reasoning_tokens: 512,
              context_input_tokens: 67063, context_tokens: 1048576 })
            await window.__frames()
            lines.push(\(Self.footer))
            // A search: its tokens, the context as it was.
            window.__emit({ type: 'usage', input_tokens: 0, output_tokens: 0 })
            await window.__frames()
            lines.push(\(Self.footer))
            return lines
          })()
          """, as: [String].self)
        #expect(lines == [
          "context —, input —, output —",
          "context 1,200 of 1,048,576, input 1,200, output 300 (thinking 120)",
          "context 67,063 of 1,048,576, input 68,263, output 1,145 (thinking 632)",
          "context 67,063 of 1,048,576, input 68,263, output 1,145 (thinking 632)",
        ], "\(lines)")
        #expect(
          try await page.evaluate(
            "document.querySelector('.computorium-session-view').dataset.contextUsage", as: String.self)
            == "67063 1048576 68263 1145 632")
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
