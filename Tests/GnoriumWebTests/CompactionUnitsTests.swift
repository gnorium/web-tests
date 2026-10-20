import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A compaction's figures are the model's context in tokens, as the loop
/// counts it now (`tokens_before`, `tokens_after`); a run recorded before
/// that keeps its characters, labeled so (prod is live history). The card's
/// range, its stubs' sizes and the stub's line under its call all say the
/// unit. Chrome headless.
@Suite("Compaction units", .serialized)
struct CompactionUnitsTests {
  static let stub = #"{"ok": true, "tool": "read_conventions", "compacted": true}"#

  @Test(arguments: [BrowserEngine.chrome])
  func aCompactionCountsTokensAndAnOlderOneCharacters(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphonID = UUID().uuidString.lowercased()
    let nocturneID = UUID().uuidString.lowercased()
    func cleanUp() async throws {
      _ = try? TestAdmin.query(
        SessionTrace.delete(table: "bibliographic_explication_nocturnes", where: "id='\(nocturneID)'")
          + "DELETE FROM bibliographic_explication_nocturnes WHERE id='\(nocturneID)'; DELETE FROM bibliographic_antiphons WHERE id='\(antiphonID)';")
      work.remove()
      try await admin.remove()
    }
    do {
      let user = try admin.column("id")
      let trace: [[String: String]] = [
        ["type": "thinking", "content": "Reading the conventions."],
        ["type": "tool", "name": "read_conventions", "arguments": "{}", "result": #"{"ok": true, "content": "Rule one."}"#, "status": "ok", "call_id": "rc"],
        [
          "type": "compaction", "mode": "micro", "micro": "1", "tokens_before": "1200", "tokens_after": "300",
          "stubbed": "rc\tread_conventions\t{}\t40\t12\t\(Self.stub)",
        ],
        ["type": "compaction", "mode": "auto", "micro": "0", "chars_before": "100", "chars_after": "60",
         "prompt": "Summarize.", "summary": "Summary."],
        ["type": "text", "content": "Done."],
      ]
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, resemblance_service_ids_json, processing_status)
          VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO bibliographic_explication_nocturnes (id, submission_id, process, resemblance, instance, provider, model, result, nocturne_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
          VALUES ('\(nocturneID)', (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'),
            'explication', '1', 1, 'DeepSeek', 'deepseek-flash', 'passed', gen_random_uuid(), '\(antiphonID)', 1200, now());
        \(try SessionTrace.append(trace, table: "bibliographic_explication_nocturnes", id: nocturneID))
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/antiphons/bibliographic/\(antiphonID)")
        let ranges = page.locator(".computorium-session-compaction-range")
        try await expect(ranges).toHaveCount(2)
        try await expect(ranges.nth(0)).toHaveText("1,200 → 300 tokens")
        try await expect(ranges.nth(1)).toHaveText("100 → 60 chars")
        try await expect(page.locator(".computorium-session-compaction-meta").first).toContainText("context 75% smaller")
        // A card's body is drawn when it is first opened.
        try await page.locator("#computorium-session-tool-rc").locator(".accordion-summary").first.click()
        try await expect(page.locator("#computorium-session-tool-rc").locator(".computorium-session-tool-stub .link-view"))
          .toHaveText("stubbed by microcompaction · 40 → 12 tokens")
        try await page.locator(".computorium-session-compaction .accordion-summary").first.click()
        try await expect(page.locator(".computorium-session-compaction-stub-head").first).toContainText("40 → 12 tokens")
        try await page.expectNoErrors()
      }
    } catch {
      do { try await cleanUp() } catch let removal {
        throw WebTestError("\(error)\n…and cleaning up failed too: \(removal)")
      }
      throw error
    }
    try await cleanUp()
  }
}
