import Foundation
import Testing
import WebTests
import WebTestsTesting

/// No paid commit: intercept form.submit after exercising the real dialog,
/// checkbox, cloned phone sidebar, and artifact navigation.
@Suite("Translation scope", .serialized)
struct TranslationScopeTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func translationScopeMatchesSelectedPreview(engine: BrowserEngine, layout: Layout) async throws {
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
        // Two processes: the header's toggle chooses whose prompts show and
        // what Commit commits for.
        let toggle = page.locator(".mission-control-object-header-view .process-toggle-view")
        try await expect(page.locator(".prompt-instances-heading")).toHaveText("Prompts")
        try await expect(toggle.locator(".toggle-button-group-button").first).toHaveAttribute("data-value", "bibliographic_explication")
        try await toggle.locator(".toggle-button-group-button[data-value$='translation']").click()
        // The translation's prompts are asked for as it is pressed: their
        // answer waited for in full.
        try await expect(page.locator(".prompt-instances-slot"), timeout: .seconds(20))
          .toHaveAttribute("aria-busy", "false")
        try await expect(page.locator(".prompt-instances-content")).toHaveAttribute("data-selected-pipeline", "bibliographic_translation")
        _ = try await page.evaluate("""
          window.__translationSubmit = null;
          window.addEventListener('submit', event => {
            if (event.target.id !== 'commit-form') return;
            event.preventDefault();
            const data = new FormData(event.target);
            window.__translationSubmit = { pipeline: data.get('pipeline'), scope: data.get('scope'), services: data.getAll('canvas[]') };
          });
          true;
          """, as: Bool.self)
        // Page 2 on screen: the translation preview is the chunk holding it,
        // every page translated.
        try await page.locator("#artifact-page-input").fill("2")
        try await page.locator("#artifact-page-input").press("Enter")
        try await expect(page.locator("#artifact-page-input")).toHaveValue("2")
        try await expect(page.locator(".prompt-instances-slot")).toHaveAttribute("aria-busy", "false")
        try await expect(page.locator(".prompt-instance-task")).toHaveCount(1)
        let task = try await page.locator(".prompt-instance-task .prompt-text-source").first.textContent()
        #expect(task.contains("Translate these pages from Italian into English: 1–2."))
        // Commit translates the stale pages while none is ticked, and the
        // pages ticked once some are.
        let commit = page.locator(".commit-trigger")
        let submitted = { () async throws -> String in
          try await page.evaluate("JSON.stringify(window.__translationSubmit)", as: String.self)
        }
        try await commit.click()
        var payload = try await submitted()
        #expect(payload.contains("\"pipeline\":\"bibliographic_translation\""))
        #expect(payload.contains("\"scope\":\"stale\""))
        _ = try await page.evaluate("""
          document.querySelectorAll(".mission-control-sidebar-view input[name='canvas[]']")[1].checked = true; true
          """, as: Bool.self)
        try await commit.click()
        payload = try await submitted()
        #expect(payload.contains("\"scope\":\"ticked\""))
        #expect(payload.contains("\"services\":[\"\(fixture.baseURL)/page-2\"]"))
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
