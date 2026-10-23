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
  /// The sessions' table, which owns their traces (`SessionTrace`).
  static let nocturnes = "bibliographic_translation_nocturne_instances"
  /// The session's trace, its blocks as received (`SessionTrace`).
  static let trace: [[String: String]] = [
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

  static let tei = #"<TEI><text><body><pb n="1" facs="https://example.org/iiif/wt1/full/1300,/0/default.jpg"/><p>Regola del tre</p><pb n="2" facs="https://example.org/iiif/wt2/full/1300,/0/default.jpg"/><p>Somma</p></body></text></TEI>"#

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aSerenadeIsOneSessionPerChunk(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reading: ScratchReading
    do { reading = try ScratchReading(owner: admin, tei: Self.tei) }
    catch { try await admin.remove(after: error) }
    let epilogue = UUID().uuidString.lowercased()
    let serenade = UUID().uuidString.lowercased()
    let nocturne = UUID().uuidString.lowercased()
    do {
      let user = try admin.column("id")
      // Failed: no worker takes it up, nothing is spent.
      _ = try TestAdmin.query(
        """
        BEGIN;
        \(reading.translation(to: epilogue))
        INSERT INTO bibliographic_serenades (id, bibliographic_epilogue_id, target_language, requested_by_user_id,
          processing_status, processing_error)
          VALUES ('\(serenade)', '\(epilogue)', 'eng', '\(user)', 'failed', 'Web tests');
        INSERT INTO bibliographic_translation_nocturnes (id, bibliographic_serenade_id, process, chunk, instance_count)
         VALUES (md5('head:' || ('\(serenade)'):: text || ':' || coalesce(('1–2')::text, ''))::uuid, '\(serenade)', 'translation', '1–2', 1)
         ON CONFLICT (id) DO UPDATE SET instance_count = bibliographic_translation_nocturnes.instance_count + 1;
        INSERT INTO bibliographic_translation_nocturne_instances (id, nocturne_id, bibliographic_serenade_id, process, chunk, instance, provider, model, result, duration_ms, created_at)
        VALUES ('\(nocturne)', md5('head:' || ('\(serenade)'):: text || ':' || coalesce(('1–2')::text, ''))::uuid, '\(serenade)', 'translation', '1–2', 1, 'openrouter', 'qwen/qwen3.8-max-0902', 'passed', 1200, now());
        \(try SessionTrace.append(Self.trace, table: Self.nocturnes, id: nocturne))
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/serenades/bibliographic/\(serenade)")
        try await ComputoriumMarks.check(page, process: "translation")
        try await ComputoriumMarks.checkThinking(page, process: "translation")
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
      remove(serenade: serenade, reading: reading)
      try await admin.remove(after: error)
    }
    remove(serenade: serenade, reading: reading)
    try await admin.remove()
  }

  /// A worker's Stop pauses a session instead of failing it (user,
  /// 2026-10-15): its serenade waits, its chunk's session says why in a
  /// blue info alert over its transcript so far, no mark turns, and no
  /// failure is shown.
  @Test(arguments: [BrowserEngine.chrome])
  func aStoppedSessionWaitsAndSaysWhy(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reading: ScratchReading
    do { reading = try ScratchReading(owner: admin, tei: Self.tei) }
    catch { try await admin.remove(after: error) }
    let epilogue = UUID().uuidString.lowercased()
    let serenade = UUID().uuidString.lowercased()
    let nocturne = UUID().uuidString.lowercased()
    let stopped = "The bibliographic translation worker was stopped."
    do {
      let user = try admin.column("id")
      _ = try TestAdmin.query(
        """
        BEGIN;
        \(reading.translation(to: epilogue))
        INSERT INTO bibliographic_serenades (id, bibliographic_epilogue_id, target_language, requested_by_user_id,
          processing_status, processing_error)
          VALUES ('\(serenade)', '\(epilogue)', 'eng', '\(user)', 'pending', '\(stopped)');
        INSERT INTO bibliographic_translation_nocturnes (id, bibliographic_serenade_id, process, chunk, instance_count)
         VALUES (md5('head:' || ('\(serenade)'):: text || ':' || coalesce(('1–2')::text, ''))::uuid, '\(serenade)', 'translation', '1–2', 1)
         ON CONFLICT (id) DO UPDATE SET instance_count = bibliographic_translation_nocturnes.instance_count + 1;
        INSERT INTO bibliographic_translation_nocturne_instances (id, nocturne_id, bibliographic_serenade_id, process, chunk, instance, provider, model, result, error_message, duration_ms, created_at)
        VALUES ('\(nocturne)', md5('head:' || ('\(serenade)'):: text || ':' || coalesce(('1–2')::text, ''))::uuid, '\(serenade)', 'translation', '1–2', 1, 'openrouter', 'qwen/qwen3.8-max-0902', 'queued', '\(stopped)', 1200, now());
        \(try SessionTrace.append(Self.trace, table: Self.nocturnes, id: nocturne))
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/serenades/bibliographic/\(serenade)")
        let session = page.locator(".computorium-session-view")
        try await expect(session).toHaveAttribute("data-computorium-session-status", "queued")
        try await expect(session.locator(".computorium-session-paused-notice")).toHaveText(stopped)
        try await expect(session.locator(".computorium-session-failed-alert")).toHaveCount(0)
        try await expect(session.getByText("write_translation").first).toBeAttached()
        try await expect(session.locator(".computorium-session-output-thinking-running")).toHaveCount(0)
        try await page.expectNoErrors()
      }
    } catch {
      remove(serenade: serenade, reading: reading)
      try await admin.remove(after: error)
    }
    remove(serenade: serenade, reading: reading)
    try await admin.remove()
  }

  private func remove(serenade: String, reading: ScratchReading) {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      \(SessionTrace.delete(table: Self.nocturnes, where: "bibliographic_serenade_id = '\(serenade)'"))
      DELETE FROM bibliographic_translation_nocturnes WHERE id IN (SELECT nocturne_id FROM bibliographic_translation_nocturne_instances WHERE bibliographic_serenade_id = '\(serenade)');
      DELETE FROM bibliographic_serenades WHERE id = '\(serenade)';
      COMMIT;
      """)
    reading.remove()
  }
}
