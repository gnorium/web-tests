import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A call is submitted by a person, committed by an admin, and answered with
/// the ordinary Computorium session inside its locution. Recorded sessions
/// are seeded as in ToolCardFieldsTests; no provider request is made.
@Suite("Disputorium arbitration", .serialized)
struct ArbitrationTests {
  static let reply = "The selected evidence supports this reading."
  static let task = "Answer this query about the evidence item shown: Evidence fixture 2."
  static let toolDefinition =
    #"[{"type":"function","function":{"name":"read_record","description":"Read the exact human Revise fields and attached evidence.","parameters":{"type":"object","properties":{},"additionalProperties":false}}}]"#

  static func trace() throws -> String {
    let blocks: [[String: String]] = [
      ["type": "task_prompt_instance", "content": task],
      ["type": "tools", "content": toolDefinition],
      ["type": "thinking", "content": String(repeating: "Reading the selected evidence carefully.\n\n", count: 90)],
      ["type": "tool", "name": "read_record", "arguments": "{}", "status": "ok", "call_id": "arbitration_read",
       "result": #"{"nodes":[{"id":"work","label":"Work","number":"1","fields":[{"id":"title","label":"Title","value":"Web tests evidence"}]}],"evidence":{"id":"selected-evidence","kind":"canvas","label":"Title page","markup":"<p>Evidence fixture 2.</p>"}}"#],
      ["type": "tools", "content": toolDefinition],
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
        CROSS JOIN computorium_worker_controls c WHERE p.singleton = true AND c.kind = 'arbitration'
      """)
    guard stopped == "true" else {
      throw WebTestError("The arbitration browser fixture requires stopped dev workers so Commit cannot call a provider.")
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
        UPDATE locutions SET arbitration_run_id = NULL WHERE locutable_type = 'bibliographic_madrigal' AND locutable_id = '\(objectID)';
        DELETE FROM arbitration_stage_runs WHERE locutable_type = 'bibliographic_madrigal' AND locutable_id = '\(objectID)';
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
        try await expect(page.locator(".prompt-instances-slot"), timeout: .seconds(20))
          .toHaveAttribute("aria-busy", "false")
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
        try await expect(page.locator(".prompt-instances-slot"), timeout: .seconds(20))
          .toHaveAttribute("aria-busy", "false")
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
        try await expect(page.locator(".prompt-instances-slot"), timeout: .seconds(20))
          .toHaveAttribute("aria-busy", "false")
        // The admin's roster: the explicated page has no checkbox, the
        // blank ones do.
        let rows = page.locator("#madrigal-canvases .roster-row")
        try await expect(rows).toHaveCount(3)
        try await expect(rows.nth(0)).toHaveAttribute("data-locked", "true")
        try await expect(rows.nth(0).locator(".checkbox-icon-wrapper")).toBeHidden()
        try await expect(rows.nth(0).locator(".checkbox-input")).toBeDisabled()
        try await expect(rows.nth(1)).toHaveAttribute("data-locked", "false")
        try await expect(rows.nth(1).locator(".checkbox-icon-wrapper")).toBeVisible()
        // Its checkbox's column kept, the locked row's ordinal, mark and
        // label line up with an unlocked row's (user, 2026-10-10).
        #expect(try await page.evaluate("""
          (() => { const rows = document.querySelectorAll('#madrigal-canvases .roster-row')
            const x = (row, s) => row.querySelector(s).getBoundingClientRect().left
            return ['.roster-marker', '.roster-status', '.roster-label'].every(s => x(rows[0], s) === x(rows[1], s)) })()
          """, as: Bool.self), "Locked and unlocked rows align")
        let call = page.locator("#locution-\(callID.uppercased())")
        try await expect(call.locator(".locution-call-status")).toHaveText("Pending")
        // The evidence item it attached, linked to it in the reader (user,
        // 2026-10-10).
        try await expect(call.locator(".locution-call-evidence")).toHaveText("Canvas 1")
        try await expect(call.locator("a:has(.locution-call-evidence)")).toHaveAttribute("href", "/mission-control/madrigals/bibliographic/\(objectID.uppercased())?canvas=0")
        try await expect(call.locator(".locution-commit")).toHaveText("Commit")
        try await expect(call.locator(".locution-commit-form[action$='/locutions/\(callID.uppercased())/commit']")).toHaveCount(1)
        try await call.locator(".locution-commit").click()
        // Stopped admission completes without contacting a provider. Wait
        // for that task to finish before replacing its result with a trace.
        var runID = ""
        for _ in 0..<300 {
          runID = try TestAdmin.query("SELECT id FROM arbitration_stage_runs WHERE call_locution_id = '\(callID)' AND result = 'failed'")
          if !runID.isEmpty { break }
          try await Task.sleep(for: .milliseconds(100))
        }
        guard UUID(uuidString: runID) != nil else {
          throw WebTestError("Commit did not create and finish the stopped arbitration fixture.")
        }
        _ = try TestAdmin.query("""
          BEGIN;
          UPDATE arbitration_stage_runs SET result = 'passed', output = '\(try Self.trace())',
            provider = 'deepseek', model = 'deepseek-flash', duration_ms = 1200, error_message = NULL WHERE id = '\(runID)';
          UPDATE locutions SET call_status = 'done' WHERE id = '\(callID)';
          INSERT INTO locutions (id, locutable_type, locutable_id, author_id, parent_id, content, depth,
            kind, arbitration_run_id, evidence_id, evidence_kind, created_at)
            VALUES ('\(replyID)', 'bibliographic_madrigal', '\(objectID)',
              (SELECT id FROM users WHERE username = 'gnorium'), '\(callID)', '\(Self.reply)', 1,
              'reply', '\(runID)', '\(fixture.baseURL)/page-1', 'canvas', now());
          COMMIT;
          """)
        try await page.openHydrated(reading.path)
        let reply = page.locator("#locution-\(replyID.uppercased())")
        let session = reply.locator(".computorium-session-view")
        try await expect(session).toHaveCount(1)
        try await expect(session.locator(".computorium-session-prompt-fieldset")).toHaveCount(2)
        try await expect(session).toContainText(Self.task)
        try await expect(session.locator(".computorium-session-output-rendered")).toContainText(Self.reply)
        try await expect(reply).toContainText("By gnorium")
        // Committed, the call still names its item; its reply names it too.
        try await expect(call.locator(".locution-call-status")).toHaveText("Done")
        try await expect(call.locator(".locution-call-evidence")).toHaveText("Canvas 1")
        try await expect(reply.locator(".locution-call-evidence").first).toHaveText("Canvas 1")
        try await expect(reply.locator("a:has(.locution-call-evidence)").first).toHaveAttribute("href", "/mission-control/madrigals/bibliographic/\(objectID.uppercased())?canvas=0")
        try await expect(session.locator(".computorium-session-prompt-fieldset legend")).toHaveCount(2)
        try await expect(session.locator(".computorium-session-output-legend")).toHaveCount(1)
        // The tools offered, where the trace recorded them, before each
        // model call: the thinking's, and the reply's after the call
        // (user, 2026-10-10).
        let tools = session.locator(".computorium-session-tools")
        try await expect(tools).toHaveCount(2)
        try await tools.first.locator(".accordion-summary").first.click()
        try await expect(tools.first).toContainText("Read the exact human Revise fields and attached evidence.")
        let tool = session.locator("#computorium-session-tool-arbitration_read")
        try await tool.locator(".accordion-summary").first.click()
        try await expect(tool.locator(".computorium-session-tool-call-definition")).toHaveCount(0)
        try await expect(tool.locator(".datum-label").filter(hasText: "nodes[0]")).toHaveCount(1)
        #expect(try await reply.evaluate("""
          el => {
            const body = el.querySelector('.locution-body');
            const thinking = el.querySelector('.computorium-session-output-thinking-body');
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
        #expect(try TestAdmin.query("SELECT count(*) FROM arbitration_stage_runs WHERE locutable_id = '\(objectID)'") == "1")
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

  /// A madrigal of three explicated pages and one laid in blank.
  static func teiThreeRead(_ fixture: FixtureServer) -> String {
    let services = (1...4).map { "\(fixture.baseURL)/page-\($0)" }
    return """
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt><title>t</title></titleStmt></fileDesc></teiHeader><text><body>
      <pb n="1" facs="\(services[0])/full/1300,/0/default.jpg"/><p>Evidence fixture 1.</p>
      <pb n="2" facs="\(services[1])/full/1300,/0/default.jpg"/><p>Evidence fixture 2.</p>
      <pb n="3" facs="\(services[2])/full/1300,/0/default.jpg"/><p>Evidence fixture 3.</p>
      <pb n="4" facs="\(services[3])/full/1300,/0/default.jpg"/>
      </body></text></TEI>
      """
  }

  /// The Evidence roster's two modes (user, 2026-10-10). Commit: boxes on
  /// the pending items alone. Attach, while the locution box has focus or
  /// holds "@gnorium": boxes on the processed items alone, the page open
  /// in the reader ticked first, at most two, neighbors; a tick apart or
  /// a third is refused under the box. Submit attaches the ticked items in
  /// order, and the call names each, linked. The box left empty, the
  /// roster is back in commit mode.
  @Test(arguments: [BrowserEngine.chrome])
  func attachModeTicksTwoConsecutiveProcessedItems(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.threePageManifest()
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reading = try ScratchReading(owner: admin, tei: Self.teiThreeRead(fixture), sourceURL: fixture.baseURL + "/manifest.json")
    let objectID = reading.madrigalID
    func remove() {
      _ = try? TestAdmin.query("DELETE FROM locutions WHERE locutable_id = '\(objectID)'")
      reading.remove()
    }
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated(reading.path)
        try await expect(page.locator(".prompt-instances-slot"), timeout: .seconds(20))
          .toHaveAttribute("aria-busy", "false")
        let roster = page.locator("#madrigal-canvases")
        let rows = roster.locator(".roster-row")
        try await expect(rows).toHaveCount(4)
        // Commit mode: the three read pages locked, the blank one ticked for.
        try await expect(rows.nth(0).locator(".checkbox-icon-wrapper")).toBeHidden()
        try await expect(rows.nth(3).locator(".checkbox-icon-wrapper")).toBeVisible()
        let body = page.locator("#locution-thread-locution-body")
        try await body.focus()
        try await expect(roster).toHaveAttribute("data-mode", "attach")
        try await expect(rows.nth(0).locator(".checkbox-icon-wrapper")).toBeVisible()
        try await expect(rows.nth(0).locator(".checkbox-input")).toBeChecked()
        try await expect(rows.nth(0).locator(".checkbox-input")).toHaveAttribute("name", "evidence[]")
        try await expect(rows.nth(0).locator(".checkbox-input")).toHaveAttribute("form", "locution-thread-form")
        try await expect(rows.nth(1).locator(".checkbox-input")).toBeChecked(false)
        try await expect(rows.nth(3).locator(".checkbox-icon-wrapper")).toBeHidden()
        try await expect(rows.nth(3).locator(".checkbox-input")).toBeDisabled()
        // A tick apart from the first is refused; its neighbor is taken; a
        // third is refused.
        try await rows.nth(2).locator("input").click()
        try await expect(rows.nth(2).locator(".checkbox-input")).toBeChecked(false)
        try await expect(page.locator(".field-validation-message-view")).toContainText("consecutive")
        try await rows.nth(1).locator("input").click()
        try await expect(rows.nth(1).locator(".checkbox-input")).toBeChecked()
        try await rows.nth(2).locator("input").click()
        try await expect(rows.nth(2).locator(".checkbox-input")).toBeChecked(false)
        // Back to commit mode when the box is left empty; attach again on
        // "@gnorium" typed.
        try await page.locator(".locution-thread-title, h3").first.click()
        try await expect(roster).toHaveAttribute("data-mode", "commit")
        try await expect(rows.nth(0).locator(".checkbox-icon-wrapper")).toBeHidden()
        try await expect(rows.nth(0).locator(".checkbox-input")).toBeChecked(false)
        try await expect(rows.nth(0).locator(".checkbox-input")).toHaveAttribute("name", "canvas[]")
        try await expect(rows.nth(3).locator(".checkbox-icon-wrapper")).toBeVisible()
        try await body.fill("@gnorium Compare these two pages.")
        try await expect(roster).toHaveAttribute("data-mode", "attach")
        try await expect(rows.nth(0).locator(".checkbox-input")).toBeChecked()
        try await rows.nth(1).locator("input").click()
        try await page.locator(".locution-thread-submit").click()
        try await expect(page.locator(".locution-call-status"), timeout: .seconds(15)).toHaveText("Pending")
        let stored = try TestAdmin.query(
          "SELECT evidence_id || '|' || coalesce(evidence_ids, '') FROM locutions WHERE locutable_id = '\(objectID)' AND kind = 'call'")
        #expect(stored == "\(fixture.baseURL)/page-1|[\"\(fixture.baseURL)/page-1\",\"\(fixture.baseURL)/page-2\"]", Comment(rawValue: stored))
        let links = page.locator(".locution-call-evidence")
        try await expect(links).toHaveCount(2)
        try await expect(links.nth(0)).toHaveText("Canvas 1")
        try await expect(links.nth(1)).toHaveText("Canvas 2")
        try await page.expectNoErrors()
      }
    } catch {
      remove()
      try await admin.remove(after: error)
    }
    remove()
    try await admin.remove()
  }

  /// A crop box on an attached canvas (user, 2026-10-10): in attach mode
  /// the reader's image of a ticked item takes a dragged box; the call
  /// stores it in the 0–1000 space by the item's id, and its locution shows
  /// the numbers beside the item's link.
  @Test(arguments: [BrowserEngine.chrome])
  func aCropBoxDrawnOnAnAttachedCanvasRidesWithTheCall(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.threePageManifest()
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reading = try ScratchReading(owner: admin, tei: Self.teiThreeRead(fixture), sourceURL: fixture.baseURL + "/manifest.json")
    let objectID = reading.madrigalID
    func remove() {
      _ = try? TestAdmin.query("DELETE FROM locutions WHERE locutable_id = '\(objectID)'")
      reading.remove()
    }
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated(reading.path)
        let viewer = page.locator(".artifact-view").first
        try await expect(viewer).toHaveAttribute("data-artifact-hydrated", "true")
        let roster = page.locator("#madrigal-canvases")
        let body = page.locator("#locution-thread-locution-body")
        // Submit at the right, under the box's right edge (user, 2026-10-10).
        let field = try #require(try await body.boundingBox())
        let submit = try #require(try await page.locator(".locution-thread-submit").boundingBox())
        #expect(abs((submit.x + submit.width) - (field.x + field.width)) < 1, "Submit under the box's right edge")
        #expect(submit.x > field.x + 1, "Submit is not at the left")
        try await body.fill("@gnorium Read the line in the box.")
        try await expect(roster).toHaveAttribute("data-mode", "attach")
        try await expect(roster.locator(".roster-row").nth(0).locator(".checkbox-input")).toBeChecked()
        // The page images on; the ticked canvas takes a box.
        let toggle = viewer.locator(".artifact-canvas-toggle button")
        if try await toggle.getAttribute("aria-pressed") != "true" { try await toggle.click() }
        let canvas = viewer.locator(".canvas-view[data-active='true'] .canvas-viewport")
        try await expect(canvas).toHaveAttribute("data-cropping", "true")
        let box = try #require(try await canvas.boundingBox())
        let (x0, y0) = (box.x + box.width * 0.4, box.y + box.height * 0.4)
        let (x1, y1) = (box.x + box.width * 0.6, box.y + box.height * 0.55)
        try await page.mouse.move(x: x0, y: y0)
        try await page.mouse.down(x: x0, y: y0)
        for step in 1...5 {
          try await page.mouse.move(x: x0 + (x1 - x0) * Double(step) / 5, y: y0 + (y1 - y0) * Double(step) / 5)
        }
        try await page.mouse.up(x: x1, y: y1)
        try await expect(canvas.locator(".canvas-crop")).toBeVisible()
        try await expect(roster).toHaveAttribute("data-mode", "attach")
        try await page.locator(".locution-thread-submit").click()
        try await expect(page.locator(".locution-call-status"), timeout: .seconds(15)).toHaveText("Pending")
        let stored = try TestAdmin.query(
          "SELECT evidence_crops FROM locutions WHERE locutable_id = '\(objectID)' AND kind = 'call'")
        let service = "\(fixture.baseURL)/page-1"
        let crops = try JSONSerialization.jsonObject(with: Data(stored.utf8)) as? [String: [Int]]
        let crop = try #require(crops?[service], Comment(rawValue: stored))
        #expect(crop.count == 4 && crop[2] > 0 && crop[3] > 0 && crop[0] + crop[2] <= 1000 && crop[1] + crop[3] <= 1000)
        try await expect(page.locator(".locution-call-evidence-crop").first)
          .toHaveText(crop.map(String.init).joined(separator: " "))
        // The locution's action row: the reactions button first, the info
        // icon after it (user, 2026-10-10).
        let order = try await page.evaluate(
          """
          [...document.querySelector('.locution-view .reactions-controls').children]
            .map(e => e.classList.contains('reaction-picker-view') ? 'picker'
              : e.classList.contains('reactions-when') ? 'when' : 'other').slice(0, 2).join(' ')
          """, as: String.self)
        #expect(order == "picker when", Comment(rawValue: order))
        try await page.expectNoErrors()
      }
    } catch {
      remove()
      try await admin.remove(after: error)
    }
    remove()
    try await admin.remove()
  }

  @Test(arguments: [BrowserEngine.chrome])
  func arbitrationPromptsLeadBothProcessesAndAreRevisable(engine: BrowserEngine) async throws {
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
        INSERT INTO lexicographic_epilogues (id, lexico_record_id, lexico_record_version_id, sentiment_id, tei,
          target, status, submitted_by_user_id, summary, definition_translation_json)
          VALUES ('\(epilogue)', '\(word.recordID.lowercased())', '\(word.versionID.lowercased())', 's-1-1',
            '<sense><def>A leaf sense.</def></sense>', 'definition', 'proposed', '\(user)', 'Web tests arbitration prompts.',
            '{"languageCode":"fra","tei":"<def xml:lang=\\"fr\\">Un sens feuille.</def>","confidence":"clear","reason":"Web tests."}');
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        let cases = [
          (scratch.overturePath, "Explication", "bibliographic_arbitration"),
          ("/mission-control/epilogues/lexicographic/\(epilogue)?process=translation", "Translation", "lexicographic_arbitration"),
        ]
        for (path, process, slot) in cases {
          try await page.openHydrated(path)
          let sections = page.locator(".prompt-instances-process")
          try await expect(sections, timeout: .seconds(20)).toHaveCount(2)
          try await expect(sections.nth(0)).toHaveAttribute("data-process", "Arbitration")
          try await expect(sections.nth(1)).toHaveAttribute("data-process", process)
          for (index, name, id) in [(0, "Arbitration", "prompt-instance-process-arbitration"), (1, process, "prompt-instance-process")] {
            // One accordion a process, its three nested (user, 2026-10-10).
            try await expect(sections.nth(index).locator("#\(id) .accordion-title").first).toHaveText(name)
            try await expect(sections.nth(index).locator("#\(id)")).toHaveAttribute("data-expanded", "false")
            try await expect(sections.nth(index).getByText("System Prompt", exact: true)).toHaveCount(2)
            try await expect(sections.nth(index).getByText("Task Prompt Template", exact: true)).toHaveCount(2)
            try await expect(sections.nth(index).getByText("Autocompaction", exact: true)).toHaveCount(1)
          }
          try await page.openHydrated(path.split(separator: "?").first.map(String.init)! + "/revise")
          let arbitration = page.locator(".prompt-revision-fields-process[data-process='\(slot)']")
          try await expect(arbitration.locator("textarea[name='prompt-system-\(slot)']")).toHaveCount(1)
          try await expect(arbitration.locator("textarea[name='prompt-task-\(slot)']")).toHaveCount(1)
          try await expect(arbitration.locator(".accordion-details")).toHaveCount(6)
          try await expect(arbitration.locator(".accordion-details[data-expanded='false']")).toHaveCount(6)
          try await expect(arbitration.locator("#prompt-revision-process-\(slot) .accordion-title").first).toHaveText("Arbitration")
          let auto = arbitration.locator("#prompt-revision-autocompaction-\(slot)")
          try await expect(auto.getByText("Autocompaction", exact: true)).toHaveCount(1)
          try await expect(auto.locator("textarea[name='prompt-system-\(slot)_autocompaction']")).toHaveCount(1)
          try await expect(auto.locator("textarea[name='prompt-task-\(slot)_autocompaction']")).toHaveCount(1)
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
