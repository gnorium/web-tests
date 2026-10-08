import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An explication is one stage, the pipeline's own (user, 2026-09-29): no
/// Sight, Proof or Vouch cards, and one session a chunk of pages—never a
/// row a page—whose trace shows the tool calls it read and saved with.
@Suite("Bibliographic explication sessions", .serialized)
struct BibliographicExplicationSessionsTests {
  static let page = #"<TEI xmlns="http://www.tei-c.org/ns/1.0"><text><body><pb n="1"/><p><s><w lemma="sea" type="noun">sea</w></s><lb/></p></body></text></TEI>"#

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aBibliographicExplicationShowsItsChunkSessionsAndNoStages(engine: BrowserEngine, layout: Layout) async throws {
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
          "type": "tool", "name": "save_page", "arguments": "{}",
          "result": #"{"ok": true, "tool": "save_page", "saved": "1", "findings_count": 0}"#,
          "status": "ok", "call_id": "call_1",
        ],
        ["type": "semblance_xml", "label": "1", "content": Self.page],
        ["type": "semblance_xml", "label": "2", "content": Self.page],
        ["type": "text", "content": "Both pages of the chunk saved."],
      ]
      let output = String(decoding: try JSONSerialization.data(withJSONObject: blocks), as: UTF8.self)
        .replacingOccurrences(of: "'", with: "''")
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, semblance_service_ids_json, processing_status)
          VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO bibliographic_explication_stage_runs (id, submission_id, stage, semblance, attempt, provider, model, output, result, run_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
          VALUES ('\(runID)',
            (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'),
            'explication', '1–2', 1, 'DeepSeek', 'deepseek-flash', '\(output)', 'passed', gen_random_uuid(),
            '\(antiphonID)', 1200, now());
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/antiphons/bibliographic/\(antiphonID)")
        // No stage cards: the stage is the pipeline's name.
        try await expect(page.locator(".stages-view")).toHaveCount(0)
        try await expect(page.getByText("Stages", exact: true)).toHaveCount(0)
        try await expect(page.locator("a[href*='stage=']")).toHaveCount(0)
        try await expect(page.locator(".pipeline-container")).toHaveAttribute("data-active-stage", "explication")
        // One session for the chunk, not a row for each of its pages (the
        // sidebar is drawn twice, for wide screens and the phone's menu).
        let rows = page.locator(".computorium-core-sessions-slot").first.locator(".roster-row")
        try await expect(rows).toHaveCount(1)
        try await expect(rows.first).toHaveAttribute("data-session-label", "1–2")
        // Its search is the site's search box, medium: 40 tall, its text
        // 16px, as every field's.
        let roster = page.locator(".computorium-core-sessions-slot").first
        let search = roster.locator(".roster-search-input .search-input")
        let medium = try await search.evaluate(
          """
          (el) => { const row = el.closest('.roster-view').querySelector('.roster-row');
            return !!row && el.closest('.search-input-view').dataset.size === 'medium'
              && el.placeholder === 'Search sessions' && el.getAttribute('aria-label') === 'Search sessions'
              && getComputedStyle(el).fontSize === '16px'
              && getComputedStyle(el).height === '40px'; }
          """).bool == true
        #expect(medium, "The roster's search is a medium search input, its text 16px")
        // It filters the rows, as it did.
        if layout == .desktop {
          try await search.fill("no such session")
          try await expect(rows.first).toHaveAttribute("data-hidden", "true")
          try await search.fill("1–2")
          try await expect(rows.first).toHaveAttribute("data-hidden", "false")
        }
        // Its trace: the tool call it saved a page with, and its last word.
        try await expect(page.locator(".session-view").getByText("save_page").first).toBeAttached()
        try await expect(page.locator(".session-view").getByText("Both pages of the chunk saved.")).toBeAttached()
      }
    } catch {
      remove(runID: runID, antiphonID: antiphonID, work: work)
      try await admin.remove(after: error)
    }
    remove(runID: runID, antiphonID: antiphonID, work: work)
    try await admin.remove()
  }

  /// A zoom's card shows its detail (user, 2026-09-29): the region as the
  /// model was sent it, a preview that expands, and its source and sent
  /// pixels beside the tool's other datums (the page thumbnail and its
  /// outlined box went with the read-only metadata's simplification,
  /// 2026-10-04).
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aZoomCardShowsItsDetail(engine: BrowserEngine, layout: Layout) async throws {
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
      let detailURL = image(600, 400)
      let result: [String: Any] = [
        "ok": true, "tool": "zoom_image", "page": "1", "region": [100, 250, 300, 200], "image": "attached below",
        "source_width": 1200, "source_height": 800, "sent_width": 600, "sent_height": 400,
        "detail_url": detailURL, "page_url": image(400, 400),
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
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, semblance_service_ids_json, processing_status)
          VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO bibliographic_explication_stage_runs (id, submission_id, stage, semblance, attempt, provider, model, output, result, run_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
          VALUES ('\(runID)',
            (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'),
            'explication', '1', 1, 'DeepSeek', 'deepseek-flash', '\(output)', 'passed', gen_random_uuid(),
            '\(antiphonID)', 1200, now());
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/antiphons/bibliographic/\(antiphonID)")
        let card = page.locator("#session-tool-call_zoom")
        try await card.locator(".accordion-summary").first.click()
        let detail = card.locator(".detail-view")
        try await expect(detail).toBeVisible()
        // The detail in place, as a semblance is: no chip, no lightbox.
        try await expect(detail.locator(".expandable-attachment-image-viewport")).toBeVisible()
        try await expect(detail.locator(".expandable-attachment-image-canvas")).toHaveAttribute("src", detailURL)
        try await expect(card.locator(".expandable-attachment-dialog")).toHaveCount(0)
        // The sizes the model received, under its own keys, in the result box.
        let box = card.locator(".session-tool-call-result-box")
        try await expect(box).toContainText("source_width")
        try await expect(box).toContainText("1200")
        try await expect(box).toContainText("sent_width")
        try await expect(box).toContainText("600")
        // Every other key too (user, 2026-10-07): the region as sent, its
        // URLs, and `image`, whose datum holds the detail itself.
        func labels(_ selector: String) async throws -> String {
          try await page.evaluate(
            "[...document.querySelectorAll('#session-tool-call_zoom \(selector) .datum-label')].map(l => l.textContent.trim()).join(' ')",
            as: String.self)
        }
        let resultLabels = try await labels(".session-tool-call-result-box")
        #expect(
          resultLabels == "detail_url image ok page page_url region sent_height sent_width source_height source_width tool",
          "Every key the zoom returned: \(resultLabels)")
        try await expect(box).toContainText("[100, 250, 300, 200]")
        // The arguments as sent, each its own datum.
        let argumentLabels = try await labels(".session-tool-call-args")
        #expect(argumentLabels == "height width x y", "Every argument: \(argumentLabels)")
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
      DELETE FROM bibliographic_explication_stage_runs WHERE id = '\(runID)';
      DELETE FROM bibliographic_antiphons WHERE id = '\(antiphonID)';
      COMMIT;
      """)
    work.remove()
  }
}
