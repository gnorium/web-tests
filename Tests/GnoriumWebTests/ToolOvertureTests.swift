import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A process's tools are revised on an overture of their vignette, in
/// Mission Control alone (user, 2026-10-21), as its prompts are: a tool
/// vignette is a pinned commit of the tools code; its page offers an
/// Amend (any reader's), which submits a palinode, frozen, opening the overture; the
/// overture's page is never indexed and holds Revise and Permit—no header
/// Commit (user, 2026-10-21): a review is a call to gnorium in its thread—
/// Permit's refusal said when pressed. The vignette here is a scratch one, of
/// commits no repository holds, put in force only where the process has
/// none and taken out of force after (the frozen palinode names it, so its
/// row stays, never in force); no review is called (no model is asked), no
/// test runs and nothing is permitted.
@Suite("Tool overtures", .serialized)
struct ToolOvertureTests {
  @Test(arguments: [BrowserEngine.chrome])
  func amendOpensAToolOvertureWhosePermitSaysWhyItWaits(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let slot = "bibliographic_translation"
    func count(_ sql: String) throws -> String {
      try TestAdmin.query(sql).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard try count("SELECT count(*) FROM active_tool_vignettes WHERE slot = '\(slot)'") == "0",
      try count(
        """
        SELECT count(*) FROM vignette_overtures
        WHERE slot = '\(slot)' AND vignette_kind = 'tool' AND permitted_at IS NULL AND discarded_at IS NULL
        """) == "0"
    else {
      try Test.cancel(Comment(rawValue: "\(slot) has tool vignettes that are not a web test's"))
      return
    }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let user = try admin.column("id")
    let vignette = UUID().uuidString.lowercased()
    let commit = String(repeating: "0", count: 40)
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO tool_vignettes (id, slot, gnorium_python_commit, philology_tools_commit, created_at)
      VALUES ('\(vignette)', '\(slot)', '\(commit)', '\(commit)', now());
      INSERT INTO active_tool_vignettes (slot, vignette_id, activated_by, activated_at)
      VALUES ('\(slot)', '\(vignette)', NULL, now());
      COMMIT;
      """)
    /// The overture the Amend opened (or its palinode's id).
    func opened(_ column: String = "o.id") throws -> String {
      try count(
        """
        SELECT \(column) FROM vignette_overtures o JOIN vignette_palinodes p ON p.id = o.vignette_palinode_id
        WHERE o.slot = '\(slot)' AND o.vignette_kind = 'tool' AND o.discarded_at IS NULL
          AND p.submitted_by_user_id = '\(user)'
        """)
    }
    // Its thread, runs and revisions go; the overture is deleted as an
    // admin discards one; the palinode, a frozen submission, stays, and with
    // it the scratch vignette it names, out of force.
    func remove() {
      let id = (try? opened()) ?? ""
      let overture = id.isEmpty ? "" : """
        DELETE FROM locutions WHERE locutable_id = '\(id)';
        DELETE FROM tool_test_runs WHERE overture_id = '\(id)';
        DELETE FROM revisions WHERE revisable_id = '\(id)';
        UPDATE vignette_overtures SET discarded_at = now(), discarded_by = '\(admin.username)' WHERE id = '\(id)';
        """
      let named = (try? count("SELECT count(*) FROM vignette_palinodes WHERE tool_vignette_id = '\(vignette)'")) ?? "1"
      _ = try? TestAdmin.query(
        """
        BEGIN;
        \(overture)
        DELETE FROM active_tool_vignettes WHERE slot = '\(slot)' AND vignette_id = '\(vignette)';
        \(named == "0" ? "DELETE FROM tool_vignettes WHERE id = '\(vignette)';" : "")
        COMMIT;
        """)
    }
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        // The tools list links the process's vignette in force.
        try await page.openHydrated("/mission-control/tools/bibliographic")
        try await expect(page.locator("a[href='/mission-control/tools/vignettes/\(vignette)' i]").first).toBeVisible()
        // Its page names its commits and offers an Amend.
        try await page.openHydrated("/mission-control/tools/vignettes/\(vignette)")
        try await expect(page.locator(".tool-details-title")).toHaveText("Bibliographic Translation Tools Vignette")
        try await expect(page.locator(".pedigree-view").filter(hasText: commit).first).toBeVisible()
        let robots = try await page.evaluate(
          "document.querySelector(\"meta[name='robots']\")?.content ?? ''", as: String.self)
        #expect(robots.contains("noindex"), "Never indexed: \(robots)")
        let amend = page.locator(".tool-details-amend button[type='submit']")
        try await expect(amend).toHaveText("Submit Amendment")
        try await amend.click()
        // Its Amend form: the vignette in edit mode, its tool files, no
        // note. Its commits are no repository's, so its files cannot be
        // read: said, and nothing to change.
        try await expect(page, timeout: .seconds(15)).toHaveURL("the Amend form") {
          $0.path.lowercased() == "/mission-control/tools/vignettes/\(vignette)/amend"
        }
        try await expect(page.locator(".form-header-title").first)
          .toContainText("Submit Amendment")
        try await expect(page.locator("#amend-vignette-form button[type='submit']")).toHaveText("Submit")
        try await expect(page.locator("textarea[name='note']")).toHaveCount(0)
        // The overture a palinode proposing nothing opens (as a migrated
        // one may), filed here as its Submit would file it.
        let palinodeRow = UUID().uuidString.lowercased()
        _ = try TestAdmin.query(
          """
          BEGIN;
          INSERT INTO vignette_palinodes (id, vignette_kind, slot, tool_vignette_id, submitted_by_user_id, created_at)
          VALUES ('\(palinodeRow)', 'tool', '\(slot)', '\(vignette)', '\(user)', now());
          INSERT INTO vignette_overtures (id, vignette_kind, slot, vignette_palinode_id, tool_vignette_id, created_at)
          VALUES (gen_random_uuid(), 'tool', '\(slot)', '\(palinodeRow)', '\(vignette)', now());
          COMMIT;
          """)
        let id = try opened()
        try await page.openHydrated("/mission-control/tools/overtures/bibliographic/\(id)")
        #expect(!id.isEmpty, "Amend opened a tool overture")
        let palinode = try opened("p.id")
        try await expect(page.locator(".disputorium-core-title")).toHaveText("Bibliographic Overture")
        // Its Pedigree: its palinode, submitted; the vignette amended is
        // named in its thread.
        try await expect(
          page.locator(".pedigree-view a[href='/mission-control/tools/palinodes/bibliographic/\(palinode)' i]")
        ).toHaveCount(1)
        try await expect(page.getByText("amending vignette")).toBeVisible()
        try await expect(page.locator("a[href='/mission-control/tools/vignettes/\(vignette)' i]").first).toBeVisible()
        try await expect(page.locator("#tool-overture-body").filter(hasText: "Not run").first).toBeVisible()
        try await expect(page.getByText("No accepted revision changes the tools yet.")).toBeVisible()
        // No header Commit: a review is a call in its thread.
        try await expect(page.locator("button[form='tool-overture-commit']")).toHaveCount(0)
        // Permit, pressed with nothing accepted, says why and sends
        // nothing; nothing is put in force. While a serenade committed
        // for translation is pending or running, Permit waits for it first
        // (user, 2026-10-21): it runs with the tools it was committed with.
        let running = try count(
          "SELECT count(*) FROM bibliographic_serenades WHERE processing_status IN ('pending', 'translating')") != "0"
        try await page.locator("button[form='tool-overture-permit']").click()
        try await expect(
          page.locator(".action-gate-alert").filter(
            hasText: running
              ? "Permit waits until the process's committed objects finish."
              : "No accepted revision changes the tools yet.")
        ).toBeVisible()
        #expect(try count("SELECT count(*) FROM locutions WHERE locutable_id = '\(id)'") == "0", "No review was called")
        #expect(try count("SELECT count(*) FROM tool_test_runs WHERE overture_id = '\(id)'") == "0", "No test ran")
        #expect(try count("SELECT vignette_id FROM active_tool_vignettes WHERE slot = '\(slot)'") == vignette)
        // The vignette's page now leads to the open overture, no Amend.
        try await page.openHydrated("/mission-control/tools/vignettes/\(vignette)")
        try await expect(page.locator(".tool-details-amend")).toHaveCount(0)
        try await expect(page.locator(".associated-links-view a[href='/mission-control/tools/overtures/bibliographic/\(id)' i]"))
          .toHaveCount(1)
        try await page.expectNoErrors()
      }
      // A reader signed out: the page, no Permit (and never a Commit).
      let id = try opened()
      try await withPage(engine, gnorium, viewport: .desktop) { page in
        try await page.openHydrated("/mission-control/tools/overtures/bibliographic/\(id)")
        try await expect(page.locator(".disputorium-core-title")).toHaveText("Bibliographic Overture")
        try await expect(page.locator("button[form='tool-overture-commit'], button[form='tool-overture-permit']"))
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

  /// Amending is open to every reader (user, 2026-10-22): a signed-in
  /// non-admin sees Submit Amendment and reaches the Amend form; a reader
  /// signed out sees it and, pressed, is told to sign in. Nothing is filed.
  @Test(arguments: [BrowserEngine.chrome])
  func anyReaderMayAmendAToolVignette(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let slot = "bibliographic_translation"
    func count(_ sql: String) throws -> String {
      try TestAdmin.query(sql).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard try count("SELECT count(*) FROM active_tool_vignettes WHERE slot = '\(slot)'") == "0",
      try count(
        """
        SELECT count(*) FROM vignette_overtures
        WHERE slot = '\(slot)' AND vignette_kind = 'tool' AND permitted_at IS NULL AND discarded_at IS NULL
        """) == "0"
    else {
      try Test.cancel(Comment(rawValue: "\(slot) has tool vignettes that are not a web test's"))
      return
    }
    let reader = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let vignette = UUID().uuidString.lowercased()
    let commit = String(repeating: "0", count: 40)
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO tool_vignettes (id, slot, gnorium_python_commit, philology_tools_commit, created_at)
      VALUES ('\(vignette)', '\(slot)', '\(commit)', '\(commit)', now());
      INSERT INTO active_tool_vignettes (slot, vignette_id, activated_by, activated_at)
      VALUES ('\(slot)', '\(vignette)', NULL, now());
      COMMIT;
      """)
    func remove() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM active_tool_vignettes WHERE slot = '\(slot)' AND vignette_id = '\(vignette)';
        DELETE FROM tool_vignettes WHERE id = '\(vignette)';
        COMMIT;
        """)
    }
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [reader.cookie]) { page in
        try await page.openHydrated("/mission-control/tools/vignettes/\(vignette)")
        let amend = page.locator(".tool-details-amend button[type='submit']")
        try await expect(amend).toHaveText("Submit Amendment")
        try await amend.click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the Amend form") {
          $0.path.lowercased() == "/mission-control/tools/vignettes/\(vignette)/amend"
        }
        try await expect(page.locator("#amend-vignette-form button[type='submit']")).toHaveText("Submit")
        try await page.expectNoErrors()
      }
      try await withPage(engine, gnorium, viewport: .desktop) { page in
        try await page.openHydrated("/mission-control/tools/vignettes/\(vignette)")
        let amend = page.locator(".tool-details-amend button[type='submit']")
        try await expect(amend).toHaveText("Submit Amendment")
        try await amend.click()
        // The Amend form opens for a reader who is signed out; its Submit
        // says signing in is needed and files nothing.
        try await expect(page, timeout: .seconds(15)).toHaveURL("the Amend form, signed out") {
          $0.path.lowercased() == "/mission-control/tools/vignettes/\(vignette)/amend"
        }
        try await page.locator("#amend-vignette-form button[type='submit']").click()
        try await expect(page.locator(".action-gate-view .alert-content")).toContainText("Signing in is needed")
        try await expect(page.locator(".action-gate-view .action-gate-alert a")).toHaveAttribute("target", "_blank")
        #expect(URL(string: try await page.url())?.path.lowercased() == "/mission-control/tools/vignettes/\(vignette)/amend")
      }
    } catch {
      remove()
      try await reader.remove(after: error)
    }
    remove()
    try await reader.remove()
  }
}
