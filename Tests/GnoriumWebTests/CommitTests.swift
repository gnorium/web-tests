import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Committing a Disputorium object (user, 2026-10-07): the header's Commit,
/// an admin's, posts at once—no dialog, no menu—for the object's ONE
/// process, decided by its state, never chosen on its page (user,
/// 2026-10-10): no process toggle anywhere. An overture commits for
/// explication; a madrigal for explication while any page is unexplicated,
/// then for translation where its witness is translated, else not at all.
/// Every commit names its ticked evidence items: with none ticked it is
/// refused under the roster before it is sent. The actions read Revise,
/// Commit, Permit, Delete. Every submission is stopped before it leaves the
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
        window.__commit = { process: data.get('process'), scope: data.get('scope'), canvases: data.getAll('canvas[]') };
      });
      return true;
    })()
    """

  struct Posted: Decodable { let process: String; let scope: String?; let canvases: [String] }

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
        // An overture: explication; no toggle, no dialog.
        try await page.openHydrated(scratch.overturePath)
        try await expect(page.locator(".process-toggle-view")).toHaveCount(0)
        try await expect(page.locator(".commit-dialog, .commit-menu")).toHaveCount(0)
        try await expect(page.locator(".mission-control-object-header-action-buttons > *"))
          .toHaveTexts(["Revise", "Commit", "Delete"])
        try await expect(page.locator(".commit-process")).toHaveAttribute("value", "bibliographic_explication")
        try await expect(page.locator(".commit-view input[name='scope']")).toHaveCount(0)
        let roster = page.locator(".overture-canvases").first
        try await expect(roster.locator(".roster-row"), timeout: .seconds(20)).toHaveCount(3)
        #expect(try await page.evaluate(Self.interceptScript, as: Bool.self))
        // Nothing ticked: refused under the roster, never sent.
        try await page.locator(".commit-trigger").click()
        try await expect(page.locator(".field-validation-message-view").first)
          .toContainText("Tick the evidence items this commit sends to explication.")
        #expect(try await Self.posted(page) == nil, "an empty commit was sent")
        // A tick clears it, and Commit posts that item.
        _ = try await page.evaluate(
          "(() => { document.querySelectorAll(\".overture-canvases input[name='canvas[]']\")[1].click(); return true })()",
          as: Bool.self)
        try await expect(page.locator(".field-validation-message-view")).toHaveCount(0)
        try await page.locator(".commit-trigger").click()
        let one = try #require(try await Self.posted(page))
        #expect(one.process == "bibliographic_explication")
        #expect(one.scope == nil)
        #expect(one.canvases == ["\(fixture.baseURL)/page-2"])
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
        let rows = page.locator("#madrigal-canvases").first.locator(".roster-row")
        try await expect(rows.nth(0)).toHaveAttribute("data-locked", "true")
        try await expect(rows.nth(2)).toHaveAttribute("data-locked", "false")

        // Every page explicated, the witness Italian: translation, no page
        // locked (a madrigal holds no translation).
        _ = try TestAdmin.query("""
          UPDATE bibliographic_madrigals SET proposed_content_json = '\(Self.madrigalTEI(fixture.baseURL, thirdRead: true))'
            WHERE id = '\(scratch.madrigalID)'
          """)
        try await page.openHydrated(scratch.madrigalPath)
        try await expect(page.locator(".commit-process")).toHaveAttribute("value", "bibliographic_translation")
        try await expect(rows.nth(0)).toHaveAttribute("data-locked", "false")
        #expect(try await page.evaluate(Self.interceptScript, as: Bool.self))
        try await page.locator(".commit-trigger").click()
        try await expect(page.locator(".field-validation-message-view").first)
          .toContainText("Tick the evidence items this commit sends to translation.")
        #expect(try await Self.posted(page) == nil)
        _ = try await page.evaluate(
          "(() => { document.querySelectorAll(\"#madrigal-canvases input[name='canvas[]']\")[0].click(); return true })()",
          as: Bool.self)
        try await page.locator(".commit-trigger").click()
        let translation = try #require(try await Self.posted(page))
        #expect(translation.process == "bibliographic_translation")
        #expect(translation.canvases == ["\(fixture.baseURL)/page-1"])

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
}
