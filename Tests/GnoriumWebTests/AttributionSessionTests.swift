import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Attribution is one evidence-bound session per concerto (user,
/// 2026-09-29): its page lists no Trawl, Weigh or Label stages, and shows the
/// session's trace — the canvases it looked at and the fields it recorded. A
/// concerto that ran the old stages still lists them, its history.
@Suite("Attribution sessions", .serialized)
struct AttributionSessionTests {
  static func trace() throws -> String {
    let blocks: [[String: String]] = [
      ["type": "thinking", "content": "The title page should give the imprint."],
      [
        "type": "tool", "name": "view_canvas", "arguments": #"{"label":"1r"}"#,
        "result": #"{"ok": true, "tool": "view_canvas", "evidence": "e1", "canvas": "1r", "image": "attached below"}"#,
        "status": "ok", "call_id": "call_1",
      ],
      [
        "type": "tool", "name": "record_field",
        "arguments": #"{"field":"date","value":{"yearQualifier":"exact","era":"anno_domini","year":1853},"reasoning":"The imprint prints it.","citations":[{"evidence":"e1","quote":"1853."}]}"#,
        "result": #"{"ok": true, "tool": "record_field", "recorded": "date", "citations": 1}"#,
        "status": "ok", "call_id": "call_2",
      ],
      ["type": "field", "field": "date", "content": "{}"],
      ["type": "text", "content": "The date is from the title page; the author stays unknown."],
      ["type": "attributions", "content": "[]"],
    ]
    return String(decoding: try JSONSerialization.data(withJSONObject: blocks), as: UTF8.self)
      .replacingOccurrences(of: "'", with: "''")
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aConcertoIsOneSessionWithNoStages(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let runID = UUID().uuidString.lowercased()
    do {
      _ = try TestAdmin.query(
        """
        INSERT INTO attribution_stage_runs (id, bibliographic_concerto_id, stage, attempt, provider, model, output, result, duration_ms, created_at)
          VALUES ('\(runID)', '\(work.concertoID)', 'attribution', 1, 'DeepSeek', 'deepseek-flash', '\(try Self.trace())', 'passed', 1200, now());
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/concertos/bibliographic/\(work.concertoID)")
        try await expect(page.locator(".computorium-core-stage-link")).toHaveCount(0)
        for stage in ["trawl", "weigh", "label"] {
          try await expect(page.locator("a[href*='stage=\(stage)']")).toHaveCount(0)
        }
        try await expect(page.locator(".pipeline-container")).toHaveAttribute("data-active-stage", "attribution")
        let session = page.locator(".session-view")
        try await expect(session.getByText("view_canvas").first).toBeAttached()
        try await expect(session.getByText("record_field").first).toBeAttached()
        try await expect(session.getByText("The date is from the title page; the author stays unknown.")).toBeAttached()
      }
    } catch {
      remove(runIDs: [runID], work: work)
      await admin.remove()
      throw error
    }
    remove(runIDs: [runID], work: work)
    await admin.remove()
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aConcertoThatRanTheOldStagesListsThem(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let runIDs = (0..<3).map { _ in UUID().uuidString.lowercased() }
    do {
      let rows = zip(runIDs, ["trawl", "weigh", "label"]).map { id, stage in
        "('\(id)', '\(work.concertoID)', '\(stage)', 1, 'DeepSeek', 'deepseek-flash', '[{\"type\":\"text\",\"content\":\"\(stage) ran\"}]', 'passed', 10, now())"
      }.joined(separator: ", ")
      _ = try TestAdmin.query(
        """
        INSERT INTO attribution_stage_runs (id, bibliographic_concerto_id, stage, attempt, provider, model, output, result, duration_ms, created_at)
          VALUES \(rows);
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/concertos/bibliographic/\(work.concertoID)")
        for stage in ["trawl", "weigh", "label"] {
          try await expect(page.locator("a[href*='stage=\(stage)']").first).toBeAttached()
        }
        try await expect(page.locator(".pipeline-container")).toHaveAttribute("data-active-stage", "label")
        try await expect(page.locator(".session-view").getByText("label ran")).toBeAttached()
      }
    } catch {
      remove(runIDs: runIDs, work: work)
      await admin.remove()
      throw error
    }
    remove(runIDs: runIDs, work: work)
    await admin.remove()
  }

  private func remove(runIDs: [String], work: ScratchWork) {
    _ = try? TestAdmin.query(
      "DELETE FROM attribution_stage_runs WHERE id IN (\(runIDs.map { "'\($0)'" }.joined(separator: ", ")));")
    work.remove()
  }
}
