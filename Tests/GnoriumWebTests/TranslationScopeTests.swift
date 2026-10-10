import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An epilogue's one process is translation (user, 2026-10-10): no
/// process toggle, no scope—its commit names the pages ticked, untranslated
/// or stale; a fresh one is locked, and its preview says it is translated.
/// No paid commit: form.submit is intercepted after exercising the real
/// checkbox, cloned phone sidebar, and artifact navigation.
@Suite("Translation scope", .serialized)
struct TranslationScopeTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func anEpiloguesCommitTranslatesTheTickedPages(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let service = fixture.baseURL + "/page-1"
    let tei = "<TEI><text><body><pb n=\"1\" facs=\"\(service)/full/max/0/default.jpg\"/><p>Regola del tre</p><pb n=\"2\" facs=\"\(fixture.baseURL)/page-2/full/max/0/default.jpg\"/><p>Somma</p></body></text></TEI>"
    let reading: ScratchReading
    do { reading = try ScratchReading(owner: admin, tei: tei, sourceURL: fixture.baseURL + "/manifest.json") }
    catch { try await admin.remove(after: error) }
    let epilogue = UUID().uuidString.lowercased()
    let serenade = UUID().uuidString.lowercased()
    defer {
      _ = try? TestAdmin.query("DELETE FROM bibliographic_epilogues WHERE id = '\(epilogue)'; DELETE FROM bibliographic_serenades WHERE id = '\(serenade)';")
      reading.remove()
    }
    do {
      let user = try admin.column("id")
      let layerObject: [String: Any] = [
        "sourceLanguage": "ita", "targetLanguage": "eng", "tei": "", "pages": [
          ["service": service, "label": "1", "sourceDigest": "old", "segments": [], "stale": true],
          ["service": fixture.baseURL + "/page-2", "label": "2", "sourceDigest": "current", "segments": [], "stale": false],
        ],
      ]
      let layer = try String(decoding: JSONSerialization.data(withJSONObject: layerObject), as: UTF8.self)
        .replacingOccurrences(of: "'", with: "''")
      _ = try TestAdmin.query("""
        BEGIN;
        UPDATE bibliographic_madrigals SET metadata_json =
          (metadata_json::jsonb || '{"language":"ita","sourceUrl":"\(fixture.baseURL)/manifest.json"}'::jsonb)::text
          WHERE id = '\(reading.madrigalID)';
        INSERT INTO bibliographic_serenades (id, bibliographic_madrigal_id, target_language, canvas_service_ids_json, requested_by_user_id, processing_status)
          VALUES ('\(serenade)', '\(reading.madrigalID)', 'eng', '[]', '\(user)', 'submitted');
        INSERT INTO bibliographic_epilogues (id, thread_id, bibliographic_overture_id, bibliographic_serenade_id, proposed_content_json, metadata_json, translation_json, processing_status)
          SELECT '\(epilogue)', '\(epilogue)', '\(reading.work.overtureID.lowercased())', '\(serenade)', p.proposed_content_json, p.metadata_json, '\(layer)', 'pending'
          FROM bibliographic_madrigals p WHERE p.id = '\(reading.madrigalID)';
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/epilogues/bibliographic/\(epilogue)")
        try await expect(page.locator(".process-toggle-view")).toHaveCount(0)
        try await expect(page.locator(".prompt-previews-heading")).toHaveText("Prompts")
        try await expect(page.locator(".prompt-previews-slot"), timeout: .seconds(20))
          .toHaveAttribute("aria-busy", "false")
        try await expect(page.locator(".prompt-previews-content")).toHaveAttribute("data-process", "bibliographic_translation")
        try await expect(page.locator(".prompt-previews-process[data-process='Explication']")).toHaveCount(0)
        try await expect(page.locator(".commit-process")).toHaveAttribute("value", "bibliographic_translation")
        try await expect(page.locator(".commit-view input[name='scope']")).toHaveCount(0)
        // Page 1 on screen, its translation stale: its prompt, as ticking
        // it alone would send it.
        let task = page.locator("[data-process='Translation'] .prompt-preview-task .prompt-text-source").first
        try await expect(task, timeout: .seconds(20)).toContainText("Translate these pages from Italian into English: 1.")
        // Page 2's is fresh: nothing is sent for it.
        try await page.locator("#artifact-page-input").fill("2")
        try await page.locator("#artifact-page-input").press("Enter")
        try await expect(page.locator("#artifact-page-input")).toHaveValue("2")
        try await expect(page.locator("[data-process='Translation'] .prompt-preview-task-notice"), timeout: .seconds(20))
          .toContainText("This evidence item has already been translated")
        _ = try await page.evaluate("""
          window.__translationSubmit = null;
          window.addEventListener('submit', event => {
            if (event.target.id !== 'commit-form' || event.defaultPrevented) return;
            event.preventDefault();
            const data = new FormData(event.target);
            window.__translationSubmit = { process: data.get('process'), services: data.getAll('canvas[]') };
          });
          true;
          """, as: Bool.self)
        let commit = page.locator(".commit-trigger")
        let submitted = { () async throws -> String in
          try await page.evaluate("JSON.stringify(window.__translationSubmit)", as: String.self)
        }
        // Nothing ticked: refused under the roster, never sent.
        try await commit.click()
        try await expect(page.locator(".field-validation-message-view").first)
          .toContainText("Tick the evidence items this commit sends to translation.")
        #expect(try await submitted() == "null")
        // Page 2's translation is fresh: locked against a commit, its
        // checkbox gone (user, 2026-10-09); page 1's is stale, and ticks.
        // (The navbar clones the sidebar into its menu: the first roster.)
        let rows = page.locator("#epilogue-canvases").first.locator(".roster-row")
        try await expect(rows.nth(0)).toHaveAttribute("data-locked", "false")
        try await expect(rows.nth(1)).toHaveAttribute("data-locked", "true")
        try await expect(rows.nth(1).locator(".checkbox-icon-wrapper")).toBeHidden()
        _ = try await page.evaluate("""
          (() => { document.querySelectorAll(".mission-control-sidebar-view input[name='canvas[]']")[0].click(); return true })()
          """, as: Bool.self)
        try await commit.click()
        let payload = try await submitted()
        #expect(payload.contains("\"process\":\"bibliographic_translation\""))
        #expect(payload.contains("\"services\":[\"\(service)\"]"))
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
      #expect(try TestAdmin.query("SELECT processing_status FROM bibliographic_epilogues WHERE id = '\(epilogue)'") == "pending")
    } catch {
      // Release the account only after its scratch foreign-key dependants.
      _ = try? TestAdmin.query("DELETE FROM bibliographic_epilogues WHERE id = '\(epilogue)'; DELETE FROM bibliographic_serenades WHERE id = '\(serenade)';")
      reading.remove()
      try await admin.remove(after: error)
    }
    _ = try? TestAdmin.query("DELETE FROM bibliographic_epilogues WHERE id = '\(epilogue)'; DELETE FROM bibliographic_serenades WHERE id = '\(serenade)';")
    reading.remove()
    try await admin.remove()
  }
}
