import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Committing a Disputorium object (user, 2026-10-07): the header's Commit,
/// an admin's, posts at once—no dialog, no menu. An object with one process
/// commits for it, with no process toggle anywhere; one with two
/// (a translatable madrigal) has the process toggle leading its header's
/// actions, explication first, and Commit posts the process chosen there,
/// which the address keeps (`?process=translation`) across a reload, as
/// Modify does. The actions read Modify, Commit, Permit, Delete. Every submission is stopped before it
/// leaves the page: a commit is costly and never run here. A throwaway admin
/// owns the scratch objects (`ScratchCommit`).
@Suite("Commit", .serialized)
struct CommitTests {
  /// Stops the next commit's submission and keeps what it would have posted.
  static let interceptScript = """
    (() => {
      window.__commit = null;
      window.addEventListener('submit', event => {
        if (event.target.id !== 'commit-form') return;
        event.preventDefault();
        const data = new FormData(event.target);
        window.__commit = { pipeline: data.get('pipeline'), scope: data.get('scope') };
      });
      return true;
    })()
    """

  struct Posted: Decodable { let pipeline: String; let scope: String }

  static func posted(_ page: Page) async throws -> Posted {
    try JSONDecoder().decode(
      Posted.self, from: Data(try await page.evaluate("JSON.stringify(window.__commit)", as: String.self).utf8))
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func commitPostsTheProcessChosen(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch = try ScratchCommit(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        // One process: no toggle, no dialog; Commit posts explication.
        try await page.openHydrated(scratch.overturePath)
        try await expect(page.locator(".process-toggle-view")).toHaveCount(0)
        try await expect(page.locator(".commit-view-dialog, .commit-view-menu")).toHaveCount(0)
        let overtureActions = page.locator(".mission-control-object-header-action-buttons > *")
        try await expect(overtureActions).toHaveTexts(["Modify", "Commit", "Delete"])
        #expect(try await page.evaluate(Self.interceptScript, as: Bool.self))
        try await page.locator(".commit-view-trigger").click()
        try await expect(page.locator("body")).toBeAttached()
        let one = try await Self.posted(page)
        #expect(one.pipeline == "bibliographic_explication")
        try await page.expectNoErrors()

        // Two processes (an Italian witness is translated): the toggle leads
        // the actions, and Commit posts what it chooses.
        _ = try TestAdmin.query("""
          UPDATE bibliographic_madrigals SET metadata_json =
            (metadata_json::jsonb || '{"language":"ita"}'::jsonb)::text WHERE id = '\(scratch.madrigalID)'
          """)
        try await page.openHydrated(scratch.madrigalPath)
        let toggle = page.locator(".mission-control-object-header-view .process-toggle-view")
        try await expect(toggle).toHaveCount(1)
        try await expect(page.locator(".mission-control-object-header-action-buttons > *"))
          .toHaveTexts(["Modify", "Commit", "Permit"])
        let buttons = toggle.locator(".toggle-button-group-button")
        try await expect(buttons).toHaveTexts(["Explication", "Translation"])
        try await expect(buttons.nth(0)).toHaveAttribute("aria-pressed", "true")
        #expect(try await page.evaluate(Self.interceptScript, as: Bool.self))
        try await page.locator(".commit-view-trigger").click()
        #expect(try await Self.posted(page).pipeline == "bibliographic_explication")
        try await buttons.nth(1).click()
        try await expect(page).toHaveURL("the address keeps the process") { $0.query?.contains("process=translation") == true }
        try await page.locator(".commit-view-trigger").click()
        #expect(try await Self.posted(page).pipeline == "bibliographic_translation")
        try await expect(page.locator(".mission-control-object-header-view a[data-value='modify']"))
          .toHaveAttribute("href", "\(scratch.madrigalPath.uppercased().replacingOccurrences(of: "/MISSION-CONTROL/MADRIGALS/BIBLIOGRAPHIC/", with: "/mission-control/madrigals/bibliographic/"))/modify?process=translation")

        // A reload keeps it, before any script runs.
        try await page.openHydrated(scratch.madrigalPath + "?process=translation")
        try await expect(buttons.nth(1)).toHaveAttribute("aria-pressed", "true")
        try await expect(page.locator(".commit-view-pipeline")).toHaveAttribute("value", "bibliographic_translation")
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
