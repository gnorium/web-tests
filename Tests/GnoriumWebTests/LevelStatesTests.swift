import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The three Disputorium objects show where their level's work stands (user,
/// 2026-10-18): a state chip, a line counting the pages, a roster that ticks
/// the pages the next Commit sends, and a Commit that reads by state—an
/// overture for calibration, then its promotion to a madrigal; a madrigal for
/// explication, then its promotion to an epilogue; an epilogue for
/// translation—with Permit beside it. Scratch rows built by SQL (dev has no
/// model); every submission is stopped before it leaves the page.
@Suite("Level states", .serialized)
struct LevelStatesTests {
  /// The status chip's words.
  static func chip(_ page: Page) -> Locator { page.locator(".mission-control-object-header-status-chip .info-chip-text").first }

  /// The overture roster's rows in order, each in its calibration's level-one
  /// mark: the plain ring done, the dotted ring waiting.
  static func expectMarks(_ roster: Locator, _ expected: [(String, String, String)]) async throws {
    let states = try await roster.evaluate(
      """
      (el) => [...el.querySelectorAll('.roster-row')].map(row => {
        const mark = row.querySelector('.roster-status');
        const shown = [...mark.children].find(c => getComputedStyle(c).display !== 'none');
        return [row.dataset.computoriumSessionLabel, mark.dataset.process, mark.dataset.status, shown ? shown.className : ''].join(':');
      }).join('|')
      """).string ?? ""
    let rows = states.split(separator: "|").map(String.init)
    #expect(rows.count == expected.count, "rows: \(states)")
    for (index, item) in expected.enumerated() where index < rows.count {
      let (label, status, slot) = item
      #expect(rows[index].hasPrefix("\(label):calibration:\(status):"), "row \(label): \(rows[index])")
      #expect(rows[index].contains(slot), "row \(label) shows \(slot): \(rows[index])")
    }
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func anUncalibratedOvertureTicksTheCalibrationItOwes(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch: ScratchOverture
    do { scratch = try ScratchOverture(owner: admin, sealed: true, calibrated: 1) }
    catch { try await admin.remove(after: error) }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(scratch.path)
        try await expect(Self.chip(page)).toHaveText("Uncalibrated")
        try await expect(page.locator(".level-progress-line-view")).toHaveText("Calibrated: 1 of 4 pages")
        // Its first Commit seals nothing (user, 2026-10-20): it is revised
        // until its promotion, and only Delete is gone.
        try await expect(page.locator(".mission-control-object-header-action-buttons > *")).toHaveTexts(["Revise", "Commit"])
        // Its Commit is for calibration, over the pages it still owes,
        // ticked to begin with; the page calibrated is locked.
        try await expect(page.locator(".commit-process")).toHaveAttribute("value", "bibliographic_calibration")
        let roster = page.locator(".overture-images").first
        let rows = roster.locator(".roster-row")
        try await expect(rows).toHaveCount(4)
        try await expect(rows.nth(0)).toHaveAttribute("data-locked", "true")
        for index in 1...3 {
          try await expect(rows.nth(index)).toHaveAttribute("data-locked", "false")
          try await expect(rows.nth(index).locator("input")).toBeChecked()
        }
        try await expect(page.locator(".commit-ticked")).toHaveAttribute("value", "1-3")
        // A page calibrated is a plain ring; the ones owed a dotted ring.
        try await Self.expectMarks(
          roster, [
            ("1", "succeeded", "roster-status-done"), ("2", "queued", "roster-status-pending"),
            ("3", "queued", "roster-status-pending"), ("4", "queued", "roster-status-pending"),
          ])
        // The scale so far stands beside it, its figures an em dash until
        // the scale can be fitted.
        try await expect(page.locator(".calibration-scale-view")).toBeVisible()
        try await expect(page.locator(".overture-promotion-note")).toHaveCount(0)
        // Commit posts calibration over those pages; with none ticked it is
        // refused under the roster.
        #expect(try await page.evaluate(CommitTests.interceptScript, as: Bool.self))
        try await page.locator(".commit-trigger").click()
        let sent = try #require(try await CommitTests.posted(page))
        #expect(sent.process == "bibliographic_calibration")
        #expect(sent.ticked == "1-3")
        _ = try await page.evaluate(
          "(() => { document.querySelectorAll(\".overture-images .roster-row input[form='commit-form']\").forEach(box => { if (box.checked) box.click() }); return true })()",
          as: Bool.self)
        _ = try await page.evaluate("(() => { window.__commit = null; return true })()", as: Bool.self)
        try await page.locator(".commit-trigger").click()
        try await expect(page.locator(".field-validation-message-view").first)
          .toContainText("Tick the evidence items this commit sends to calibration.")
        #expect(try await CommitTests.posted(page) == nil)
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      scratch.remove()
      try await admin.remove(after: error)
    }
    scratch.remove()
    try await admin.remove()
  }

  @Test(arguments: [BrowserEngine.chrome])
  func anOvertureNoCommitHasSealedIsRevisedCommittedAndDeleted(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch: ScratchOverture
    do { scratch = try ScratchOverture(owner: admin, sealed: false) }
    catch { try await admin.remove(after: error) }
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated(scratch.path)
        try await expect(Self.chip(page)).toHaveText("Uncalibrated")
        try await expect(page.locator(".mission-control-object-header-action-buttons > *"))
          .toHaveTexts(["Revise", "Commit", "Delete"])
        // Every page is owed: all ticked.
        try await expect(page.locator(".commit-ticked")).toHaveAttribute("value", "0-3")
        try await expect(page.locator(".level-progress-line-view")).toHaveText("Calibrated: 0 of 4 pages")
      }
    } catch {
      scratch.remove()
      try await admin.remove(after: error)
    }
    scratch.remove()
    try await admin.remove()
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aCalibratedOverturesCommitIsItsPromotion(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch: ScratchOverture
    do { scratch = try ScratchOverture(owner: admin, sealed: true, calibrated: 4) }
    catch { try await admin.remove(after: error) }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(scratch.path)
        try await expect(Self.chip(page)).toHaveText("Calibrated")
        try await expect(page.locator(".level-progress-line-view")).toHaveText("Calibrated: 4 of 4 pages")
        try await expect(page.locator(".commit-process")).toHaveAttribute("value", "promote_madrigal")
        try await expect(page.locator(".commit-ticked")).toHaveCount(0)
        // The header will be frozen: the scale so far and a sentence saying so.
        try await expect(page.locator(".overture-promotion-note")).toContainText("freezes the scale below as its header")
        try await expect(page.locator(".calibration-scale-view")).toBeVisible()
        let rows = page.locator(".overture-images").first.locator(".roster-row")
        try await expect(rows).toHaveCount(4)
        for index in 0..<4 { try await expect(rows.nth(index)).toHaveAttribute("data-locked", "true") }
        // Commit posts the promotion at once: nothing to tick.
        #expect(try await page.evaluate(CommitTests.interceptScript, as: Bool.self))
        try await page.locator(".commit-trigger").click()
        let sent = try #require(try await CommitTests.posted(page))
        #expect(sent.process == "promote_madrigal")
        #expect(sent.ticked == nil)
        try await expect(page.locator(".field-validation-message-view")).toHaveCount(0)
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      scratch.remove()
      try await admin.remove(after: error)
    }
    scratch.remove()
    try await admin.remove()
  }

  @Test(arguments: [BrowserEngine.chrome])
  func aPromotedOvertureLinksItsMadrigal(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch: ScratchOverture
    do { scratch = try ScratchOverture(owner: admin, sealed: true, calibrated: 4, promoted: true) }
    catch { try await admin.remove(after: error) }
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated(scratch.path)
        try await expect(Self.chip(page)).toHaveText("Promoted")
        try await expect(page.locator(".overture-promoted")).toContainText("Promoted to madrigal")
        try await expect(page.locator(".overture-promoted a[href='\(scratch.madrigalPath)' i]")).toHaveCount(1)
        try await expect(page.locator(".commit-trigger")).toHaveCount(0)
        try await expect(page.locator(".mission-control-object-header-action-buttons")).toHaveCount(0)
        try await expect(page.locator(".calibration-scale-view")).toHaveCount(0)
        try await expect(page.locator(".locution-thread-settled-note")).toContainText("has been promoted")
        // Its Pedigree names the promotion as a Commit of the overture, for explication.
        try await page.locator(".pedigree-accordion .accordion-summary").first.click()
        try await expect(page.locator(".pedigree-rows")).toContainText("for explication")
        // The madrigal it made is unexplicated, with the header frozen.
        try await page.openHydrated(scratch.madrigalPath)
        try await expect(Self.chip(page)).toHaveText("Unexplicated")
        try await expect(page.locator(".level-progress-line-view")).toHaveText("Explicated: 0 of 4 pages")
      }
    } catch {
      scratch.remove()
      try await admin.remove(after: error)
    }
    scratch.remove()
    try await admin.remove()
  }

  // MARK: - The madrigal

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aMadrigalReadsByHowManyPagesAreExplicated(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch: ScratchCommit
    do { scratch = try ScratchCommit(owner: admin, sourceURL: fixture.baseURL + "/manifest.json") }
    catch { try await admin.remove(after: error) }
    let source = fixture.baseURL + "/manifest.json"
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        // Two of three pages read: partly explicated, Commit for explication,
        // the explicated pages locked and the page owed open.
        _ = try TestAdmin.query("""
          UPDATE bibliographic_madrigals SET proposed_content_json = '\(CommitTests.madrigalTEI(fixture.baseURL, thirdRead: false))',
            metadata_json = (metadata_json::jsonb || '{"language":"ita"}'::jsonb)::text WHERE id = '\(scratch.madrigalID)'
          """)
        try await page.openHydrated(scratch.madrigalPath)
        try await expect(Self.chip(page)).toHaveText("Partly explicated")
        try await expect(page.locator(".level-progress-line-view")).toHaveText("Explicated: 2 of 3 pages")
        try await expect(page.locator(".commit-process")).toHaveAttribute("value", "bibliographic_explication")
        let rows = page.locator("#madrigal-images").first.locator(".roster-row")
        try await expect(rows.nth(0)).toHaveAttribute("data-locked", "true")
        try await expect(rows.nth(2)).toHaveAttribute("data-locked", "false")

        // The first page changed at its source since it was read: stale, so
        // owed again and open to the next Commit.
        _ = try TestAdmin.query("""
          INSERT INTO testament_page_changes (source_url, canvas_id, change, before, after, service_id)
            VALUES ('\(source)', '\(fixture.baseURL)/canvas/1', 'image', 'a', 'b', '\(fixture.baseURL)/page-1')
          """)
        try await page.openHydrated(scratch.madrigalPath)
        try await expect(page.locator(".level-progress-line-view")).toHaveText("Explicated: 1 of 3 pages, 1 stale")
        try await expect(rows.nth(0)).toHaveAttribute("data-locked", "false")
        try await expect(rows.nth(1)).toHaveAttribute("data-locked", "true")
        _ = try TestAdmin.query("DELETE FROM testament_page_changes WHERE source_url = '\(source)'")

        // Every page read: explicated, and its Commit promotes it, with
        // nothing to tick; Permit stays beside it.
        _ = try TestAdmin.query("""
          UPDATE bibliographic_madrigals SET proposed_content_json = '\(CommitTests.madrigalTEI(fixture.baseURL, thirdRead: true))'
            WHERE id = '\(scratch.madrigalID)'
          """)
        try await page.openHydrated(scratch.madrigalPath)
        try await expect(Self.chip(page)).toHaveText("Explicated")
        try await expect(page.locator(".commit-process")).toHaveAttribute("value", "promote_epilogue")
        try await expect(page.locator(".mission-control-object-header-action-buttons > *"))
          .toHaveTexts(["Revise", "Commit", "Permit"])
        #expect(try await page.evaluate(CommitTests.interceptScript, as: Bool.self))
        try await page.locator(".commit-trigger").click()
        let sent = try #require(try await CommitTests.posted(page))
        #expect(sent.process == "promote_epilogue")
        #expect(sent.ticked == nil)
        try await page.expectNoHorizontalOverflow()
      }
      #expect(try scratch.stillPending(), "nothing was committed")
    } catch {
      scratch.remove()
      try await admin.remove(after: error)
    }
    scratch.remove()
    try await admin.remove()
  }

  // MARK: - The epilogue

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func anEpilogueReadsByHowManyPagesAreTranslated(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch: ScratchCommit
    do { scratch = try ScratchCommit(owner: admin, sourceURL: fixture.baseURL + "/manifest.json") }
    catch { try await admin.remove(after: error) }
    do {
      _ = try TestAdmin.query("""
        UPDATE bibliographic_madrigals SET proposed_content_json = '\(CommitTests.madrigalTEI(fixture.baseURL, thirdRead: true))',
          metadata_json = (metadata_json::jsonb || '{"language":"ita"}'::jsonb)::text WHERE id = '\(scratch.madrigalID)'
        """)
      // Nothing translated yet: every page open, the madrigal promoted.
      try scratch.addEpilogue(base: fixture.baseURL, translated: [])
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(try scratch.epiloguePath())
        try await expect(Self.chip(page)).toHaveText("Untranslated")
        try await expect(page.locator(".level-progress-line-view")).toHaveText("Translated: 0 of 3 pages")
        try await expect(page.locator(".commit-process")).toHaveAttribute("value", "bibliographic_translation")
        let rows = page.locator("#epilogue-images").first.locator(".roster-row")
        try await expect(rows).toHaveCount(3)
        for index in 0..<3 { try await expect(rows.nth(index)).toHaveAttribute("data-locked", "false") }
        // Permit is offered untranslated.
        try await expect(page.locator(".mission-control-object-header-action-buttons > *"))
          .toHaveTexts(["Revise", "Commit", "Permit"])
        try await page.expectNoHorizontalOverflow()

        // One page translated, one of them stale after its wording changed.
        _ = try TestAdmin.query("DELETE FROM bibliographic_epilogues WHERE bibliographic_madrigal_id = '\(scratch.madrigalID)'")
        try scratch.addEpilogue(base: fixture.baseURL, translated: [1, 2], stale: [2])
        try await page.openHydrated(try scratch.epiloguePath())
        try await expect(Self.chip(page)).toHaveText("Partly translated")
        try await expect(page.locator(".level-progress-line-view")).toHaveText("Translated: 1 of 3 pages, 1 stale")
        try await expect(rows.nth(0)).toHaveAttribute("data-locked", "true")
        try await expect(rows.nth(1)).toHaveAttribute("data-locked", "false")
        try await expect(rows.nth(2)).toHaveAttribute("data-locked", "false")

        // Every page translated: only Permit remains.
        _ = try TestAdmin.query("DELETE FROM bibliographic_epilogues WHERE bibliographic_madrigal_id = '\(scratch.madrigalID)'")
        try scratch.addEpilogue(base: fixture.baseURL, translated: [1, 2, 3])
        try await page.openHydrated(try scratch.epiloguePath())
        try await expect(Self.chip(page)).toHaveText("Translated")
        try await expect(page.locator(".commit-trigger")).toHaveCount(0)
        try await expect(page.locator(".mission-control-object-header-action-buttons > *")).toHaveTexts(["Revise", "Permit"])
      }
    } catch {
      scratch.remove()
      try await admin.remove(after: error)
    }
    scratch.remove()
    try await admin.remove()
  }
}
