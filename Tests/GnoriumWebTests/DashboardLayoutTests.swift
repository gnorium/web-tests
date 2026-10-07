import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Dashboard summary and numbered worker layout", .serialized)
struct DashboardLayoutTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func dashboardAndWorkerKeepGeometryAndExactAmounts(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    guard let dashboard = ProcessInfo.processInfo.environment["GNORIUM_DASHBOARD_FIXTURE_PATH"],
      let worker = ProcessInfo.processInfo.environment["GNORIUM_WORKER_VISUAL_FIXTURE_PATH"] else {
      try Test.cancel("Export styled DashboardLayoutFixtureTests fixtures first.")
    }
    let directory = URL(fileURLWithPath: "/Users/Madhavik/Downloads/Gnorium/gnorium-web/Public")
    let name = "dashboard-layout-\(UUID().uuidString).html", workerName = "worker-layout-\(UUID().uuidString).html"
    let file = directory.appendingPathComponent(name), workerFile = directory.appendingPathComponent(workerName)
    try Data(contentsOf: URL(fileURLWithPath: dashboard)).write(to: file)
    try Data(contentsOf: URL(fileURLWithPath: worker)).write(to: workerFile)
    defer { try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: workerFile) }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/\(name)")
      #expect(try await page.evaluate("""
        (()=>{ const grid=document.querySelector('.mission-control-dashboard-needs-attention-view');
          const cards=[...grid.children].map(e=>e.getBoundingClientRect());
          const near=(a,b)=>Math.abs(a-b)<2;
          return cards.length===4 && getComputedStyle(grid).display==='grid'
            && near(cards[0].top,cards[1].top) && near(cards[2].top,cards[3].top)
            && cards[2].top>cards[0].bottom && cards[1].left>cards[0].right
            && near(cards[0].width,cards[1].width) && near(cards[0].left,cards[2].left);
        })()
        """, as: Bool.self), "Four Attention figures form two equal columns and two rows at both widths")
      try await expect(page.locator(".mission-control-dashboard-sections")).toContainText("Summary")
      try await expect(page.locator(".mission-control-dashboard-sections")).toContainText("Attention")
      try await expect(page.locator(".mission-control-dashboard-sections")).toContainText("Telemetry")
      try await expect(page.locator(".mission-control-dashboard-sections")).toContainText("Activity")
      try await expect(page.locator(".mission-control-openrouter-summary")).toContainText("Current balance")
      try await expect(page.locator(".mission-control-openrouter-summary")).toContainText("Usage (all time)")
      try await expect(page.locator(".mission-control-openrouter-summary")).toContainText("$19.70378517")
      try await expect(page.locator(".mission-control-openrouter-summary")).toContainText("$0.29621483")
      try await expect(page.locator(".mission-control-sponsorship-summary")).toContainText("$0.296214830001")
      #expect(try await page.evaluate("""
        (()=>{const boxes=['.mission-control-openrouter-summary','.mission-control-sponsorship-summary'].map(s=>document.querySelector(s));
          return boxes.every(e=>{const s=getComputedStyle(e);return parseFloat(s.borderTopWidth)>0 && parseFloat(s.paddingTop)>0 && parseFloat(s.borderRadius)>0;})
            && boxes[0].getBoundingClientRect().bottom<boxes[1].getBoundingClientRect().top;})()
        """, as: Bool.self), "Provider and sponsorship are distinct ordered boxes")
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
      try await page.openHydrated("/\(workerName)")
      try await expect(page.locator("h1")).toContainText("Worker 2")
      #expect(try await page.evaluate("document.querySelector('.mission-control-worker-view').textContent.includes('Latest 100 assignments.') && !document.querySelector('.mission-control-worker-view').textContent.includes('recorded since')", as: Bool.self))
      try await expect(page.locator(".mission-control-worker-data")).toContainText("Working")
      try await expect(page.locator(".mission-control-worker-data")).toContainText("3 waiting")
      try await expect(page.locator(".mission-control-worker-history-table")).toContainText("Process")
      try await expect(page.locator(".mission-control-worker-history-table")).toContainText("Recognition")
      try await expect(page.locator(".mission-control-worker-history-table a[href=\"/mission-control/antiphons/bibliographic/recorded\"]")).toHaveAttribute("href", "/mission-control/antiphons/bibliographic/recorded")
      try await expect(page.locator(".mission-control-worker-data a")).toHaveAttribute("href", "/mission-control/workers")
      #expect(try await page.evaluate("""
        (()=>{const p=document.querySelector('.mission-control-worker-data');const r=p.getBoundingClientRect();
          return [...p.querySelectorAll('.datum-view')].every(e=>{const b=e.getBoundingClientRect();return b.width>0 && Math.abs(b.width-r.width)<2;});})()
        """, as: Bool.self), "Worker fields fill the available width")
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
      try await page.locator(".mission-control-worker-data a").click()
      try await expect(page.locator("h1")).toContainText("Workers")
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func newRecordPopulatedFieldsAreGreenAndEmptyFieldsStayNeutral(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    guard let path = ProcessInfo.processInfo.environment["GNORIUM_NEW_RECORD_FIXTURE_PATH"] else {
      try Test.cancel("Export new record comparison fixture first.")
    }
    let directory = URL(fileURLWithPath: "/Users/Madhavik/Downloads/Gnorium/gnorium-web/Public")
    let name = "new-record-layout-\(UUID().uuidString).html", ordinaryName = "ordinary-record-layout-\(UUID().uuidString).html"
    let file = directory.appendingPathComponent(name), ordinary = directory.appendingPathComponent(ordinaryName)
    // These isolated layout fixtures have no persisted source UUID or prompt instance endpoint.
    try String(contentsOfFile: path, encoding: .utf8).replacingOccurrences(of: "data-source-url=", with: "data-fixture-source-url=").write(to: file, atomically: true, encoding: .utf8)
    try String(contentsOfFile: path + ".ordinary.html", encoding: .utf8).replacingOccurrences(of: "data-source-url=", with: "data-fixture-source-url=").write(to: ordinary, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: ordinary) }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/\(name)")
      try await expect(page.locator("#fixture-sparse-year")).toHaveValue("1910")
      #expect(try await page.evaluate("document.querySelector('#fixture-sparse-month')===null && document.querySelector('#fixture-sparse-day')===null", as: Bool.self))
      try await expect(page.locator("[data-dropdown-id=fixture-filled-month] button")).toBeVisible()
      try await expect(page.locator("#fixture-filled-day")).toHaveValue("3")
      try await expect(page.locator("#apparatus-metadata")).toHaveAttribute("data-expanded", "true")
      try await expect(page.locator("#apparatus-metadata")).toContainText("Pronunciation")
      try await expect(page.locator("#apparatus-metadata")).toContainText("Inflections")
      #expect(try await page.evaluate("""
        (()=>{const meta=document.querySelector('.record-metadata-change > .metadata-accordion-view > .accordion-view');
          const tree=document.querySelector('[data-tree-change=added] > .sentiment-view > .record-row-view > .accordion-view');
          const fields=[...document.querySelectorAll('#apparatus-metadata [data-metadata-added=true]')];
          const probe=document.createElement('span');probe.style.borderColor='var(--border-color-green)';document.body.append(probe);
          const green=getComputedStyle(probe).borderTopColor;probe.style.borderColor='var(--border-color-base)';const neutral=getComputedStyle(probe).borderTopColor;probe.remove();
          return meta && tree && fields.length>=3 && getComputedStyle(meta).borderTopColor===neutral
            && getComputedStyle(tree).borderTopColor===green && fields.every(e=>getComputedStyle(e).borderTopColor===green && e.textContent.trim()!=='' && e.textContent.trim()!=='—')
            && [...document.querySelectorAll('#apparatus-metadata .datum-view')].some(e=>e.textContent.includes('Pronunciation')&&!e.querySelector('[data-metadata-added=true]'));
        })()
        """, as: Bool.self), "Aggregate metadata opens with neutral frame; new sentiment and populated fields green, empty pronunciation neutral")
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
      try await page.openHydrated("/\(ordinaryName)")
      #expect(try await page.evaluate("document.querySelectorAll('[data-record-change=added],[data-tree-change=added],[data-metadata-added=true]').length===0", as: Bool.self))
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }

}
