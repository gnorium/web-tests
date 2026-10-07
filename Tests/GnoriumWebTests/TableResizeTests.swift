import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A table's column is resized by its heading's handle: a drag widens it, a
/// double-click fits it to its values (TableView). A column that fits its
/// heading (`fitsHeader`, the records lists' Treatment) can still be dragged
/// wider, and a double-click fits it back to its heading alone. With a mouse,
/// at desktop width.
@Suite("Table resize", .serialized)
struct TableResizeTests {
  struct Width: Decodable {
    let width: Double
  }

  /// The column heading's rendered width.
  static func width(_ page: Page, _ column: String) async throws -> Double {
    try await page.evaluate(
      "({ width: document.querySelector(\"main .table-table th[data-table-column-id='\(column)']\").getBoundingClientRect().width })",
      as: Width.self
    ).width
  }

  /// Drags `column`'s handle `by` pixels along the line, in steps.
  static func drag(_ page: Page, _ column: String, by distance: Double) async throws {
    let handle = page.locator("main .table-table th[data-table-column-id='\(column)'] .table-resizer")
    guard let box = try await handle.boundingBox() else {
      Issue.record("\(column): its resize handle is not shown")
      return
    }
    let x = box.x + box.width / 2
    let y = box.y + box.height / 2
    try await page.mouse.down(x: x, y: y)
    for step in 1...4 {
      try await page.mouse.move(x: x + distance * Double(step) / 4, y: y)
    }
    try await page.mouse.up(x: x + distance, y: y)
  }

  static func fit(_ page: Page, _ column: String) async throws {
    try await page.locator("main .table-table th[data-table-column-id='\(column)'] .table-resizer").dblclick()
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func recordTitlesStartReadableAndKeepExplicitResizing(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      for path in ["/biblio-records", "/lexico-records"] {
        try await page.openHydrated(path)
        try await page.expectNoErrors()
        let initial = try await Self.width(page, "title")
        if layout == .desktop {
          #expect(initial >= 300, "\(path): default desktop Title is \(initial), expected readable 320px descriptor")
        } else {
          #expect(initial >= 140, "\(path): phone priority Title must remain readable (\(initial))")
        }
        _ = try await page.evaluate("(() => { document.querySelector('main th[data-table-column-id=\"title\"] .table-resizer').scrollIntoView({ block: 'center', inline: 'center' }); return true; })()", as: Bool.self)
        try await Self.drag(page, "title", by: 120)
        let resized = try await Self.width(page, "title")
        #expect(resized > initial + 100, "\(path): Title must respond to an actual handle drag")
        try await expect(page.locator("main .table-table")).toHaveAttribute("data-manually-resized", "true")
        // A viewport change must keep the explicitly pinned colgroup geometry.
        let pinned = try await page.evaluate("document.querySelector('main col[data-table-column-id=\"title\"]').getAttribute('width')", as: String.self)
        let alternate = layout == .desktop ? Layout.phone : Layout.desktop
        try await page.setViewport(alternate.viewport(for: engine))
        let retained = try await page.evaluate("document.querySelector('main col[data-table-column-id=\"title\"]').getAttribute('width')", as: String.self)
        #expect(retained == pinned, "\(path): viewport change must retain the explicitly resized colgroup width")
        try await expect(page.locator("main .table-table")).toHaveAttribute("data-manually-resized", "true")
        try await page.setViewport(layout.viewport(for: engine))
        try await page.openHydrated(path)
        let restored = try await Self.width(page, "title")
        #expect(abs(restored - initial) < 3, "\(path): reload should restore its readable default")
      }
    }
  }

  @Test(arguments: gnorium.engines)
  func aColumnIsDraggedWiderAndFitsOnADoubleClick(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine)) { page in
      for (path, column) in [("/lexico-records", "language"), ("/biblio-records", "type"), ("/mission-control/lifecycles/bibliographic", nil)] {
        try await page.openHydrated(path)
        try await page.expectNoErrors()
        let id: String
        if let column {
          id = column
        } else {
          // The first column with a handle shown.
          id = try await page.evaluate(
            """
            [...document.querySelectorAll('main .table-table th[data-table-column-id]')]
              .find((th) => { const r = th.querySelector('.table-resizer'); return r && r.getBoundingClientRect().width > 0 })
              .getAttribute('data-table-column-id')
            """, as: String.self)
        }
        let before = try await Self.width(page, id)
        try await Self.drag(page, id, by: 120)
        let dragged = try await Self.width(page, id)
        #expect(dragged > before + 100, "\(path) \(id): dragged 120 wider, \(before) became \(dragged)")
        try await Self.fit(page, id)
        let fitted = try await Self.width(page, id)
        #expect(fitted < dragged - 20, "\(path) \(id): a double-click left it \(fitted) (dragged to \(dragged))")
      }
    }
  }

  @Test(arguments: gnorium.engines)
  func aColumnThatFitsItsHeadingIsDraggedWiderAndFitsBack(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine)) { page in
      for path in ["/biblio-records", "/lexico-records"] {
        try await page.openHydrated(path)
        try await page.expectNoErrors()
        try await expect(page.locator("main th[data-table-column-id='treatment']")).toHaveAttribute("data-fits-header", "true")
        let before = try await Self.width(page, "treatment")
        try await Self.drag(page, "treatment", by: 120)
        let dragged = try await Self.width(page, "treatment")
        #expect(dragged > before + 100, "\(path): Operation dragged 120 wider, \(before) became \(dragged)")
        try await Self.fit(page, "treatment")
        let fitted = try await Self.width(page, "treatment")
        let heading = try await page.evaluate(
          """
          (() => {
            const th = document.querySelector("main th[data-table-column-id='treatment']")
            const style = getComputedStyle(th)
            return { width: th.querySelector('.table-header-label, .table-sort-button').scrollWidth
              + parseFloat(style.paddingLeft) + parseFloat(style.paddingRight) }
          })()
          """, as: Width.self
        ).width
        #expect(fitted < dragged - 20, "\(path): a double-click left Operation \(fitted) (dragged to \(dragged))")
        #expect(abs(fitted - heading) < 4, "\(path): Operation fits to \(fitted), its heading is \(heading)")
      }
    }
  }
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func dashboardTablesResizeAfterLiveUpdates(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/mission-control")
      // Install observation before the client starts, using the actual public
      // dashboard HTML on the same origin. A hydrated original table is not
      // evidence that an SSE replacement was rehydrated.
      let original = try await page.evaluate("fetch('/mission-control').then(response => response.text())", as: String.self)
      let observer = """
        <script>
        (() => {
          const ids = ['workers-summary', 'recent-activity'];
          const first = new Map(), replaced = new Set();
          window.__liveTablesReplaced = false;
          const observer = new MutationObserver(() => {
            for (const id of ids) {
              const table = document.querySelector(`#live-region-${id} .table-view`);
              if (!table) continue;
              if (!first.has(id)) first.set(id, table);
              else if (first.get(id) !== table && table.dataset.tableHydrated === 'true') replaced.add(id);
            }
            if (replaced.size === ids.length) {
              window.__liveTablesReplaced = true;
              observer.disconnect();
            }
          });
          observer.observe(document.documentElement, {childList: true, subtree: true, attributes: true});
        })();
        </script>
        """
      let name = "dashboard-live-resize-\(UUID().uuidString).html"
      let file = URL(fileURLWithPath: "/Users/Madhavik/Downloads/Gnorium/gnorium-web/Public").appendingPathComponent(name)
      try original.replacingOccurrences(of: "<head>", with: "<head>" + observer).write(to: file, atomically: true, encoding: .utf8)
      defer { try? FileManager.default.removeItem(at: file) }
      try await page.openHydrated("/\(name)")
      let liveTablesReady = try await page.evaluate("""
        new Promise(resolve => {
          const deadline = Date.now() + 15000;
          const check = () => {
            if (window.__liveTablesReplaced) resolve(true);
            else if (Date.now() >= deadline) resolve(false);
            else setTimeout(check, 50);
          };
          check();
        })
        """, as: Bool.self)
      #expect(liveTablesReady, "Observed SSE replacement nodes receive table interaction bindings")
      for selector in [".mission-control-workers-table", ".mission-control-dashboard-recent-activity-table"] {
        let headerSelector = "\(selector) th[data-table-column-id]:first-child"
        let before = try await page.evaluate("document.querySelector(\"\(headerSelector)\").getBoundingClientRect().width", as: Double.self)
        let handle = page.locator("\(headerSelector) .table-resizer")
        _ = try await page.evaluate("document.querySelector(\"\(headerSelector) .table-resizer\").scrollIntoView({block: 'center', inline: 'center'})")
        guard let box = try await handle.boundingBox() else { Issue.record("No resize handle for \(selector)"); continue }
        let x = box.x + box.width / 2, y = box.y + box.height / 2
        try await page.mouse.down(x: x, y: y)
        for step in 1...4 { try await page.mouse.move(x: x + 80 * Double(step) / 4, y: y) }
        try await page.mouse.up(x: x + 80, y: y)
        let after = try await page.evaluate("document.querySelector(\"\(headerSelector)\").getBoundingClientRect().width", as: Double.self)
        #expect(after > before + 60, "\(selector) drag must change its column width: \(before) -> \(after)")
        try await handle.dblclick()
      }
      // Each process links its prompt page and its snapshots.
      try await expect(page.locator("main a[href*='/mission-control/prompts/']")).toHaveCount(4)
      try await page.expectNoErrors()
      try await page.expectNoHorizontalOverflow()
    }
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func sharedPoolAdminFieldsFillWidthAndActionsShareRow(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    guard let path = ProcessInfo.processInfo.environment["GNORIUM_WORKERS_FIXTURE_PATH"],
      FileManager.default.fileExists(atPath: path) else {
      try Test.cancel("Export the actual shared worker admin view first.")
    }
    let name = "workers-layout-\(UUID().uuidString).html"
    let file = URL(fileURLWithPath: "/Users/Madhavik/Downloads/Gnorium/gnorium-web/Public").appendingPathComponent(name)
    try Data(contentsOf: URL(fileURLWithPath: path)).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/\(name)")
      try await expect(page.locator("h1")).toHaveText("Workers")
      try await expect(page.locator("#worker-count")).toHaveAttribute("value", "4")
      let geometry = try await page.evaluate("""
        (() => {
          const content = document.querySelector('.workers-content');
          const count = document.querySelector('#worker-count');
          const buttons = [...content.querySelectorAll('.mission-control-worker-control-actions button')];
          const box = content.getBoundingClientRect();
          const input = count.getBoundingClientRect();
          const rects = buttons.map(button => button.getBoundingClientRect());
          const fields = [...content.querySelectorAll('.datum-view')];
          return Math.abs(input.width - box.width) < 4
            && fields.every(field => Math.abs(field.getBoundingClientRect().width - box.width) < 4)
            && rects.length === 2 && Math.abs(rects[0].top - rects[1].top) < 4
            && buttons[0].form?.getAttribute('action') === '/mission-control/workers/count'
            && buttons[1].form?.getAttribute('action') === '/mission-control/workers'
            && buttons[0].textContent.trim() === 'Save Worker Count'
            && buttons[1].textContent.trim() === 'Start';
        })()
        """, as: Bool.self)
      #expect(geometry, "Global fields fill available width and Save/Start share one row at supported widths")
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func sharedComputoriumPoolIsPublicFromBothDashboardKinds(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      for kind in ["bibliographic", "lexicographic"] {
        try await page.openHydrated("/mission-control/\(kind)")
        let link = page.locator(".mission-control-workers-table a[href='/mission-control/workers']")
        try await expect(link).toHaveCount(1)
        try await expect(link).toHaveText("Worker 1")
        try await expect(page.locator(".mission-control-workers-table th[data-table-column-id='pipeline']")).toHaveCount(0)
        if layout == .phone { try await link.tap() }
        else { try await link.click() }
        try await expect(page.locator("h1")).toHaveText("Workers")
        try await expect(page.locator(".mission-control-worker-settings .datum-view")).toHaveCount(6)
        try await expect(page.locator("main input[name='count'], main input[name='enabled']")).toHaveCount(0)
        let breadcrumb = try await page.evaluate("document.querySelector('.breadcrumb-list')?.textContent || ''", as: String.self)
        #expect(breadcrumb.contains("Workers"))
        #expect(!breadcrumb.contains("Bibliographic") && !breadcrumb.contains("Lexicographic") && !breadcrumb.contains("Explication"))
        try await page.expectNoHorizontalOverflow()
      }
      try await page.expectNoErrors()
      try await page.expectNoHorizontalOverflow()
    }
  }

}
