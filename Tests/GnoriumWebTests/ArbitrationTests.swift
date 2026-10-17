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
  /// The image the fixture session records as sent: gone at its source,
  /// with no archived copy, so its chip shows an empty frame.
  static let sentImage = "http://127.0.0.1:9/sent-page-1.jpg"
  static let toolDefinition =
    #"[{"type":"function","function":{"name":"read_record","description":"Read the exact human Revise fields and attached evidence.","parameters":{"type":"object","properties":{},"additionalProperties":false}}}]"#

  /// The sessions' table, which owns their traces (`SessionTrace`).
  static let sessions = "bibliographic_arbitration_sessions"

  /// The session's trace, its blocks as received: the first four while it
  /// runs, the rest appended as it goes on.
  static let trace: [[String: String]] = [
    ["type": "task_prompt_instance", "content": task],
    ["type": "image_sent", "url": sentImage, "source_sha256": "abc", "sha256": "def", "caption": ""],
    ["type": "tools", "content": toolDefinition],
    ["type": "thinking", "content": String(repeating: "Reading the selected evidence carefully.\n\n", count: 90)],
    ["type": "tool", "name": "read_record", "arguments": "{}", "status": "ok", "call_id": "arbitration_read",
     "result": #"{"nodes":[{"id":"work","label":"Work","number":"1","fields":[{"id":"title","label":"Title","value":"Web tests evidence"}]}],"evidence":{"id":"selected-evidence","kind":"canvas","label":"Title page","markup":"<p>Evidence fixture 2.</p>"}}"#],
    ["type": "tools", "content": toolDefinition],
    ["type": "text", "content": reply],
  ]

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
    func remove() {
      // The Commit stamps the seed vignette with its first committing
      // object and admin (PromptCommits.apply): the throwaway admin's stamp
      // goes with the account, as the row stood before.
      _ = try? TestAdmin.query("""
        BEGIN;
        UPDATE prompt_vignettes SET committed_object_type = NULL, committed_object_id = NULL, committed_by_user_id = NULL,
          committed_at = NULL WHERE committed_by_user_id = '\(adminID)';
        DELETE FROM locutions WHERE locutable_type = 'bibliographic_madrigal' AND locutable_id = '\(objectID)' AND kind = 'reply';
        UPDATE locutions SET arbitration_session_id = NULL WHERE locutable_type = 'bibliographic_madrigal' AND locutable_id = '\(objectID)';
        \(SessionTrace.delete(table: Self.sessions, where: "locutable_type = 'bibliographic_madrigal' AND locutable_id = '\(objectID)'"))
        DELETE FROM bibliographic_arbitration_sessions WHERE locutable_type = 'bibliographic_madrigal' AND locutable_id = '\(objectID)';
        DELETE FROM locutions WHERE locutable_type = 'bibliographic_madrigal' AND locutable_id = '\(objectID)';
        COMMIT;
        """)
      reading.remove()
    }
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        // Resemblance 2 is laid in blank: pending explication, it has no box
        // to tick, and the page on screen is never read unticked (user,
        // 2026-10-15). The box refuses the call under the field; nothing is
        // posted.
        try await page.openHydrated(reading.path + "?resemblance=1")
        try await expect(page.locator(".prompt-previews-slot"), timeout: .seconds(20))
          .toHaveAttribute("aria-busy", "false")
        try await expect(page.locator(".disputorium-core-work #artifact-page-total"), timeout: .seconds(20)).toHaveText("3")
        try await expect(page.locator("#locution-thread-locution-resemblance")).toHaveValue("1")
        try await expect(page.locator("#locution-thread-process")).toHaveValue("explication")
        try await expect(page.locator(".locution-thread-form input[type='checkbox']")).toHaveCount(0)
        try await expect(page.locator(".locution-thread-submit")).toHaveText("Submit")
        try await page.locator("#locution-thread-locution-body").fill("@gnorium What does the selected evidence support?")
        try await page.locator(".locution-thread-submit").click()
        try await expect(page.locator("#madrigal-resemblances .roster-row").nth(1).locator(".checkbox-input")).toBeDisabled()
        try await expect(page.locator(".field-validation-message-view"))
          .toContainText("Tick evidence, metadata, a prompt or a locution for this call.")
        try await expect(page.locator(".locution-call-page")).toHaveCount(0)
        #expect(try TestAdmin.query("SELECT count(*) FROM locutions WHERE locutable_id = '\(objectID)'") == "0")
        // Resemblance 1 has markup: explicated, queryable—and locked against a
        // commit: its row keeps its mark and loses its checkbox. Ticked
        // from page 3, the page on screen (user, 2026-10-17).
        try await page.openHydrated(reading.path + "?resemblance=2")
        try await expect(page.locator(".prompt-previews-slot"), timeout: .seconds(20))
          .toHaveAttribute("aria-busy", "false")
        try await expect(page.locator(".disputorium-core-work #artifact-page-total"), timeout: .seconds(20)).toHaveText("3")
        try await expect(page.locator("#locution-thread-locution-resemblance")).toHaveValue("2")
        try await page.locator("#locution-thread-locution-body").fill("@gnorium What does the selected evidence support?")
        try await page.locator("#madrigal-resemblances .roster-row").nth(0).locator("input").click()
        try await page.locator(".locution-thread-submit").click()
        // Posted pending: no status chip on a call (user, 2026-10-11), and
        // no Commit for a contributor.
        try await expect(page.locator(".locution-call-page"), timeout: .seconds(15)).toHaveCount(1)
        try await expect(page.locator(".locution-call-status")).toHaveCount(0)
        try await expect(page.locator(".locution-commit")).toHaveCount(0)
      }
      let callID = try TestAdmin.query("""
        SELECT id FROM locutions WHERE locutable_type = 'bibliographic_madrigal'
          AND locutable_id = '\(objectID)' AND author_id = '\(contributorID)' AND kind = 'call'
        """)
      #expect(UUID(uuidString: callID) != nil)
      let evidence = try TestAdmin.query("SELECT evidence_id || '|' || evidence_kind || '|' || call_process FROM locutions WHERE id = '\(callID)'")
      #expect(evidence == "\(fixture.baseURL)/page-1|image|explication")
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated(reading.path)
        try await expect(page.locator(".prompt-previews-slot"), timeout: .seconds(20))
          .toHaveAttribute("aria-busy", "false")
        // The admin's roster: the explicated page has no checkbox, the
        // blank ones do.
        let rows = page.locator("#madrigal-resemblances .roster-row")
        try await expect(rows).toHaveCount(3)
        try await expect(rows.nth(0)).toHaveAttribute("data-locked", "true")
        try await expect(rows.nth(0).locator(".checkbox-icon-wrapper")).toBeHidden()
        try await expect(rows.nth(0).locator(".checkbox-input")).toBeDisabled()
        try await expect(rows.nth(1)).toHaveAttribute("data-locked", "false")
        try await expect(rows.nth(1).locator(".checkbox-icon-wrapper")).toBeVisible()
        // Its checkbox's column kept, the locked row's ordinal, mark and
        // label line up with an unlocked row's (user, 2026-10-10).
        #expect(try await page.evaluate("""
          (() => { const rows = document.querySelectorAll('#madrigal-resemblances .roster-row')
            const x = (row, s) => row.querySelector(s).getBoundingClientRect().left
            return ['.roster-marker', '.roster-status', '.roster-label'].every(s => x(rows[0], s) === x(rows[1], s)) })()
          """, as: Bool.self), "Locked and unlocked rows align")
        let call = page.locator("#locution-\(callID.uppercased())")
        // No status chip; its Commit under its words, above its reactions,
        // where an act's verdicts stand (user, 2026-10-11).
        try await expect(call.locator(".locution-call-status")).toHaveCount(0)
        try await expect(call.locator(".locution-header .locution-commit")).toHaveCount(0)
        #expect(try await call.evaluate("""
          el => {
            const commit = el.querySelector('.locution-call-actions'), said = el.querySelector('.locution-said'),
              reactions = el.querySelector('.reactions-view');
            return !!commit && said.getBoundingClientRect().bottom <= commit.getBoundingClientRect().top
              && commit.getBoundingClientRect().bottom <= reactions.getBoundingClientRect().top;
          }
          """).bool == true, "Commit sits between the call's words and its reactions")
        // Its byline names the page its writer was on, and nothing else,
        // linked to the page turned to it (user, 2026-10-17): "… submitted
        // locution ‹id› on Resemblance 3", not the page it ticked.
        try await expect(call.locator(".locution-header")).toContainText("submitted locution \(callID.uppercased()) on Resemblance 3")
        try await expect(call.locator("a:has(.locution-call-page)")).toHaveAttribute("href", "/mission-control/madrigals/bibliographic/\(objectID.uppercased())?resemblance=2")
        // Its body stays as typed; what it ticked is one sentence in a box
        // after it, as a revision's Changed line is: "Attached Resemblance
        // 1.", the page's image a line-high chip opening the lightbox (user,
        // 2026-10-17). No picture above the words; nothing full size, which
        // only a session transcript shows.
        try await expect(call.locator(".locution-anchor")).toHaveCount(0)
        try await expect(call.locator(".locution-body-rendered")).toHaveText("@gnorium What does the selected evidence support?")
        let attachments = call.locator(".list-sentence-view.locution-attachments")
        try await expect(attachments).toHaveCount(1)
        let words = try await attachments.evaluate(
          "e => [...e.childNodes].filter(n => n.nodeType === 3).map(n => n.textContent).join('|') + '|' + e.querySelector('.locution-attachments-item a').textContent").string
        #expect(words == "Attached |.|Resemblance 1", Comment(rawValue: words ?? "—"))
        try await expect(attachments).toHaveCSS("border-top-style", "solid")
        let attached = attachments.locator(".locution-attachment")
        try await expect(attached).toHaveCount(1)
        try await expect(attached).toHaveAttribute("data-presentation", "line")
        try await expect(attached.locator(".expandable-attachment-trigger")).toHaveCount(1)
        try await expect(call.locator(
          ".expandable-attachment-view[data-presentation='received'], .expandable-attachment-view[data-presentation='inline']"))
          .toHaveCount(0)
        try await expect(call.locator(".locution-commit")).toHaveText("Commit")
        try await expect(call.locator(".locution-commit-form[action$='/locutions/\(callID.uppercased())/commit']")).toHaveCount(1)
        try await call.locator(".locution-commit").click()
        // The workers are stopped: the session waits, queued, contacting no
        // provider. The test plays its states from here, held so the
        // resumer leaves it be.
        var sessionID = ""
        for _ in 0..<300 {
          sessionID = try TestAdmin.query("SELECT id FROM bibliographic_arbitration_sessions WHERE call_locution_id = '\(callID)' AND result = 'queued'")
          if !sessionID.isEmpty { break }
          try await Task.sleep(for: .milliseconds(100))
        }
        guard UUID(uuidString: sessionID) != nil else {
          throw WebTestError("Commit did not create the waiting arbitration fixture.")
        }
        // gnorium's reply, submitted with the Commit (user, 2026-10-15).
        let replyID = try TestAdmin.query(
          "SELECT id FROM locutions WHERE arbitration_session_id = '\(sessionID)' AND kind = 'reply'")
        guard UUID(uuidString: replyID) != nil else { throw WebTestError("The Commit submitted no reply.") }
        // Running (its trace's rows stand in for the live buffer here): its
        // first four blocks, received 100ms apart—the rest follow on that
        // pace, however long the test takes to append them, so a replay
        // plays the whole trace in under a second.
        let began = Date()
        _ = try TestAdmin.query("""
          BEGIN;
          UPDATE bibliographic_arbitration_sessions SET result = 'running',
            error_message = NULL, held_by = 'web_tests', held_until = NOW() + interval '1 hour' WHERE id = '\(sessionID)';
          \(try SessionTrace.append(Array(Self.trace.prefix(4)), table: Self.sessions, id: sessionID, start: began, stepMs: 100))
          UPDATE locutions SET call_status = 'running' WHERE id = '\(callID)';
          COMMIT;
          """)
        // Mission Control counts the running session as claimed work, its
        // count opening the running calls (user, 2026-10-15); the panel is
        // brought up to date in place, so its spinner is never re-created and
        // its turn never restarts.
        try await page.openHydrated("/mission-control/bibliographic")
        let worker = page.locator("#live-region-live-telemetry .mission-control-dashboard-live-telemetry-worker")
        try await expect(worker).toContainText("claimed")
        try await expect(worker.locator("a").first).toHaveAttribute("href", "/mission-control/locutions/bibliographic?status=running")
        try await expect(worker.locator(".rotating-sector-view")).toHaveCount(1)
        let inPlace = try await page.evaluate("""
          (async () => {
            const region = document.querySelector('#live-region-live-telemetry')
            const spinner = () => region.querySelector('.mission-control-dashboard-live-telemetry-worker .rotating-sector-view')
            const first = spinner(), shape = () => first.querySelector('*') || first
            const time = () => (shape().getAnimations({ subtree: true })[0] || first.getAnimations({ subtree: true })[0])?.currentTime ?? null
            const text = region.textContent, before = time()
            // Until the stream has pushed the panel again (its elapsed time moves).
            for (let i = 0; i < 60 && region.textContent === text; i++) await new Promise(r => setTimeout(r, 250))
            return [region.textContent !== text, spinner() === first, before === null || time() > before].join(' ')
          })()
          """, as: String.self)
        #expect(inPlace == "true true true", "The panel updates in place (pushed, same spinner, its turn running on): \(inPlace)")
        // Each figure the machines and arbitration both have is split
        // (user, 2026-10-16): the machines' part opens the Nocturnes list,
        // which holds no arbitration; arbitration's opens the Locutions list,
        // gnorium's replies of the hour, this session's among them.
        let figures = page.locator("#live-region-live-telemetry .mission-control-dashboard-live-telemetry-figures")
        let hour = "/mission-control/locutions/bibliographic?createdBy=gnorium&createdOn=-1h.."
        for label in ["Calls / min", "Tokens / min"] {
          let links = figures.locator(".datum-view").filter(hasText: label).locator("a")
          try await expect(links).toHaveCount(2)
          let machines = try #require(try await links.nth(0).getAttribute("href"))
          #expect(machines.hasPrefix("/mission-control/nocturnes/") && !machines.contains("arbitration"),
            "\(label)'s machines open the nocturnes: \(machines)")
          try await expect(links.nth(1)).toHaveAttribute("href", hour)
          try await expect(links.nth(1)).toContainText("arbitration")
        }
        try await page.openHydrated(hour)
        // Its row by its id: its trace holds no text block yet and its words
        // are filled as it ends, so its Locution reads "—", unlinked
        // (LocutionsView, MissionControlController.locutions).
        let listed = page.locator("tr[data-row-id='\(replyID.uppercased())']")
        try await expect(listed).toHaveCount(1)
        try await expect(listed).toContainText("gnorium")

        // A watch stream that runs out of time ("renew") ends nothing (user,
        // 2026-10-17): the reply's watch attaches again at once, the chip
        // stays "Arbitrating" with no guess, and follows the session's own
        // status as the new stream brings it. The page served with the
        // test's EventSource, whose frames the test sends.
        try await expectRenewKeepsArbitrating(page, path: reading.path, replyID: replyID)

        // The thread: the call (its words and own actions), the Commit, then
        // gnorium's reply, submitted with the Commit under its own id, its
        // session streaming in it (user, 2026-10-15).
        try await page.openHydrated(reading.path)
        let slot = page.locator("#locution-\(replyID.uppercased())")
        try await expect(slot).toHaveCount(1)
        try await expect(call.locator(".computorium-session-view")).toHaveCount(0)
        try await expect(slot.locator(".locution-header")).toContainText(
          "gnorium submitted locution \(replyID.uppercased()) replying to locution \(callID.uppercased())")
        #expect(try await page.evaluate("""
          (() => { const top = s => document.querySelector(s).getBoundingClientRect().top
            return top('#locution-\(callID.uppercased())') < top('#commit-\(callID.uppercased())')
              && top('#commit-\(callID.uppercased())') < top('#locution-\(replyID.uppercased())') })()
          """, as: Bool.self), "Call, its commit, then gnorium's reply")
        let live = slot.locator(".computorium-session-view")
        try await expect(live, timeout: .seconds(15)).toContainText("Reading the selected evidence carefully.")
        // While the session runs, the page's status chip says so (user,
        // 2026-10-17): "Arbitrating", with arbitration's own mark, the
        // turning ring sector—never explication's turning disc sector; its
        // Thinking card's running mark the same.
        let chip = page.locator(".disputorium-core-header-status-chip")
        try await expect(chip.locator(".info-chip-text")).toHaveText("Arbitrating")
        try await expect(chip.locator(".rotating-ring-sector-view")).toHaveCount(1)
        try await expect(chip.locator(".rotating-sector-view")).toHaveCount(0)
        try await ComputoriumMarks.checkThinking(page, process: "arbitration", scope: "#locution-\(replyID.uppercased())")
        try await expect(live).not.toContainText(Self.reply)
        // The rest of its trace, appended as its next batch: a trace only grows.
        _ = try TestAdmin.query(try SessionTrace.append(
          Array(Self.trace.dropFirst(4)), table: Self.sessions, id: sessionID, start: began.addingTimeInterval(0.4), stepMs: 100))
        try await expect(live, timeout: .seconds(15)).toContainText(Self.reply)
        // A worker's Stop pauses it: the reply says why, in an info alert
        // under its transcript, and no mark turns any more; started again,
        // it streams on in the same reply (user, 2026-10-15).
        _ = try TestAdmin.query("""
          UPDATE bibliographic_arbitration_sessions SET result = 'queued',
            error_message = 'The arbitration worker was stopped.' WHERE id = '\(sessionID)'
          """)
        let paused = slot.locator(".computorium-session-paused-notice")
        try await expect(paused, timeout: .seconds(15)).toHaveText("The arbitration worker was stopped.")
        try await expect(paused).toHaveAttribute("data-color", "blue")
        // Paused, the chip says the madrigal's own status again; running
        // again, "Arbitrating".
        try await expect(chip.locator(".info-chip-text")).toHaveText("Pending")
        try await expect(chip.locator(".ring-icon-view")).toHaveCount(1)
        try await expect(chip.locator(".rotating-ring-sector-view")).toHaveCount(0)
        try await expect(slot.locator(".computorium-session-output-thinking-running")).toHaveCount(0)
        try await expect(slot).not.toContainText("failed without a recorded reason")
        _ = try TestAdmin.query("UPDATE bibliographic_arbitration_sessions SET result = 'running', error_message = NULL WHERE id = '\(sessionID)'")
        try await expect(paused, timeout: .seconds(15)).toHaveCount(0)
        try await expect(chip.locator(".info-chip-text")).toHaveText("Arbitrating")
        // The session ends and fills its reply: the same element, no second
        // reply drawn.
        _ = try await slot.evaluate("el => { window.__slot = el; return true }")
        _ = try TestAdmin.query("""
          BEGIN;
          UPDATE bibliographic_arbitration_sessions SET result = 'passed',
            provider = 'deepseek', model = 'deepseek-flash', duration_ms = 1200, error_message = NULL,
            finished_at = NOW() WHERE id = '\(sessionID)';
          UPDATE locutions SET call_status = 'done' WHERE id = '\(callID)';
          UPDATE locutions SET content = '\(Self.reply)' WHERE id = '\(replyID)';
          COMMIT;
          """)
        try await expect(slot.locator(".computorium-session-view"), timeout: .seconds(15))
          .toHaveAttribute("data-computorium-session-status", "succeeded")
        #expect(try await slot.evaluate("el => el === window.__slot").bool == true, "The same element")
        // Done, the chip says the madrigal's status again.
        try await expect(chip.locator(".info-chip-text")).toHaveText("Pending")
        try await expect(chip.locator(".rotating-ring-sector-view")).toHaveCount(0)
        try await expect(page.locator(".locution-view .computorium-session-view")).toHaveCount(1)

        try await page.openHydrated(reading.path)
        let reply = page.locator("#locution-\(replyID.uppercased())")
        let session = reply.locator(".computorium-session-view")
        try await expect(session).toHaveCount(1)
        // Its received boxes as sent: our system prompt and the task, one
        // box each (the template's own boxes stand around them, unlegended).
        try await expect(session.locator(".computorium-session-system-fieldset")).toHaveCount(1)
        try await expect(session.locator(".computorium-session-task-fieldset")).toHaveCount(1)
        try await expect(session).toContainText(Self.task)
        try await expect(session.locator(".computorium-session-output-rendered")).toContainText(Self.reply)
        try await expect(reply).toContainText("gnorium submitted locution")
        // Answered, the session stands in the reply alone; the admin's
        // Commit is an act of the thread between the call and the reply.
        let commit = page.locator("#commit-\(callID.uppercased())")
        try await expect(commit).toContainText("committed locution \(callID.uppercased())")
        #expect(try await page.evaluate("""
          (() => { const top = s => document.querySelector(s).getBoundingClientRect().top
            return top('#locution-\(callID.uppercased())') < top('#commit-\(callID.uppercased())')
              && top('#commit-\(callID.uppercased())') < top('#locution-\(replyID.uppercased())') })()
          """, as: Bool.self), "The commit stands between the call and its reply")
        // Committed, the call still names its page; its reply names the
        // call it answers instead.
        try await expect(call.locator(".locution-call-status")).toHaveCount(0)
        try await expect(call.locator(".locution-commit")).toHaveCount(0)
        try await expect(call.locator(".locution-call-page")).toHaveText("Resemblance 3")
        try await expect(reply.locator(".locution-call-page")).toHaveCount(0)
        try await expect(reply.locator(".locution-header")).toContainText("gnorium submitted locution \(replyID.uppercased()) replying to locution \(callID.uppercased())")
        try await expect(reply.locator(".locution-header a[href='#locution-\(callID.uppercased())']")).toHaveCount(1)
        // Our two boxes legended, by name: the system prompt's, the task's.
        try await expect(session.locator(".computorium-session-prompt-fieldset legend")).toHaveCount(2)
        try await expect(session.locator(".computorium-session-system-fieldset .computorium-session-prompt-legend-title"))
          .toHaveText("System prompt")
        try await expect(session.locator(".computorium-session-task-fieldset .computorium-session-prompt-legend-title"))
          .toHaveText("Task prompt")
        // Embedded in the reply, the session reads as everywhere else (user,
        // 2026-10-17): one stream, no box or legend around the model's
        // output; embedded alone and read-only, no pager, no re-run and no
        // header, and no row of controls of its own. The reply's controls
        // are one row, as a person's locution's (user, 2026-10-17): the
        // reaction picker, its session's Raw, Replay, then one ⓘ with the
        // model and when; no Raw of the locution's own. The page image in
        // the task prompt as the model received it.
        try await expect(session.locator(".computorium-session-output")).toHaveCount(1)
        try await expect(session.locator(".computorium-session-output-fieldset, .computorium-session-output-legend"))
          .toHaveCount(0)
        try await expect(session.locator(".computorium-session-controls, .computorium-session-byline")).toHaveCount(0)
        try await expect(session.locator(".computorium-session-page-nav, .computorium-session-rerun, .computorium-session-header"))
          .toHaveCount(0)
        try await expect(reply.locator(".reactions-when")).toHaveCount(1)
        try await expect(reply.locator(".reactions-when")).toHaveAttribute("data-local-time-prefix", "By deepseek-flash on ")
        try await expect(reply.locator(".locution-markdown-toggle")).toHaveCount(0)
        try await expect(reply.locator(".reactions-raw-info > .replay-btn")).toHaveText("Replay")
        let row = try await reply.evaluate("""
          el => { const row = el.querySelector('.reactions-row')
            const parts = [row.querySelector('.reaction-picker-view'),
              ...row.querySelector('.reactions-raw-info').children]
            const kinds = parts.map(e => e.classList.contains('reaction-picker-view') ? 'picker'
              : e.classList.contains('computorium-session-markdown-toggle') ? 'raw'
              : e.classList.contains('replay-btn') ? 'replay'
              : e.classList.contains('reactions-when') ? 'info' : 'other').join(' ')
            // One flex row: every control's middle on one line.
            // The picker draws as its contents (display: contents): its button's box.
            const box = e => getComputedStyle(e).display === 'contents' ? e.querySelector('button') : e
            const middles = parts.map(e => { const r = box(e).getBoundingClientRect(); return r.top + r.height / 2 })
            const oneLine = middles.every(m => Math.abs(m - middles[0]) <= 1)
            return kinds + (getComputedStyle(row).display === 'flex' && oneLine ? ' one-row' : ' split ' + JSON.stringify(middles)) }
          """).string
        #expect(row == "picker raw replay info one-row", Comment(rawValue: row ?? "—"))
        // Replay brings the page to the stream's end, where its tokens
        // appear, and follows it there (user, 2026-10-17): the reader starts
        // where the reply's transcript end is out of view.
        let tailInView = """
          (() => { const content = document.querySelector('#locution-\(replyID.uppercased()) .computorium-session-output-content'), tail = content.lastElementChild
            const r = tail.getBoundingClientRect(), s = getComputedStyle(content.parentElement)
            const line = parseFloat(s.lineHeight) || parseFloat(s.fontSize) * 1.2
            return r.bottom >= 0 && r.bottom - innerHeight <= line })()
          """
        let away = try await page.evaluate("""
          (() => { const content = document.querySelector('#locution-\(replyID.uppercased()) .computorium-session-output-content'), tail = content.lastElementChild
            // Room below a short thread, so the reader can stand past its end.
            document.body.style.paddingBlockEnd = (2 * innerHeight) + 'px'
            const end = document.documentElement.scrollHeight - innerHeight
            const bottom = tail.getBoundingClientRect().bottom + window.scrollY
            // Past it where the page runs on below it, else above it.
            window.scrollTo(0, bottom + 8 <= end ? bottom + 8 : 0)
            const r = tail.getBoundingClientRect(); return r.bottom < 0 || r.bottom - innerHeight > 64 })()
          """, as: Bool.self)
        #expect(away, "The reader starts away from the transcript's end")
        // Every word the chip says from here, for the replay's assertions.
        try await expect(chip.locator(".info-chip-text")).toHaveText("Pending")
        _ = try await page.evaluate("""
          (() => { const text = document.querySelector('.disputorium-core-header-status-chip .info-chip-text')
            window.__chipTexts = [text.textContent]
            new MutationObserver(() => window.__chipTexts.push(text.textContent))
              .observe(text, { childList: true, characterData: true, subtree: true })
            return true })()
          """, as: Bool.self)
        // Clicked where it stands, without scrolling it into view first.
        _ = try await reply.locator(".replay-btn").evaluate("el => el.click()")
        try await Task.sleep(for: .milliseconds(400))
        let during = try await page.evaluate(tailInView, as: Bool.self)
        try await Task.sleep(for: .milliseconds(2000))
        let after = try await page.evaluate(tailInView, as: Bool.self)
        #expect(during && after, "Replay scrolled to the stream's end and follows it: \(during) → \(after)")
        try await expect(reply.locator(".locution-anchor")).toHaveCount(0)
        // Its replay says "Arbitrating" on the page's chip while it plays,
        // the madrigal's status once it ends, as an explication's replay does.
        #expect(try await page.evaluate("window.__chipTexts.includes('Arbitrating')", as: Bool.self),
          "The chip said Arbitrating during the replay")
        try await expect(chip.locator(".info-chip-text"), timeout: .seconds(15)).toHaveText("Pending")
        try await expect(chip.locator(".rotating-ring-sector-view")).toHaveCount(0)
        // The page image in the task prompt as the model received it (user,
        // 2026-10-17): one stage at the message's whole width, zoomed in
        // place—no chip, thumbnail, name or lightbox, no loose lines under
        // it; the prompts as sent read in the base text color (user,
        // 2026-10-15).
        let taskImages = session.locator(".computorium-session-task-fieldset .computorium-session-task-images")
        let received = session.locator(".expandable-attachment-view[data-presentation='received']")
        try await expect(received).toHaveCount(1)
        try await expect(taskImages.locator(".expandable-attachment-view[data-presentation='received']")).toHaveCount(1)
        try await expect(received).toHaveAttribute("data-attachment-hydrated", "true")
        try await expect(session.locator(
          ".expandable-attachment-trigger, .expandable-attachment-image-thumb, .expandable-attachment-name, .expandable-attachment-dialog"
        )).toHaveCount(0)
        try await expect(session.locator(".computorium-session-task-fieldset")).not.toContainText("1.jpg")
        try await expect(session.locator(".computorium-session-sent-images")).toHaveCount(0)
        #expect(try await taskImages.evaluate("""
          el => { const s = getComputedStyle(el), inner = el.clientWidth - parseFloat(s.paddingLeft) - parseFloat(s.paddingRight)
            const frame = el.querySelector('.expandable-attachment-image-frame').getBoundingClientRect()
            return frame.width > 0 && Math.abs(frame.width - inner) <= 1 }
          """).bool == true, "The received stage spans its message's width")
        // The address sent is gone and no copy is archived yet: the stage
        // shows the page as the reader does, never a broken image.
        #expect(try await received.locator("img.expandable-attachment-image-received").evaluate("""
          async img => { img.scrollIntoView(); img.loading = 'eager'
            for (let i = 0; i < 40 && !(img.complete && img.naturalWidth > 0); i++) await new Promise(r => setTimeout(r, 250))
            return img.complete && img.naturalWidth > 0 }
          """).bool == true, "The received image falls back to an image that loads")
        #expect(try await session.locator(".computorium-session-task-fieldset").evaluate(
          "el => !el.innerText.includes('SHA-256') && !el.innerText.includes('Archived')").bool == true,
          "No hash or archive line on the surface (Raw keeps the hash)")
        #expect(try await session.evaluate("""
          el => { const probe = document.createElement('span'); probe.style.color = 'var(--color-base)'
            document.body.appendChild(probe); const base = getComputedStyle(probe).color; probe.remove()
            const texts = [...el.querySelectorAll('.computorium-session-prompt-fieldset .computorium-session-prompt-rendered p')]
            return texts.length > 0 && texts.every(p => getComputedStyle(p).color === base) }
          """).bool == true, "Sent prompts read in the base text color")
        // Raw, the session's one switch: the user turn as sent, its image
        // block where it stood, in place of the rendered prompt and image;
        // off again, the image as received.
        let taskFieldset = session.locator(".computorium-session-task-fieldset")
        let raw = reply.locator(".computorium-session-markdown-toggle button")
        try await raw.click()
        try await expect(session).toHaveAttribute("data-raw-view", "true")
        try await expect(taskFieldset.locator(".computorium-session-prompt-body")).toBeVisible()
        try await expect(taskFieldset.locator(".computorium-session-prompt-body")).toContainText("\"image_url\"")
        try await expect(taskFieldset.locator(".computorium-session-prompt-body")).toContainText("SHA-256 def")
        try await expect(taskImages).toBeHidden()
        try await raw.click()
        try await expect(session).toHaveAttribute("data-raw-view", "false")
        try await expect(received).toBeVisible()
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
            return getComputedStyle(body).maxHeight === 'none' && body.scrollHeight <= body.clientHeight
              && getComputedStyle(thinking).maxHeight === '256px' && getComputedStyle(thinking).overflowY === 'auto'
              && thinking.clientHeight <= 256 && thinking.scrollHeight > thinking.clientHeight;
          }
          """).bool == true, "The reply grows to its session; its thinking keeps its own 256px scroll")
        // An admin submits through exactly the same pending process, the
        // page ticked as any caller ticks it.
        try await page.locator("#locution-thread-locution-body").fill("@gnorium Read this evidence again.")
        try await page.locator("#madrigal-resemblances .roster-row").nth(0).locator("input").click()
        try await page.locator(".locution-thread-submit").click()
        try await expect(page.locator(".locution-commit"), timeout: .seconds(15)).toHaveCount(1)
        try await expect(page.locator(".locution-call-status")).toHaveCount(0)
        #expect(try TestAdmin.query("SELECT count(*) FROM bibliographic_arbitration_sessions WHERE locutable_id = '\(objectID)'") == "1")
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

  /// The madrigal page, its arbitration session running, with an
  /// EventSource the test drives in place of the reply's watch stream: a
  /// "renew" end reattaches the watch and leaves the chip on "Arbitrating";
  /// the new stream's "succeeded" brings the madrigal's status back. The
  /// stand-in is installed before the page's own scripts (`addInitScript`),
  /// only on a document opened at `#renew-test`, so every later load is the
  /// real page. Nothing is written to disk.
  func expectRenewKeepsArbitrating(_ page: Page, path: String, replyID: String) async throws {
    try await page.addInitScript("""
      if (location.hash === '#renew-test') {
        const Real = window.EventSource
        window.__streams = []
        window.EventSource = class {
          // The reply's watch only; any other stream stays the real one.
          constructor(url, options) {
            if (!String(url).includes('/arbitration/stream')) return new Real(url, options)
            this.url = url; this.handlers = {}; window.__streams.push(this)
            setTimeout(() => { this.emit('start', '{"watch":true,"process":"arbitration"}'); window.__stream = this }, 0)
          }
          addEventListener(name, fn) { (this.handlers[name] ??= []).push(fn) }
          emit(name, data) { for (const fn of this.handlers[name] ?? []) fn({ data }) }
          close() {}
        }
        window.__label = () => document.querySelector('#locution-\(replyID.uppercased()) .computorium-session-view')
          .dataset.computoriumSessionResemblance ?? ''
        window.__status = (text) => window.__stream.emit('chunk',
          JSON.stringify({ type: 'status', text, resemblance: window.__label(), canvas_index: -1, message: '' }))
      }
      """)
    try await page.openHydrated(path + "#renew-test")
    let chip = page.locator(".disputorium-core-header-status-chip .info-chip-text")
    let session = page.locator("#locution-\(replyID.uppercased()) .computorium-session-view")
    #expect(try await page.evaluate("""
      (async () => { for (let i = 0; i < 50 && !window.__stream; i++) await new Promise(r => setTimeout(r, 100)); return !!window.__stream })()
      """, as: Bool.self), "The reply's watch is attached")
    _ = try await page.evaluate("(() => { window.__status('running'); return true })()", as: Bool.self)
    try await expect(chip).toHaveText("Arbitrating")
    // The stream's time is up: a new watch, nothing painted as ended.
    _ = try await page.evaluate("(() => { window.__stream.emit('done', '{\"status\":\"renew\"}'); return true })()", as: Bool.self)
    #expect(try await page.evaluate("""
      (async () => { for (let i = 0; i < 50 && window.__streams.length < 2; i++) await new Promise(r => setTimeout(r, 100))
        for (let i = 0; i < 50 && window.__stream !== window.__streams[1]; i++) await new Promise(r => setTimeout(r, 100))
        return window.__streams.length === 2 && window.__stream === window.__streams[1] })()
      """, as: Bool.self), "Renew attaches the watch again")
    try await expect(chip).toHaveText("Arbitrating")
    try await expect(page.locator(".disputorium-core-header-status-chip .rotating-ring-sector-view")).toHaveCount(1)
    try await expect(session).not.toHaveAttribute("data-computorium-session-status", "succeeded")
    // The new stream's status, the session's own: still running, then done.
    _ = try await page.evaluate("(() => { window.__status('running'); return true })()", as: Bool.self)
    try await expect(chip).toHaveText("Arbitrating")
    _ = try await page.evaluate("""
      (() => { window.__status('succeeded'); window.__stream.emit('done', '{"status":"passed","error":""}'); return true })()
      """, as: Bool.self)
    try await expect(chip).toHaveText("Pending")
    try await expect(page.locator(".disputorium-core-header-status-chip .rotating-ring-sector-view")).toHaveCount(0)
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
  /// holds "@gnorium": boxes on the processed items alone, none ticked
  /// (user, 2026-10-15), at most two, neighbors; a tick apart or a third
  /// is refused under the box. A call that ticks nothing is refused under
  /// the box. Submit attaches the ticked items in order, and the call names
  /// each, linked. The box left empty, the roster is back in commit mode.
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
        try await expect(page.locator(".prompt-previews-slot"), timeout: .seconds(20))
          .toHaveAttribute("aria-busy", "false")
        let roster = page.locator("#madrigal-resemblances")
        let rows = roster.locator(".roster-row")
        try await expect(rows).toHaveCount(4)
        // Commit mode: the three read pages locked, the blank one ticked for.
        try await expect(rows.nth(0).locator(".checkbox-icon-wrapper")).toBeHidden()
        try await expect(rows.nth(3).locator(".checkbox-icon-wrapper")).toBeVisible()
        let body = page.locator("#locution-thread-locution-body")
        try await body.focus()
        try await expect(roster).toHaveAttribute("data-mode", "attach")
        try await expect(rows.nth(0).locator(".checkbox-icon-wrapper")).toBeVisible()
        try await expect(rows.nth(0).locator(".checkbox-input")).toBeChecked(false)
        try await expect(rows.nth(0).locator(".checkbox-input")).toHaveAttribute("name", "evidence[]")
        try await expect(rows.nth(0).locator(".checkbox-input")).toHaveAttribute("form", "locution-thread-form")
        try await expect(rows.nth(1).locator(".checkbox-input")).toBeChecked(false)
        try await expect(rows.nth(3).locator(".checkbox-icon-wrapper")).toBeHidden()
        try await expect(rows.nth(3).locator(".checkbox-input")).toBeDisabled()
        // A tick apart from the first is refused; its neighbor is taken; a
        // third is refused.
        try await rows.nth(0).locator("input").click()
        try await expect(rows.nth(0).locator(".checkbox-input")).toBeChecked()
        try await rows.nth(2).locator("input").click()
        try await expect(rows.nth(2).locator(".checkbox-input")).toBeChecked(false)
        try await expect(page.locator(".field-validation-message-view")).toContainText("consecutive")
        try await rows.nth(1).locator("input").click()
        try await expect(rows.nth(1).locator(".checkbox-input")).toBeChecked()
        // A tick keeps the box focused and the roster attaching (user,
        // 2026-10-16): the box still empty, nothing closes under the pointer.
        try await expect(body).toBeFocused()
        try await expect(roster).toHaveAttribute("data-mode", "attach")
        try await rows.nth(2).locator("input").click()
        try await expect(rows.nth(2).locator(".checkbox-input")).toBeChecked(false)
        // Back to commit mode when the box is left empty; attach again on
        // "@gnorium" typed.
        try await page.locator(".locution-thread-title, h3").first.click()
        try await expect(roster).toHaveAttribute("data-mode", "commit")
        try await expect(rows.nth(0).locator(".checkbox-icon-wrapper")).toBeHidden()
        try await expect(rows.nth(0).locator(".checkbox-input")).toBeChecked(false)
        try await expect(rows.nth(0).locator(".checkbox-input")).toHaveAttribute("form", "commit-form")
        try await expect(rows.nth(3).locator(".checkbox-icon-wrapper")).toBeVisible()
        try await body.fill("@gnorium Compare these two pages.")
        try await expect(roster).toHaveAttribute("data-mode", "attach")
        try await expect(rows.nth(0).locator(".checkbox-input")).toBeChecked(false)
        // Nothing ticked, nothing to read: refused under the box, unsent.
        try await page.locator(".locution-thread-submit").click()
        try await expect(page.locator(".field-validation-message-view"))
          .toContainText("Tick evidence, metadata, a prompt or a locution for this call.")
        #expect(try TestAdmin.query("SELECT count(*) FROM locutions WHERE locutable_id = '\(objectID)'") == "0")
        try await rows.nth(0).locator("input").click()
        try await rows.nth(1).locator("input").click()
        try await page.locator(".locution-thread-submit").click()
        // Pending: no status chip; an admin's Commit stands under the call's words.
        try await expect(page.locator(".locution-said + .locution-call-actions .locution-commit"), timeout: .seconds(15))
          .toHaveText("Commit")
        try await expect(page.locator(".locution-call-status")).toHaveCount(0)
        let stored = try TestAdmin.query(
          "SELECT evidence_id || '|' || coalesce(evidence_ids, '') FROM locutions WHERE locutable_id = '\(objectID)' AND kind = 'call'")
        #expect(stored == "\(fixture.baseURL)/page-1|[\"\(fixture.baseURL)/page-1\",\"\(fixture.baseURL)/page-2\"]", Comment(rawValue: stored))
        // The byline names the page on screen alone (user, 2026-10-17); both
        // ticked pages are its Attachments, each image a line-high chip.
        try await expect(page.locator(".locution-call-page")).toHaveCount(1)
        try await expect(page.locator(".locution-header").first).toContainText("on Resemblance 1")
        try await expect(page.locator(".locution-header").first).not.toContainText("Resemblance 2")
        let both = try await page.locator(".locution-attachments").first.evaluate("""
          el => [...el.querySelectorAll('.locution-attachments-item')].map(item => {
            const path = item.querySelector('.locution-thread-path')
            return path ? [...path.children].filter(c => !c.classList.contains('breadcrumb-separator-view'))
              .map(c => c.textContent.trim()).join(' › ') : item.querySelector('a').textContent.trim() }).join(' | ')
          """).string
        #expect(both == "Resemblance 1 | Resemblance 2", Comment(rawValue: both ?? "—"))
        try await expect(page.locator(".locution-attachments .locution-attachment[data-presentation='line']"))
          .toHaveCount(2)
        try await page.expectNoErrors()
      }
    } catch {
      remove()
      try await admin.remove(after: error)
    }
    remove()
    try await admin.remove()
  }

  /// A call ticks its object's Metadata accordions whole and the thread's
  /// locutions (user, 2026-10-15, 2026-10-16): one box on each, shown only
  /// while a call is written, none ticked, a press on one keeping the box
  /// focused. The call stores what was ticked; its byline names the page on
  /// screen, and its Attached line what it ticked (user, 2026-10-17).
  @Test(arguments: [BrowserEngine.chrome])
  func aCallTicksMetadataAccordionsAndLocutions(engine: BrowserEngine) async throws {
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
        let body = page.locator("#locution-thread-locution-body")
        try await body.fill("The title reads oddly.")
        try await page.locator(".locution-thread-submit").click()
        let first = page.locator(".locution-view").first
        try await expect(first, timeout: .seconds(15)).toBeVisible()
        let firstID = try TestAdmin.query("SELECT id FROM locutions WHERE locutable_id = '\(objectID)'").uppercased()
        try await page.openHydrated(reading.path)
        // Its stretch of the rail folds it and opens it again, a pointer's
        // way to its avatar's toggle (user, 2026-10-16).
        let entry = page.locator("#locution-\(firstID)")
        let rail = entry.locator(".locution-rail")
        try await expect(rail).toHaveCSS("cursor", "pointer")
        try await rail.click()
        try await expect(entry).toHaveAttribute("data-collapsed", "true")
        try await expect(entry.locator(".locution-collapse")).toHaveAttribute("aria-expanded", "false")
        try await rail.click()
        try await expect(entry).toHaveAttribute("data-collapsed", "false")
        // Hidden until a call is written.
        let work = page.locator("#metadata-tick-work")
        let locutionTick = page.locator("#locution-tick-\(firstID)")
        try await expect(work).toBeHidden()
        try await expect(locutionTick).toBeHidden()
        // A header bearing a tick keeps its height when the tick shows, the
        // box centered on the header's line (user, 2026-10-17).
        let headers = """
          [...document.querySelectorAll('.accordion-summary')].filter(s => s.querySelector('.call-tick-view'))
            .map(s => s.getBoundingClientRect().height)
          """
        let ticks = """
          [...document.querySelectorAll('.accordion-summary .call-tick-view')].filter(t => t.offsetParent)
            .map(t => { const box = t.querySelector('.checkbox-icon').getBoundingClientRect()
              const title = t.closest('.accordion-title').getBoundingClientRect()
              return Math.abs((box.top + box.bottom) / 2 - (title.top + title.bottom) / 2) })
          """
        let before = try await page.evaluate(headers, as: [Double].self)
        try await body.focus()
        try await expect(page.locator("html")).toHaveAttribute("data-locution-attaching", "true")
        let after = try await page.evaluate(headers, as: [Double].self)
        #expect(!before.isEmpty && before == after, "headers keep their height as their ticks show: \(before) → \(after)")
        let offsets = try await page.evaluate(ticks, as: [Double].self)
        #expect(!offsets.isEmpty && offsets.allSatisfy { $0 < 0.5 }, "each tick centered on its header's line: \(offsets)")
        try await expect(locutionTick).toBeVisible()
        try await expect(locutionTick).toBeChecked(false)
        try await locutionTick.click()
        try await expect(locutionTick).toBeChecked()
        try await expect(body).toBeFocused()
        // The work's Metadata, ticked from its header, leaves it closed.
        try await expect(work).toBeVisible()
        let open = "(()=>{const e=document.getElementById('record-metadata');return String((e.matches('details')?e:e.querySelector('details')).open)})()"
        let wasOpen = try await page.evaluate(open, as: String.self)
        try await work.click()
        try await expect(work).toBeChecked()
        let isOpen = try await page.evaluate(open, as: String.self)
        #expect(isOpen == wasOpen, "a tick in the header leaves the accordion as it was")
        try await body.fill("@gnorium Is the title right?")
        // And an image on another page than the one on screen (page 1).
        let page2 = page.locator("#madrigal-resemblances .roster-row").nth(1).locator("input")
        try await page2.click()
        try await expect(page2).toBeChecked()
        try await page.locator(".locution-thread-submit").click()
        try await expect(page.locator(".locution-said + .locution-call-actions .locution-commit"), timeout: .seconds(15))
          .toHaveText("Commit")
        let stored = try TestAdmin.query("""
          SELECT coalesce(evidence_id, '—') || '|' || coalesce(metadata_ids, '') || '|' || coalesce(locution_ids, '')
          FROM locutions WHERE locutable_id = '\(objectID)' AND kind = 'call'
          """)
        #expect(stored == "\(fixture.baseURL)/page-2|[\"work\"]|[\"\(firstID)\"]", Comment(rawValue: stored))
        // Its body as typed; the byline names the page on screen, and
        // nothing ticked (user, 2026-10-17); its Attachments list the three
        // in the order its message carries them—Metadata, evidence,
        // locutions—the page's image a line-high chip.
        let call = page.locator(".locution-view").last
        try await expect(call.locator(".locution-header")).toContainText("on Resemblance 1")
        try await expect(call.locator(".locution-header")).not.toContainText("Resemblance 2")
        try await expect(call.locator(".locution-body-rendered")).toHaveText("@gnorium Is the title right?")
        let attachments = call.locator(".list-sentence-view.locution-attachments")
        try await expect(attachments).toContainText("Attached ")
        let crumbs = try await attachments.evaluate("""
          el => [...el.querySelectorAll('.locution-attachments-item')].map(item => {
            const path = item.querySelector('.locution-thread-path')
            return path ? [...path.children].filter(c => !c.classList.contains('breadcrumb-separator-view'))
              .map(c => c.textContent.trim()).join(' › ') : item.querySelector('a').textContent.trim() }).join(' | ')
          """).string
        let joined = try await attachments.evaluate(
          "e => [...e.childNodes].filter(n => n.nodeType === 3).map(n => n.textContent).join('|')").string
        #expect(joined == "Attached |, |, and |.", Comment(rawValue: joined ?? "—"))
        // Metadata by its node's heading, as its accordion names it.
        #expect(crumbs?.hasPrefix("Metadata › ") == true && crumbs?.hasSuffix(" | Resemblance 2 | Locution \(firstID)") == true
          && crumbs?.components(separatedBy: " | ").count == 3, Comment(rawValue: crumbs ?? "—"))
        try await expect(attachments.locator(".locution-attachments-item a[href='#locution-\(firstID)']")).toHaveCount(1)
        try await expect(attachments.locator(".locution-attachments-item").nth(1)
          .locator(".locution-attachment[data-presentation='line']")).toHaveCount(1)
        // A locution that ticks nothing, a plain one, has no Attachments.
        try await expect(page.locator("#locution-\(firstID) .locution-attachments")).toHaveCount(0)
        try await page.expectNoErrors()
      }
    } catch {
      remove()
      try await admin.remove(after: error)
    }
    remove()
    try await admin.remove()
  }

  /// A crop box on an attached resemblance (user, 2026-10-10): in attach mode
  /// the reader's image of a ticked item takes a dragged box; the call
  /// stores it in the 0–1000 space by the item's id, and its locution shows
  /// the numbers beside the item's link.
  @Test(arguments: [BrowserEngine.chrome])
  func aCropBoxDrawnOnAnAttachedResemblanceRidesWithTheCall(engine: BrowserEngine) async throws {
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
        let roster = page.locator("#madrigal-resemblances")
        let body = page.locator("#locution-thread-locution-body")
        // Submit at the right, under the box's right edge (user, 2026-10-10).
        let field = try #require(try await body.boundingBox())
        let submit = try #require(try await page.locator(".locution-thread-submit").boundingBox())
        #expect(abs((submit.x + submit.width) - (field.x + field.width)) < 1, "Submit under the box's right edge")
        #expect(submit.x > field.x + 1, "Submit is not at the left")
        try await body.fill("@gnorium Read the line in the box.")
        try await expect(roster).toHaveAttribute("data-mode", "attach")
        try await roster.locator(".roster-row").nth(0).locator("input").click()
        try await expect(roster.locator(".roster-row").nth(0).locator(".checkbox-input")).toBeChecked()
        // The page images on; the ticked resemblance takes a box.
        let toggle = viewer.locator(".artifact-canvas-toggle button")
        if try await toggle.getAttribute("aria-pressed") != "true" { try await toggle.click() }
        let resemblance = viewer.locator(".canvas-view[data-active='true'] .canvas-viewport")
        try await expect(resemblance).toHaveAttribute("data-cropping", "true")
        let box = try #require(try await resemblance.boundingBox())
        let (x0, y0) = (box.x + box.width * 0.4, box.y + box.height * 0.4)
        let (x1, y1) = (box.x + box.width * 0.6, box.y + box.height * 0.55)
        try await page.mouse.move(x: x0, y: y0)
        try await page.mouse.down(x: x0, y: y0)
        for step in 1...5 {
          try await page.mouse.move(x: x0 + (x1 - x0) * Double(step) / 5, y: y0 + (y1 - y0) * Double(step) / 5)
        }
        try await page.mouse.up(x: x1, y: y1)
        try await expect(resemblance.locator(".canvas-crop")).toBeVisible()
        try await expect(roster).toHaveAttribute("data-mode", "attach")
        try await page.locator(".locution-thread-submit").click()
        // Pending: no status chip; an admin's Commit stands under the call's words.
        try await expect(page.locator(".locution-said + .locution-call-actions .locution-commit"), timeout: .seconds(15))
          .toHaveText("Commit")
        try await expect(page.locator(".locution-call-status")).toHaveCount(0)
        let stored = try TestAdmin.query(
          "SELECT evidence_crops FROM locutions WHERE locutable_id = '\(objectID)' AND kind = 'call'")
        let service = "\(fixture.baseURL)/page-1"
        let crops = try JSONSerialization.jsonObject(with: Data(stored.utf8)) as? [String: [Int]]
        let crop = try #require(crops?[service], Comment(rawValue: stored))
        #expect(crop.count == 4 && crop[2] > 0 && crop[3] > 0 && crop[0] + crop[2] <= 1000 && crop[1] + crop[3] <= 1000)
        // Its Attachments say a crop box was drawn on the page.
        try await expect(page.locator(".locution-attachments-item").first).toContainText("crop")
        // The locution's control row: Raw right before the info icon (user,
        // 2026-10-12); the reactions button ends the pills, before the
        // controls (user, 2026-10-15).
        let order = try await page.evaluate(
          """
          [...document.querySelector('.locution-view .reactions-raw-info').children]
            .map(e => e.classList.contains('locution-markdown-toggle') ? 'raw'
              : e.classList.contains('reaction-picker-view') ? 'picker'
              : e.classList.contains('reactions-when') ? 'when' : 'other').slice(0, 3).join(' ')
          """, as: String.self)
        #expect(order == "raw when", Comment(rawValue: order))
        try await expect(page.locator(".locution-view .reactions-row > .reaction-picker-view + .reactions-controls").first)
          .toBeAttached()
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
          VALUES ('\(epilogue)', '\(word.recordID.lowercased())', '\(word.versionID.lowercased())', '\(word.leaf)',
            '<sense><def>A leaf sense.</def></sense>', 'definition', 'committed', '\(user)', 'Web tests arbitration prompts.',
            '{"languageCode":"fra","tei":"<def xml:lang=\\"fr\\">Un sens feuille.</def>","confidence":"clear","reason":"Web tests."}');
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        // The process after Arbitration: the overture's page's explication,
        // filled; the epilogue's completed translation sends nothing, so it
        // has no accordion (user, 2026-10-17).
        let cases: [(String, String?, String)] = [
          (scratch.overturePath, "Explication", "bibliographic_arbitration"),
          ("/mission-control/epilogues/lexicographic/\(epilogue)?process=translation", nil, "lexicographic_arbitration"),
        ]
        for (path, process, slot) in cases {
          try await page.openHydrated(path)
          let sections = page.locator(".prompt-previews-process")
          try await expect(page.locator(".prompt-previews-slot"), timeout: .seconds(20)).toHaveAttribute("aria-busy", "false")
          try await expect(sections, timeout: .seconds(20)).toHaveCount(process == nil ? 1 : 2)
          try await expect(sections.nth(0)).toHaveAttribute("data-process", "Arbitration")
          if let process { try await expect(sections.nth(1)).toHaveAttribute("data-process", process) }
          // Arbitration's task with nothing ticked is its template; the
          // process's is filled.
          var shown = [(0, "Arbitration", "prompt-preview-process-arbitration", false)]
          if let process { shown.append((1, process, "prompt-preview-process", true)) }
          for (index, name, id, filled) in shown {
            // One accordion a process, its three nested (user, 2026-10-10).
            try await expect(sections.nth(index).locator("#\(id) .prompt-preview-title-words").first).toHaveText(name)
            try await expect(sections.nth(index).locator("#\(id)")).toHaveAttribute("data-expanded", "false")
            try await expect(sections.nth(index).getByText("System Prompt", exact: true)).toHaveCount(2)
            // Its task filled as sent, or its template where none can be
            // (user, 2026-10-17); its autocompaction's a template (user,
            // 2026-10-10).
            try await expect(sections.nth(index).getByText("Task Prompt", exact: true)).toHaveCount(filled ? 1 : 0)
            try await expect(sections.nth(index).getByText("Task Prompt Template", exact: true)).toHaveCount(filled ? 1 : 2)
            try await expect(sections.nth(index).getByText("Autocompaction", exact: true)).toHaveCount(1)
          }
          try await page.openHydrated(path.split(separator: "?").first.map(String.init)! + "/revise")
          let arbitration = page.locator(".prompt-revision-fields-process[data-process='\(slot)']")
          try await expect(arbitration.locator("textarea[name='prompt-system-\(slot)']")).toHaveCount(1)
          try await expect(arbitration.locator("textarea[name='prompt-task-\(slot)']")).toHaveCount(1)
          // The process, its prompts, autocompaction's and the continuation
          // prompt's (user, 2026-10-15).
          try await expect(arbitration.locator(".accordion-details")).toHaveCount(7)
          try await expect(arbitration.locator(".accordion-details[data-expanded='false']")).toHaveCount(7)
          try await expect(arbitration.locator("textarea[name='prompt-task-\(slot)_continuation']")).toHaveCount(1)
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
