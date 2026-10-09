import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Review navigation regressions", .serialized)
struct ReviewNavigationTests {
  @Test(arguments: [BrowserEngine.chrome])
  func promptComparisonRetainsSelectionsAcrossServerPages(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let userID = try admin.column("id")
    let ids = (0..<26).map { _ in UUID().uuidString.uppercased() }
    let values = ids.enumerated().map { index, id in
      """
      ('\(id)', '\(id)', 'bibliographic_explication', 'Web tests comparison \(index)', 'Web tests task', false,
       '2026-01-01T00:00:00Z'::timestamptz + interval '\(index) minutes', 'bibliographicOverture',
       gen_random_uuid(), '\(userID)', now())
      """
    }.joined(separator: ",")
    _ = try TestAdmin.query("""
      INSERT INTO prompt_vignettes
        (id, hash, stage, system_prompt, task_prompt, is_proprietary_content, created_at,
         committed_object_type, committed_object_id, committed_by_user_id, committed_at)
      VALUES \(values);
      """)
    func removeVignettes() {
      _ = try? TestAdmin.query("DELETE FROM prompt_vignettes WHERE id IN (\(ids.map { "'\($0)'" }.joined(separator: ","))) AND committed_by_user_id = '\(userID)';")
    }
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        let path = "/mission-control/prompts/bibliographic/explication/vignettes?createdBy=\(admin.username)&sort=createdOn&order=asc"
        try await page.openHydrated(path)
        let rows = page.locator(".prompt-vignettes-table input[name='row-selection']")
        try await expect(rows).toHaveCount(25)
        let first = try await rows.first.getAttribute("value")
        try await rows.first.click()
        #expect(try await page.evaluate("document.querySelector('.compare-button').disabled", as: Bool.self))
        try await page.locator(".prompt-vignettes-table .pagination-next").first.click()
        try await expect(page).toHaveURL("second vignette page") { $0.query?.contains("page=2") == true }
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
        try await expect(rows).toHaveCount(1)
        let second = try await rows.first.getAttribute("value")
        try await rows.first.click()
        #expect(try await page.evaluate("!document.querySelector('.compare-button').disabled", as: Bool.self))
        try await page.locator(".prompt-vignettes-table .pagination-prev").first.click()
        try await expect(rows).toHaveCount(25)
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
        #expect(try await page.evaluate("document.querySelector('input[name=\"row-selection\"]').checked", as: Bool.self))
        // Deselecting and reselecting on the first page must retain the
        // other page's selection, including the header's mixed state.
        try await rows.first.click()
        #expect(try await page.evaluate("document.querySelector('.compare-button').disabled", as: Bool.self))
        try await rows.first.click()
        #expect(try await page.evaluate("document.querySelector('#select-all').indeterminate", as: Bool.self))
        try await page.locator(".compare-button").click()
        try await expect(page.locator(".prompt-compare-content")).toBeVisible()
        let url = try await page.url()
        let query = URLComponents(string: url)?.queryItems ?? []
        #expect(Set(query.filter { ["from", "to"].contains($0.name) }.compactMap(\.value)) == Set([first, second].compactMap { $0 }))
        try await page.expectNoErrors()
      }
    } catch {
      removeVignettes()
      try await admin.remove(after: error)
    }
    removeVignettes()
    try await admin.remove()
  }

  @Test(arguments: [BrowserEngine.chrome])
  func evaluationTimesSortByLocalClockAcrossMidnightAndNoon(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    // The real evaluation page supplies its server-rendered table. Only
    // browser copies of its rows change; evaluation history is read-only.
    try await withPage(engine, gnorium, viewport: .desktop) { page in
      try await page.setTimeZone("America/New_York")
      try await page.openHydrated("/mission-control/evaluations")
      let table = page.locator(".evaluation-runs-table-view").first
      try await expect(table.locator("tbody tr").first).toBeAttached()
      #expect(try await table.evaluate("el => !!el.querySelector('[data-evaluation-time-sort][data-sort-value] time[datetime]')") == .bool(true))
      _ = try await table.evaluate("""
        table => {
          table.id = 'web-tests-time-sort';
          const body = table.querySelector('tbody');
          const source = body.querySelector('tr');
          const rows = [[23, 59], [13, 0], [9, 31], [0, 1], [12, 0], [9, 0]].map(([hour, minute]) => {
            const row = source.cloneNode(true);
            row.dataset.webTestsMinute = String(hour * 60 + minute);
            const cell = row.querySelector('[data-evaluation-time-sort]');
            cell.dataset.sortValue = '9999';
            cell.querySelector('time').dateTime = new Date(2026, 0, 2, hour, minute).toISOString();
            return row;
          });
          body.replaceChildren(...rows);
          return true;
        }
        """)
      let sort = page.locator("#web-tests-time-sort .table-sort-button[data-column-id='createdAt']")
      try await sort.click()
      let ordered = "[...document.querySelectorAll('#web-tests-time-sort tbody tr')].map(row => Number(row.dataset.webTestsMinute))"
      #expect(try await page.evaluate(ordered, as: [Int].self) == [1, 540, 571, 720, 780, 1439])
      #expect(try await page.evaluate("""
        [...document.querySelectorAll('#web-tests-time-sort [data-evaluation-time-sort]')]
          .every(cell => Number(cell.dataset.sortValue) === Number(cell.closest('tr').dataset.webTestsMinute))
        """, as: Bool.self))
      try await sort.click()
      #expect(try await page.evaluate(ordered, as: [Int].self) == [1439, 780, 720, 571, 540, 1])
      // Change the browser's zone without changing the instants: the next
      // sort refreshes the displayed times and their keys together.
      try await page.setTimeZone("Asia/Kolkata")
      try await sort.click()
      #expect(try await page.evaluate("""
        (() => {
          const cells = [...document.querySelectorAll('#web-tests-time-sort [data-evaluation-time-sort]')];
          const values = cells.map(cell => Number(cell.dataset.sortValue));
          return cells.every(cell => {
            const date = new Date(cell.querySelector('time').dateTime);
            return Number(cell.dataset.sortValue) === date.getHours() * 60 + date.getMinutes();
          }) && values.every((value, index) => index === 0 || values[index - 1] <= value);
        })()
        """, as: Bool.self))
      try await page.expectNoErrors()
    }
  }

  @Test(arguments: [BrowserEngine.chrome])
  func replacingTestamentReadersReleasesDetachedKeyboardListeners(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let fixtures = try await FixtureServer.threePageManifest()
    defer { fixtures.stop() }
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated(SubmitTestamentReaderTests.form)
        _ = try await page.evaluate("""
          (() => {
            const matchMedia = window.matchMedia.bind(window);
            window.matchMedia = query => {
              const result = matchMedia(query);
              if (query === '(prefers-reduced-motion: reduce)') Object.defineProperty(result, 'matches', {value: false});
              return result;
            };
            window.webTestsOldReaders = [];
            return true;
          })()
          """)
        let source = page.locator(".submit-testament-form input[name='source-url']")
        let reader = page.locator(".submit-testament-reader")
        for index in 0..<3 {
          // Distinct URLs produce distinct reader storage keys; the local
          // fixture serves the same manifest for each query.
          try await source.fill(fixtures.baseURL + "/manifest.json?reader=\(index)")
          let current = reader.locator(".artifact-view[data-manifest-url$='%3Freader%3D\(index)']")
          try await expect(current.locator("#artifact-page-total"), timeout: .seconds(15)).toHaveText("3")
          try await expect(reader.locator(".artifact-view")).toHaveCount(1)
          try await expect(reader.locator(".artifact-view")).toHaveAttribute("data-artifact-hydrated", "true")
          if index < 2 {
            _ = try await page.evaluate("""
              (() => {
                const root = document.querySelector('.submit-testament-reader .artifact-view');
                const key = 'gnorium:artifact-canvas:' + root.dataset.manifestUrl;
                window.webTestsOldReaders.push({root, key, page: root.querySelector('#artifact-page-input').value,
                  saved: localStorage.getItem(key), changes: 0});
                const entry = window.webTestsOldReaders.at(-1);
                root.addEventListener('artifact-canvas-change', () => entry.changes++);
                return true;
              })()
              """)
          }
        }
        // Focus outside the field so the arrow is a reader command.
        _ = try await page.evaluate("document.activeElement.blur()")
        try await page.keyboard.press("ArrowRight")
        try await expect(reader.locator("#artifact-page-input")).toHaveValue("2")
        #expect(try await page.evaluate("""
          window.webTestsOldReaders.length === 2 && window.webTestsOldReaders.every(entry =>
            !entry.root.isConnected && entry.root.querySelector('#artifact-page-input').value === entry.page
            && entry.changes === 0 && localStorage.getItem(entry.key) === entry.saved)
          """, as: Bool.self))
        // Clearing the last URL also releases its listener without a
        // replacement load to happen to trigger cleanup.
        _ = try await page.evaluate("window.webTestsClearedReader = document.querySelector('.submit-testament-reader .artifact-view')")
        try await source.fill("")
        try await expect(reader.locator(".artifact-view")).toHaveCount(0)
        _ = try await page.evaluate("document.activeElement.blur()")
        try await page.keyboard.press("ArrowRight")
        #expect(try await page.evaluate("window.webTestsClearedReader.querySelector('#artifact-page-input').value", as: String.self) == "2")
        try await page.expectNoErrors()
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }

  @Test(arguments: [BrowserEngine.chrome])
  func pedigreeFolksongLinksOpenBothRecordKinds(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let line = try ScratchLine(owner: admin, links: 1)
    let word = try ScratchWord(owner: admin)
    let overtureID = try TestAdmin.query("SELECT id FROM bibliographic_overtures WHERE bibliographic_folksong_id = '\(line.folksongID)';")
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        for (kind, path) in [
          ("bibliographic", "/mission-control/overtures/bibliographic/\(overtureID)"),
          ("lexicographic", "/mission-control/overtures/lexicographic/\(word.overtureID)"),
        ] {
          try await page.openHydrated(path)
          try await page.locator("#pedigree-rows > .accordion-summary").click()
          let folksong = page.locator("#pedigree-rows a[href*='/folksongs/\(kind)/']").first
          try await expect(folksong).toBeVisible()
          try await expect(page.locator("#pedigree-rows a[href*='/instances/']")).toHaveCount(0)
          try await folksong.press("Enter")
          try await expect(page).toHaveURL("Folksong page") { $0.path.contains("/folksongs/\(kind)/") }
          try await expect(page.locator(".mission-control-object-header-title")).toContainText("Folksong")
          try await page.expectNoErrors()
        }
      }
    } catch {
      word.remove()
      line.remove()
      try await admin.remove(after: error)
    }
    word.remove()
    line.remove()
    try await admin.remove()
  }
}
