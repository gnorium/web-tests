import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Committing a Disputorium object (user, 2026-10-07): the header's Commit,
/// an admin's, posts at once—no dialog, no menu—for the object's ONE
/// process, decided by its state, never chosen on its page (user,
/// 2026-10-10): no process toggle anywhere. An overture commits once, for
/// calibration of the pages it misses (ticked to begin with); a madrigal for
/// explication while any page is unexplicated, then for translation (a
/// serenade, which submits the first epilogue) where its witness is
/// translatable, else only Permit remains; an epilogue commits for
/// translation (user, 2026-10-20: no promotion).
/// Every commit names its ticked evidence items: with none ticked it is
/// refused under the roster before it is sent. The actions read Revise,
/// Commit, Permit, Discard. Every submission is stopped before it leaves the
/// page: a commit is costly and never run here. A throwaway admin owns the
/// scratch objects (`ScratchCommit`).
@Suite("Commit", .serialized)
struct CommitTests {
  /// Stops the next commit's submission—one the page let go—and keeps
  /// what it would have posted.
  static let interceptScript = """
    (() => {
      window.__commit = null;
      window.addEventListener('submit', event => {
        if (event.target.id !== 'commit-form' || event.defaultPrevented) return;
        event.preventDefault();
        const data = new FormData(event.target);
        window.__commit = { process: data.get('process'), scope: data.get('scope'), ticked: data.get('ticked') };
      });
      return true;
    })()
    """

  struct Posted: Decodable { let process: String; let scope: String?; let ticked: String? }

  static func posted(_ page: Page) async throws -> Posted? {
    let json = try await page.evaluate("JSON.stringify(window.__commit)", as: String.self)
    guard json != "null" else { return nil }
    return try JSONDecoder().decode(Posted.self, from: Data(json.utf8))
  }

  static func madrigalTEI(_ base: String, thirdRead: Bool) -> String {
    let tei = """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><text><body>\
      <pb n="1" facs="\(base)/page-1/full/max/0/default.jpg"/><p><s>Alpha.</s></p>\
      <pb n="2" facs="\(base)/page-2/full/max/0/default.jpg"/><p><s>Beta.</s></p>\
      <pb n="3" facs="\(base)/page-3/full/max/0/default.jpg"/>\(thirdRead ? "<p><s>Gamma.</s></p>" : "")\
      </body></text></TEI>
      """
    return String(decoding: try! JSONSerialization.data(withJSONObject: ["teiXml": tei]), as: UTF8.self)
      .replacingOccurrences(of: "'", with: "''")
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func commitPostsTheObjectsOneProcess(engine: BrowserEngine, layout: Layout) async throws {
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
        // An overture: calibration of the pages it misses, every one ticked to
        // begin with; no toggle, no dialog.
        try await page.openHydrated(scratch.overturePath)
        try await expect(page.locator(".process-toggle-view")).toHaveCount(0)
        try await expect(page.locator(".commit-dialog, .commit-menu")).toHaveCount(0)
        try await expect(page.locator(".mission-control-object-header-action-buttons > *"))
          .toHaveTexts(["Revise", "Commit", "Permit", "Discard"])
        try await expect(page.locator(".commit-process")).toHaveAttribute("value", "bibliographic_calibration")
        try await expect(page.locator(".commit-view input[name='scope']")).toHaveCount(0)
        let roster = page.locator(".overture-evidence-items").first
        try await expect(roster.locator(".roster-row"), timeout: .seconds(20)).toHaveCount(3)
        try await expect(roster.locator(".roster-row input[form='commit-form']:checked")).toHaveCount(3)
        #expect(try await page.evaluate(Self.interceptScript, as: Bool.self))
        // Commit posts the three ticked pages, in ranges (user, 2026-10-11).
        try await page.locator(".commit-trigger").click()
        let all = try #require(try await Self.posted(page))
        #expect(all.process == "bibliographic_calibration")
        #expect(all.ticked == "0-2")
        // Nothing ticked: refused under the roster, never sent.
        _ = try await page.evaluate(
          "(() => { window.__commit = null; document.querySelector(\".overture-evidence-items\").querySelectorAll(\".roster-row input[form='commit-form']\").forEach(box => box.click()); return true })()",
          as: Bool.self)
        try await page.locator(".commit-trigger").click()
        try await expect(page.locator(".field-validation-message-view").first)
          .toContainText("Tick the evidence items this commit sends to calibration.")
        #expect(try await Self.posted(page) == nil, "an empty commit was sent")
        // A tick clears it, and Commit posts that item.
        _ = try await page.evaluate(
          "(() => { document.querySelectorAll(\".overture-evidence-items .roster-row input[form='commit-form']\")[1].click(); return true })()",
          as: Bool.self)
        try await expect(page.locator(".field-validation-message-view")).toHaveCount(0)
        try await page.locator(".commit-trigger").click()
        let one = try #require(try await Self.posted(page))
        #expect(one.process == "bibliographic_calibration")
        #expect(one.scope == nil)
        #expect(one.ticked == "1")
        try await page.expectNoErrors()

        // A madrigal with a page unexplicated: explication, its explicated
        // pages locked, even where the witness is translated.
        _ = try TestAdmin.query("""
          UPDATE bibliographic_madrigals SET proposed_content_json = '\(Self.madrigalTEI(fixture.baseURL, thirdRead: false))',
            metadata_json = (metadata_json::jsonb || '{"language":"ita"}'::jsonb)::text WHERE id = '\(scratch.madrigalID)'
          """)
        try await page.openHydrated(scratch.madrigalPath)
        try await expect(page.locator(".process-toggle-view")).toHaveCount(0)
        try await expect(page.locator(".mission-control-object-header-action-buttons > *"))
          .toHaveTexts(["Revise", "Commit", "Permit"])
        try await expect(page.locator(".commit-process")).toHaveAttribute("value", "bibliographic_explication")
        let rows = page.locator("#madrigal-images").first.locator(".roster-row")
        try await expect(rows.nth(0)).toHaveAttribute("data-locked", "true")
        try await expect(rows.nth(2)).toHaveAttribute("data-locked", "false")

        // Every page explicated, the witness Italian: the Commit is for
        // translation, a serenade over the pages ticked.
        _ = try TestAdmin.query("""
          UPDATE bibliographic_madrigals SET proposed_content_json = '\(Self.madrigalTEI(fixture.baseURL, thirdRead: true))'
            WHERE id = '\(scratch.madrigalID)'
          """)
        try await page.openHydrated(scratch.madrigalPath)
        try await expect(page.locator(".commit-process")).toHaveAttribute("value", "bibliographic_translation")
        #expect(try await page.evaluate(Self.interceptScript, as: Bool.self))
        try await page.locator(".commit-trigger").click()
        let translation = try #require(try await Self.posted(page))
        #expect(translation.process == "bibliographic_translation")
        #expect(translation.ticked != nil, "the pages it sends to translation")
        try await expect(page.locator(".field-validation-message-view")).toHaveCount(0)

        // English and every page explicated: nothing to commit for.
        _ = try TestAdmin.query("""
          UPDATE bibliographic_madrigals SET metadata_json =
            (metadata_json::jsonb || '{"language":"eng"}'::jsonb)::text WHERE id = '\(scratch.madrigalID)'
          """)
        try await page.openHydrated(scratch.madrigalPath)
        try await expect(page.locator(".mission-control-object-header-action-buttons > *"))
          .toHaveTexts(["Revise", "Permit"])
        try await expect(page.locator(".commit-view")).toHaveCount(0)
        try await page.expectNoHorizontalOverflow()
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

  /// A Commit for translation refused while a revision filed on the object is open
  /// (user, 2026-10-20: nothing hover-only): Commit stays enabled, and
  /// pressing it shows why in the header's alert—on a phone as on a
  /// desktop—and sends nothing.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func refusedCommitSaysWhyWhenPressed(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch: ScratchCommit
    do { scratch = try ScratchCommit(owner: admin, sourceURL: fixture.baseURL + "/manifest.json") }
    catch { try await admin.remove(after: error) }
    do {
      // Every page explicated, the witness Italian: the Commit is for translation.
      _ = try TestAdmin.query("""
        UPDATE bibliographic_madrigals SET proposed_content_json = '\(Self.madrigalTEI(fixture.baseURL, thirdRead: true))',
          metadata_json = (metadata_json::jsonb || '{"language":"ita"}'::jsonb)::text WHERE id = '\(scratch.madrigalID)'
        """)
      let revisionID = try scratch.addOpenRevision()
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(scratch.madrigalPath)
        try await expect(page.locator(".commit-process")).toHaveAttribute("value", "bibliographic_translation")
        let trigger = page.locator(".commit-trigger").first
        try await expect(trigger).not.toBeDisabled()
        let alert = page.locator(".action-gate-alert[data-gate-action='commit']").first
        try await expect(alert).toBeHidden()
        #expect(try await page.evaluate(Self.interceptScript, as: Bool.self))
        try await trigger.click()
        try await expect(alert).toBeVisible()
        try await expect(alert).toContainText("Accept or reject its open revision first")
        let text = try await alert.innerText()
        #expect(text.lowercased().contains(revisionID), "The reason names the open revision: \(text)")
        #expect(try await Self.posted(page) == nil, "a refused Commit was sent")
        try await page.expectNoHorizontalOverflow()
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
