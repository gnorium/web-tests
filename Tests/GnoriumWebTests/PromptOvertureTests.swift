import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A process's prompts are revised on an overture of their vignette, in
/// Mission Control alone (user, 2026-10-21): the Prompts list links each
/// process's vignette in force; its page offers an admin Amend, which
/// submits a palinode, frozen, opening the overture; the overture's page is
/// never indexed, its Pedigree the line palinode › overture, its thread
/// opening with the palinode's submitting naming the vignette amended, and
/// holds Revise, Permit and Discard—no header Commit (user, 2026-10-21):
/// a review is a call to gnorium in its thread, which needs nothing
/// ticked—Permit's refusal said when pressed; the palinode's page is the
/// submission and its Pedigree alone. No call is ever committed here (no
/// model is asked) and nothing is permitted (no prompt put in force).
@Suite("Prompt overtures", .serialized)
struct PromptOvertureTests {
  @Test(arguments: [BrowserEngine.chrome])
  func amendOpensAnOvertureWhosePermitSaysWhyItWaits(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let user = try admin.column("id")
    let slot = "bibliographic_translation"
    let open = try TestAdmin.query(
      """
      SELECT count(*) FROM vignette_overtures
      WHERE slot = '\(slot)' AND vignette_kind = 'prompt' AND permitted_at IS NULL AND discarded_at IS NULL
      """)
    guard open.trimmingCharacters(in: .whitespacesAndNewlines) == "0" else {
      try await admin.remove()
      try Test.cancel(Comment(rawValue: "\(slot) has an open overture that is not a web test's"))
      return
    }
    let vignette = try TestAdmin.query("SELECT vignette_id FROM active_prompt_vignettes WHERE slot = '\(slot)'")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    /// The overture the Amend opened, and its palinode.
    func opened(_ column: String = "o.id") throws -> String {
      try TestAdmin.query(
        """
        SELECT \(column) FROM vignette_overtures o JOIN vignette_palinodes p ON p.id = o.vignette_palinode_id
        WHERE o.slot = '\(slot)' AND o.vignette_kind = 'prompt' AND o.permitted_at IS NULL AND o.discarded_at IS NULL
          AND p.submitted_by_user_id = '\(user)'
        """
      ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    // Its thread and revisions go; the overture is discarded as an admin
    // discards one; the palinode, a frozen submission, stays.
    func remove() {
      guard let id = try? opened(), !id.isEmpty else { return }
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM locutions WHERE locutable_id = '\(id)';
        DELETE FROM revisions WHERE revisable_id = '\(id)';
        UPDATE vignette_overtures SET discarded_at = now(), discarded_by = '\(admin.username)' WHERE id = '\(id)';
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
        try await expect(amend).toHaveText("Submit Amendment")
        try await amend.click()
        // Its Amend form: the vignette in edit mode, every prompt, no note.
        try await expect(page, timeout: .seconds(15)).toHaveURL("the Amend form") {
          $0.path.lowercased() == "/mission-control/prompts/vignettes/\(vignette)/amend"
        }
        try await expect(page.locator(".form-header-view h1, .form-header-title").first)
          .toContainText("Submit Amendment to Bibliographic Translation Prompts")
        // Submit with nothing changed: refused, said, nothing filed.
        let submit = page.locator("#amend-vignette-form button[type='submit']")
        try await expect(submit).toHaveText("Submit")
        try await submit.click()
        try await expect(page.getByText("Nothing differs from the vignette in force.")).toBeVisible()
        #expect(try opened().isEmpty, "Nothing was filed")
        try await expect(page.locator("textarea[name='note']")).toHaveCount(0)
        // A changed system prompt: the palinode, frozen, holding it,
        // opening the overture whose proposal it is.
        _ = try await page.evaluate(
          """
          (() => {
            const area = document.querySelector("textarea[name='prompt-system-\(slot)']")
            area.value += '\\nWeb tests overture line.'
            area.dispatchEvent(new Event('input', { bubbles: true }))
            return true
          })()
          """, as: Bool.self)
        try await submit.click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the overture") {
          $0.path.lowercased().hasPrefix("/mission-control/prompts/overtures/bibliographic/")
        }
        let id = try opened()
        #expect(!id.isEmpty, "Amend opened an overture")
        let palinode = try opened("p.id")
        let path = "/mission-control/prompts/overtures/bibliographic/\(id)"
        let palinodePath = "/mission-control/prompts/palinodes/bibliographic/\(palinode)"
        let robots = try await page.evaluate(
          "document.querySelector(\"meta[name='robots']\")?.content ?? ''", as: String.self)
        #expect(robots.contains("noindex"), "Never indexed: \(robots)")
        try await expect(page.locator(".disputorium-core-title")).toHaveText("Bibliographic Overture")
        try await expect(page.locator(".pedigree-view a[href='\(palinodePath)' i]")).toHaveCount(1)
        // Its thread opens with its palinode's submitting, naming the
        // vignette amended.
        try await expect(page.getByText("amending vignette")).toBeVisible()
        try await expect(page.locator("a[href='/mission-control/prompts/vignettes/\(vignette)' i]").first).toBeVisible()
        // Its proposal is its body's change, no revision filed.
        try await expect(page.locator("#prompt-overture-body")).toContainText("Web tests overture line.")
        #expect(try TestAdmin.query("SELECT count(*) FROM revisions WHERE revisable_id = '\(id)'")
          .trimmingCharacters(in: .whitespacesAndNewlines) == "0", "No revision was filed")
        // No header Commit: a review is a call in its thread.
        try await expect(page.locator("button[form='prompt-overture-commit']")).toHaveCount(0)
        try await expect(page.locator("button[form='prompt-overture-permit']")).toHaveCount(1)
        // Permit waits on an open revision, asking no review; pressed, it
        // says why and sends nothing.
        let revision = UUID().uuidString.lowercased()
        _ = try TestAdmin.query(
          """
          INSERT INTO revisions (id, revisable_type, revisable_id, requested_by_user_id, status, prompt_changes_json,
            created_at)
          VALUES ('\(revision)', 'bibliographicPromptOverture', '\(id)', '\(user)', 'pending', '[]', now());
          """)
        try await page.openHydrated(path)
        try await page.locator("button[form='prompt-overture-permit']").click()
        try await expect(
          page.locator(".action-gate-alert").filter(hasText: "Accept or reject its open revision first: \(revision)")
        ).toBeVisible()
        // A call to gnorium ticks the diffs it reads (user, 2026-10-21):
        // while it is written each changed part offers its box, none
        // ticked; posted pending, it holds the one ticked. It is never
        // committed here.
        try await page.locator("#locution-thread-locution-body").fill("@gnorium Is this change sound?")
        let ticks = page.locator(".prompt-change-view .call-tick-view")
        try await expect(ticks.first).toBeVisible()
        try await expect(ticks.first.locator("input")).toBeChecked(false)
        let part = try #require(try await ticks.first.locator("input").getAttribute("value"))
        #expect(part.hasPrefix("prompt-diff-"), "A diff's review id: \(part)")
        try await ticks.first.locator("input").click()
        try await page.locator(".locution-thread-submit").click()
        try await expect(page.getByText("Is this change sound?").first, timeout: .seconds(15)).toBeVisible()
        let ticked = try TestAdmin.query(
          "SELECT prompt_ids FROM locutions WHERE locutable_id = '\(id)' AND kind = 'call'")
        #expect(ticked.trimmingCharacters(in: .whitespacesAndNewlines) == "[\"\(part)\"]", "Only the ticked diff: \(ticked)")
        let calls = try TestAdmin.query(
          "SELECT count(*) FROM locutions WHERE locutable_id = '\(id)' AND kind = 'call' AND call_status = 'pending'")
        #expect(calls.trimmingCharacters(in: .whitespacesAndNewlines) == "1", "The call was posted, pending")
        let committed = try TestAdmin.query(
          "SELECT count(*) FROM locutions WHERE locutable_id = '\(id)' AND kind = 'reply'")
        #expect(committed.trimmingCharacters(in: .whitespacesAndNewlines) == "0", "No review was committed")
        let status = try TestAdmin.query("SELECT committed_at IS NULL FROM vignette_overtures WHERE id = '\(id)'")
        #expect(status.trimmingCharacters(in: .whitespacesAndNewlines) == "t", "The overture is never committed")
        let still = try TestAdmin.query("SELECT vignette_id FROM active_prompt_vignettes WHERE slot = '\(slot)'")
        #expect(still.trimmingCharacters(in: .whitespacesAndNewlines) == vignette, "Nothing is put in force")

        // The palinode's page: the submission and its Pedigree, leading to
        // the overture; no thread, no action.
        try await page.openHydrated(palinodePath)
        try await expect(page.locator(".mission-control-object-header-view h1, .palinode-title").first)
          .toHaveText("Bibliographic Palinode")
        try await expect(page.locator(".pedigree-view a[href='\(path)' i]")).toHaveCount(1)
        try await expect(page.locator(".palinode-submission a[href='/mission-control/prompts/vignettes/\(vignette)' i]"))
          .toHaveCount(1)
        try await expect(page.locator("button[form='prompt-overture-commit']")).toHaveCount(0)
        try await expect(page.locator(".vignette-palinode-content")).toContainText("Web tests overture line.")

        // The vignette's page now leads to the open overture, no Amend.
        try await page.openHydrated("/mission-control/prompts/vignettes/\(vignette)")
        try await expect(page.locator(".prompt-details-amend")).toHaveCount(0)
        try await expect(page.locator(".associated-links-view a[href='\(path)' i]")).toHaveCount(1)
        try await page.expectNoErrors()
      }
      // A reader signed out: the page, no Permit (and never a Commit).
      let id = try opened()
      try await withPage(engine, gnorium, viewport: .desktop) { page in
        try await page.openHydrated("/mission-control/prompts/overtures/bibliographic/\(id)")
        try await expect(page.locator(".disputorium-core-title")).toHaveText("Bibliographic Overture")
        try await expect(page.locator("button[form='prompt-overture-commit'], button[form='prompt-overture-permit']"))
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
