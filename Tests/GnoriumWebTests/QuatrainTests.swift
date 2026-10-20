import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The quatrain as a Computorium object (BUILD-PLAN U1): in the sidebar's
/// COMPUTORIUM, in its own list, and on its own page—how far the measuring
/// has come, each page's state in the level-one marks, the scale so far, and
/// the sessions. A scratch quatrain built by SQL (dev has no model).
@Suite("Quatrains", .serialized)
struct QuatrainTests {
  /// The roster's rows in order, each in its state's level-one mark: the
  /// plain ring passed, the red disc failed, the dotted ring sector running,
  /// the dotted ring waiting.
  static func expectRoster(_ page: Page, _ expected: [(String, String, String, String)]) async throws {
    let roster = page.locator(".computorium-core-sessions-slot").first
    try await expect(roster.locator(".roster-row")).toHaveCount(expected.count)
    let states = try await roster.evaluate(
      """
      (el) => [...el.querySelectorAll('.roster-row')].map(row => {
        const mark = row.querySelector('.roster-status');
        const shown = [...mark.children].find(c => getComputedStyle(c).display !== 'none');
        const shape = shown ? (shown.querySelector('svg') || shown).getAttribute('class') || '' : '';
        return [row.dataset.computoriumSessionLabel, mark.dataset.process, mark.dataset.status, shown ? shown.className : '', shape].join(':');
      }).join('|')
      """).string ?? ""
    let rows = states.split(separator: "|").map(String.init)
    #expect(rows.count == expected.count, "rows: \(states)")
    for (index, item) in expected.enumerated() where index < rows.count {
      let (label, status, slot, shape) = item
      #expect(rows[index].hasPrefix("\(label):calibration:\(status):"), "row \(label): \(rows[index])")
      #expect(rows[index].contains(slot), "row \(label) shows \(slot): \(rows[index])")
      #expect(rows[index].contains(shape), "row \(label) is a \(shape): \(rows[index])")
    }
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func theSidebarAndTheListLeadToTheQuatrain(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch = try ScratchQuatrain(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/quatrains/bibliographic")
        // COMPUTORIUM lists its objects in order: Quatrains, Antiphons, Serenades.
        let links = try await page.evaluate(
          """
          (() => {
            const list = [...document.querySelectorAll('.mission-control-sidebar-list')].find(e => e.offsetParent !== null || e.getClientRects().length) || document.querySelector('.mission-control-sidebar-list');
            const items = [...list.children].map(li => li.textContent.trim()).filter(Boolean);
            const at = items.indexOf('COMPUTORIUM');
            return items.slice(at + 1, at + 4).join(',');
          })()
          """, as: String.self)
        #expect(links == "Quatrains,Antiphons,Serenades", "COMPUTORIUM lists \(links)")
        try await expect(page.locator("h1").first).toHaveText("Quatrains")
        // Its columns, then its row: the title, the overture it calibrates, its pages.
        let heads = try await page.evaluate(
          "[...document.querySelectorAll('.bibliographic-quatrains-table thead th')].map(th => th.textContent.trim()).join('|')",
          as: String.self)
        #expect(heads.hasPrefix("ID|Title|Overture|Pages|Status|Created by"), "columns: \(heads)")
        let row = page.locator(".bibliographic-quatrains-table tbody tr").filter(hasText: scratch.quatrainID).first
        try await expect(row).toContainText(scratch.title)
        try await expect(row).toContainText("Calibrating")
        try await expect(row).toContainText("4")
        try await expect(row.locator("a[href='\(scratch.overturePath)' i]")).toHaveCount(1)
        // The lexicographic tab is empty for now.
        try await page.openHydrated("/mission-control/quatrains/lexicographic")
        try await expect(page.getByText("No lexicographic quatrains.")).toBeVisible()
        // The ID opens its page.
        try await page.openHydrated("/mission-control/quatrains/bibliographic")
        try await page.locator("a[href='\(scratch.path)' i]").first.click()
        try await expect(page.locator("h1").first).toHaveText("Bibliographic Quatrain")
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      scratch.remove()
      try await admin.remove(after: error)
    }
    scratch.remove()
    try await admin.remove()
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func theQuatrainPageTellsHowFarItHasComeAndWhereEachPageStands(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch = try ScratchQuatrain(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(scratch.path)
        // Calibrating: the level-one process mark (the dotted ring sector
        // turning), in the header's own words.
        let chip = page.locator(".computorium-core-header-status-chip").first
        try await expect(chip).toContainText("Calibrating")
        try await expect(chip.locator(".rotating-dotted-ring-sector-view")).toHaveCount(1)
        try await expect(page.locator(".process-container")).toHaveAttribute("data-active-process", "calibration")
        // How far it has come: the pages of its scope that have passed.
        try await expect(page.locator(".quatrain-progress-label")).toHaveText("Measuring resemblances: 1 of 4.")
        // Pedigree: the overture, then the quatrain it was committed in.
        try await page.locator("#pedigree-rows > .accordion-summary").click()
        try await expect(page.locator("#pedigree-rows")).toContainText("Quatrain ID")
        try await expect(page.locator("#pedigree-rows")).toContainText("for calibration")
        // The roster: ordinal, mark, label; one row a page. The failed
        // page waits to be tried again while the machine works the quatrain.
        try await Self.expectRoster(
          page,
          [
            ("1", "succeeded", "roster-status-done", "ring-icon-view"),
            ("2", "queued", "roster-status-pending", "dotted-ring-view"),
            ("3", "running", "roster-status-running", "rotating-dotted-ring-sector-view"),
            ("4", "queued", "roster-status-pending", "dotted-ring-view"),
          ])
        // The scale so far: a bordered block headed by its columns, no
        // heading of its own; the dev model service is not there, so what is
        // unknown reads as a dash.
        let scale = page.locator(".calibration-scale-view")
        try await expect(scale).toHaveCount(1)
        for head in ["Axis", "Em", "Measurements", "Body", "Measure", "Height", "Margin", "Width"] {
          try await expect(scale.locator("th").filter(hasText: head).first).toBeAttached()
        }
        try await expect(scale.locator("h1, h2, h3, h4, h5, h6")).toHaveCount(0)
        // The sessions: the first page's, its tool call in the transcript.
        try await expect(page.locator(".computorium-session-view").getByText("measure_page").first).toBeAttached()
        // A quatrain not failed offers no Continue, even to an admin.
        try await expect(page.getByRole(.button, name: "Continue")).toHaveCount(0)
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      scratch.remove()
      try await admin.remove(after: error)
    }
    scratch.remove()
    try await admin.remove()
  }

  /// A failed quatrain says why in one sentence and offers an admin
  /// Continue; a reader sees the page and no button, and Continue posted by
  /// anyone else is refused.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aFailedQuatrainOffersContinueToAnAdminAlone(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reader = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let scratch = try ScratchQuatrain(owner: admin, status: "failed")
    do {
      // A plain account: the page, no Continue.
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [reader.cookie]) { page in
        try await page.openHydrated(scratch.path)
        try await expect(page.locator(".computorium-core-header-status-chip").first).toContainText("Failed")
        try await expect(page.getByRole(.button, name: "Continue")).toHaveCount(0)
        try await expect(page.locator(".quatrain-progress")).toHaveCount(0)
        try await expect(page.locator("div.computorium-core-view")).toContainText("Resemblance 2 cannot be measured.")
        // It opens on the page that failed it; the failed page's mark is the
        // red disc, the roster's failed dot.
        try await Self.expectRoster(
          page,
          [
            ("1", "succeeded", "roster-status-done", "ring-icon-view"),
            ("2", "failed", "roster-status-failed", "disc-icon-view"),
            ("3", "running", "roster-status-running", "rotating-dotted-ring-sector-view"),
            ("4", "queued", "roster-status-pending", "dotted-ring-view"),
          ])
        try await page.openHydrated(scratch.path + "?resemblance=1")
        let colors = try await (page.locator(".computorium-core-sessions-slot").first.evaluate(
          "(el) => [...el.querySelectorAll('.roster-status')].map(m => getComputedStyle(m).color).join('|')"
        ).string ?? "").split(separator: "|").map(String.init)
        let red = try await page.evaluate(
          "(() => { const p = document.createElement('span'); p.style.color = 'var(--color-red)'; document.body.append(p); const c = getComputedStyle(p).color; p.remove(); return c; })()",
          as: String.self)
        #expect(colors.count == 4 && colors[1] == red && colors[0] != red && colors[3] != red, "marks: \(colors)")
      }
      // An admin: Continue, which takes the quatrain up again.
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(scratch.path)
        let continueButton = page.getByRole(.button, name: "Continue")
        try await expect(continueButton).toHaveCount(1)
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
        try await continueButton.click()
        // The post answers before the page is read back, and the page must
        // stay open until it has: wait for the move. Dev has no model
        // service, so the runner may fail it again at once, for another
        // reason than the one it had: either way it was taken up.
        let before = "Resemblance 2 cannot be measured."
        var status = try scratch.status()
        var error = try scratch.error()
        for _ in 0..<40 where status == "failed" && error == before {
          try await Task.sleep(for: .milliseconds(250))
          status = try scratch.status()
          error = try scratch.error()
        }
        #expect(status != "failed" || error != before, "Continue takes it up again: \(status), \(error)")
      }
    } catch {
      scratch.remove()
      try await reader.remove(after: error)
      try await admin.remove(after: error)
    }
    scratch.remove()
    try await reader.remove()
    try await admin.remove()
  }
}
