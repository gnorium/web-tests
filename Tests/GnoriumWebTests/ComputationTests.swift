import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A call is submitted by a person, committed by an admin, and answered with
/// the ordinary Computorium session inside its locution. Recorded sessions
/// are seeded as in ToolCardFieldsTests; no provider request is made.
@Suite("Disputorium computation", .serialized)
struct ComputationTests {
  static let reply = "The selected evidence supports this reading."
  static let task = "Answer this query about the evidence item shown: Evidence fixture 2."
  static let toolDefinition =
    #"[{"type":"function","function":{"name":"read_record","description":"Read the exact human Revise fields and attached evidence.","parameters":{"type":"object","properties":{},"additionalProperties":false}}}]"#

  static func trace() throws -> String {
    let blocks: [[String: String]] = [
      ["type": "task_prompt_instance", "content": task],
      ["type": "tools", "content": toolDefinition],
      ["type": "thinking", "content": String(repeating: "Reading the selected evidence carefully.\n\n", count: 90)],
      ["type": "tool", "name": "read_record", "arguments": "{}", "status": "ok", "call_id": "computation_read",
       "result": #"{"nodes":[{"id":"work","label":"Work","number":"1","fields":[{"id":"title","label":"Title","value":"Web tests evidence"}]}],"evidence":{"id":"selected-evidence","kind":"canvas","label":"Title page","markup":"<p>Evidence fixture 2.</p>"}}"#],
      ["type": "text", "content": reply],
    ]
    return String(decoding: try JSONSerialization.data(withJSONObject: blocks), as: UTF8.self)
      .replacingOccurrences(of: "'", with: "''")
  }

  /// A madrigal of one explicated page (markup) and two laid in blank.
  static func tei(_ fixture: FixtureServer) -> String {
    let services = (1...3).map { "\(fixture.baseURL)/page-\($0)" }
    return """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt><title>t</title></titleStmt></fileDesc></teiHeader><text><body>
      <pb n="1" facs="\(services[0])/full/1300,/0/default.jpg"/><p>Evidence fixture 1.</p>
      <pb n="2" facs="\(services[1])/full/1300,/0/default.jpg"/>
      <pb n="3" facs="\(services[2])/full/1300,/0/default.jpg"/>
      </body></text></TEI>
      """
  }

  @Test(arguments: [BrowserEngine.chrome])
  func contributorSubmitsAdminCommitsAndTheReplyEmbedsASession(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    // This suite exercises the real Commit route, with the worker stopped,
    // then supplies the recorded result. It never enables a worker or model.
    let stopped = try TestAdmin.query("""
      SELECT (NOT p.enabled OR NOT c.enabled)::text FROM computorium_worker_pool p
        CROSS JOIN computorium_worker_controls c WHERE p.singleton = true AND c.kind = 'computation'
      """)
    guard stopped == "true" else {
      throw WebTestError("The computation browser fixture requires stopped dev workers so Commit cannot call a provider.")
    }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reading = try ScratchReading(owner: contributor, tei: Self.tei(fixture), sourceURL: fixture.baseURL + "/manifest.json")
    let objectID = reading.madrigalID
    let contributorID = try contributor.column("id")
    let adminID = try admin.column("id")
    let replyID = UUID().uuidString.lowercased()
    func remove() {
      // The Commit stamps the seed vignette with its first committing
      // object and admin (PromptCommits.apply): the throwaway admin's stamp
      // goes with the account, as the row stood before.
      _ = try? TestAdmin.query("""
        BEGIN;
        UPDATE prompt_vignettes SET committed_object_type = NULL, committed_object_id = NULL, committed_by_user_id = NULL,
          committed_at = NULL WHERE committed_by_user_id = '\(adminID)';
        DELETE FROM locutions WHERE locutable_type = 'bibliographic_madrigal' AND locutable_id = '\(objectID)' AND kind = 'reply';
        UPDATE locutions SET computation_run_id = NULL WHERE locutable_type = 'bibliographic_madrigal' AND locutable_id = '\(objectID)';
        DELETE FROM computation_stage_runs WHERE locutable_type = 'bibliographic_madrigal' AND locutable_id = '\(objectID)';
        DELETE FROM locutions WHERE locutable_type = 'bibliographic_madrigal' AND locutable_id = '\(objectID)';
        COMMIT;
        """)
      reading.remove()
    }
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        // Canvas 2 is laid in blank: pending explication, not queryable.
        // The box refuses the call under the field; nothing is posted.
        try await page.openHydrated(reading.path + "?canvas=1")
        try await expect(page.locator(".disputorium-core-work #artifact-page-total"), timeout: .seconds(20)).toHaveText("3")
        try await expect(page.locator("#locution-thread-locution-canvas")).toHaveValue("1")
        try await expect(page.locator("#locution-thread-process")).toHaveValue("explication")
        try await expect(page.locator(".locution-thread-form input[type='checkbox']")).toHaveCount(0)
        try await expect(page.locator(".locution-thread-submit")).toHaveText("Submit")
        try await page.locator("#locution-thread-locution-body").fill("@gnorium What does the selected evidence support?")
        try await page.locator(".locution-thread-submit").click()
        try await expect(page.locator(".field-validation-message-view")).toContainText("This evidence item has not been explicated yet.")
        try await expect(page.locator(".locution-call-status")).toHaveCount(0)
        #expect(try TestAdmin.query("SELECT count(*) FROM locutions WHERE locutable_id = '\(objectID)'") == "0")
        // Canvas 1 has markup: explicated, queryable—and locked against a
        // commit: its row keeps its mark and loses its checkbox.
        try await page.openHydrated(reading.path + "?canvas=0")
        try await expect(page.locator(".disputorium-core-work #artifact-page-total"), timeout: .seconds(20)).toHaveText("3")
        try await expect(page.locator("#locution-thread-locution-canvas")).toHaveValue("0")
        try await page.locator("#locution-thread-locution-body").fill("@gnorium What does the selected evidence support?")
        try await page.locator(".locution-thread-submit").click()
        try await expect(page.locator(".locution-call-status"), timeout: .seconds(15)).toHaveText("Pending")
        try await expect(page.locator(".locution-commit")).toHaveCount(0)
      }
      let callID = try TestAdmin.query("""
        SELECT id FROM locutions WHERE locutable_type = 'bibliographic_madrigal'
          AND locutable_id = '\(objectID)' AND author_id = '\(contributorID)' AND kind = 'call'
        """)
      #expect(UUID(uuidString: callID) != nil)
      let evidence = try TestAdmin.query("SELECT evidence_id || '|' || evidence_kind || '|' || call_process FROM locutions WHERE id = '\(callID)'")
      #expect(evidence == "\(fixture.baseURL)/page-1|canvas|explication")
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated(reading.path)
        // The admin's roster: the explicated page has no checkbox, the
        // blank ones do.
        let rows = page.locator("#madrigal-canvases .roster-row")
        try await expect(rows).toHaveCount(3)
        try await expect(rows.nth(0)).toHaveAttribute("data-locked", "true")
        try await expect(rows.nth(0).locator(".checkbox-icon-wrapper")).toBeHidden()
        try await expect(rows.nth(0).locator(".checkbox-input")).toBeDisabled()
        try await expect(rows.nth(1)).toHaveAttribute("data-locked", "false")
        try await expect(rows.nth(1).locator(".checkbox-icon-wrapper")).toBeVisible()
        let call = page.locator("#locution-\(callID.uppercased())")
        try await expect(call.locator(".locution-call-status")).toHaveText("Pending")
        try await expect(call.locator(".locution-commit")).toHaveText("Commit")
        try await expect(call.locator(".locution-commit-form[action$='/locutions/\(callID.uppercased())/commit']")).toHaveCount(1)
        try await call.locator(".locution-commit").click()
        // Stopped admission completes without contacting a provider. Wait
        // for that task to finish before replacing its result with a trace.
        var runID = ""
        for _ in 0..<300 {
          runID = try TestAdmin.query("SELECT id FROM computation_stage_runs WHERE call_locution_id = '\(callID)' AND result = 'failed'")
          if !runID.isEmpty { break }
          try await Task.sleep(for: .milliseconds(100))
        }
        guard UUID(uuidString: runID) != nil else {
          throw WebTestError("Commit did not create and finish the stopped computation fixture.")
        }
        _ = try TestAdmin.query("""
          BEGIN;
          UPDATE computation_stage_runs SET result = 'passed', output = '\(try Self.trace())',
            provider = 'deepseek', model = 'deepseek-flash', duration_ms = 1200, error_message = NULL WHERE id = '\(runID)';
          UPDATE locutions SET call_status = 'done' WHERE id = '\(callID)';
          INSERT INTO locutions (id, locutable_type, locutable_id, author_id, parent_id, content, depth,
            kind, computation_run_id, evidence_id, evidence_kind, created_at)
            VALUES ('\(replyID)', 'bibliographic_madrigal', '\(objectID)',
              (SELECT id FROM users WHERE username = 'gnorium'), '\(callID)', '\(Self.reply)', 1,
              'reply', '\(runID)', '\(fixture.baseURL)/page-1', 'canvas', now());
          COMMIT;
          """)
        try await page.openHydrated(reading.path)
        let reply = page.locator("#locution-\(replyID.uppercased())")
        let session = reply.locator(".session-view")
        try await expect(session).toHaveCount(1)
        try await expect(session.locator(".session-prompt-fieldset")).toHaveCount(2)
        try await expect(session).toContainText(Self.task)
        try await expect(session.locator(".session-output-rendered")).toContainText(Self.reply)
        try await expect(reply).toContainText("By gnorium")
        try await expect(session.locator(".session-prompt-fieldset legend")).toHaveCount(2)
        try await expect(session.locator(".session-output-legend")).toHaveCount(1)
        let tool = session.locator("#session-tool-computation_read")
        try await tool.locator(".accordion-summary").first.click()
        try await expect(tool.locator(".session-tool-call-definition > .datum-view")).toHaveCount(1)
        try await expect(tool).toContainText("Read the exact human Revise fields and attached evidence.")
        try await expect(tool.locator(".datum-label").filter(hasText: "nodes[0]")).toHaveCount(1)
        #expect(try await reply.evaluate("""
          el => {
            const body = el.querySelector('.locution-body');
            const thinking = el.querySelector('.session-output-thinking-body');
            return getComputedStyle(body).maxHeight === '512px' && getComputedStyle(body).overflowY === 'auto'
              && body.clientHeight <= 512 && body.scrollHeight > body.clientHeight
              && getComputedStyle(thinking).maxHeight === '256px' && getComputedStyle(thinking).overflowY === 'auto'
              && thinking.clientHeight <= 256 && thinking.scrollHeight > thinking.clientHeight;
          }
          """).bool == true, "The complete embedded session and its thinking keep their existing inner scroll limits")
        // An admin submits through exactly the same pending stage.
        try await page.locator("#locution-thread-locution-body").fill("@gnorium Read this evidence again.")
        try await page.locator(".locution-thread-submit").click()
        try await expect(page.locator(".locution-call-status").filter(hasText: "Pending"), timeout: .seconds(15)).toHaveCount(1)
        try await expect(page.locator(".locution-commit")).toHaveCount(1)
        #expect(try TestAdmin.query("SELECT count(*) FROM computation_stage_runs WHERE locutable_id = '\(objectID)'") == "1")
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      remove()
      try? await admin.remove()
      try await contributor.remove(after: error)
    }
    remove()
    try await admin.remove()
    try await contributor.remove()
  }

  @Test(arguments: [BrowserEngine.chrome])
  func computationPromptsLeadBothProcessesAndAreRevisable(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let scratch = try ScratchCommit(owner: contributor, sourceURL: fixture.baseURL + "/manifest.json")
    let word = try ScratchWord(owner: contributor, language: "fra")
    let epilogue = UUID().uuidString.lowercased()
    let user = try contributor.column("id")
    func remove() {
      _ = try? TestAdmin.query("DELETE FROM lexicographic_epilogues WHERE id = '\(epilogue)'")
      word.remove()
      scratch.remove()
    }
    do {
      _ = try TestAdmin.query("""
        INSERT INTO lexicographic_epilogues (id, lexico_record_id, lexico_record_version_id, sentiment_id, definition,
          target, status, submitted_by_user_id, summary, definition_translation_json)
          VALUES ('\(epilogue)', '\(word.recordID.lowercased())', '\(word.versionID.lowercased())', 's-1-1',
            'A leaf sense.', 'definition', 'proposed', '\(user)', 'Web tests computation prompts.',
            '{"language_code":"fra","definition":"Un sens feuille."}');
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        let cases = [
          (scratch.overturePath, "Explication", "bibliographic_computation"),
          ("/mission-control/epilogues/lexicographic/\(epilogue)?process=translation", "Translation", "lexicographic_computation"),
        ]
        for (path, process, slot) in cases {
          try await page.openHydrated(path)
          let sections = page.locator(".prompt-instances-process")
          try await expect(sections, timeout: .seconds(20)).toHaveCount(2)
          try await expect(sections.nth(0)).toHaveAttribute("data-process", "Computation")
          try await expect(sections.nth(1)).toHaveAttribute("data-process", process)
          for index in 0..<2 {
            try await expect(sections.nth(index).getByText("System Prompt", exact: true)).toHaveCount(1)
            try await expect(sections.nth(index).getByText("Task Prompt Template", exact: true)).toHaveCount(1)
          }
          try await page.openHydrated(path.split(separator: "?").first.map(String.init)! + "/revise")
          let computation = page.locator(".prompt-revision-fields-process[data-process='\(slot)']")
          try await expect(computation.locator("textarea[name='prompt-system-\(slot)']")).toHaveCount(1)
          try await expect(computation.locator("textarea[name='prompt-task-\(slot)']")).toHaveCount(1)
          try await expect(computation.locator(".accordion-details")).toHaveCount(2)
          try await expect(computation.locator(".accordion-details[data-expanded='false']")).toHaveCount(2)
          try await page.expectNoHorizontalOverflow()
        }
      }
    } catch {
      remove()
      try await contributor.remove(after: error)
    }
    remove()
    try await contributor.remove()
  }
}
