import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A process's prompts are revised on a palinode of their vignette, in
/// Mission Control alone (user, 2026-10-20): the Prompts list links each
/// process's vignette in force; its page offers an admin Amend, which opens
/// the palinode; the palinode's page is never indexed and holds Revise,
/// Commit and Permit, each refusal said when pressed. No review is ever
/// called here (no model is asked) and nothing is permitted (no prompt put
/// in force).
@Suite("Prompt palinodes", .serialized)
struct PromptPalinodeTests {
  @Test(arguments: [BrowserEngine.chrome])
  func amendOpensAPalinodeWhoseCommitAndPermitSayWhyTheyWait(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let user = try admin.column("id")
    let slot = "bibliographic_translation"
    let open = try TestAdmin.query("SELECT count(*) FROM vignette_palinodes WHERE slot = '\(slot)' AND permitted_at IS NULL")
    guard open.trimmingCharacters(in: .whitespacesAndNewlines) == "0" else {
      try await admin.remove()
      try Test.cancel(Comment(rawValue: "\(slot) has an open palinode that is not a web test's"))
      return
    }
    let vignette = try TestAdmin.query("SELECT vignette_id FROM active_prompt_vignettes WHERE slot = '\(slot)'")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    func opened() throws -> String {
      try TestAdmin.query(
        "SELECT id FROM vignette_palinodes WHERE slot = '\(slot)' AND permitted_at IS NULL AND opened_by_user_id = '\(user)'"
      ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func remove() {
      guard let id = try? opened(), !id.isEmpty else { return }
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM locutions WHERE locutable_id = '\(id)';
        DELETE FROM revisions WHERE revisable_id = '\(id)';
        DELETE FROM vignette_palinodes WHERE id = '\(id)';
        COMMIT;
        """)
    }
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        // The Prompts list links each process's vignette in force.
        try await page.openHydrated("/mission-control/prompts/bibliographic")
        try await expect(page.locator("a[href='/mission-control/prompts/vignettes/\(vignette)' i]").first).toBeVisible()
        // Its page offers an admin Amend.
        try await page.openHydrated("/mission-control/prompts/vignettes/\(vignette)")
        let amend = page.locator(".prompt-details-amend button[type='submit']")
        try await expect(amend).toHaveText("Amend")
        try await amend.click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the palinode") {
          $0.path.lowercased().hasPrefix("/mission-control/prompts/palinodes/bibliographic/")
        }
        let id = try opened()
        #expect(!id.isEmpty, "Amend opened a palinode")
        let path = "/mission-control/prompts/palinodes/bibliographic/\(id)"
        let robots = try await page.evaluate(
          "document.querySelector(\"meta[name='robots']\")?.content ?? ''", as: String.self)
        #expect(robots.contains("noindex"), "Never indexed: \(robots)")
        try await expect(page.locator(".disputorium-core-title")).toHaveText("Bibliographic Palinode")
        try await expect(page.locator(".pedigree-view a[href='/mission-control/prompts/vignettes/\(vignette)' i]")).toHaveCount(1)
        try await expect(page.getByText("No accepted revision changes the prompts yet.")).toBeVisible()
        // Commit, pressed with nothing accepted, says why and sends nothing.
        try await page.locator("button[form='prompt-palinode-commit']").click()
        try await expect(page.locator(".action-gate-alert").filter(hasText: "No accepted revision changes the prompts yet."))
          .toBeVisible()
        let calls = try TestAdmin.query("SELECT count(*) FROM locutions WHERE locutable_id = '\(id)'")
        #expect(calls.trimmingCharacters(in: .whitespacesAndNewlines) == "0", "No review was called")

        // An accepted change: its body draws it; Permit waits on a review.
        let system = try ScratchPalinode.inForce(slot, "system_prompt")
        let task = try ScratchPalinode.inForce(slot, "task_prompt")
        func sql(_ text: String) -> String { text.replacingOccurrences(of: "'", with: "''") }
        _ = try TestAdmin.query(
          """
          INSERT INTO revisions (id, revisable_type, revisable_id, prompt_changes_json, status, requested_by_user_id,
            evaluated_by_user_id, evaluated_at, created_at)
          VALUES (gen_random_uuid(), 'bibliographicPromptPalinode', '\(id)', json_build_array(json_build_object('slot', '\(slot)',
              'prompt', 'main', 'previous', json_build_object('system', '\(sql(system))', 'task', '\(sql(task))'),
              'proposed', json_build_object('system', '\(sql(system + "\nWeb tests palinode line."))', 'task', '\(sql(task))')))::text,
            'accepted', '\(user)', '\(user)', now(), now())
          """)
        try await page.openHydrated(path)
        try await expect(page.locator("#prompt-palinode-body")).toContainText("Web tests palinode line.")
        try await page.locator("button[form='prompt-palinode-permit']").click()
        try await expect(page.locator(".action-gate-alert").filter(hasText: "Commit it for review first.")).toBeVisible()
        let still = try TestAdmin.query("SELECT vignette_id FROM active_prompt_vignettes WHERE slot = '\(slot)'")
        #expect(still.trimmingCharacters(in: .whitespacesAndNewlines) == vignette, "Nothing is put in force")

        // The vignette's page now leads to the open palinode, no Amend.
        try await page.openHydrated("/mission-control/prompts/vignettes/\(vignette)")
        try await expect(page.locator(".prompt-details-amend")).toHaveCount(0)
        try await expect(page.locator(".associated-links-view a[href='\(path)' i]")).toHaveCount(1)
        try await page.expectNoErrors()
      }
      // A reader signed out: the page, no Commit or Permit.
      let id = try opened()
      try await withPage(engine, gnorium, viewport: .desktop) { page in
        try await page.openHydrated("/mission-control/prompts/palinodes/bibliographic/\(id)")
        try await expect(page.locator(".disputorium-core-title")).toHaveText("Bibliographic Palinode")
        try await expect(page.locator("button[form='prompt-palinode-commit'], button[form='prompt-palinode-permit']"))
          .toHaveCount(0)
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      remove()
      try await admin.remove(after: error)
    }
    remove()
    try await admin.remove()
  }
}
