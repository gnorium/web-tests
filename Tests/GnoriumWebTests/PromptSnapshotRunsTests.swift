import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A prompt snapshot's runs are its associated runs (user, 2026-10-07): its
/// page's "See associated runs." opens the Lifecycles page's runs filtered
/// by it (`?snapshot=`), the filter bar showing it as any filter value, the
/// list its own empty state when no run used it. A placeholder—a version
/// no commit has run with—has no Pedigree and no runs. Chrome, desktop.
@Suite("Prompt snapshot runs", .serialized)
struct PromptSnapshotRunsTests {
  @Test(arguments: [BrowserEngine.chrome])
  func aSnapshotsRunsAreTheRunsListFilteredByIt(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    // A version a commit ran with, of an object long gone, which no run
    // used; and a placeholder.
    let id = UUID().uuidString
    let placeholder = UUID().uuidString
    _ = try TestAdmin.query(
      """
      INSERT INTO prompt_templates(id, hash, stage, system_prompt, task_prompt, template_version,
        is_proprietary_content, created_at, committed_object_type, committed_object_id, committed_by_user_id,
        committed_at)
      VALUES ('\(id)', '\(id)', 'bibliographic_explication', 'Web tests system.', 'Web tests task {page}',
          'web-tests', false, NOW(), 'bibliographicOverture', gen_random_uuid(),
          (SELECT id FROM users WHERE username = 'gnorium'), NOW()),
        ('\(placeholder)', '\(placeholder)', 'bibliographic_explication', 'Web tests placeholder.',
          'Web tests task {page}', 'web-tests', false, NOW(), NULL, NULL, NULL, NULL)
      """)
    defer { _ = try? TestAdmin.query("DELETE FROM prompt_templates WHERE id IN ('\(id)', '\(placeholder)')") }
    try await withPage(engine, gnorium, viewport: .desktop) { page in
      try await page.openHydrated("/mission-control/prompts/snapshots/\(placeholder)")
      try await expect(page.getByText("Web tests placeholder.").first).toBeAttached()
      try await expect(page.locator(".pedigree-view")).toHaveCount(0)
      try await expect(page.locator(".associated-links-view")).toHaveCount(0)

      try await page.openHydrated("/mission-control/prompts/snapshots/\(id)")
      // Its id, unlinked, above the object whose commit ran with it, that
      // commit its act.
      let labels = page.locator(".pedigree-view .datum-label")
      try await expect(labels.first).toHaveText("Snapshot ID")
      try await expect(labels.nth(1)).toHaveText("Overture ID")
      try await expect(labels.nth(2)).toHaveText("Committed")
      try await expect(page.locator(".pedigree-view a[href*='/mission-control/prompts/snapshots/']")).toHaveCount(0)
      try await expect(page.getByText("Suggested")).toHaveCount(0)
      let runs = page.locator(".associated-links-view a")
      try await expect(runs).toHaveText("runs")
      try await expect(page.locator(".associated-links-view")).toHaveText("See associated runs.")
      try await runs.click()
      try await expect(page, timeout: .seconds(15)).toHaveURL("the runs, filtered by the snapshot") {
        $0.path == "/mission-control/lifecycles/bibliographic"
          && ($0.query ?? "").contains("snapshot=\(id)") && ($0.query ?? "").contains("show=runs")
      }
      // The filter bar holds it as any filter value; no run used it.
      try await expect(page.locator(".filter-bar-view").getByText("Prompt snapshot").first).toBeAttached()
      try await expect(page.locator(".filter-bar-view").getByText(id).first).toBeAttached()
      try await expect(page.locator(".mission-control-core-empty")).toHaveCount(1)
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }
}
