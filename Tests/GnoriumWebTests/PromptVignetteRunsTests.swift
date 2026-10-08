import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A prompt vignette's runs are its associated runs (user, 2026-10-07): its
/// page's "See associated runs." opens the Runs page filtered by it
/// (`?vignette=`), the filter bar showing it as any filter value, the
/// list its own empty state when no run used it. A placeholder—a version
/// no commit has run with—has no Pedigree and no runs. Chrome, desktop.
@Suite("Prompt vignette runs", .serialized)
struct PromptVignetteRunsTests {
  @Test(arguments: [BrowserEngine.chrome])
  func aVignettesRunsAreTheRunsListFilteredByIt(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    // A version a commit ran with, of an object long gone, which no run
    // used; and a placeholder.
    let id = UUID().uuidString
    let placeholder = UUID().uuidString
    _ = try TestAdmin.query(
      """
      INSERT INTO prompt_vignettes(id, hash, stage, system_prompt, task_prompt,
        is_proprietary_content, created_at, committed_object_type, committed_object_id, committed_by_user_id,
        committed_at)
      VALUES ('\(id)', '\(id)', 'bibliographic_explication', 'Web tests system.', 'Web tests task {page}',
          false, NOW(), 'bibliographicOverture', gen_random_uuid(),
          (SELECT id FROM users WHERE username = 'gnorium'), NOW()),
        ('\(placeholder)', '\(placeholder)', 'bibliographic_explication', 'Web tests placeholder.',
          'Web tests task {page}', false, NOW(), NULL, NULL, NULL, NULL)
      """)
    defer { _ = try? TestAdmin.query("DELETE FROM prompt_vignettes WHERE id IN ('\(id)', '\(placeholder)')") }
    try await withPage(engine, gnorium, viewport: .desktop) { page in
      try await page.openHydrated("/mission-control/prompts/vignettes/\(placeholder)")
      try await expect(page.getByText("Web tests placeholder.").first).toBeAttached()
      try await expect(page.locator(".pedigree-view")).toHaveCount(0)
      try await expect(page.locator(".associated-links-view")).toHaveCount(0)

      try await page.openHydrated("/mission-control/prompts/vignettes/\(id)")
      // Its id, unlinked, above the object whose commit ran with it, that
      // commit its act.
      let labels = page.locator(".pedigree-view .datum-label")
      try await expect(labels.first).toHaveText("Vignette ID")
      try await expect(labels.nth(1)).toHaveText("Overture ID")
      try await expect(labels.nth(2)).toHaveText("Committed")
      try await expect(page.locator(".pedigree-view a[href*='/mission-control/prompts/vignettes/']")).toHaveCount(0)
      try await expect(page.getByText("Suggested")).toHaveCount(0)
      let runs = page.locator(".associated-links-view a")
      try await expect(runs).toHaveText("runs")
      try await expect(page.locator(".associated-links-view")).toHaveText("See associated runs.")
      try await runs.click()
      try await expect(page, timeout: .seconds(15)).toHaveURL("the runs, filtered by the vignette") {
        $0.path == "/mission-control/runs/bibliographic" && ($0.query ?? "") == "vignette=\(id)"
      }
      // The filter bar holds it as any filter value; no run used it.
      try await expect(page.locator(".filter-bar-view").getByText("Prompt vignette").first).toBeAttached()
      try await expect(page.locator(".filter-bar-view").getByText(id).first).toBeAttached()
      try await expect(page.locator(".mission-control-core-empty")).toHaveCount(1)
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }
}
