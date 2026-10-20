import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Image attachment preview", .serialized)
struct ImageAttachmentTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func boundedInlineImageUsesResultDatum(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    guard let path = ProcessInfo.processInfo.environment["GNORIUM_IMAGE_FIXTURE_PATH"],
      FileManager.default.fileExists(atPath: path) else {
      try Test.cancel("Export the actual ComputoriumSessionView image fixture first.")
    }
    let name = "image-layout-\(UUID().uuidString).html"
    let file = URL(fileURLWithPath: "/Users/Madhavik/Downloads/Gnorium/gnorium-web/Public").appendingPathComponent(name)
    try Data(contentsOf: URL(fileURLWithPath: path)).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/\(name)")
      try await page.locator(".computorium-session-tool-call-rendered summary").click()
      let geometry = try await page.evaluate("""
        (() => {
          const box = document.querySelector('.computorium-session-tool-call-result-box');
          const view = box.querySelector('.expandable-attachment-view[data-presentation="inline"]');
          const viewport = view.querySelector('.expandable-attachment-image-viewport');
          const datum = view.closest('.datum-value'), style = getComputedStyle(datum);
          const width = datum.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
          const r = viewport.getBoundingClientRect();
          return view.dataset.attachmentHydrated === 'true' && view.querySelectorAll('img').length === 1
            && r.height > 0 && r.height <= innerHeight * .64 + 1 && Math.abs(r.width - width) < 1
            && box.querySelector('.datum-view') && !document.querySelector('.detail-page-image')
            && !document.querySelector('.expandable-attachment-dialog, .expandable-attachment-image-trigger');
        })()
        """, as: Bool.self)
      #expect(geometry, "One bounded inline image fills its result datum alongside the recorded tool fields")
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func liveToolImageHydratesAfterInsertion(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    // The region as the trace records it sent: a IIIF request this server
    // answers at any path under the page's service.
    let fixture = try await FixtureServer.threePageManifest()
    let sent = fixture.baseURL + "/page-1/pct:0,0,100,100/max/0/default.jpg"
    let nocturneID = UUID().uuidString.lowercased()
    let antiphonID = UUID().uuidString.lowercased()
    let name = "image-live-\(UUID().uuidString).html"
    let file = URL(fileURLWithPath: "/Users/Madhavik/Downloads/Gnorium/gnorium-web/Public").appendingPathComponent(name)
    do {
      let user = try admin.column("id")
      let preparing: [[String: String]] = [["type": "thinking", "content": "Preparing the image fixture."]]
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, image_service_ids_json, processing_status, created_at, updated_at)
          VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted', now(), now());
        INSERT INTO bibliographic_explication_nocturnes (id, submission_id, process, image, instance, provider, model, result, nocturne_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
          VALUES ('\(nocturneID)', (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'),
            'explication', '1', 1, 'fixture', 'fixture', 'passed',
            gen_random_uuid(), '\(antiphonID)', 1, now());
        \(try SessionTrace.append(preparing, table: "bibliographic_explication_nocturnes", id: nocturneID))
        COMMIT;
        """)
      let antiphon = "/mission-control/antiphons/bibliographic/\(antiphonID)"
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(antiphon)
        let original = try await page.evaluate("fetch('\(antiphon)').then(r=>r.text())", as: String.self)
        let mock = """
          <script>
          window.__imageMock='installed'; window.__errs=[]; window.addEventListener('error',e=>window.__errs.push(String(e.message)));
          window.EventSource=class {
            constructor(url) { window.__imageMockURL=url; window.__imageMock='constructed'; this.handlers={}; setTimeout(()=>{
              window.__imageMock='emitted';
              this.emit('start','{}');
              this.emit('chunk',JSON.stringify({type:'tool',image:'1',name:'view_canvas',arguments:'{"label":"1"}',result:JSON.stringify({ok:true,canvas:'1',source_width:3000,source_height:4000,sent_width:900,sent_height:1200}),status:'ok',call_id:'late-image'}));
              this.emit('chunk',JSON.stringify({type:'image_sent',image:'1',url:'\(sent)'}));
              this.emit('chunk',JSON.stringify({type:'thinking',image:'1',text:'Reading the page live.'}));
            },500); }
            addEventListener(name,fn) { (this.handlers[name]??=[]).push(fn); }
            emit(name,data) { window.__imageMockHandlers=Object.keys(this.handlers); for(const fn of this.handlers[name]??[])fn({data}); }
            close() {}
          };
          </script>
          """
        try original.replacingOccurrences(of:"<head>",with:"<head>"+mock)
          .replacingOccurrences(of:"data-auto-watch=\"0\"",with:"data-auto-watch=\"1\"")
          .write(to:file,atomically:true,encoding:.utf8)
        try await page.openHydrated("/\(name)")
        // The image the model received, once, in its round's message (user,
        // 2026-10-17): the full-width stage, never inside the tool's card.
        let image = page.locator(".computorium-session-view .expandable-attachment-view[data-presentation='received']")
        do { try await expect(image).toBeAttached() } catch {
          print(try await page.evaluate("JSON.stringify({mock:window.__imageMock,auto:document.querySelector('.process-container')?.dataset.autoWatch,kind:document.querySelector('.process-container')?.dataset.computoriumCoreKind,tools:document.querySelectorAll('.computorium-session-tool-call').length,url:window.__imageMockURL,handlers:window.__imageMockHandlers,focus:document.querySelector('.computorium-session-view')?.dataset.computoriumSessionImage,output:!!document.querySelector('.computorium-session-view .computorium-session-output-content'),atts:[...document.querySelectorAll('.expandable-attachment-view')].map(e=>e.dataset.presentation+'@'+(e.closest('[class]')?.parentElement?.className||'')),kids:[...(document.querySelector('.computorium-session-output-content')?.children||[])].map(e=>e.className).slice(-6),errs:window.__errs})",as:String.self))
          throw error
        }
        // Live, a tool card arrives closed and the thinking card open, each
        // left as it arrived (user, 2026-10-10).
        let arrived = try await page.evaluate("""
          (()=>{const el=document.querySelector('#computorium-session-tool-late-image');
            const tool=el.matches('details')?el:(el.closest('details')||el.querySelector('details'));
            const t=document.querySelector("[id^='computorium-session-thinking-live-']")||document.querySelector('.computorium-session-output-thinking');
            const thinking=t&&(t.matches('details')?t:(t.querySelector('details')||t.closest('details')));
            return 'tool ' + (tool ? (tool.hasAttribute('open') ? 'open' : 'closed') : 'none') + ', thinking ' + (thinking ? (thinking.hasAttribute('open') ? 'open' : 'closed') : 'none');})()
          """, as: String.self)
        #expect(arrived == "tool closed, thinking open", "A live tool card arrives closed; the thinking card open: \(arrived)")
        try await page.locator("#computorium-session-tool-late-image summary").click()
        // Opened, the card holds the tool's fields and no image; the image
        // stands once, in the round's message, ready to zoom once read.
        var shown = false
        for _ in 0..<50 where !shown {
          shown = try await page.evaluate(
            "(()=>{const v=document.querySelectorAll(\".computorium-session-view .expandable-attachment-view[data-presentation='received']\");return v.length===1&&v[0].dataset.attachmentHydrated==='true'&&v[0].getBoundingClientRect().height>0})()",
            as: Bool.self)
          if !shown { try await Task.sleep(for: .milliseconds(100)) }
        }
        #expect(shown, "A late SSE tool's image stands once in its round's message, hydrated")
        let card = try await page.evaluate("""
          (()=>{const card=document.querySelector('#computorium-session-tool-late-image');const box=card.querySelector('.computorium-session-tool-call-result-box');return !card.querySelector('.expandable-attachment-view') && !!box && box.textContent.includes('source_width') && box.textContent.includes('sent_width');})()
          """, as: Bool.self)
        #expect(card, "The tool's card shows its fields and no image")
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      try? FileManager.default.removeItem(at:file)
      _ = try? TestAdmin.query(SessionTrace.delete(table: "bibliographic_explication_nocturnes", where: "id='\(nocturneID)'")
        + "DELETE FROM bibliographic_explication_nocturnes WHERE id='\(nocturneID)'; DELETE FROM bibliographic_antiphons WHERE id='\(antiphonID)';")
      work.remove()
      try await admin.remove(after:error)
    }
    try? FileManager.default.removeItem(at:file)
    _ = try TestAdmin.query(SessionTrace.delete(table: "bibliographic_explication_nocturnes", where: "id='\(nocturneID)'")
      + "DELETE FROM bibliographic_explication_nocturnes WHERE id='\(nocturneID)'; DELETE FROM bibliographic_antiphons WHERE id='\(antiphonID)';")
    work.remove()
    try await admin.remove()
  }

}
