import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A recognition is one stage, the pipeline's own (user, 2026-09-29): no
/// Sight, Proof or Vouch cards, and one session a chunk of pages — never a
/// row a page — whose trace shows the tool calls it read and committed with.
@Suite("Recognition sessions", .serialized)
struct RecognitionSessionsTests {
  static let page = #"<TEI xmlns="http://www.tei-c.org/ns/1.0"><text><body><pb n="1"/><p><s><w lemma="sea" type="noun">sea</w></s><lb/></p></body></text></TEI>"#

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aRecognitionShowsItsChunkSessionsAndNoStages(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphonID = UUID().uuidString.lowercased()
    let runID = UUID().uuidString.lowercased()
    do {
      let user = try admin.column("id")
      let blocks: [[String: String]] = [
        ["type": "image_url", "content": "https://example.org/iiif/web-tests/full/1300,/0/default.jpg"],
        ["type": "thinking", "content": "Reading the first page of the chunk."],
        [
          "type": "tool", "name": "commit_page", "arguments": "{}",
          "result": #"{"ok": true, "tool": "commit_page", "committed": "1", "findings_count": 0}"#,
          "status": "ok", "call_id": "call_1",
        ],
        ["type": "semblance_xml", "label": "1", "content": Self.page],
        ["type": "semblance_xml", "label": "2", "content": Self.page],
        ["type": "text", "content": "Both pages of the chunk committed."],
      ]
      let output = String(decoding: try JSONSerialization.data(withJSONObject: blocks), as: UTF8.self)
        .replacingOccurrences(of: "'", with: "''")
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_hallmark_id, requested_by_user_id, semblance_service_ids_json, processing_status)
          VALUES ('\(antiphonID)', '\(work.hallmarkID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO recognition_stage_runs (id, submission_id, stage, semblance, attempt, provider, model, output, result, run_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
          VALUES ('\(runID)',
            (SELECT e.batch_id FROM bibliographic_evidences e
               JOIN bibliographic_overtures o ON o.bibliographic_evidence_id = e.id
               JOIN bibliographic_hallmarks h ON h.bibliographic_overture_id = o.id
              WHERE h.id = '\(work.hallmarkID.lowercased())'),
            'recognition', 'Pages 1–2', 1, 'DeepSeek', 'deepseek-flash', '\(output)', 'passed', gen_random_uuid(),
            '\(antiphonID)', 1200, now());
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/antiphons/bibliographic/\(antiphonID)")
        // No stage cards: the stage is the pipeline's name.
        try await expect(page.locator(".computorium-core-stage-link")).toHaveCount(0)
        try await expect(page.getByText("Stages", exact: true)).toHaveCount(0)
        for stage in ["sight", "proof", "vouch"] {
          try await expect(page.locator("a[href*='stage=\(stage)']")).toHaveCount(0)
        }
        try await expect(page.locator(".pipeline-container")).toHaveAttribute("data-active-stage", "recognition")
        // One session for the chunk, not a row for each of its pages (the
        // sidebar is drawn twice, for wide screens and the phone's menu).
        let rows = page.locator(".computorium-core-sessions-slot").first.locator(".roster-row")
        try await expect(rows).toHaveCount(1)
        try await expect(rows.first).toHaveAttribute("data-session-label", "Pages 1–2")
        // Its trace: the tool call it committed a page with, and its last word.
        try await expect(page.locator(".session-view").getByText("commit_page").first).toBeAttached()
        try await expect(page.locator(".session-view").getByText("Both pages of the chunk committed.")).toBeAttached()
      }
    } catch {
      remove(runID: runID, antiphonID: antiphonID, work: work)
      try await admin.remove(after: error)
    }
    remove(runID: runID, antiphonID: antiphonID, work: work)
    try await admin.remove()
  }

  /// A zoom's card shows its detail (user, 2026-09-29): the region as the
  /// model was sent it, and the page with the region's box outlined where
  /// the call asked (x 100, y 250, width 300, height 200 of 1000).
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aZoomCardShowsItsDetailAndTheOutlinedBox(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphonID = UUID().uuidString.lowercased()
    let runID = UUID().uuidString.lowercased()
    func image(_ width: Int, _ height: Int) -> String {
      let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='\(width)' height='\(height)'><rect width='100%' height='100%' fill='#ccc'/></svg>"
      return "data:image/svg+xml;base64," + Data(svg.utf8).base64EncodedString()
    }
    do {
      let user = try admin.column("id")
      let result: [String: Any] = [
        "ok": true, "tool": "zoom_image", "page": "1", "region": [100, 250, 300, 200], "image": "attached below",
        "source_width": 1200, "source_height": 800, "sent_width": 600, "sent_height": 400,
        "detail_url": image(600, 400), "page_url": image(400, 400),
      ]
      let blocks: [[String: String]] = [
        [
          "type": "tool", "name": "zoom_image", "arguments": #"{"x": 100, "y": 250, "width": 300, "height": 200}"#,
          "result": String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self),
          "status": "ok", "call_id": "call_zoom",
        ],
        ["type": "text", "content": "Looked closer."],
      ]
      let output = String(decoding: try JSONSerialization.data(withJSONObject: blocks), as: UTF8.self)
        .replacingOccurrences(of: "'", with: "''")
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_hallmark_id, requested_by_user_id, semblance_service_ids_json, processing_status)
          VALUES ('\(antiphonID)', '\(work.hallmarkID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO recognition_stage_runs (id, submission_id, stage, semblance, attempt, provider, model, output, result, run_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
          VALUES ('\(runID)',
            (SELECT e.batch_id FROM bibliographic_evidences e
               JOIN bibliographic_overtures o ON o.bibliographic_evidence_id = e.id
               JOIN bibliographic_hallmarks h ON h.bibliographic_overture_id = o.id
              WHERE h.id = '\(work.hallmarkID.lowercased())'),
            'recognition', 'Page 1', 1, 'DeepSeek', 'deepseek-flash', '\(output)', 'passed', gen_random_uuid(),
            '\(antiphonID)', 1200, now());
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/antiphons/bibliographic/\(antiphonID)")
        let card = page.locator("#session-tool-call_zoom")
        try await card.locator(".accordion-summary").first.click()
        let detail = card.locator(".detail-view")
        try await expect(detail).toBeVisible()
        try await expect(detail.locator(".detail-view-image")).toBeVisible()
        try await expect(detail.locator(".detail-view-image")).toHaveAttribute("src", result["detail_url"] as! String)
        try await expect(detail.locator(".datum-view")).toContainText("1200 × 800")
        // The box sits on the page where the region is: 10% in, 25% down,
        // 30% wide and 20% high — once the page, lazily loaded, has come in.
        let pageImage = detail.locator(".detail-view-page-image")
        for _ in 0..<50 {
          if try await pageImage.evaluate("el => el.complete && el.naturalHeight > 0") == .bool(true) { break }
          try await Task.sleep(for: .milliseconds(100))
        }
        let frame = try #require(try await detail.locator(".detail-view-page-image").boundingBox())
        let box = try #require(try await detail.locator(".detail-view-box").boundingBox())
        #expect(abs((box.x - frame.x) / frame.width - 0.10) < 0.02)
        #expect(abs((box.y - frame.y) / frame.height - 0.25) < 0.02)
        #expect(abs(box.width / frame.width - 0.30) < 0.02)
        #expect(abs(box.height / frame.height - 0.20) < 0.02)
        // The card fits the phone: no sideways scroll.
        let overflow = try await page.evaluate("document.documentElement.scrollWidth > document.documentElement.clientWidth")
        #expect(overflow == .bool(false))
      }
    } catch {
      remove(runID: runID, antiphonID: antiphonID, work: work)
      try await admin.remove(after: error)
    }
    remove(runID: runID, antiphonID: antiphonID, work: work)
    try await admin.remove()
  }

  private func remove(runID: String, antiphonID: String, work: ScratchWork) {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM recognition_stage_runs WHERE id = '\(runID)';
      DELETE FROM bibliographic_antiphons WHERE id = '\(antiphonID)';
      COMMIT;
      """)
    work.remove()
  }
}
