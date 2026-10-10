import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Translation is one session per chunk of pages (user, 2026-09-29): a
/// serenade's page lists its chunks as sessions ("1–2"), shows the
/// focused one's trace—each page opened, translated and committed, its
/// last words—and no processes.
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
  func aSerenadeIsOneSessionPerChunk(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphon = UUID().uuidString.lowercased()
    let madrigal = UUID().uuidString.lowercased()
    let serenade = UUID().uuidString.lowercased()
    do {
      let user = try admin.column("id")
      // Failed: no worker takes it up, nothing is spent.
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, resemblance_service_ids_json, processing_status)
          VALUES ('\(antiphon)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO bibliographic_madrigals (id, thread_id, bibliographic_antiphon_id, biblio_record_id, proposed_content_json,
          metadata_json, processing_status)
          VALUES ('\(madrigal)', '\(madrigal)', '\(antiphon)', '\(work.recordID.lowercased())', '\(Self.tei)',
            (SELECT metadata_json FROM biblio_record_versions WHERE id = '\(work.versionID.lowercased())'), 'committed');
        INSERT INTO bibliographic_serenades (id, bibliographic_madrigal_id, target_language, requested_by_user_id,
          processing_status, processing_error)
          VALUES ('\(serenade)', '\(madrigal)', 'eng', '\(user)', 'failed', 'Web tests');
        INSERT INTO bibliographic_translation_runs (id, bibliographic_serenade_id, process, chunk, attempt, provider, model, output,
          result, duration_ms, created_at)
          VALUES (gen_random_uuid(), '\(serenade)', 'translation', '1–2', 1, 'openrouter', 'qwen/qwen3.8-max-0902',
            '\(try Self.trace())', 'passed', 1200, now());
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/serenades/bibliographic/\(serenade)")
        try await ComputoriumMarks.check(page, process: "translation")
        let process = page.locator(".process-container")
        try await expect(process).toHaveAttribute("data-active-process", "translation")
        try await expect(page.locator(".processes-view")).toHaveCount(0)
        try await expect(page.locator("a[href*='process=']")).toHaveCount(0)
        try await expect(process).toHaveAttribute("data-item-order", "1–2")
        let session = page.locator(".computorium-session-view")
        try await expect(session.getByText("open_page").first).toBeAttached()
        try await expect(session.getByText("write_translation").first).toBeAttached()
        try await expect(session.getByText("Two pages of arithmetic, translated.")).toBeAttached()
      }
    } catch {
      remove(antiphon: antiphon, madrigal: madrigal, serenade: serenade, work: work)
      try await admin.remove(after: error)
    }
    remove(antiphon: antiphon, madrigal: madrigal, serenade: serenade, work: work)
    try await admin.remove()
  }

  private func remove(antiphon: String, madrigal: String, serenade: String, work: ScratchWork) {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM bibliographic_translation_runs WHERE bibliographic_serenade_id = '\(serenade)';
      DELETE FROM bibliographic_serenades WHERE id = '\(serenade)';
      DELETE FROM bibliographic_madrigals WHERE id = '\(madrigal)';
      DELETE FROM bibliographic_antiphons WHERE id = '\(antiphon)';
      COMMIT;
      """)
    work.remove()
  }
}
