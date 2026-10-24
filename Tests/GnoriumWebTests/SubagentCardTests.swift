import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A subagent is a whole agent with a page of its own (user, 2026-10-24).
/// Its parent's `spawn_subagent` call shows the subagent's report in its
/// gray result box and, over the box, a link to that page—the way a
/// compaction card's stub leads to its card—and never the subagent's trace
/// inline. The Workers page says a parent that yielded its worker is
/// awaiting subagents. Chrome, desktop.
@Suite("Subagent card", .serialized)
struct SubagentCardTests {
  @Test(arguments: [BrowserEngine.chrome])
  func theSpawnCallLeadsToTheSubagentsPage(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphonID = UUID().uuidString.lowercased()
    let nocturneID = UUID().uuidString.lowercased()
    let child = UUID().uuidString.lowercased()
    func cleanUp() {
      _ = try? TestAdmin.query(
        SessionTrace.delete(table: "bibliographic_explication_nocturne_instances", where: "id='\(nocturneID)'")
          + "DELETE FROM bibliographic_explication_nocturnes WHERE id IN (SELECT nocturne_id FROM bibliographic_explication_nocturne_instances WHERE id='\(nocturneID)'); DELETE FROM bibliographic_antiphons WHERE id='\(antiphonID)';")
      work.remove()
    }
    do {
      let user = try admin.column("id")
      let report = #"{"ok": true, "tool": "spawn_subagent", "summary": "Zones L1 to L40 read.", "result": "done"}"#
      let recorded: [[String: String]] = [
        ["type": "thinking", "content": "Assigning the zones."],
        ["type": "tool", "name": "spawn_subagent", "arguments": #"{"units": "L1-L40"}"#, "result": report, "status": "ok", "call_id": "spawn1"],
        ["type": "subagent", "key": "L1-L40", "child": child, "status": "succeeded", "call_id": "spawn1"],
        ["type": "text", "content": "Merged."],
      ]
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, image_service_ids_json, processing_status)
          VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO bibliographic_explication_nocturnes (id, bibliographic_antiphon_id, submission_id, process, image, instance_count)
         VALUES (md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid, '\(antiphonID)', (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'), 'explication', '1', 1)
         ON CONFLICT (id) DO UPDATE SET instance_count = bibliographic_explication_nocturnes.instance_count + 1;
        INSERT INTO bibliographic_explication_nocturne_instances (id, nocturne_id, instance, provider, model, result, nocturne_batch_id, duration_ms, created_at)
        VALUES ('\(nocturneID)', md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid, 1, 'fixture', 'fixture', 'passed', gen_random_uuid(), 1, now());
        \(try SessionTrace.append(recorded, table: "bibliographic_explication_nocturne_instances", id: nocturneID))
        COMMIT;
        """)
      let antiphon = "/mission-control/antiphons/bibliographic/\(antiphonID)"
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated(antiphon)
        let call = page.locator("#computorium-session-tool-spawn1")
        try await call.locator(".accordion-summary").first.click()
        // The report, in the gray box; the link over it.
        try await expect(call.locator(".tool-result-box-view")).toContainText("Zones L1 to L40 read.")
        let link = call.locator(".computorium-session-tool-subagent a")
        try await expect(link).toHaveAttribute("href", "/mission-control/subagents/\(child)")
        try await expect(link).toHaveText("Subagent L1-L40")
        let above = try await page.evaluate(
          """
          (() => { const line = document.querySelector('#computorium-session-tool-spawn1').closest('.computorium-session-tool-call')
            .querySelector('.computorium-session-tool-subagent'); const box = line.parentElement.querySelector('.tool-result-box-view')
            return !!(line.compareDocumentPosition(box) & Node.DOCUMENT_POSITION_FOLLOWING) })()
          """, as: Bool.self)
        #expect(above, "The link stands over the result box")
        // Never the subagent's trace inline.
        try await expect(page.locator(".subagent-trace-view")).toHaveCount(0)
        try await page.expectNoErrors()
      }
    } catch {
      cleanUp()
      try await admin.remove(after: error)
    }
    cleanUp()
    try await admin.remove()
  }

  @Test(arguments: [BrowserEngine.chrome])
  func theWorkersPageSaysAwaitingSubagents(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/workers")
        try await expect(page.locator(".mission-control-worker-settings")).toContainText("Awaiting Subagents")
        try await page.expectNoErrors()
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }
}
