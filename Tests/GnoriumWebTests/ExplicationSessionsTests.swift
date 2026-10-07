import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Explication is one session per cluster of utterances (user, 2026-09-29):
/// the antiphon's page lists its clusters as sessions ("Cluster 1 of 2 · 2
/// utterances"), shows the focused one's trace—each utterance read and
/// assigned, its last words—and no stages.
@Suite("Explication sessions", .serialized)
struct ExplicationSessionsTests {
  static func trace() throws -> String {
    let blocks: [[String: String]] = [
      ["type": "thinking", "content": "The sentence speaks of a person adding by hand."],
      [
        "type": "tool", "name": "read_utterance", "arguments": #"{"utterance":"u-1"}"#,
        "result": #"{"ok": true, "utterance": "u-1", "sentence": "The ⟦computer⟧ added the columns."}"#,
        "status": "ok", "call_id": "call_1",
      ],
      [
        "type": "tool", "name": "assign",
        "arguments": #"{"utterance":"u-1","status":"assigned","sentiments":["s-1-1"],"confidence":"clear","meaning":"a person who calculates","reason":"added the columns"}"#,
        "result": #"{"ok": true, "utterance": "u-1", "unassigned": []}"#,
        "status": "ok", "call_id": "call_2",
      ],
      ["type": "assignment", "utterance": "u-1", "content": "{}"],
      ["type": "text", "content": "Both uses are the human calculator."],
    ]
    return String(decoding: try JSONSerialization.data(withJSONObject: blocks), as: UTF8.self)
      .replacingOccurrences(of: "'", with: "''")
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func anAntiphonIsOneSessionPerCluster(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    let antiphon = UUID().uuidString.lowercased()
    let clustering = UUID().uuidString.lowercased()
    let clusters = [UUID().uuidString.lowercased(), UUID().uuidString.lowercased()]
    let run = UUID().uuidString.lowercased()
    do {
      let user = try admin.column("id")
      // Failed and needing a person: no worker takes it up, nothing is spent.
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO lexicographic_antiphons (id, lexicographic_instance_id, lexicographic_notation_id, requested_by_user_id,
          processing_status, processing_error, language, sentence, created_at, updated_at)
          VALUES ('\(antiphon)', (SELECT lexicographic_instance_id FROM lexicographic_overtures WHERE id = '\(word.overtureID)'),
            '\(word.notationID)', '\(user)', 'failed', 'Needs a person: web tests', 'eng', '\(word.title)', now(), now());
        INSERT INTO utterance_clusterings (id, lexicographic_antiphon_id, method, threshold, model, model_version,
          dimensions, recipe, utterance_ids_json)
          VALUES ('\(clustering)', '\(antiphon)', 'agglomerative-average-cosine-v1', 0.35, 'test/embedding',
            'Test via Stub', 3, 'utterance-v1', '["u-1","u-2","u-3"]');
        INSERT INTO utterance_clusters (id, utterance_clustering_id, position, utterance_ids_json)
          VALUES ('\(clusters[0])', '\(clustering)', 0, '["u-1","u-2"]'), ('\(clusters[1])', '\(clustering)', 1, '["u-3"]');
        INSERT INTO explication_stage_runs (id, lexicographic_antiphon_id, stage, attempt, provider, model, output, result,
          duration_ms, utterance_cluster_id, created_at)
          VALUES ('\(run)', '\(antiphon)', 'explication', 1, 'openrouter', 'qwen/qwen3.8-max-0902', '\(try Self.trace())',
            'passed', 1200, '\(clusters[0])', now());
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/antiphons/lexicographic/\(antiphon)")
        try await expect(page.locator(".pipeline-container")).toHaveAttribute("data-active-stage", "explication")
        try await expect(page.locator(".stages-view")).toHaveCount(0)
        try await expect(page.locator("a[href*='stage=']")).toHaveCount(0)
        let pipeline = page.locator(".pipeline-container")
        try await expect(pipeline).toHaveAttribute(
          "data-item-order", "Cluster 1 of 2 · 2 utterances,Cluster 2 of 2 · 1 utterance")
        let session = page.locator(".session-view")
        try await expect(session.getByText("read_utterance").first).toBeAttached()
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
      DELETE FROM explication_stage_runs WHERE lexicographic_antiphon_id = '\(antiphon)';
      DELETE FROM utterance_clusterings WHERE lexicographic_antiphon_id = '\(antiphon)';
      DELETE FROM lexicographic_antiphons WHERE id = '\(antiphon)';
      COMMIT;
      """)
    word.remove()
  }
}
