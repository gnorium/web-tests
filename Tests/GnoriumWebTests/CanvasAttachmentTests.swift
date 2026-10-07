import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Canvas attachment preview", .serialized)
struct CanvasAttachmentTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func boundedImageAndExistingLightbox(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    guard let path = ProcessInfo.processInfo.environment["GNORIUM_CANVAS_FIXTURE_PATH"],
      FileManager.default.fileExists(atPath: path) else {
      try Test.cancel("Export the actual SessionView canvas fixture first.")
    }
    let name = "canvas-layout-\(UUID().uuidString).html"
    let file = URL(fileURLWithPath: "/Users/Madhavik/Downloads/Gnorium/gnorium-web/Public").appendingPathComponent(name)
    try Data(contentsOf: URL(fileURLWithPath: path)).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/\(name)")
      try await page.locator(".session-tool-call-rendered summary").click()
      let geometry = try await page.evaluate("""
        (() => {
          const box = document.querySelector('.session-tool-call-result-box');
          const image = box.querySelector('.expandable-attachment-image-preview');
          const visibleImages = [...document.querySelectorAll('img')].filter(i => {
            const r=i.getBoundingClientRect(); return r.width>0 && r.height>0 && getComputedStyle(i).visibility !== 'hidden';
          });
          const r=image.getBoundingClientRect(), b=box.getBoundingClientRect();
          return visibleImages.length===1 && r.height>0 && r.height<=innerHeight*.64+1
            && r.left>=b.left-1 && r.right<=b.right+1 && r.top>=b.top-1 && r.bottom<=b.bottom+1
            && Math.abs(r.width/r.height-.75)<.01 && !box.querySelector('.datum-view')
            && !document.querySelector('.detail-page-image');
        })()
        """, as: Bool.self)
      #expect(geometry, "Exactly one bounded image belongs inside the white output surface; metadata stays outside")
      try await page.expectNoHorizontalOverflow()
      try await page.locator(".expandable-attachment-image-trigger").click()
      try await expect(page.locator(".expandable-attachment-dialog")).toHaveAttribute("data-open", "true")
      try await page.locator(".expandable-attachment-dialog .dialog-close-button").click()
      try await expect(page.locator(".expandable-attachment-dialog")).toHaveAttribute("data-open", "false")
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
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, semblance_service_ids_json, processing_status)
          VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO bibliographic_explication_stage_runs (id, submission_id, stage, semblance, attempt, provider, model, output, result, run_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
          VALUES ('\(runID)', (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'),
            'explication', 'Page 1', 1, 'fixture', 'fixture', '[{"type":"thinking","content":"Preparing the canvas fixture."}]', 'passed',
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
              this.emit('chunk',JSON.stringify({type:'tool',name:'view_canvas',arguments:'{"label":"1"}',result:JSON.stringify({ok:true,canvas:'1',page_url:src,detail_url:src,source_width:3000,source_height:4000,sent_width:900,sent_height:1200}),status:'ok',call_id:'late-canvas'}));
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
        let image = page.locator("#session-tool-late-canvas .expandable-attachment-image-preview")
        do { try await expect(image).toBeAttached() } catch {
          print(try await page.evaluate("JSON.stringify({mock:window.__canvasMock,auto:document.querySelector('.pipeline-container')?.dataset.autoWatch,kind:document.querySelector('.pipeline-container')?.dataset.computoriumCoreKind,tools:document.querySelectorAll('.session-tool-call').length,url:window.__canvasMockURL,handlers:window.__canvasMockHandlers,focus:document.querySelector('.session-view')?.dataset.sessionSemblance,output:!!document.querySelector('.session-view .session-output-content')})",as:String.self))
          throw error
        }
        try await page.locator("#session-tool-late-canvas summary").click()
        let parity = try await page.evaluate("""
          (()=>{const card=document.querySelector('#session-tool-late-canvas');const box=card.querySelector('.session-tool-call-result-box');const img=box.querySelector('img');const r=img.getBoundingClientRect();return card.querySelector('.expandable-attachment-view').dataset.attachmentHydrated==='true' && !!box && !box.querySelector('.datum-view') && r.height>0 && r.height<=innerHeight*.64+1 && card.textContent.includes('Source Pixels') && card.textContent.includes('Sent Pixels');})()
          """, as:Bool.self)
        #expect(parity,"A late SSE tool uses the shared bounded preview and hydrates its existing lightbox")
        try await page.locator("#session-tool-late-canvas .expandable-attachment-image-trigger").click()
        try await expect(page.locator("#session-tool-late-canvas .expandable-attachment-dialog")).toHaveAttribute("data-open","true")
        try await page.locator("#session-tool-late-canvas .dialog-close-button").click()
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      try? FileManager.default.removeItem(at:file)
      _ = try? TestAdmin.query("DELETE FROM bibliographic_explication_stage_runs WHERE id='\(runID)'; DELETE FROM bibliographic_antiphons WHERE id='\(antiphonID)';")
      work.remove()
      try await admin.remove(after:error)
    }
    try? FileManager.default.removeItem(at:file)
    _ = try TestAdmin.query("DELETE FROM bibliographic_explication_stage_runs WHERE id='\(runID)'; DELETE FROM bibliographic_antiphons WHERE id='\(antiphonID)';")
    work.remove()
    try await admin.remove()
  }

}
