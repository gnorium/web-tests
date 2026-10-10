import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Canvas attachment preview", .serialized)
struct CanvasAttachmentTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func boundedInlineImageUsesResultDatum(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    guard let path = ProcessInfo.processInfo.environment["GNORIUM_CANVAS_FIXTURE_PATH"],
      FileManager.default.fileExists(atPath: path) else {
      try Test.cancel("Export the actual ComputoriumSessionView canvas fixture first.")
    }
    let name = "canvas-layout-\(UUID().uuidString).html"
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
    let runID = UUID().uuidString.lowercased()
    let antiphonID = UUID().uuidString.lowercased()
    let name = "canvas-live-\(UUID().uuidString).html"
    let file = URL(fileURLWithPath: "/Users/Madhavik/Downloads/Gnorium/gnorium-web/Public").appendingPathComponent(name)
    do {
      let user = try admin.column("id")
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, canvas_service_ids_json, processing_status, created_at, updated_at)
          VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted', now(), now());
        INSERT INTO bibliographic_explication_runs (id, submission_id, process, canvas, attempt, provider, model, output, result, run_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
          VALUES ('\(runID)', (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'),
            'explication', '1', 1, 'fixture', 'fixture', '[{"type":"thinking","content":"Preparing the canvas fixture."}]', 'passed',
            gen_random_uuid(), '\(antiphonID)', 1, now());
        COMMIT;
        """)
      let antiphon = "/mission-control/antiphons/bibliographic/\(antiphonID)"
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(antiphon)
        let original = try await page.evaluate("fetch('\(antiphon)').then(r=>r.text())", as: String.self)
        let mock = """
          <script>
          window.__canvasMock='installed';
          window.EventSource=class {
            constructor(url) { window.__canvasMockURL=url; window.__canvasMock='constructed'; this.handlers={}; setTimeout(()=>{
              window.__canvasMock='emitted';
              this.emit('start','{}');
              const src='data:image/svg+xml;base64,'+btoa('<svg xmlns="http://www.w3.org/2000/svg" width="3000" height="4000"><rect width="3000" height="4000" fill="#e7dec7"/></svg>');
              this.emit('chunk',JSON.stringify({type:'tool',canvas:'1',name:'view_canvas',arguments:'{"label":"1"}',result:JSON.stringify({ok:true,canvas:'1',page_url:src,crop_url:src,source_width:3000,source_height:4000,sent_width:900,sent_height:1200}),status:'ok',call_id:'late-canvas'}));
              this.emit('chunk',JSON.stringify({type:'thinking',canvas:'1',text:'Reading the page live.'}));
            },500); }
            addEventListener(name,fn) { (this.handlers[name]??=[]).push(fn); }
            emit(name,data) { window.__canvasMockHandlers=Object.keys(this.handlers); for(const fn of this.handlers[name]??[])fn({data}); }
            close() {}
          };
          </script>
          """
        try original.replacingOccurrences(of:"<head>",with:"<head>"+mock)
          .replacingOccurrences(of:"data-auto-watch=\"0\"",with:"data-auto-watch=\"1\"")
          .write(to:file,atomically:true,encoding:.utf8)
        try await page.openHydrated("/\(name)")
        let image = page.locator("#computorium-session-tool-late-canvas .expandable-attachment-image-viewport")
        do { try await expect(image).toBeAttached() } catch {
          print(try await page.evaluate("JSON.stringify({mock:window.__canvasMock,auto:document.querySelector('.process-container')?.dataset.autoWatch,kind:document.querySelector('.process-container')?.dataset.computoriumCoreKind,tools:document.querySelectorAll('.computorium-session-tool-call').length,url:window.__canvasMockURL,handlers:window.__canvasMockHandlers,focus:document.querySelector('.computorium-session-view')?.dataset.computoriumSessionCanvas,output:!!document.querySelector('.computorium-session-view .computorium-session-output-content')})",as:String.self))
          throw error
        }
        // Live, a tool card arrives closed and the thinking card open, each
        // left as it arrived (user, 2026-10-10).
        let arrived = try await page.evaluate("""
          (()=>{const el=document.querySelector('#computorium-session-tool-late-canvas');
            const tool=el.matches('details')?el:(el.closest('details')||el.querySelector('details'));
            const t=document.querySelector("[id^='computorium-session-thinking-live-']")||document.querySelector('.computorium-session-output-thinking');
            const thinking=t&&(t.matches('details')?t:(t.querySelector('details')||t.closest('details')));
            return 'tool ' + (tool ? (tool.hasAttribute('open') ? 'open' : 'closed') : 'none') + ', thinking ' + (thinking ? (thinking.hasAttribute('open') ? 'open' : 'closed') : 'none');})()
          """, as: String.self)
        #expect(arrived == "tool closed, thinking open", "A live tool card arrives closed; the thinking card open: \(arrived)")
        try await page.locator("#computorium-session-tool-late-canvas summary").click()
        // The detail in place: in the result box with every field the model
        // received, its image its `image` datum's width and no taller than the bound,
        // no chip and no lightbox (user, 2026-10-07).
        let parity = try await page.evaluate("""
          (()=>{const card=document.querySelector('#computorium-session-tool-late-canvas');const box=card.querySelector('.computorium-session-tool-call-result-box');const view=box&&box.querySelector('.expandable-attachment-view[data-presentation="inline"]');const vp=view&&view.querySelector('.expandable-attachment-image-viewport');const r=vp?vp.getBoundingClientRect():{height:0,width:0};const v=view&&view.closest('.datum-value');const cs=v?getComputedStyle(v):null;const w=v?v.clientWidth-parseFloat(cs.paddingLeft)-parseFloat(cs.paddingRight):Infinity;return !!view && view.dataset.attachmentHydrated==='true' && r.height>0 && r.height<=innerHeight*.64+1 && r.width>=w-1 && !card.querySelector('.expandable-attachment-dialog') && box.textContent.includes('source_width') && box.textContent.includes('sent_width');})()
          """, as:Bool.self)
        #expect(parity,"A late SSE tool's zoom is in place in its result box with its fields")
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      try? FileManager.default.removeItem(at:file)
      _ = try? TestAdmin.query("DELETE FROM bibliographic_explication_runs WHERE id='\(runID)'; DELETE FROM bibliographic_antiphons WHERE id='\(antiphonID)';")
      work.remove()
      try await admin.remove(after:error)
    }
    try? FileManager.default.removeItem(at:file)
    _ = try TestAdmin.query("DELETE FROM bibliographic_explication_runs WHERE id='\(runID)'; DELETE FROM bibliographic_antiphons WHERE id='\(antiphonID)';")
    work.remove()
    try await admin.remove()
  }

}
