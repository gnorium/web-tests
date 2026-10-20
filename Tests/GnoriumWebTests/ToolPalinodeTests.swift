import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A process's tools are revised on a palinode of their vignette, in
/// Mission Control alone (user, 2026-10-20), as its prompts are: a tool
/// vignette is a pinned commit of the tools code; its page offers an admin
/// Amend, which opens the palinode; the palinode's page is never indexed
/// and holds Revise, Commit and Permit, each refusal said when pressed. The
/// vignette here is a scratch one, of commits no repository holds, put in
/// force only where the process has none and removed after; no review is
/// called (no model is asked), no test runs and nothing is permitted.
@Suite("Tool palinodes", .serialized)
struct ToolPalinodeTests {
  @Test(arguments: [BrowserEngine.chrome])
  func amendOpensAToolPalinodeWhoseCommitAndPermitSayWhyTheyWait(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let slot = "bibliographic_translation"
    func count(_ sql: String) throws -> String {
      try TestAdmin.query(sql).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard try count("SELECT count(*) FROM active_tool_vignettes WHERE slot = '\(slot)'") == "0",
      try count("SELECT count(*) FROM vignette_palinodes WHERE slot = '\(slot)' AND vignette_kind = 'tool'") == "0"
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
    func opened() throws -> String {
      try count(
        "SELECT id FROM vignette_palinodes WHERE slot = '\(slot)' AND vignette_kind = 'tool' AND opened_by_user_id = '\(user)'")
    }
    func remove() {
      let id = (try? opened()) ?? ""
      let palinode = id.isEmpty ? "" : """
        DELETE FROM locutions WHERE locutable_id = '\(id)';
        DELETE FROM tool_test_runs WHERE palinode_id = '\(id)';
        DELETE FROM revisions WHERE revisable_id = '\(id)';
        DELETE FROM vignette_palinodes WHERE id = '\(id)';
        """
      _ = try? TestAdmin.query(
        """
        BEGIN;
        \(palinode)
        DELETE FROM active_tool_vignettes WHERE slot = '\(slot)' AND vignette_id = '\(vignette)';
        DELETE FROM tool_vignettes WHERE id = '\(vignette)';
        COMMIT;
        """)
    }
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        // The tools list links the process's vignette in force.
        try await page.openHydrated("/mission-control/tools/bibliographic")
        try await expect(page.locator("a[href='/mission-control/tools/vignettes/\(vignette)' i]").first).toBeVisible()
        // Its page names its commits and offers an admin Amend.
        try await page.openHydrated("/mission-control/tools/vignettes/\(vignette)")
        try await expect(page.locator(".tool-details-title")).toHaveText("Bibliographic Translation Tool Vignette")
        try await expect(page.locator(".pedigree-view").filter(hasText: commit).first).toBeVisible()
        let robots = try await page.evaluate(
          "document.querySelector(\"meta[name='robots']\")?.content ?? ''", as: String.self)
        #expect(robots.contains("noindex"), "Never indexed: \(robots)")
        let amend = page.locator(".tool-details-amend button[type='submit']")
        try await expect(amend).toHaveText("Amend")
        try await amend.click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the palinode") {
          $0.path.lowercased().hasPrefix("/mission-control/tools/palinodes/bibliographic/")
        }
        let id = try opened()
        #expect(!id.isEmpty, "Amend opened a tool palinode")
        try await expect(page.locator(".disputorium-core-title")).toHaveText("Bibliographic Palinode")
        try await expect(page.locator(".pedigree-view a[href='/mission-control/tools/vignettes/\(vignette)' i]"))
          .toHaveCount(1)
        try await expect(page.locator(".pedigree-view").filter(hasText: "Not run").first).toBeVisible()
        try await expect(page.getByText("No accepted revision changes the tools yet.")).toBeVisible()
        // Commit, pressed with nothing accepted, says why and sends nothing.
        try await page.locator("button[form='tool-palinode-commit']").click()
        try await expect(
          page.locator(".action-gate-alert").filter(hasText: "No accepted revision changes the tools yet.")
        ).toBeVisible()
        #expect(try count("SELECT count(*) FROM locutions WHERE locutable_id = '\(id)'") == "0", "No review was called")
        #expect(try count("SELECT count(*) FROM tool_test_runs WHERE palinode_id = '\(id)'") == "0", "No test ran")
        // Permit says the same; nothing is put in force.
        try await page.locator("button[form='tool-palinode-permit']").click()
        try await expect(
          page.locator(".action-gate-alert").filter(hasText: "No accepted revision changes the tools yet.")
        ).toBeVisible()
        #expect(try count("SELECT vignette_id FROM active_tool_vignettes WHERE slot = '\(slot)'") == vignette)
        // The vignette's page now leads to the open palinode, no Amend.
        try await page.openHydrated("/mission-control/tools/vignettes/\(vignette)")
        try await expect(page.locator(".tool-details-amend")).toHaveCount(0)
        try await expect(page.locator(".associated-links-view a[href='/mission-control/tools/palinodes/bibliographic/\(id)' i]"))
          .toHaveCount(1)
        try await page.expectNoErrors()
      }
      // A reader signed out: the page, no Commit or Permit.
      let id = try opened()
      try await withPage(engine, gnorium, viewport: .desktop) { page in
        try await page.openHydrated("/mission-control/tools/palinodes/bibliographic/\(id)")
        try await expect(page.locator(".disputorium-core-title")).toHaveText("Bibliographic Palinode")
        try await expect(page.locator("button[form='tool-palinode-commit'], button[form='tool-palinode-permit']"))
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
