import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Following the stream (user, 2026-10-17): as tokens arrive, a growing
/// card's capped box keeps its own end in view and the page keeps the
/// transcript's end in view. A reader who scrolls an element up stops it
/// following—the box and the page each on its own—and scrolling it back to
/// its end resumes it.
@Suite("Stream follow", .serialized)
struct StreamFollowTests {
  struct State: Decodable {
    /// The live thinking card's capped box overflows its cap.
    let overflows: Bool
    /// That box is at its end, within one of its lines.
    let boxAtEnd: Bool
    let boxTop: Double
    /// The transcript's end is in view, within one of its lines.
    let tailInView: Bool
    let scrollY: Double
    let tailBottom: Double
    let viewport: Double
  }

  /// Emits `chunks` thinking suffixes into the open card, then waits for
  /// the stream's frame to settle, and reads the state.
  static func emit(_ chunks: Int, from start: Int) -> String {
    """
    (async () => {
      for (let i = \(start); i < \(start + chunks); i++)
        window.__emit({ type: 'thinking', append: '1', text: 'Reasoning line ' + i + ' about the page.\\n\\n' })
      await window.__frames()
      return window.__state()
    })()
    """
  }

  static let state = "(async () => { await window.__frames(); return window.__state() })()"

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func boxesAndThePageFollowUntilScrolledUp(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphonID = UUID().uuidString.lowercased()
    let nocturneID = UUID().uuidString.lowercased()
    let name = "stream-follow-\(UUID().uuidString).html"
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
      let recorded: [[String: String]] = [["type": "thinking", "content": "Preparing the stream-follow fixture."]]
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
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(antiphon)
        let original = try await page.evaluate("fetch('\(antiphon)').then(r=>r.text())", as: String.self)
        // A watch whose frames the test sends, one by one.
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
          window.__line=(el)=>{ const s=getComputedStyle(el); return parseFloat(s.lineHeight)||parseFloat(s.fontSize)*1.2 };
          window.__state=()=>{
            const cards=document.querySelectorAll(".computorium-session-output-content .computorium-session-output-thinking");
            const box=cards[cards.length-1].querySelector('.computorium-session-output-thinking-body');
            // The transcript draws as its contents (display: contents): its end
            // is its last block's end (a range would count text scrolled away
            // inside a box).
            const tail=document.querySelector('.computorium-session-view .computorium-session-output-content').lastElementChild;
            const r=tail.getBoundingClientRect();
            return { overflows: box.scrollHeight>box.clientHeight+1,
              boxAtEnd: box.scrollHeight-box.clientHeight-box.scrollTop<=window.__line(box), boxTop: box.scrollTop,
              tailInView: r.bottom>=0 && r.bottom-innerHeight<=window.__line(document.querySelector('.computorium-session-view .computorium-session-output-content').parentElement), scrollY: window.scrollY, tailBottom: r.bottom, viewport: innerHeight };
          };
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
        // The transcript, taller than the viewport, ending in a thinking
        // card as it opens.
        let prose = (1...80).map { "Paragraph \($0) of the page's reply, long enough to wrap." }.joined(separator: "\n\n")
        let proseJS = String(decoding: try JSONSerialization.data(withJSONObject: [prose]), as: UTF8.self)
        _ = try await page.evaluate("""
          (async () => {
            window.__emit({ type: 'text', reset: '1', text: \(proseJS)[0] })
            window.__emit({ type: 'thinking', text: 'Reasoning opens.\\n\\n' })
            await window.__frames()
            // The reader at the page's end: following.
            window.scrollTo(0, document.documentElement.scrollHeight)
            await window.__frames()
            return true
          })()
          """)
        // Tokens keep the box and the page at their ends.
        var state = try await page.evaluate(Self.emit(40, from: 0), as: State.self)
        #expect(state.overflows && state.boxAtEnd && state.tailInView, "The box and the page follow: \(state)")

        // The box scrolled up stops following; the page still follows.
        _ = try await page.evaluate("""
          (async () => { const cards = document.querySelectorAll('.computorium-session-output-thinking')
            cards[cards.length - 1].querySelector('.computorium-session-output-thinking-body').scrollTop = 0
            await window.__frames(); return true })()
          """)
        state = try await page.evaluate(Self.emit(20, from: 40), as: State.self)
        #expect(state.boxTop < 1 && !state.boxAtEnd, "The box the reader scrolled up stays put: \(state)")
        #expect(state.tailInView, "The page still follows: \(state)")

        // Back at its end, the box follows again.
        _ = try await page.evaluate("""
          (async () => { const cards = document.querySelectorAll('.computorium-session-output-thinking')
            const box = cards[cards.length - 1].querySelector('.computorium-session-output-thinking-body')
            box.scrollTop = box.scrollHeight; await window.__frames(); return true })()
          """)
        state = try await page.evaluate(Self.emit(20, from: 60), as: State.self)
        #expect(state.boxAtEnd && state.tailInView, "Scrolled back to its end, the box follows again: \(state)")

        // The page scrolled up stops following; the box still follows.
        let readerY = try await page.evaluate("""
          (async () => { window.scrollTo(0, Math.max(0, window.scrollY - innerHeight)); await window.__frames(); return window.scrollY })()
          """, as: Double.self)
        state = try await page.evaluate(Self.emit(20, from: 80), as: State.self)
        #expect(abs(state.scrollY - readerY) < 1 && !state.tailInView, "The page the reader scrolled up stays put: \(readerY) → \(state)")
        #expect(state.boxAtEnd, "The box still follows: \(state)")

        // Back at the page's end, the page follows again.
        _ = try await page.evaluate("""
          (async () => { window.scrollTo(0, document.documentElement.scrollHeight); await window.__frames(); return true })()
          """)
        state = try await page.evaluate(Self.emit(20, from: 100), as: State.self)
        #expect(state.tailInView && state.boxAtEnd, "Scrolled back to its end, the page follows again: \(state)")
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
