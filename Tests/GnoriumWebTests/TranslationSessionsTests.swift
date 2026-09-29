import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Translation is one session per chunk of pages (user, 2026-09-29): a
/// madrigal's page lists its chunks as sessions ("Pages 1–2"), shows the
/// focused one's trace — each page opened, translated and committed, its
/// last words — and no Carry, Blend or Match stage cards; a madrigal that ran
/// those lists their runs after its chunks, as history.
@Suite("Translation sessions", .serialized)
struct TranslationSessionsTests {
  static func trace() throws -> String {
    let blocks: [[String: String]] = [
      ["type": "thinking", "content": "The page is a heading and a rule of arithmetic."],
      [
        "type": "tool", "name": "open_page", "arguments": #"{"page":"1"}"#,
        "result": #"{"ok": true, "page": "1", "of": "1 of 2"}"#, "status": "ok", "call_id": "call_1",
      ],
      [
        "type": "tool", "name": "write_translation",
        "arguments": #"{"page":"1","segments":[{"key":"s1","text":"The rule of three","note":""}]}"#,
        "result": #"{"ok": true, "written": ["s1"], "missing": []}"#, "status": "ok", "call_id": "call_2",
      ],
      ["type": "translated_page", "page": "1", "content": "{}"],
      ["type": "text", "content": "Two pages of arithmetic, translated."],
    ]
    return String(decoding: try JSONSerialization.data(withJSONObject: blocks), as: UTF8.self)
      .replacingOccurrences(of: "'", with: "''")
  }

  static let tei = #"{"teiXml":"<TEI><text><body><pb n=\"1\" facs=\"https://example.org/iiif/wt1/full/1300,/0/default.jpg\"/><p>Regola del tre</p><pb n=\"2\" facs=\"https://example.org/iiif/wt2/full/1300,/0/default.jpg\"/><p>Somma</p></body></text></TEI>"}"#

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aMadrigalIsOneSessionPerChunkWithItsHistory(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphon = UUID().uuidString.lowercased()
    let proposal = UUID().uuidString.lowercased()
    let madrigal = UUID().uuidString.lowercased()
    do {
      let user = try admin.column("id")
      // Failed: no worker takes it up, nothing is spent.
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_hallmark_id, requested_by_user_id, semblance_service_ids_json, processing_status)
          VALUES ('\(antiphon)', '\(work.hallmarkID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO bibliographic_proposals (id, thread_id, bibliographic_antiphon_id, biblio_record_id, proposed_content_json,
          metadata_json, processing_status)
          VALUES ('\(proposal)', '\(proposal)', '\(antiphon)', '\(work.recordID.lowercased())', '\(Self.tei)',
            (SELECT metadata_json FROM biblio_record_versions WHERE id = '\(work.versionID.lowercased())'), 'committed');
        INSERT INTO bibliographic_madrigals (id, bibliographic_proposal_id, target_language, requested_by_user_id,
          processing_status, processing_error)
          VALUES ('\(madrigal)', '\(proposal)', 'eng', '\(user)', 'failed', 'Web tests');
        INSERT INTO translation_stage_runs (id, bibliographic_madrigal_id, stage, chunk, attempt, provider, model, output,
          result, duration_ms, created_at)
          VALUES (gen_random_uuid(), '\(madrigal)', 'translation', 'Pages 1–2', 1, 'openrouter', 'qwen/qwen3.8-max-0902',
            '\(try Self.trace())', 'passed', 1200, now()),
          (gen_random_uuid(), '\(madrigal)', 'carry', NULL, 1, 'deepseek', 'deepseek-flash',
            '[{"type":"text","content":"carry ran"}]', 'passed', 10, now() - interval '1 day');
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/madrigals/bibliographic/\(madrigal)")
        let pipeline = page.locator(".pipeline-container")
        try await expect(pipeline).toHaveAttribute("data-active-stage", "translation")
        try await expect(page.locator(".computorium-core-stage-link")).toHaveCount(0)
        for stage in ["carry", "blend", "match"] {
          try await expect(page.locator("a[href*='stage=\(stage)']")).toHaveCount(0)
        }
        try await expect(pipeline).toHaveAttribute("data-item-order", "Pages 1–2,Carry")
        let session = page.locator(".session-view")
        try await expect(session.getByText("open_page").first).toBeAttached()
        try await expect(session.getByText("write_translation").first).toBeAttached()
        try await expect(session.getByText("Two pages of arithmetic, translated.")).toBeAttached()

        try await page.openHydrated("/mission-control/madrigals/bibliographic/\(madrigal)?semblance=Carry")
        try await expect(page.locator(".session-view").getByText("carry ran")).toBeAttached()
      }
    } catch {
      remove(antiphon: antiphon, proposal: proposal, madrigal: madrigal, work: work)
      try await admin.remove(after: error)
    }
    remove(antiphon: antiphon, proposal: proposal, madrigal: madrigal, work: work)
    try await admin.remove()
  }

  private func remove(antiphon: String, proposal: String, madrigal: String, work: ScratchWork) {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM translation_stage_runs WHERE bibliographic_madrigal_id = '\(madrigal)';
      DELETE FROM bibliographic_madrigals WHERE id = '\(madrigal)';
      DELETE FROM bibliographic_proposals WHERE id = '\(proposal)';
      DELETE FROM bibliographic_antiphons WHERE id = '\(antiphon)';
      COMMIT;
      """)
    work.remove()
  }
}
