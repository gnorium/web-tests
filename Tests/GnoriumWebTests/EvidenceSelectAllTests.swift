import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The Select all left of an Evidence roster's heading (user, 2026-10-24): one
/// tick that ticks or clears every box the commit may tick, through the
/// same ticks the rows keep. Ticked where all are, partly (indeterminate)
/// where some are, clear where none. Nothing is committed here: the
/// submission is never sent.
@Suite("Evidence select all", .serialized)
struct EvidenceSelectAllTests {
  static let state = """
    (() => {
      const box = document.querySelector('.evidence-header-view .evidence-select-all input');
      const rows = [...document.querySelectorAll('.overture-evidence-items .roster-row input[form=\"commit-form\"]')];
      return JSON.stringify({
        checked: box.checked, indeterminate: box.indeterminate, disabled: box.disabled,
        ticked: rows.filter(row => row.checked).length, rows: rows.length
      });
    })()
    """

  struct State: Decodable { let checked: Bool; let indeterminate: Bool; let disabled: Bool; let ticked: Int; let rows: Int }

  static func read(_ page: Page) async throws -> State {
    let json = try await page.evaluate(state, as: String.self)
    return try JSONDecoder().decode(State.self, from: Data(json.utf8))
  }

  /// A press on a box, as a reader's: the inputs are drawn by their labels.
  static func tap(_ page: Page, _ selector: String) async throws {
    _ = try await page.evaluate("(() => { document.querySelector('\(selector)').click(); return true })()", as: Bool.self)
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func selectAllTicksAndClearsEveryRowAndReadsPartly(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch: ScratchCommit
    do { scratch = try ScratchCommit(owner: admin, sourceURL: fixture.baseURL + "/manifest.json") }
    catch { try await admin.remove(after: error) }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(scratch.overturePath)
        let roster = page.locator(".overture-evidence-items").first
        try await expect(roster.locator(".roster-row"), timeout: .seconds(20)).toHaveCount(3)
        // Left of the heading, in its row.
        try await expect(page.locator(".evidence-header-view .evidence-select-all")).toHaveCount(1)
        let box = try await page.evaluate(
          "(() => { const a = document.querySelector('.evidence-select-all').getBoundingClientRect(); const h = document.querySelector('.evidence-header-view h6').getBoundingClientRect(); return a.right <= h.left && Math.abs((a.top + a.bottom) / 2 - (h.top + h.bottom) / 2) < 8 })()",
          as: Bool.self)
        #expect(box, "the select-all stands left of the Evidence heading")
        let selectSelector = ".evidence-header-view .evidence-select-all input"

        // Clear every tick through it, then tick every one.
        var now = try await Self.read(page)
        if now.checked { try await Self.tap(page, selectSelector) }
        else if now.indeterminate { try await Self.tap(page, selectSelector); try await Self.tap(page, selectSelector) }
        now = try await Self.read(page)
        #expect(now.ticked == 0 && !now.checked && !now.indeterminate && !now.disabled)
        try await Self.tap(page, selectSelector)
        now = try await Self.read(page)
        #expect(now.ticked == now.rows && now.rows == 3 && now.checked && !now.indeterminate)

        // One row cleared: partly.
        _ = try await page.evaluate(
          "(() => { document.querySelectorAll(\".overture-evidence-items .roster-row input[form='commit-form']\")[1].click(); return true })()",
          as: Bool.self)
        now = try await Self.read(page)
        #expect(now.ticked == 2 && !now.checked && now.indeterminate)
        // From partly, it ticks all.
        try await Self.tap(page, selectSelector)
        now = try await Self.read(page)
        #expect(now.ticked == 3 && now.checked && !now.indeterminate)
        // None: clear and unmarked.
        try await Self.tap(page, selectSelector)
        now = try await Self.read(page)
        #expect(now.ticked == 0 && !now.checked && !now.indeterminate)
        // The commit reads what it set.
        #expect(try await page.evaluate(CommitTests.interceptScript, as: Bool.self))
        try await Self.tap(page, selectSelector)
        try await page.locator(".commit-trigger").click()
        let posted = try #require(try await CommitTests.posted(page))
        #expect(posted.ticked == "0-2")
        try await page.expectNoErrors()
      }
      #expect(try scratch.stillPending(), "nothing was committed")
    } catch {
      scratch.remove()
      try await admin.remove(after: error)
    }
    scratch.remove()
    try await admin.remove()
  }
}
