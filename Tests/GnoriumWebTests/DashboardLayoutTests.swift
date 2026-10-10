import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Dashboard summary and numbered worker layout", .serialized)
struct DashboardLayoutTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func visitorChartsUseTheFigureCardFrame(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/")
      let region = page.locator(".watchtower-visitors-view")
      try await expect(region.locator(".watchtower-visitors-cards .mission-control-dashboard-figure-card-tile")).toHaveCount(6)
      try await expect(region.locator(".watchtower-visitors-trends > .mission-control-dashboard-figure-card-view")).toHaveCount(3)
      #expect(try await page.evaluate("""
        (() => {
          const figure = document.querySelector('.watchtower-visitors-cards .mission-control-dashboard-figure-card-tile');
          const reference = getComputedStyle(figure);
          const properties = ['borderTopWidth', 'borderRightWidth', 'borderBottomWidth', 'borderLeftWidth',
            'borderTopStyle', 'borderTopColor', 'borderRadius', 'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft'];
          const cards = [...document.querySelectorAll('.watchtower-visitors-trends .mission-control-dashboard-figure-card-tile')];
          return cards.length === 3 && cards.every((card, index) => {
            const style = getComputedStyle(card), box = card.getBoundingClientRect();
            const header = card.querySelector('.watchtower-visitors-trend-header');
            const bars = card.querySelector('.watchtower-visitors-weeks');
            const axis = card.querySelector('.watchtower-visitors-trend-axis');
            return properties.every(p => style[p] === reference[p]) && parseFloat(style.borderTopWidth) > 0
              && header.children.length === 2 && header.textContent.includes('per week, last 52 weeks')
              && header.lastElementChild.textContent.startsWith('Highest ')
              && bars.children.length === 52 && axis.children.length === 2
              && [header, bars, axis].every(e => { const r = e.getBoundingClientRect();
                return r.left >= box.left + parseFloat(style.paddingLeft) && r.right <= box.right - parseFloat(style.paddingRight)
                  && r.top >= box.top + parseFloat(style.paddingTop) && r.bottom <= box.bottom - parseFloat(style.paddingBottom); })
              && (index === 0 || box.top > cards[index - 1].getBoundingClientRect().bottom);
          });
        })()
        """, as: Bool.self), "All three charts share the numeric figure card frame and contain their header, bars and date axis")
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }

  /// The Prompts table lists Arbitration first, then Explication and
  /// Translation (user, 2026-10-10); New locutions (1w) links to the
  /// Locutions list under its own Created on filter and is its length.
  @Test(arguments: [BrowserEngine.chrome])
  func promptsListArbitrationFirstAndNewLocutionsIsItsListsLength(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        for tab in ["bibliographic", "lexicographic"] {
          try await page.openHydrated("/mission-control/\(tab)")
          let processes = try await page.evaluate(
            """
            (() => {
              const table = [...document.querySelectorAll('.mission-control-dashboard-section')]
                .find(s => s.querySelector('h2')?.textContent.trim() === 'Prompts');
              return [...table.querySelectorAll('tbody tr')].map(r => r.querySelector('td').textContent.trim()).join(' ');
            })()
            """, as: String.self)
          #expect(processes == "Arbitration Explication Translation", "\(tab): \(processes)")
        }
        let figure = page.locator("a[href='/mission-control/locutions?createdOn=-7d..']").first
        try await expect(figure).toBeAttached()
        let shown = try await figure.innerText()
        let count = shown.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? ""
        try await page.openHydrated("/mission-control/locutions?createdOn=-7d..")
        // One page of rows on dev; a paged list is counted by the server test.
        let listed = try await page.evaluate(
          "document.querySelector('.pagination-view') ? 'paged' : String(document.querySelectorAll('.locution-view').length)",
          as: String.self)
        if listed != "paged" { #expect(count == listed, "figure \(count) vs list \(listed)") }
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }

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
      // A running run's model reads as the Runs page has it, in the row's
      // own sans, size and color (user, 2026-10-08): never mono.
      let model = try await page.evaluate("""
        (()=>{const m=document.querySelector('.mission-control-dashboard-live-telemetry-model');
          const n=m.previousElementSibling;const a=getComputedStyle(m),b=getComputedStyle(n);
          return [a.fontFamily===b.fontFamily && !a.fontFamily.includes('Mono'), a.fontSize===b.fontSize, a.color===b.color].join(' ');})()
        """, as: String.self)
      #expect(model == "true true true", "The telemetry model matches its neighbors: \(model)")
      // A claimed worker's running mark is blue, as every running mark is
      // (the roster's running sector), never the text color it would inherit.
      try await expect(page.locator(".mission-control-dashboard-live-telemetry-worker")).toContainText("1 claimed")
      let mark = try await page.evaluate("""
        (()=>{const s=document.querySelector('.mission-control-dashboard-live-telemetry-worker .rotating-sector-view');
          if(!s) return 'no mark';
          const probe=document.createElement('span');probe.style.color='var(--color-blue)';document.body.appendChild(probe);
          const blue=getComputedStyle(probe).color;probe.remove();
          const text=getComputedStyle(s.parentElement).color;
          return getComputedStyle(s).color===blue && blue!==text ? 'blue' : getComputedStyle(s).color+' vs '+blue;})()
        """, as: String.self)
      #expect(mark == "blue", "The worker's running mark is the running blue: \(mark)")
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
      try await page.openHydrated("/\(workerName)")
      try await expect(page.locator("h1")).toContainText("Worker 2")
      #expect(try await page.evaluate("document.querySelector('.mission-control-worker-view').textContent.includes('Latest 100 assignments.') && !document.querySelector('.mission-control-worker-view').textContent.includes('recorded since')", as: Bool.self))
      try await expect(page.locator(".mission-control-worker-data")).toContainText("Working")
      try await expect(page.locator(".mission-control-worker-data")).toContainText("3 waiting")
      try await expect(page.locator(".mission-control-worker-history-table")).toContainText("Process")
      try await expect(page.locator(".mission-control-worker-history-table")).toContainText("Explication")
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
    // These isolated layout fixtures have no persisted source UUID or prompt folksong endpoint.
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
          const treeFrame=tree?.closest('.outliner-item[data-outliner-accordion=true]');
          const fields=[...document.querySelectorAll('#apparatus-metadata [data-metadata-added=true]')];
          const probe=document.createElement('span');probe.style.borderColor='var(--border-color-green)';document.body.append(probe);
          const green=getComputedStyle(probe).borderTopColor;probe.style.borderColor='var(--border-color-base)';const neutral=getComputedStyle(probe).borderTopColor;probe.remove();
          return meta && treeFrame && fields.length>=3 && getComputedStyle(meta).borderTopColor===neutral
            && getComputedStyle(treeFrame).borderTopColor===neutral && getComputedStyle(treeFrame).borderTopWidth==='1px' && fields.every(e=>getComputedStyle(e).borderTopColor===green && e.textContent.trim()!=='' && e.textContent.trim()!=='—')
            && [...document.querySelectorAll('#apparatus-metadata .datum-view')].some(e=>e.textContent.includes('Pronunciation')&&!e.querySelector('[data-metadata-added=true]'));
        })()
        """, as: Bool.self), "Aggregate metadata and added sentiment frames stay neutral; populated fields green, empty pronunciation neutral")
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
      try await page.openHydrated("/\(ordinaryName)")
      #expect(try await page.evaluate("document.querySelectorAll('[data-record-change=added],[data-tree-change=added],[data-metadata-added=true]').length===0", as: Bool.self))
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }

}
