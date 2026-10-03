import Foundation
import Testing
import WebTests
import WebTestsTesting

/// No paid commit: intercept form.submit after exercising the real dialog,
/// checkbox, cloned phone sidebar, and artifact navigation.
@Suite("Attribution evidence roster", .serialized)
struct AttributionEvidenceRosterTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func translationScopeMatchesSelectedPreview(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.attributionManifest()
    defer { fixture.stop() }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let service = fixture.baseURL + "/page-1"
    let tei = "<TEI><text><body><pb n=\"1\" facs=\"\(service)/full/max/0/default.jpg\"/><p>Regola del tre</p><pb n=\"2\" facs=\"\(fixture.baseURL)/page-2/full/max/0/default.jpg\"/><p>Somma</p></body></text></TEI>"
    let reading: ScratchReading
    do { reading = try ScratchReading(owner: admin, tei: tei) }
    catch { try await admin.remove(after: error) }
    let epilogue = UUID().uuidString.lowercased()
    let madrigal = UUID().uuidString.lowercased()
    defer {
      _ = try? TestAdmin.query("DELETE FROM bibliographic_epilogues WHERE id = '\(epilogue)'; DELETE FROM bibliographic_madrigals WHERE id = '\(madrigal)';")
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
        UPDATE bibliographic_evidences SET source_url = '\(fixture.baseURL)/manifest.json'
          WHERE id = (SELECT o.bibliographic_evidence_id FROM bibliographic_overtures o
            JOIN bibliographic_hallmarks h ON h.bibliographic_overture_id = o.id
            WHERE h.id = '\(reading.work.hallmarkID.lowercased())');
        UPDATE bibliographic_proposals SET metadata_json =
          (metadata_json::jsonb || '{"language":"ita","sourceUrl":"\(fixture.baseURL)/manifest.json"}'::jsonb)::text
          WHERE id = '\(reading.proposalID)';
        INSERT INTO bibliographic_madrigals (id, bibliographic_proposal_id, target_language, semblance_service_ids_json, requested_by_user_id, processing_status)
          VALUES ('\(madrigal)', '\(reading.proposalID)', 'eng', '[]', '\(user)', 'submitted');
        INSERT INTO bibliographic_epilogues (id, thread_id, bibliographic_overture_id, bibliographic_madrigal_id, proposed_content_json, metadata_json, translation_json, processing_status)
          SELECT '\(epilogue)', '\(epilogue)', h.bibliographic_overture_id, '\(madrigal)', p.proposed_content_json, p.metadata_json, '\(layer)', 'pending'
          FROM bibliographic_proposals p JOIN bibliographic_antiphons a ON a.id = p.bibliographic_antiphon_id
          JOIN bibliographic_hallmarks h ON h.id = a.bibliographic_hallmark_id WHERE p.id = '\(reading.proposalID)';
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
      _ = try? TestAdmin.query("DELETE FROM bibliographic_epilogues WHERE id = '\(epilogue)'; DELETE FROM bibliographic_madrigals WHERE id = '\(madrigal)';")
      reading.remove()
      try await admin.remove(after: error)
    }
    _ = try? TestAdmin.query("DELETE FROM bibliographic_epilogues WHERE id = '\(epilogue)'; DELETE FROM bibliographic_madrigals WHERE id = '\(madrigal)';")
    reading.remove()
    try await admin.remove()
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func scopeIsExplicitAndRecognitionIndependent(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.attributionManifest()
    defer { fixture.stop() }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch = try ScratchCommit(owner: admin, sourceURL: fixture.baseURL + "/manifest.json")
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        for path in [scratch.overturePath, scratch.hallmarkPath] {
          try await page.openHydrated(path)
          try await expect(page.locator("#artifact-page-total")).toHaveText("3")
          try await expect(page.locator(".prompt-instances-view")).toHaveCount(1)
          let sectionSpacing = try await page.evaluate("""
            (() => {
              const outer = document.querySelector('.disputorium-core-view');
              const content = document.querySelector('.disputorium-core-content');
              const work = document.querySelector('.disputorium-core-work');
              const record = document.querySelector('.record-view');
              const section = document.querySelector('.record-section');
              const tree = document.querySelector('.record-tree-section');
              return !!outer && !!content && !!work && !!record
                && getComputedStyle(outer).rowGap === '24px'
                && getComputedStyle(content).rowGap === '24px'
                && getComputedStyle(record).rowGap === '24px'
                && (!section || getComputedStyle(section).rowGap === '24px')
                && (!tree || getComputedStyle(tree).rowGap === '8px');
            })()
            """, as: Bool.self)
          #expect(sectionSpacing, "Record sections have 24px spacing; tree rows remain 8px apart")

          if path == scratch.hallmarkPath {
            let context = page.locator(".prompt-instance-body").nth(0).locator(".prompt-instance-context")
            try await expect(context).toContainText("Semblance 1:")
            let task = try await page.locator(".prompt-instance-body").nth(0).locator(".prompt-text-source").nth(1).textContent()
            #expect(task.contains("Title page"))
            #expect(!task.contains("{page}"), "Recognition shows concrete page input, not its template")

            // Warm the explicit recognition URL, then hold the other treatment's
            // response while returning to that cached preview. No job is sent.
            let attribution = page.locator(".pipeline-selection-toggle[data-pipeline='attribution']")
            let recognition = page.locator(".pipeline-selection-toggle[data-pipeline='recognition']")
            try await attribution.click()
            try await expect(page.locator(".prompt-instances-content")).toHaveAttribute("data-selected-pipeline", "attribution")
            try await attribution.press("ArrowRight")
            try await expect(page.locator(".prompt-instances-content")).toHaveAttribute("data-selected-pipeline", "recognition")
            try await expect(recognition).toBeFocused()
            _ = try await page.evaluate("""
              window.__originalPromptFetch = window.fetch;
              window.__releasePrompt = null;
              window.fetch = function(input, options) {
                const url = new URL(typeof input === 'string' ? input : input.url, location.href);
                if (url.searchParams.get('pipeline') === 'attribution') {
                  document.body.setAttribute('data-prompt-request-held', 'true');
                  return new Promise(resolve => {
                    window.__releasePrompt = () => resolve(window.__originalPromptFetch(input, options));
                  });
                }
                return window.__originalPromptFetch(input, options);
              };
              true;
              """, as: Bool.self)
            try await attribution.click()
            try await expect(page.locator("body")).toHaveAttribute("data-prompt-request-held", "true")
            try await expect(page.locator(".commit-view-trigger")).toBeDisabled()
            try await recognition.click()
            try await expect(page.locator(".commit-view-trigger")).not.toBeDisabled()
            try await expect(page.locator(".prompt-instances-slot")).toHaveAttribute("aria-busy", "false")
            try await expect(page.locator(".prompt-instances-content")).toHaveAttribute("data-selected-pipeline", "recognition")
            try await expect(recognition).toHaveAttribute("aria-checked", "true")
            _ = try await page.evaluate("""
              window.fetch = window.__originalPromptFetch;
              window.__releasePrompt();
              true;
              """, as: Bool.self)
            // The next treatment (Recognition) is first; Attribution is last.
            // Home/End keep focus when the fragment replaces the selector DOM.
            try await recognition.press("End")
            try await expect(page.locator(".prompt-instances-content")).toHaveAttribute("data-selected-pipeline", "attribution")
            try await expect(attribution).toBeFocused()
            try await attribution.press("Home")
            try await expect(page.locator(".prompt-instances-content")).toHaveAttribute("data-selected-pipeline", "recognition")
            try await expect(recognition).toBeFocused()
          }
          _ = try await page.evaluate("""
            window.__evidenceSubmit = null;
            HTMLFormElement.prototype.submit = function() {
              window.__evidenceSubmit = { pipeline: new FormData(this).get('pipeline'),
                canvases: new FormData(this).getAll('evidence_canvas[]') };
            };
            true;
            """, as: Bool.self)
          let rosterRoot: String
          if layout == .phone {
            try await page.locator(".sidebar-menu-btn").click()
            rosterRoot = "#navbar-slide-sidebar-slot .attribution-evidence-roster"
          } else {
            rosterRoot = ".mission-control-sidebar-view .attribution-evidence-roster"
          }
          // Scope remains empty at first; an identical printed title page can
          // still be selected by its own canonical ID.
          let roster = page.locator(rosterRoot).nth(0)
          try await expect(roster.locator("input[name='evidence_canvas[]']")).toHaveCount(3)
          try await roster.locator(".roster-row").nth(1).locator("label").click()
          let selected = try await page.evaluate("document.querySelectorAll(\"input[name='evidence_canvas[]']:checked\").length", as: Int.self)
          #expect(selected == 1)
          if layout == .phone { try await page.locator(".navbar-slide-close-btn").click() }
          try await expect(page.locator("#artifact-page-input")).toHaveValue("2")
          if path == scratch.hallmarkPath {
            try await expect(page.locator(".prompt-instance-body").nth(0).locator(".prompt-instance-context")).toContainText("Semblance 2:")
            try await page.locator(".pipeline-selection-toggle[data-pipeline='attribution']").click()
            try await expect(page.locator(".prompt-instances-content")).toHaveAttribute("data-selected-pipeline", "attribution")
            try await expect(page.locator(".prompt-instance-body").nth(0).locator(".prompt-instance-context")).toContainText("1 selected")
            let task = try await page.locator(".prompt-instance-body").nth(0).locator(".prompt-text-source").nth(1).textContent()
            let evidence = try await page.locator(".prompt-instance-body").nth(0)
              .locator(".prompt-instance-attachment[data-name='evidence_pages.json'] .prompt-instance-file-content").textContent()
            #expect(evidence.replacingOccurrences(of: "\\/", with: "/").contains(fixture.baseURL + "/canvas/2"))
            #expect(!task.contains("{manifest}"), "Selected canonical evidence is materialized without a paid request")
          }
          _ = try await page.evaluate("document.querySelectorAll(\"input[name='evidence_canvas[]']\").forEach(input => input.checked = false); true", as: Bool.self)
          try await page.locator(".commit-view-trigger").click()
          let dialog = page.locator(".commit-view-option[data-pipeline='attribution'] .commit-view-dialog")
          try await dialog.locator(".dialog-primary-button button").click()
          try await expect(dialog.locator(".commit-evidence-warning")).toHaveAttribute("data-visible", "true")
          let blocked = try await page.evaluate("window.__evidenceSubmit === null", as: Bool.self)
          #expect(blocked, "no paid job is created from an empty selection")
          _ = try await page.evaluate("""
            const input = document.querySelector(".mission-control-sidebar-view input[value='\(fixture.baseURL)/canvas/2']");
            input.checked = true;
            true;
            """, as: Bool.self)
          try await dialog.locator(".dialog-primary-button button").click()
          let payload = try await page.evaluate("JSON.stringify(window.__evidenceSubmit)", as: String.self)
          #expect(payload.contains(fixture.baseURL + "/canvas/2"))
          #expect(!payload.contains(fixture.baseURL + "/page-2"), "commit carries canonical canvas IDs, not image services")
          try await dialog.locator(".dialog-default-button button").click()
          try await page.expectNoHorizontalOverflow()
          try await page.expectNoErrors()
        }
      }
      // A second isolated browser context has no account cookie. Reading the
      // concrete inputs does not grant dispatch privileges.
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(scratch.hallmarkPath)
        try await expect(page.locator(".prompt-instances-view")).toHaveCount(1)
        try await expect(page.locator(".prompt-instance-body").nth(0).locator(".prompt-instance-context")).toContainText("Semblance 1:")
        try await expect(page.locator(".commit-view-trigger")).toHaveCount(0)
        try await expect(page.locator(".pipeline-selection-toggle")).toHaveCount(2)
        try await expect(page.locator(".pipeline-selection-toggle[data-pipeline='translation']")).toHaveCount(0)
        let oneRow = try await page.evaluate("""
          (() => {
            const group = document.querySelector('.pipeline-selection-group');
            const buttons = [...group.querySelectorAll('button')];
            return group.getAttribute('role') === 'radiogroup'
              && group.getAttribute('aria-label') === 'Treatment'
              && buttons.every(button => Math.abs(button.getBoundingClientRect().top - buttons[0].getBoundingClientRect().top) < 1);
          })()
          """, as: Bool.self)
        #expect(oneRow, "Public treatment choices remain one row and one exclusive group")
        try await page.locator(".pipeline-selection-toggle[data-pipeline='attribution']").click()
        try await expect(page.locator(".prompt-instances-content")).toHaveAttribute("data-selected-pipeline", "attribution")
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
        try await expect(page.locator("input[name='evidence_canvas[]']")).toHaveCount(0)
      }
      #expect(try scratch.stillPending())
    } catch {
      scratch.remove()
      try await admin.remove(after: error)
    }
    scratch.remove()
    try await admin.remove()
  }
}
