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
    let postlude = UUID().uuidString.lowercased()
    defer {
      _ = try? TestAdmin.query("DELETE FROM bibliographic_epilogues WHERE id = '\(epilogue)'; DELETE FROM bibliographic_postludes WHERE id = '\(postlude)';")
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
        UPDATE bibliographic_notations SET metadata_json =
          (metadata_json::jsonb || '{"language":"ita","sourceUrl":"\(fixture.baseURL)/manifest.json"}'::jsonb)::text
          WHERE id = '\(reading.notationID)';
        INSERT INTO bibliographic_postludes (id, bibliographic_notation_id, target_language, semblance_service_ids_json, requested_by_user_id, processing_status)
          VALUES ('\(postlude)', '\(reading.notationID)', 'eng', '[]', '\(user)', 'submitted');
        INSERT INTO bibliographic_epilogues (id, thread_id, bibliographic_overture_id, bibliographic_postlude_id, proposed_content_json, metadata_json, translation_json, processing_status)
          SELECT '\(epilogue)', '\(epilogue)', '\(reading.work.overtureID.lowercased())', '\(postlude)', p.proposed_content_json, p.metadata_json, '\(layer)', 'pending'
          FROM bibliographic_notations p WHERE p.id = '\(reading.notationID)';
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/epilogues/bibliographic/\(epilogue)")
        try await expect(page.locator(".pipeline-selection-toggle[data-pipeline='translation']")).toHaveCount(1)
        try await page.locator(".pipeline-selection-toggle[data-pipeline='translation']").click()
        try await expect(page.locator(".prompt-instances-content")).toHaveAttribute("data-selected-pipeline", "translation")
        _ = try await page.evaluate("""
          window.__translationSubmit = null;
          HTMLFormElement.prototype.submit = function() {
            const data = new FormData(this);
            window.__translationSubmit = { pipeline: data.get('pipeline'), scope: data.get('scope'), services: data.getAll('semblance[]') };
          };
          const original = window.fetch;
          window.fetch = function(input, options) {
            const url = new URL(typeof input === 'string' ? input : input.url, location.href);
            if (url.searchParams.get('pipeline') === 'translation') {
              document.body.setAttribute('data-preview-scope', url.searchParams.get('scope'));
              document.body.setAttribute('data-preview-services', JSON.stringify(url.searchParams.getAll('service[]')));
            }
            return original(input, options);
          };
          document.querySelectorAll(".mission-control-sidebar-view input[name='semblance[]']")[1].checked = true;
          true;
          """, as: Bool.self)
        // Page 1 is stale; page 2 is fresh and ticked. Keeping page 2 visible
        // makes an ignored scope observable without relying on neighbor prose.
        try await page.locator("#artifact-page-input").fill("2")
        try await page.locator("#artifact-page-input").press("Enter")
        try await expect(page.locator("#artifact-page-input")).toHaveValue("2")
        for scope in ["stale", "all", "ticked"] {
          _ = try await page.evaluate("""
            (() => {
              const scope = document.querySelector('.commit-translation-scope');
              scope.value = '\(scope)';
              scope.dispatchEvent(new Event('change', { bubbles: true }));
              return true;
            })();
            """, as: Bool.self)
          try await expect(page.locator("body")).toHaveAttribute("data-preview-scope", scope)
          try await expect(page.locator(".prompt-instances-slot")).toHaveAttribute("aria-busy", "false")
          if scope == "stale" {
            try await expect(page.locator(".prompt-instance-body")).toHaveCount(0)
            try await expect(page.locator(".prompt-instances-notice")).toContainText("No concrete task is ready for the visible page")
          } else {
            try await expect(page.locator(".prompt-instance-body")).toHaveCount(1)
            let chunk = scope == "all" ? "Pages 1–2" : "Page 2"
            try await expect(page.locator(".prompt-instance-context")).toContainText("\(chunk), containing the selected semblance")
            // Runtime opens the text through open_page. Its concrete task
            // identifies the assigned chunk and each page's segment count.
            let task = try await page.locator(".prompt-instance-body .prompt-text-source").nth(1).textContent()
            #expect(task.contains("Translate these pages from Italian into English: \(chunk)."))
            let pageSummaries = task.components(separatedBy: "Pages:").last?
              .components(separatedBy: "The glossary so far:").first?
              .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            #expect(pageSummaries == (scope == "all" ? "- 1: 1 segment - 2: 1 segment" : "- 2: 1 segment"))
          }
          if scope == "ticked" {
            let selected = try await page.locator("body").getAttribute("data-preview-services")
            #expect(selected == "[\"\(fixture.baseURL)/page-2\"]")
          }
          try await page.locator(".commit-view-trigger").click()
          let dialog = page.locator(".commit-view-option[data-value='translation-\(scope)'] .commit-view-dialog")
          try await dialog.locator(".dialog-primary-button button").click()
          let payload = try await page.evaluate("JSON.stringify(window.__translationSubmit)", as: String.self)
          #expect(payload.contains("\"pipeline\":\"translation\""))
          #expect(payload.contains("\"scope\":\"\(scope)\""))
          #expect(payload.contains("\"services\":[\"\(fixture.baseURL)/page-2\"]"))
          try await dialog.locator(".dialog-default-button button").click()
        }
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
      #expect(try TestAdmin.query("SELECT processing_status FROM bibliographic_epilogues WHERE id = '\(epilogue)'") == "pending")
    } catch {
      // Release the account only after its scratch foreign-key dependants.
      _ = try? TestAdmin.query("DELETE FROM bibliographic_epilogues WHERE id = '\(epilogue)'; DELETE FROM bibliographic_postludes WHERE id = '\(postlude)';")
      reading.remove()
      try await admin.remove(after: error)
    }
    _ = try? TestAdmin.query("DELETE FROM bibliographic_epilogues WHERE id = '\(epilogue)'; DELETE FROM bibliographic_postludes WHERE id = '\(postlude)';")
    reading.remove()
    try await admin.remove()
  }
}
