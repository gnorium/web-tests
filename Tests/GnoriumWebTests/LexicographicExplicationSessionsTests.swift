import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Explication is one session, on the first of the title's ranked clusters
/// (user, 2026-09-29; one sentiment per object, 2026-10-10): the antiphon's
/// page lists that one session ("Quotes"), never its
/// title's other candidates, shows its trace—each quote read and
/// assigned, its last words—and no processes.
@Suite("Lexicographic explication sessions", .serialized)
struct LexicographicExplicationSessionsTests {
  /// The session's trace, its blocks as received (`SessionTrace`).
  static let trace: [[String: String]] = [
    ["type": "thinking", "content": "The sentence speaks of a person adding by hand."],
    [
      "type": "tool", "name": "read_quote", "arguments": #"{"quote":"u-1"}"#,
      "result": #"{"ok": true, "quote": "u-1", "sentence": "The ⟦computer⟧ added the columns."}"#,
      "status": "ok", "call_id": "call_1",
    ],
    [
      "type": "tool", "name": "assign",
      "arguments": #"{"quote":"u-1","status":"assigned","sentiments":["s-1-1"],"confidence":"clear","meaning":"a person who calculates","reason":"added the columns"}"#,
      "result": #"{"ok": true, "quote": "u-1", "unassigned": []}"#,
      "status": "ok", "call_id": "call_2",
    ],
    ["type": "assignment", "quote": "u-1", "content": "{}"],
    ["type": "text", "content": "Both uses are the human calculator."],
  ]

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func anAntiphonIsOneSessionOnItsFirstCluster(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    let antiphon = UUID().uuidString.lowercased()
    let clustering = UUID().uuidString.lowercased()
    let clusters = [UUID().uuidString.lowercased(), UUID().uuidString.lowercased()]
    let nocturne = UUID().uuidString.lowercased()
    do {
      let user = try admin.column("id")
      // Failed and needing a person: no worker takes it up, nothing is spent.
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO lexicographic_antiphons (id, lexicographic_fountain_id, lexicographic_madrigal_id, requested_by_user_id,
          processing_status, processing_error, language, sentence, created_at, updated_at)
          VALUES ('\(antiphon)', (SELECT lexicographic_fountain_id FROM lexicographic_overtures WHERE id = '\(word.overtureID)'),
            '\(word.madrigalID)', '\(user)', 'failed', 'Needs a person: web tests', 'eng', '\(word.title)', now(), now());
        INSERT INTO quote_clusterings (id, lexicographic_antiphon_id, method, threshold, model, model_version,
          dimensions, recipe, quote_ids_json)
          VALUES ('\(clustering)', '\(antiphon)', 'agglomerative-average-cosine-v1', 0.35, 'test/embedding',
            'Test via Stub', 3, 'quote-v1', '["u-1","u-2","u-3"]');
        INSERT INTO quote_clusters (id, quote_clustering_id, position, quote_ids_json)
          VALUES ('\(clusters[0])', '\(clustering)', 0, '["u-1","u-2"]'), ('\(clusters[1])', '\(clustering)', 1, '["u-3"]');
        INSERT INTO lexicographic_explication_nocturnes (id, lexicographic_antiphon_id, process, instance, provider, model, result,
          duration_ms, quote_cluster_id, created_at)
          VALUES ('\(nocturne)', '\(antiphon)', 'explication', 1, 'openrouter', 'qwen/qwen3.8-max-0902',
            'passed', 1200, '\(clusters[0])', now());
        \(try SessionTrace.append(Self.trace, table: "lexicographic_explication_nocturnes", id: nocturne))
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/antiphons/lexicographic/\(antiphon)")
        try await expect(page.locator(".process-container")).toHaveAttribute("data-active-process", "explication")
        try await expect(page.locator(".processes-view")).toHaveCount(0)
        try await expect(page.locator("a[href*='process=']")).toHaveCount(0)
        let process = page.locator(".process-container")
        try await expect(process).toHaveAttribute(
          "data-item-order", "Quotes")
        let session = page.locator(".computorium-session-view")
        try await expect(session.getByText("read_quote").first).toBeAttached()
        try await expect(session.getByText("assign", exact: true).first).toBeAttached()
        try await expect(session.getByText("Both uses are the human calculator.")).toBeAttached()
      }
    } catch {
      remove(antiphon: antiphon, word: word)
      try await admin.remove(after: error)
    }
    remove(antiphon: antiphon, word: word)
    try await admin.remove()
  }

  private func remove(antiphon: String, word: ScratchWord) {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      \(SessionTrace.delete(table: "lexicographic_explication_nocturnes", where: "lexicographic_antiphon_id = '\(antiphon)'"))
      DELETE FROM lexicographic_explication_nocturnes WHERE lexicographic_antiphon_id = '\(antiphon)';
      DELETE FROM quote_clusterings WHERE lexicographic_antiphon_id = '\(antiphon)';
      DELETE FROM lexicographic_antiphons WHERE id = '\(antiphon)';
      COMMIT;
      """)
    word.remove()
  }
}
