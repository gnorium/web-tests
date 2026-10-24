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
        CROSS JOIN computorium_services c WHERE p.singleton = true AND c.service = 'arbitration'
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
        // Image 2 is laid in blank: pending explication, it has no box
        // to tick, and the page on screen is never read unticked (user,
        // 2026-10-15). A call may tick nothing (user, 2026-10-21): it posts,
        // reading no page.
        try await page.openHydrated(reading.path + "?image=1")
        try await expect(page.locator(".prompt-previews-slot"), timeout: .seconds(20))
          .toHaveAttribute("aria-busy", "false")
        try await expect(page.locator(".disputorium-core-object #artifact-page-total"), timeout: .seconds(20)).toHaveText("3")
        try await expect(page.locator("#thread-locution-image")).toHaveValue("1")
        try await expect(page.locator("#thread-process")).toHaveValue("explication")
        try await expect(page.locator(".thread-form input[type='checkbox']")).toHaveCount(0)
        try await expect(page.locator(".thread-submit")).toHaveText("Submit")
        try await expect(page.locator("#madrigal-images .roster-row").nth(1).locator(".checkbox-input")).toBeDisabled()
        try await page.locator("#thread-locution-body").fill("@gnorium Hi")
        try await page.locator(".thread-submit").click()
        try await expect(page.locator(".locution-view"), timeout: .seconds(15)).toHaveCount(1)
        try await expect(page.locator(".locution-call-page")).toHaveCount(0)
        #expect(try TestAdmin.query("""
          SELECT count(*) FROM locutions WHERE locutable_id = '\(objectID)' AND kind = 'call' AND query = 'Hi'
            AND evidence_id IS NULL AND metadata_ids IS NULL AND prompt_ids IS NULL AND locution_ids IS NULL
          """) == "1")
        // Gone again: the rest reads the thread's one ticked call.
        _ = try TestAdmin.query("DELETE FROM locutions WHERE locutable_id = '\(objectID)' AND query = 'Hi'")
        // Image 1 has markup: explicated, queryable—and locked against a
        // commit: its row keeps its mark and loses its checkbox. Ticked
        // from page 3, the page on screen (user, 2026-10-17).
        try await page.openHydrated(reading.path + "?image=2")
        try await expect(page.locator(".prompt-previews-slot"), timeout: .seconds(20))
          .toHaveAttribute("aria-busy", "false")
        try await expect(page.locator(".disputorium-core-object #artifact-page-total"), timeout: .seconds(20)).toHaveText("3")
        try await expect(page.locator("#thread-locution-image")).toHaveValue("2")
        try await page.locator("#thread-locution-body").fill("@gnorium What does the selected evidence support?")
        try await page.locator("#madrigal-images .roster-row").nth(0).locator("input").click()
        try await page.locator(".thread-submit").click()
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
        let rows = page.locator("#madrigal-images .roster-row")
        try await expect(rows).toHaveCount(3)
        try await expect(rows.nth(0)).toHaveAttribute("data-locked", "true")
        try await expect(rows.nth(0).locator(".checkbox-icon-wrapper")).toBeHidden()
        try await expect(rows.nth(0).locator(".checkbox-input")).toBeDisabled()
        try await expect(rows.nth(1)).toHaveAttribute("data-locked", "false")
        try await expect(rows.nth(1).locator(".checkbox-icon-wrapper")).toBeVisible()
        // Its checkbox's column kept, the locked row's ordinal, mark and
        // label line up with an unlocked row's (user, 2026-10-10).
        #expect(try await page.evaluate("""
          (() => { const rows = document.querySelectorAll('#madrigal-images .roster-row')
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
        // locution ‹id› on Image 3", not the page it ticked.
        try await expect(call.locator(".locution-header")).toContainText("submitted locution \(callID.uppercased()) on Image 3")
        try await expect(call.locator("a:has(.locution-call-page)")).toHaveAttribute("href", "/mission-control/madrigals/bibliographic/\(objectID.uppercased())?image=2")
        // Its body stays as typed; what it ticked is one sentence in a box
        // after it, as a revision's Modified line is: "Attached Image
        // 1.", the page's image a line-high chip opening the lightbox (user,
        // 2026-10-17). No picture above the words; nothing full size, which
        // only a session transcript shows.
        try await expect(call.locator(".locution-anchor")).toHaveCount(0)
        try await expect(call.locator(".locution-body-rendered")).toHaveText("@gnorium What does the selected evidence support?")
        let attachments = call.locator(".list-sentence-view.locution-attachments")
        try await expect(attachments).toHaveCount(1)
        let words = try await attachments.evaluate(
          "e => e.querySelector('.list-sentence-lead').textContent + '|' + [...e.childNodes].filter(n => n.nodeType === 3).map(n => n.textContent).join('|') + '|' + e.querySelector('.locution-attachments-item a').textContent").string
        #expect(words == "Attached| |.|Image 1", Comment(rawValue: words ?? "—"))
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
        // A revision the session suggests as the page watches joins the
        // thread at once, its act drawn as the server draws it, no reload
        // (user, 2026-10-18).
        try await expectSuggestedRevisionJoinsTheThread(
          page, path: reading.path, replyID: replyID, madrigalID: objectID, by: adminID)

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
        // mark of the highest level its object has fully reached (user,
        // 2026-10-21): this madrigal has one page of three explicated, so it
        // is calibrated, the turning ring sector; an overture's the dotted
        // ring sector, a fully explicated madrigal's the disc sector. Its
        // Thinking card's running mark the same.
        let chip = page.locator(".disputorium-core-header-status-chip")
        try await expect(chip.locator(".info-chip-text")).toHaveText("Arbitrating")
        try await expect(chip.locator(".rotating-ring-sector-view")).toHaveCount(1)
        try await expect(chip.locator(".rotating-dotted-ring-sector-view, .rotating-sector-view")).toHaveCount(0)
        try await ComputoriumMarks.checkThinking(
          page, process: "arbitration", arbitrated: "calibrated", scope: "#locution-\(replyID.uppercased())")
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
        // A provider-side stop pauses it too, in prose (user, 2026-10-17):
        // the reason the server records, never the service's code.
        _ = try TestAdmin.query("""
          UPDATE bibliographic_arbitration_sessions SET error_message = 'Paused: no answer in round 6; carrying on.'
          WHERE id = '\(sessionID)'
          """)
        try await expect(paused, timeout: .seconds(15)).toHaveText("Paused: no answer in round 6; carrying on.")
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
        try await expect(call.locator(".locution-call-page")).toHaveText("Image 3")
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
        // reaction picker, its session's Raw, Replay (its speed is in the
        // replay's bar, user, 2026-10-21), then one ⓘ with the
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
            // Above the playback bar, which sticks over the viewport's foot.
            const bar = document.querySelector('.replay-seek-view:not([hidden])')
            const foot = bar ? Math.min(innerHeight, bar.getBoundingClientRect().top) : innerHeight
            return r.bottom >= 0 && r.bottom - foot <= line })()
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
        // Replay's speed (user, 2026-10-21): the recorded waits divided by
        // it, changed mid-replay at once, the viewer's choice kept.
        try await expectReplaySpeed(page, path: reading.path, replyID: replyID)
        // Replay's seek bar (user, 2026-10-21): a moment sought shows exactly
        // the frames recorded by then, and plays on from there at the speed.
        try await expectReplaySeek(page, path: reading.path, replyID: replyID)
        // A long session's seek (user, 2026-10-21): its thousands of
        // deltas folded and drawn once, the handle dragged smoothly, the bar
        // there before the frames are.
        try await expectReplayScrub(page, path: reading.path, replyID: replyID)
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
        // Its box is the image as drawn, no taller than half the small
        // viewport (user, 2026-10-17): no letterbox above or below.
        #expect(try await received.locator("img.expandable-attachment-image-received").evaluate("""
          img => { const r = img.getBoundingClientRect(), probe = document.createElement('div')
            probe.style.height = '50svh'; document.body.appendChild(probe); const half = probe.getBoundingClientRect().height; probe.remove()
            return r.height <= half + 1 && Math.abs(parseFloat(getComputedStyle(img).maxHeight) - half) <= 0.5
              && Math.abs(r.width / r.height - img.naturalWidth / img.naturalHeight) * r.height <= 1 }
          """).bool == true, "The received image's box is its drawn size, capped at 50svh")
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
        // The tools offered: once, as the chat template writes them into
        // the system turn, though both model calls sent them (user,
        // 2026-10-21).
        let tools = session.locator(".computorium-session-tools")
        try await expect(tools).toHaveCount(1)
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
        // Failed, its alert is prose (user, 2026-10-17): a session that
        // stopped with the service's code reads "Stopped: …"; the code stays
        // in the log and the trace. An admin's Continue carries the
        // session on from its saved trace (user, 2026-10-18).
        _ = try TestAdmin.query("""
          BEGIN;
          UPDATE bibliographic_arbitration_sessions SET result = 'failed',
            error_message = 'SESSION_EMPTY_RESPONSE: round 6: empty response after 3 tries' WHERE id = '\(sessionID)';
          UPDATE locutions SET call_status = 'failed' WHERE id = '\(callID)';
          COMMIT;
          """)
        try await page.openHydrated(reading.path)
        let failed = page.locator("#locution-\(replyID.uppercased())")
        try await expect(failed.locator(".computorium-session-view")).toHaveAttribute("data-computorium-session-status", "failed")
        try await expect(failed.locator(".computorium-session-failed-alert"))
          .toContainText("Stopped: no answer in round 6 after 3 tries.")
        try await expect(failed).not.toContainText("SESSION_")
        // Continue: large, blue solid, semibold, a row of its own, as a
        // call's Commit; posted to the call.
        let continueButton = failed.locator(".locution-call-actions .locution-continue")
        try await expect(continueButton).toHaveCount(1)
        try await expect(continueButton).toHaveText("Continue")
        try await expect(failed.locator("form.locution-continue-form[action$='/locutions/\(callID.uppercased())/continue']"))
          .toHaveCount(1)
        #expect(try await continueButton.evaluate("""
          el => ['button-color-blue', 'button-weight-solid', 'button-size-large'].every(c => el.classList.contains(c))
          """).bool == true, "Continue is large and blue solid")
        #expect(try await continueButton.evaluate("""
          el => getComputedStyle([...el.querySelectorAll('*')].find(n => !n.children.length && n.textContent.trim() === 'Continue') ?? el).fontWeight
          """).string == "600", "Continue is semibold")
        try await expect(failed.locator(".locution-pages-nav")).toHaveCount(0)
        // Its Raw, on a failed reply with a long trace (prod's ran past a
        // megabyte): M↓ shows it without blocking the page, and again puts
        // it away (user, 2026-10-18).
        // Rounds as the template carries them: Raw is drawn from these.
        let long = (0..<300).flatMap { index -> [[String: String]] in
          let words = "Round \(index): " + String(repeating: "Reading the page again with care. ", count: 120)
          return [
            ["type": "chat_template_input", "content": "<｜User｜>" + words],
            ["type": "thinking", "content": words],
            ["type": "chat_template_output", "content": words, "end": "<｜end▁of▁sentence｜>"],
          ]
        }
        _ = try TestAdmin.query("BEGIN; \(try SessionTrace.append(long, table: Self.sessions, id: sessionID)) COMMIT;")
        try await page.openHydrated(reading.path)
        let failedSession = failed.locator(".computorium-session-view")
        let failedRaw = failed.locator(".reactions-raw-info .computorium-session-markdown-toggle button")
        _ = try await page.evaluate("""
          (() => { window.__long = []; new PerformanceObserver(l => { for (const e of l.getEntries()) window.__long.push(e.duration) })
            .observe({ type: 'longtask' }); return true })()
          """, as: Bool.self)
        try await failedRaw.click()
        try await expect(failedSession, timeout: .seconds(15)).toHaveAttribute("data-raw-view", "true")
        try await expect(failedSession.locator(".chat-template-raw-view").first).toBeVisible()
        try await failedRaw.click()
        try await expect(failedSession).toHaveAttribute("data-raw-view", "false")
        let blocked = try await page.evaluate("Math.max(0, ...window.__long)", as: Double.self)
        #expect(blocked < 500, "No task blocked the page for long: \(blocked) ms")
        let vignette = try TestAdmin.query("SELECT prompt_vignette_id FROM bibliographic_arbitration_sessions WHERE id = '\(sessionID)'")
        _ = try await page.evaluate("(() => { window.__notReloaded = true; return true })()", as: Bool.self)
        try await continueButton.click()
        // The same session continued, never restarted (user, 2026-10-18):
        // no new session, queued again on its call (its saved trace the
        // service carries on once a worker takes it), on the vignette it was
        // committed with; the reply still its.
        let resumed = page.locator("#locution-\(replyID.uppercased())")
        try await expect(resumed.locator(".computorium-session-view"), timeout: .seconds(15))
          .not.toHaveAttribute("data-computorium-session-status", "failed")
        #expect(try TestAdmin.query("""
          SELECT string_agg(id || ':' || instance || ':' || result, ',') FROM bibliographic_arbitration_sessions
          WHERE call_locution_id = '\(callID)'
          """) == "\(sessionID):1:queued")
        #expect(try TestAdmin.query("SELECT prompt_vignette_id FROM bibliographic_arbitration_sessions WHERE id = '\(sessionID)'") == vignette)
        #expect(try TestAdmin.query("SELECT call_status || '|' || arbitration_session_id FROM locutions WHERE id = '\(callID)'")
          == "committed|\(sessionID)")
        #expect(try TestAdmin.query("SELECT arbitration_session_id FROM locutions WHERE id = '\(replyID)'") == sessionID)
        #expect(try TestAdmin.query("""
          SELECT count(*) FROM event_logs WHERE action = 'continue' AND resource_id = '\(callID)' AND user_id = '\(adminID)'
          """) == "1")
        // Posted in place (user, 2026-10-18): no reload, the transcript's
        // end brought into view and followed as the session goes on.
        #expect(try await page.evaluate("window.__notReloaded === true", as: Bool.self), "Continue does not reload the page")
        let continuedTailInView = """
          (async () => {
            for (let i = 0; i < 50; i++) {
              const content = document.querySelector('#locution-\(replyID.uppercased()) .computorium-session-output-content')
              // The last child drawn: the hidden Raw view the transcript ends in has no box.
              const tail = content && ([...content.children].reverse().find(e => e.getClientRects().length > 0) ?? content)
              const rect = tail && tail.getBoundingClientRect()
              if (rect && rect.bottom <= innerHeight + 2 && rect.bottom > 0) return true
              await new Promise(r => setTimeout(r, 100))
            }
            return false
          })()
          """
        #expect(try await page.evaluate(continuedTailInView, as: Bool.self), "The transcript's end is in view after Continue")
        _ = try TestAdmin.query("""
          BEGIN;
          \(try SessionTrace.append([["type": "thinking", "content": "Carried on: one more round of reading."]],
            table: Self.sessions, id: sessionID))
          COMMIT;
          """)
        #expect(try await page.evaluate("""
          (async () => {
            for (let i = 0; i < 100; i++) {
              if (document.querySelector('#locution-\(replyID.uppercased())').textContent.includes('Carried on: one more round of reading.')) return true
              await new Promise(r => setTimeout(r, 200))
            }
            return false
          })()
          """, as: Bool.self), "The continued session's new tokens arrive")
        #expect(try await page.evaluate(continuedTailInView, as: Bool.self), "The page follows the transcript's end")
        // One instance: no pager.
        try await expect(resumed.locator(".locution-pages-nav")).toHaveCount(0)
        // The Continue, an act of the thread.
        let act = page.locator(".thread-event-line").filter(hasText: "continued locution \(callID.uppercased())")
        try await expect(act).toHaveCount(1)
        try await expect(act).not.toContainText("instance")
        // Waiting again: its Continue drawn hidden, shown only should it fail
        // as the page watches—without a reload.
        try await expect(resumed.locator(".locution-continue")).toBeHidden()
        _ = try TestAdmin.query("""
          BEGIN;
          UPDATE bibliographic_arbitration_sessions SET result = 'failed', error_message = 'Stopped: no saved trace to continue from.'
            WHERE id = '\(sessionID)';
          UPDATE locutions SET call_status = 'failed' WHERE id = '\(callID)';
          COMMIT;
          """)
        try await expect(resumed.locator(".locution-continue"), timeout: .seconds(20)).toBeVisible()
        // The ⓘ a bare icon: the controls 8 apart (user, 2026-10-17).
        #expect(try await resumed.locator(".reactions-controls").evaluate("el => getComputedStyle(el).columnGap").string == "8px")
        #expect(try TestAdmin.query("SELECT count(*) FROM bibliographic_arbitration_sessions WHERE call_locution_id = '\(callID)'") == "1")
        // An admin submits through exactly the same pending process, the
        // page ticked as any caller ticks it.
        try await page.locator("#thread-locution-body").fill("@gnorium Read this evidence again.")
        try await page.locator("#madrigal-images .roster-row").nth(0).locator("input").click()
        try await page.locator(".thread-submit").click()
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
  /// "renew" end reattaches the watch and leaves the chip on "Arbitrating"
  /// (the turning ring sector: one page of three explicated, the madrigal
  /// is calibrated); the new stream's "succeeded" brings the madrigal's
  /// status back. The stand-in is installed before the page's own scripts
  /// (`addInitScript`), only on a document opened at `#renew-test`, so
  /// every later load is the real page. Nothing is written to disk.
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
          .dataset.computoriumSessionImage ?? ''
        window.__status = (text) => window.__stream.emit('chunk',
          JSON.stringify({ type: 'status', text, image: window.__label(), image_index: -1, message: '' }))
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
    // The madrigal's own state again: Pending, its verdict to come.
    try await expect(chip).toHaveText("Pending")
    try await expect(page.locator(".disputorium-core-header-status-chip .rotating-ring-sector-view")).toHaveCount(0)
  }

  /// Replay's speed (user, 2026-10-21) on the reply's replay, its stream
  /// the test's stand-in (at `#pace-test`): frames recorded 0, 4 and 12
  /// seconds in. The group is in the replay's bar (user, 2026-10-21),
  /// hidden until Replay. Switched to 2× as the replay starts, the second
  /// shows 2s after the first; switched to 4× as it shows, the third 2s
  /// after it (8s left at 4×, not 4s at 2×). The group is "Replay speed",
  /// its buttons 1×, 2× and 4× pressed by aria-pressed; the last choice is
  /// kept across a reload, then set back to 1×, and the page left as
  /// freshly loaded.
  func expectReplaySpeed(_ page: Page, path: String, replyID: String) async throws {
    let reply = "#locution-\(replyID.uppercased())"
    try await page.addInitScript("""
      if (location.hash === '#pace-test') {
        const Real = window.EventSource
        window.EventSource = class {
          // The reply's replay only; any other stream stays the real one.
          constructor(url, options) {
            if (!String(url).includes('replay=1')) return new Real(url, options)
            this.handlers = {}
            setTimeout(() => {
              const image = document.querySelector('\(reply) .computorium-session-view').dataset.computoriumSessionImage ?? ''
              const frame = (at, fields) => this.emit('chunk', JSON.stringify({ replay_at: String(at), image, image_index: -1, ...fields }))
              this.emit('start', '{"replay":true,"process":"arbitration"}')
              // Every frame at once, as the server sends a replay's.
              frame(0, { type: 'reset', text: '', reset: '1' })
              frame(0, { type: 'text', text: 'Pace one.', reset: '1' })
              frame(4000, { type: 'text', text: ' Pace two.', append: '1' })
              frame(12000, { type: 'text', text: ' Pace three.', append: '1' })
              frame(12000, { type: 'status', text: 'succeeded', message: '' })
              this.emit('done', '{"status":"passed","error":"","message":"","replayed":"true"}')
            }, 0)
          }
          addEventListener(name, fn) { (this.handlers[name] ??= []).push(fn) }
          emit(name, data) { for (const fn of this.handlers[name] ?? []) fn({ data }) }
          close() {}
        }
      }
      """)
    try await page.openHydrated(path + "?pace=1#pace-test")
    // Drawn hidden in the reply's bar; the bar moves to the foot of the
    // page's content column once Replay is pressed.
    let group = page.locator("\(reply) .replay-seek-view .replay-speed-view, .layout-content-area > .replay-seek-view .replay-speed-view")
    try await expect(group).toHaveCount(1)
    try await expect(group).toBeHidden()
    try await expect(group).toHaveAttribute("role", "group")
    try await expect(group).toHaveAttribute("aria-label", "Replay speed")
    let buttons = group.locator(".toggle-button-group-button")
    #expect(try await buttons.allTextContents().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } == ["1×", "2×", "4×"])
    try await expect(buttons.nth(0)).toHaveAttribute("aria-pressed", "true")
    // When each frame shows; 2× pressed the moment the first does, 4× the
    // moment the second does.
    _ = try await page.evaluate("""
      (() => { const content = document.querySelector('\(reply) .computorium-session-view')
        window.__paced = {}
        new MutationObserver(() => {
          const text = content.textContent
          for (const word of ['one', 'two', 'three'])
            if (text.includes('Pace ' + word + '.') && !window.__paced[word]) {
              window.__paced[word] = performance.now()
              const speed = { one: '2', two: '4' }[word]
              if (speed) document.querySelector('.layout-content-area > .replay-seek-view .replay-speed-view [data-value="' + speed + '"]').click()
            }
        }).observe(content, { childList: true, subtree: true, characterData: true })
        return true })()
      """, as: Bool.self)
    _ = try await page.locator("\(reply) .replay-btn").evaluate("el => el.click()")
    try await expect(page.locator("\(reply) .computorium-session-view"), timeout: .seconds(20))
      .toContainText("Pace three.")
    let gaps = try await page.evaluate("""
      [window.__paced.two - window.__paced.one, window.__paced.three - window.__paced.two].map(Math.round).join(' ')
      """, as: String.self)
    let ms = gaps.split(separator: " ").compactMap { Int($0) }
    #expect(ms.count == 2 && (1500...3200).contains(ms[0]),
      "Switched to 2× as it starts, a 4s recorded wait takes 2s, not 4s: \(gaps)")
    #expect(ms.count == 2 && (1500...3200).contains(ms[1]),
      "Switched to 4× mid-replay, the 8s left take 2s, not 4s at 2×: \(gaps)")
    try await expect(buttons.nth(2)).toHaveAttribute("aria-pressed", "true")
    // The replay ends where its frames end, the done held until then.
    try await expect(page.locator("\(reply) .computorium-session-view"))
      .toHaveAttribute("data-computorium-session-status", "succeeded")
    // The viewer's last choice, kept; set back to 1× for what follows.
    try await page.openHydrated(path)
    try await expect(buttons.nth(2)).toHaveAttribute("aria-pressed", "true")
    try await expect(buttons.nth(0)).toHaveAttribute("aria-pressed", "false")
    // Hidden in the reply's bar until a replay: clicked where it stands.
    _ = try await buttons.nth(0).evaluate("el => el.click()")
    try await expect(buttons.nth(0)).toHaveAttribute("aria-pressed", "true")
    #expect(try await page.evaluate("localStorage.getItem('gnorium:replay-speed')", as: String.self) == "1")
    try await page.openHydrated(path)
  }

  /// Replay's seek bar (user, 2026-10-21) on the reply's replay, its stream
  /// the test's stand-in (at `#seek-test`): frames recorded 0, 60 and 120
  /// seconds in, a model call starting at 0 and at 60. Drawn hidden in the
  /// reply until Replay is pressed; then a bar at the end of the page's
  /// content area (`.layout-content-area`), sticky at the foot of the viewport
  /// over the page's content, holding Pause, the track, the clock, the
  /// speed and a close ×: "0:0x / 2:00", a slider "Replay position" to
  /// 120000 with one tick (the second call), and Pause. Escape leaves it
  /// playing. The arrows seek 5s: twelve
  /// show the 60s frame and not the 120s one; Home draws the transcript
  /// again from its start; Pause holds it, a click on the track's 3/4 goes
  /// to 90s still held. At 4×, sought to the end (it ends) and back 5s to
  /// 115s, then played, the last frame shows in
  /// about 1.25s, not 5s; the replay ends at "2:00 / 2:00" with Play, which
  /// starts it over. Its × cancels the replay: the bar hidden, the
  /// session's finished view whole again (its last frame, succeeded), focus
  /// on Replay; Replay again starts a new replay from 0:00. The speed is
  /// set back to 1× and the page left freshly loaded.
  func expectReplaySeek(_ page: Page, path: String, replyID: String) async throws {
    let reply = "#locution-\(replyID.uppercased())"
    try await page.addInitScript("""
      if (location.hash === '#seek-test') {
        const Real = window.EventSource
        window.EventSource = class {
          // The reply's replay only; any other stream stays the real one.
          constructor(url, options) {
            if (!String(url).includes('replay=1')) return new Real(url, options)
            this.handlers = {}
            setTimeout(() => {
              const image = document.querySelector('\(reply) .computorium-session-view').dataset.computoriumSessionImage ?? ''
              const frame = (at, fields) => this.emit('chunk', JSON.stringify({ replay_at: String(at), image, image_index: -1, ...fields }))
              this.emit('start', '{"replay":true,"process":"arbitration"}')
              // Every frame at once, as the server sends a replay's.
              frame(0, { type: 'reset', text: '', reset: '1' })
              frame(0, { type: 'chat_template_input', text: '', continues: 'false', reset: '1' })
              frame(0, { type: 'text', text: 'Seek one.' })
              frame(60000, { type: 'chat_template_input', text: '', continues: 'true' })
              frame(60000, { type: 'text', text: 'Seek two.' })
              frame(120000, { type: 'text', text: ' Seek three.', append: '1' })
              frame(120000, { type: 'status', text: 'succeeded', message: '' })
              this.emit('done', '{"status":"passed","error":"","message":"","replayed":"true"}')
            }, 0)
          }
          addEventListener(name, fn) { (this.handlers[name] ??= []).push(fn) }
          emit(name, data) { for (const fn of this.handlers[name] ?? []) fn({ data }) }
          close() {}
        }
      }
      """)
    try await page.openHydrated(path + "?seek=1#seek-test")
    let session = page.locator("\(reply) .computorium-session-view")
    // Drawn hidden with the reply; moved, once shown, to the page's
    // content column.
    try await expect(page.locator("\(reply) .replay-seek-view")).toHaveCount(1)
    try await expect(page.locator("\(reply) .replay-seek-view")).toBeHidden()
    try await expect(page.locator(".replay-seek-view:not([hidden])")).toHaveCount(0)
    let seek = page.locator(".layout-content-area > .replay-seek-view")
    let slider = seek.locator(".replay-seek-slider")
    let toggle = seek.locator(".replay-seek-toggle")
    let time = seek.locator(".replay-seek-time")
    let close = seek.locator(".replay-seek-close")
    _ = try await page.locator("\(reply) .replay-btn").evaluate("el => el.click()")
    try await expect(seek).toBeVisible()
    try await expect(page.locator("\(reply) .replay-seek-view")).toHaveCount(0)
    // One bar, holding all of playback: Pause, track, clock, speed, ×.
    try await expect(page.locator(".replay-seek-view:not([hidden])")).toHaveCount(1)
    try await expect(seek.locator(".replay-speed-view")).toHaveCount(1)
    try await expect(close).toHaveAttribute("aria-label", "Close replay")
    let parts = try await seek.evaluate("""
      el => [...el.children].map(e => e.classList.contains('replay-seek-toggle') ? 'toggle'
        : e.classList.contains('replay-seek-slider') ? 'slider'
        : e.classList.contains('replay-seek-time') ? 'time'
        : e.classList.contains('replay-speed-view') ? 'speed'
        : e.classList.contains('replay-seek-close') ? 'close' : 'other').join(' ')
      """).string
    #expect(parts == "toggle slider time speed close", Comment(rawValue: parts ?? "—"))
    // Sticky at the foot of the viewport over the page, within the
    // content column, wherever the reader has scrolled to.
    let placed = try await seek.evaluate("""
      el => { const s = getComputedStyle(el)
        window.scrollTo(0, 0)
        const r = el.getBoundingClientRect(), column = el.parentElement.getBoundingClientRect()
        return s.position === 'sticky' && Number(s.zIndex) > 0
          && r.top >= 0 && r.bottom <= innerHeight + 1
          && r.left >= column.left - 1 && r.right <= column.right + 1 }
      """).bool
    #expect(placed == true, "The bar sticks to the viewport's foot within the content column")
    // At rest at the page's end, one space above it and below it, to the
    // footer's rule (user, 2026-10-21).
    let spaces = try await seek.evaluate("""
      el => { const section = document.querySelector('.page-section')
        section.style.minHeight = (2 * innerHeight) + 'px'
        window.scrollTo(0, document.documentElement.scrollHeight)
        let above = el.previousElementSibling
        while (above && above.getBoundingClientRect().height === 0) above = above.previousElementSibling
        const bar = el.getBoundingClientRect(), footer = document.querySelector('.layout-footer').getBoundingClientRect()
        const result = [bar.top - above.getBoundingClientRect().bottom, footer.top - bar.bottom]
        section.style.minHeight = ''
        window.scrollTo(0, 0)
        return result }
      """)
    let above = spaces[0].double ?? -1, below = spaces[1].double ?? -2
    #expect(above > 0 && abs(above - below) <= 1, "Equal space above and below the bar: \(above) / \(below)")
    // Escape never stops it: only × closes.
    try await toggle.focus()
    try await page.keyboard.press("Escape")
    try await expect(seek).toBeVisible()
    try await expect(toggle).toHaveAttribute("aria-label", "Pause")
    try await expect(slider).toHaveAttribute("role", "slider")
    try await expect(slider).toHaveAttribute("aria-label", "Replay position")
    try await expect(slider).toHaveAttribute("aria-valuemax", "120000")
    try await expect(slider.locator(".slider-tick")).toHaveCount(1)
    try await expect(toggle).toHaveAttribute("aria-label", "Pause")
    try await expect(toggle.locator("svg.pause-icon-view")).toHaveCount(1)
    try await expect(time).toContainText(" / 2:00")
    try await expect(time).toContainText("0:0")
    try await expect(session).toContainText("Seek one.")
    try await expect(session).not.toContainText("Seek two.")
    // Forward: twelve 5s steps to 60s—its frames, none later.
    try await slider.focus()
    for _ in 0..<12 { try await page.keyboard.press("ArrowRight") }
    try await expect(session).toContainText("Seek two.")
    try await expect(session).not.toContainText("Seek three.")
    try await expect(time).toContainText("1:0")
    // Said in words: a minute and a few seconds of two minutes.
    #expect(try await slider.evaluate("""
      el => { const words = el.getAttribute('aria-valuetext') ?? ''
        return words.startsWith('1 minute') && words.endsWith(' of 2 minutes') }
      """).bool == true, "The position in words")
    // Back to the start: drawn again, without what came after.
    try await page.keyboard.press("Home")
    try await expect(session).not.toContainText("Seek two.")
    try await expect(session).toContainText("Seek one.")
    try await expect(time).toContainText("0:0")
    // Pause holds it where it stands.
    try await toggle.click()
    try await expect(toggle).toHaveAttribute("aria-label", "Play")
    try await expect(toggle.locator("svg.play-icon-view")).toHaveCount(1)
    try await expect(toggle.locator("svg.pause-icon-view")).toHaveCount(0)
    let held = try await slider.getAttribute("aria-valuenow") ?? ""
    try await Task.sleep(for: .milliseconds(800))
    #expect(try await slider.getAttribute("aria-valuenow") == held, "Paused, the position holds")
    // Its rotating marks stand still with it (user, 2026-10-21).
    try await expect(session).toHaveAttribute("data-replay-paused", "true")
    #expect(try await session.evaluate("""
      el => [...el.querySelectorAll('.rotating-sector-shape, .rotating-ring-sector-shape, .rotating-ring-sector-with-disc-ring, .rotating-dotted-ring-sector-shape')]
        .every(shape => getComputedStyle(shape).animationPlayState === 'paused')
      """).bool == true, "Paused, the replayed session's marks are held")
    // A click on the track's 3/4: 90s, still paused.
    let point = try await slider.evaluate("""
      el => { el.scrollIntoView({ block: 'center' }); const track = el.querySelector('.slider-track').getBoundingClientRect()
        return [track.left + track.width * 0.75, track.top + track.height / 2] }
      """)
    try await page.mouse.click(x: point[0].double ?? 0, y: point[1].double ?? 0)
    try await expect(session).toContainText("Seek two.")
    try await expect(session).not.toContainText("Seek three.")
    let clicked = Int(try await slider.getAttribute("aria-valuenow") ?? "") ?? 0
    #expect((86000...94000).contains(clicked), "The track's 3/4 is 90s: \(clicked)")
    try await expect(toggle).toHaveAttribute("aria-label", "Play")
    // At 4×, from 115s: the last frame 5 recorded seconds on, about 1.25s.
    _ = try await seek.locator(".replay-speed-view [data-value='4']").evaluate("el => el.click()")
    try await slider.focus()
    try await page.keyboard.press("End")
    try await page.keyboard.press("ArrowLeft")
    try await expect(session).not.toContainText("Seek three.")
    // A seek brings the session's own end (its process container's foot,
    // above any Drumrolls thread below) to just above the sticky bar, never
    // the page's end (user, 2026-10-22).
    #expect(try await page.evaluate("""
      (() => { const box = document.querySelector('\(reply) .process-container, [data-computorium-core-process]')
        const bar = document.querySelector('.replay-seek-view:not([hidden])')
        if (!box || !bar) return true
        return box.getBoundingClientRect().bottom <= bar.getBoundingClientRect().top + 2 })()
      """, as: Bool.self) == true, "A seek leaves the session's end above the bar")
    _ = try await page.evaluate("""
      (() => { const content = document.querySelector('\(reply) .computorium-session-view')
        window.__soughtFrom = performance.now(); window.__soughtShown = 0
        new MutationObserver(() => {
          if (!window.__soughtShown && content.textContent.includes('Seek three.')) window.__soughtShown = performance.now()
        }).observe(content, { childList: true, subtree: true, characterData: true })
        return true })()
      """, as: Bool.self)
    try await toggle.click()
    // Played again: its marks turn again.
    try await expect(session).not.toHaveAttribute("data-replay-paused", "true")
    try await expect(toggle).toHaveAttribute("aria-label", "Pause")
    try await expect(session, timeout: .seconds(10)).toContainText("Seek three.")
    let waited = try await page.evaluate("Math.round(window.__soughtShown - window.__soughtFrom)", as: Int.self)
    #expect((700...3500).contains(waited), "5 recorded seconds at 4× take about 1.25s, not 5s: \(waited)ms")
    // The end: its status, the clock full, Play to start over.
    try await expect(session).toHaveAttribute("data-computorium-session-status", "succeeded")
    try await expect(time).toHaveText("2:00 / 2:00")
    try await expect(toggle).toHaveAttribute("aria-label", "Play")
    try await expect(seek).toBeVisible()
    try await toggle.click()
    try await expect(toggle).toHaveAttribute("aria-label", "Pause")
    try await expect(session).not.toContainText("Seek two.")
    try await expect(session).toContainText("Seek one.")
    // × cancels it: the bar put away, the session's finished view whole.
    try await close.click()
    try await expect(seek).toBeHidden()
    try await expect(page.locator(".replay-seek-view:not([hidden])")).toHaveCount(0)
    try await expect(session).toContainText("Seek three.")
    try await expect(session).toHaveAttribute("data-computorium-session-status", "succeeded")
    let replay = page.locator("\(reply) .replay-btn")
    try await expect(replay).not.toHaveAttribute("aria-disabled", "true")
    #expect(try await replay.evaluate("el => document.activeElement === el").bool == true, "Focus back on Replay")
    // Replay again: a new replay, from 0:00.
    _ = try await replay.evaluate("el => el.click()")
    try await expect(seek).toBeVisible()
    try await expect(time).toContainText("0:0")
    try await expect(session).toContainText("Seek one.")
    try await expect(session).not.toContainText("Seek two.")
    try await expect(toggle).toHaveAttribute("aria-label", "Pause")
    // 1× again for what follows, and the page as freshly loaded.
    _ = try await seek.locator(".replay-speed-view [data-value='1']").evaluate("el => el.click()")
    #expect(try await page.evaluate("localStorage.getItem('gnorium:replay-speed')", as: String.self) == "1")
    try await page.openHydrated(path)
  }

  /// A long replay's seek bar (user, 2026-10-21) on the reply's replay, its
  /// stream the test's stand-in (at `#scrub-test`): a text block "w0 "
  /// grown by 9,999 `append` deltas ("w1 " … "w9999 "), one every 10
  /// recorded ms, sent 1.5s after Replay is pressed. The bar shows at once
  /// as Replay is pressed, before any frame; End pressed then waits busy
  /// (`aria-busy`) and lands at the end as the frames come—the whole text,
  /// exactly the deltas joined, drawn once. Home and End again (back, then
  /// forward over all 10,000 frames) each land within a second. Played
  /// from 10s, a drag along the track moves the handle at every step
  /// (`aria-valuenow` rising through each), the replay held under the
  /// hand, and the transcript lands at the time let go, playing on.
  func expectReplayScrub(_ page: Page, path: String, replyID: String) async throws {
    let reply = "#locution-\(replyID.uppercased())"
    try await page.addInitScript("""
      if (location.hash === '#scrub-test') {
        const Real = window.EventSource
        window.EventSource = class {
          constructor(url, options) {
            if (!String(url).includes('replay=1')) return new Real(url, options)
            this.handlers = {}
            setTimeout(() => {
              const image = document.querySelector('\(reply) .computorium-session-view').dataset.computoriumSessionImage ?? ''
              const frame = (at, fields) => this.emit('chunk', JSON.stringify({ replay_at: String(at), image, image_index: -1, ...fields }))
              this.emit('start', '{"replay":true,"process":"arbitration"}')
              frame(0, { type: 'reset', text: '', reset: '1' })
              frame(0, { type: 'chat_template_input', text: '', continues: 'false', reset: '1' })
              frame(0, { type: 'text', text: 'w0 ' })
              for (let i = 1; i < 10000; i++) frame(i * 10, { type: 'text', text: 'w' + i + ' ', append: '1' })
              frame(99990, { type: 'status', text: 'succeeded', message: '' })
              this.emit('done', '{"status":"passed","error":"","message":"","replayed":"true"}')
            }, 1500)
          }
          addEventListener(name, fn) { (this.handlers[name] ??= []).push(fn) }
          emit(name, data) { for (const fn of this.handlers[name] ?? []) fn({ data }) }
          close() {}
        }
      }
      """)
    try await page.openHydrated(path + "?scrub=1#scrub-test")
    let session = page.locator("\(reply) .computorium-session-view")
    let seek = page.locator(".layout-content-area > .replay-seek-view")
    let slider = seek.locator(".replay-seek-slider")
    let toggle = seek.locator(".replay-seek-toggle")
    let time = seek.locator(".replay-seek-time")
    let expected = (0..<10000).map { "w\($0) " }.joined()
    let rendered = """
      [...document.querySelectorAll('\(reply) .computorium-session-output-rendered')].map(e => e.textContent).join('').trim()
      """
    // The bar at once, before any frame, its length the session's recorded
    // one where the page knows it.
    _ = try await page.evaluate("(() => { window.__pressedAt = performance.now(); return true })()", as: Bool.self)
    _ = try await page.locator("\(reply) .replay-btn").evaluate("el => el.click()")
    try await expect(seek, timeout: .milliseconds(1000)).toBeVisible()
    let before = try await page.evaluate("""
      (() => { const bar = document.querySelector('.layout-content-area > .replay-seek-view')
        return [performance.now() - window.__pressedAt, bar.dataset.replayDurationMs ?? '',
          bar.querySelector('.replay-seek-slider').getAttribute('aria-valuemax')] })()
      """)
    #expect((before[0].double ?? 9999) < 1500, "The bar shows before the frames come: \(before[0].double ?? -1)ms")
    if let hint = before[1].string, !hint.isEmpty {
      #expect(before[2].string == hint, "Its length the session's recorded one: \(hint)")
    }
    // End before the frames (where the page knows the length): busy, the
    // handle there; it lands at the end as they come.
    try await slider.focus()
    if (Int(before[1].string ?? "") ?? 0) > 0 {
      try await page.keyboard.press("End")
      try await expect(seek).toHaveAttribute("aria-busy", "true")
      try await expect(slider).toHaveAttribute("aria-valuenow", before[1].string ?? "")
    } else {
      try await expect(slider, timeout: .seconds(5)).toHaveAttribute("aria-valuemax", "99990")
      try await page.keyboard.press("End")
    }
    try await expect(session, timeout: .seconds(10)).toHaveAttribute("data-computorium-session-status", "succeeded")
    try await expect(seek).not.toHaveAttribute("aria-busy", "true")
    try await expect(time).toHaveText("1:39 / 1:39")
    #expect(try await page.evaluate(rendered, as: String.self) == expected.trimmingCharacters(in: .whitespaces),
      "The transcript is the deltas joined, exactly")
    // Back to the start, over all 10,000 frames again, and back 30s from a
    // checkpoint: each lands within a second.
    var landed = ""
    for key in ["Home", "End", "PageDown"] {
      let result = try await page.evaluate("""
        (async () => { const slider = document.querySelector('.layout-content-area > .replay-seek-view .replay-seek-slider')
          slider.focus()
          const start = performance.now()
          slider.dispatchEvent(new KeyboardEvent('keydown', { key: '\(key)', bubbles: true }))
          await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))
          const took = performance.now() - start
          return [took, \(rendered)] })()
        """)
      let took = result[0].double ?? 9999
      #expect(took < 1000, "\(key) lands within a second over 10,000 frames: \(took)ms")
      landed = result[1].string ?? ""
    }
    // 30s back from the end: 69,990ms, every word by then and none after.
    let prefix = (0..<7000).map { "w\($0) " }.joined()
    #expect(landed.hasPrefix(prefix.trimmingCharacters(in: .whitespaces)), "Drawn again from a checkpoint, the same text")
    #expect(!landed.contains("w7100 "), "Nothing from after the time sought")
    // Played from 10s, then dragged along the track: the handle at every
    // step and the transcript with it, as a video's frame follows its
    // scrubber (user, 2026-10-21); the clock held under the hand, landing
    // where it is let go.
    try await slider.focus()
    try await page.keyboard.press("Home")
    for _ in 0..<2 { try await page.keyboard.press("ArrowRight") }
    try await expect(toggle).toHaveAttribute("aria-label", "Pause")
    let track = try await slider.evaluate("""
      el => { el.scrollIntoView({ block: 'center' }); const r = el.querySelector('.slider-track').getBoundingClientRect()
        return [r.left, r.width, r.top + r.height / 2] }
      """)
    let left = track[0].double ?? 0, width = track[1].double ?? 0, y = track[2].double ?? 0
    try await page.mouse.down(x: left + width * 0.2, y: y)
    var values: [Int] = []
    var lastWords: [String] = []
    for step in 1...8 {
      // Back over the middle steps too: drawn again from a checkpoint.
      let fraction = step == 5 ? 0.32 : 0.2 + 0.05 * Double(step)
      try await page.mouse.move(x: left + width * fraction, y: y)
      _ = try await page.evaluate(
        "new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(() => r(true)))))",
        as: Bool.self)
      values.append(Int(try await slider.getAttribute("aria-valuenow") ?? "") ?? -1)
      lastWords.append(try await page.evaluate("(\(rendered)).split(' ').pop()", as: String.self))
    }
    #expect(values.allSatisfy { $0 >= 0 } && Set(values).count == values.count, "The handle moves at every step: \(values)")
    // The transcript at the handle's time at every step, the handle not let
    // go: the last word the last recorded by then (one every 10ms).
    #expect(lastWords == values.map { "w\($0 / 10)" }, "The transcript follows the handle: \(values) → \(lastWords)")
    #expect(try await slider.getAttribute("data-dragging") == "true", "Held under the hand")
    // Held: its marks stand still with it.
    #expect(try await session.getAttribute("data-replay-paused") == "true", "The session's marks held while dragged")
    let held = try await page.evaluate(rendered, as: String.self)
    try await Task.sleep(for: .milliseconds(300))
    #expect(try await page.evaluate(rendered, as: String.self) == held, "The clock waits while dragged")
    try await page.mouse.up(x: left + width * 0.6, y: y)
    let dropped = Int(try await slider.getAttribute("aria-valuenow") ?? "") ?? 0
    #expect((55000...65000).contains(dropped), "Let go at the track's 3/5: \(dropped)")
    // There: every word by then, none from 5s later; playing on.
    let word = dropped / 10
    try await expect(session).toContainText("w\(word) ")
    #expect(try await page.evaluate(rendered, as: String.self).contains("w\(word + 500) ") == false,
      "Nothing from after the time let go")
    try await expect(toggle).toHaveAttribute("aria-label", "Pause")
    try await expect(session).not.toHaveAttribute("data-replay-paused", "true")
    try await expect(session, timeout: .seconds(3)).toContainText("w\(word + 50) ")
    try await page.openHydrated(path)
  }

  /// The madrigal page, its arbitration session running, its reply's watch
  /// the test's stand-in (as `expectRenewKeepsArbitrating`'s, at
  /// `#suggest-test`): a suggested revision is filed (a row by the
  /// throwaway admin, as the session's tool files gnorium's), then the
  /// stream brings the `suggest_revision` call's result. Its act ("…
  /// suggested revision ‹id›") is in the thread's timeline without a
  /// reload, once, linked to its revision, after the entries before it.
  func expectSuggestedRevisionJoinsTheThread(
    _ page: Page, path: String, replyID: String, madrigalID: String, by userID: String
  ) async throws {
    try await page.addInitScript("""
      if (location.hash === '#suggest-test') {
        const Real = window.EventSource
        window.EventSource = class {
          constructor(url, options) {
            if (!String(url).includes('/arbitration/stream')) return new Real(url, options)
            this.url = url; this.handlers = {}
            setTimeout(() => { this.emit('start', '{"watch":true,"process":"arbitration"}'); window.__suggestStream = this }, 0)
          }
          addEventListener(name, fn) { (this.handlers[name] ??= []).push(fn) }
          emit(name, data) { for (const fn of this.handlers[name] ?? []) fn({ data }) }
          close() {}
        }
      }
      """)
    let revisionID = UUID().uuidString
    defer { _ = try? TestAdmin.query("DELETE FROM revisions WHERE id = '\(revisionID)'") }
    // A query makes it a new document: the page the renew check left is at the
    // same address, and a hash alone is no navigation (no reload, no init script).
    try await page.openHydrated(path + "?suggest=1#suggest-test")
    #expect(try await page.evaluate("""
      (async () => { for (let i = 0; i < 50 && !window.__suggestStream; i++) await new Promise(r => setTimeout(r, 100)); return !!window.__suggestStream })()
      """, as: Bool.self), "The reply's watch is attached")
    let act = page.locator(".thread-timeline #revision-\(revisionID)")
    try await expect(act).toHaveCount(0)
    _ = try await page.evaluate("(() => { window.__notReloaded = true; return true })()", as: Bool.self)
    _ = try TestAdmin.query("""
      INSERT INTO revisions (id, revisable_type, revisable_id, prompt_changes_json, status, requested_by_user_id, created_at)
      VALUES ('\(revisionID)', 'bibliographicMadrigal', '\(madrigalID)', '[]', 'pending', '\(userID)', now())
      """)
    _ = try await page.evaluate("""
      (() => { const label = document.querySelector('#locution-\(replyID.uppercased()) .computorium-session-view')
          .dataset.computoriumSessionImage ?? ''
        window.__suggestStream.emit('chunk', JSON.stringify({ type: 'tool', name: 'suggest_revision', arguments: '{}',
          status: 'ok', call_id: 'web_tests_suggest', result: '{"revision":"\(revisionID)"}', image: label }))
        return true })()
      """, as: Bool.self)
    try await expect(act, timeout: .seconds(15)).toHaveCount(1)
    try await expect(act.locator(".thread-event-line")).toContainText("suggested revision")
    try await expect(act.locator(".thread-event-line a[href$='/revisions/\(revisionID)']")).toHaveCount(1)
    // In its place: the last entry, its timestamp's ⓘ live.
    #expect(try await page.evaluate("""
      (() => { const entries = [...document.querySelectorAll('.thread-timeline > *')]
        return entries[entries.length - 1]?.id === 'revision-\(revisionID)' })()
      """, as: Bool.self), "The act is the thread's last entry")
    #expect(try await page.evaluate("window.__notReloaded === true", as: Bool.self), "The act arrives without a reload")
    // The route behind it (`?part=thread`): the thread alone, with the act,
    // none of the page around it.
    let fragment = try await page.evaluate(
      "fetch(location.pathname + '?part=thread').then(r => r.text())", as: String.self)
    #expect(fragment.contains("id=\"revision-\(revisionID)\"") || fragment.lowercased().contains("id=\"revision-\(revisionID.lowercased())\""),
      "the thread fragment holds the revision's act")
    #expect(fragment.contains("suggested revision"), "the fragment says what was done")
    #expect(fragment.contains("thread-view"), "the fragment is the thread")
    for chrome in ["<html", "<!DOCTYPE", "layout-main", "disputorium-core-view", "artifact-view"] {
      #expect(!fragment.contains(chrome), "the fragment carries the page's chrome: \(chrome)")
    }
    try await page.expectNoErrors()
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
  /// is refused under the box. A call may tick nothing (user, 2026-10-21):
  /// no refusal. Submit attaches the ticked items in order, and the call names
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
        let roster = page.locator("#madrigal-images")
        let rows = roster.locator(".roster-row")
        try await expect(rows).toHaveCount(4)
        // Commit mode: the three read pages locked, the blank one ticked for.
        try await expect(rows.nth(0).locator(".checkbox-icon-wrapper")).toBeHidden()
        try await expect(rows.nth(3).locator(".checkbox-icon-wrapper")).toBeVisible()
        let body = page.locator("#thread-locution-body")
        try await body.focus()
        try await expect(roster).toHaveAttribute("data-mode", "attach")
        try await expect(rows.nth(0).locator(".checkbox-icon-wrapper")).toBeVisible()
        try await expect(rows.nth(0).locator(".checkbox-input")).toBeChecked(false)
        try await expect(rows.nth(0).locator(".checkbox-input")).toHaveAttribute("name", "evidence[]")
        try await expect(rows.nth(0).locator(".checkbox-input")).toHaveAttribute("form", "thread-form")
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
        try await page.locator(".thread-title, h3").first.click()
        try await expect(roster).toHaveAttribute("data-mode", "commit")
        try await expect(rows.nth(0).locator(".checkbox-icon-wrapper")).toBeHidden()
        try await expect(rows.nth(0).locator(".checkbox-input")).toBeChecked(false)
        try await expect(rows.nth(0).locator(".checkbox-input")).toHaveAttribute("form", "commit-form")
        try await expect(rows.nth(3).locator(".checkbox-icon-wrapper")).toBeVisible()
        try await body.fill("@gnorium Compare these two pages.")
        try await expect(roster).toHaveAttribute("data-mode", "attach")
        try await expect(rows.nth(0).locator(".checkbox-input")).toBeChecked(false)
        try await rows.nth(0).locator("input").click()
        try await rows.nth(1).locator("input").click()
        try await page.locator(".thread-submit").click()
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
        try await expect(page.locator(".locution-header").first).toContainText("on Image 1")
        try await expect(page.locator(".locution-header").first).not.toContainText("Image 2")
        let both = try await page.locator(".locution-attachments").first.evaluate("""
          el => [...el.querySelectorAll('.locution-attachments-item')].map(item => {
            const path = item.querySelector('.thread-path')
            return path ? [...path.children].filter(c => !c.classList.contains('breadcrumb-separator-view'))
              .map(c => c.textContent.trim()).join(' › ') : item.querySelector('a').textContent.trim() }).join(' | ')
          """).string
        #expect(both == "Image 1 | Image 2", Comment(rawValue: both ?? "—"))
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
        let body = page.locator("#thread-locution-body")
        try await body.fill("The title reads oddly.")
        try await page.locator(".thread-submit").click()
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
        let page2 = page.locator("#madrigal-images .roster-row").nth(1).locator("input")
        try await page2.click()
        try await expect(page2).toBeChecked()
        try await page.locator(".thread-submit").click()
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
        try await expect(call.locator(".locution-header")).toContainText("on Image 1")
        try await expect(call.locator(".locution-header")).not.toContainText("Image 2")
        try await expect(call.locator(".locution-body-rendered")).toHaveText("@gnorium Is the title right?")
        let attachments = call.locator(".list-sentence-view.locution-attachments")
        try await expect(attachments).toContainText("Attached ")
        let crumbs = try await attachments.evaluate("""
          el => [...el.querySelectorAll('.locution-attachments-item')].map(item => {
            const path = item.querySelector('.thread-path')
            return path ? [...path.children].filter(c => !c.classList.contains('breadcrumb-separator-view'))
              .map(c => c.textContent.trim()).join(' › ') : item.querySelector('a').textContent.trim() }).join(' | ')
          """).string
        let joined = try await attachments.evaluate(
          "e => e.querySelector('.list-sentence-lead').textContent + '|' + [...e.childNodes].filter(n => n.nodeType === 3).map(n => n.textContent).join('|')").string
        #expect(joined == "Attached| |, |, and |.", Comment(rawValue: joined ?? "—"))
        // Metadata by its node's heading, as its accordion names it.
        #expect(crumbs?.hasPrefix("Metadata › ") == true && crumbs?.hasSuffix(" | Image 2 | Locution \(firstID)") == true
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

  /// A crop box on an attached image (user, 2026-10-10): in attach mode
  /// the reader's image of a ticked item takes a dragged box; the call
  /// stores it in the 0–1000 space by the item's id, and its locution shows
  /// the numbers beside the item's link.
  @Test(arguments: [BrowserEngine.chrome])
  func aCropBoxDrawnOnAnAttachedImageRidesWithTheCall(engine: BrowserEngine) async throws {
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
        let roster = page.locator("#madrigal-images")
        let body = page.locator("#thread-locution-body")
        // Submit at the right, under the box's right edge (user, 2026-10-10).
        let field = try #require(try await body.boundingBox())
        let submit = try #require(try await page.locator(".thread-submit").boundingBox())
        #expect(abs((submit.x + submit.width) - (field.x + field.width)) < 1, "Submit under the box's right edge")
        #expect(submit.x > field.x + 1, "Submit is not at the left")
        try await body.fill("@gnorium Read the line in the box.")
        try await expect(roster).toHaveAttribute("data-mode", "attach")
        try await roster.locator(".roster-row").nth(0).locator("input").click()
        try await expect(roster.locator(".roster-row").nth(0).locator(".checkbox-input")).toBeChecked()
        // The page images on; the ticked image takes a box.
        let toggle = viewer.locator(".artifact-canvas-toggle button")
        if try await toggle.getAttribute("aria-pressed") != "true" { try await toggle.click() }
        let image = viewer.locator(".canvas-view[data-active='true'] .canvas-viewport")
        try await expect(image).toHaveAttribute("data-cropping", "true")
        let box = try #require(try await image.boundingBox())
        let (x0, y0) = (box.x + box.width * 0.4, box.y + box.height * 0.4)
        let (x1, y1) = (box.x + box.width * 0.6, box.y + box.height * 0.55)
        try await page.mouse.move(x: x0, y: y0)
        try await page.mouse.down(x: x0, y: y0)
        for step in 1...5 {
          try await page.mouse.move(x: x0 + (x1 - x0) * Double(step) / 5, y: y0 + (y1 - y0) * Double(step) / 5)
        }
        try await page.mouse.up(x: x1, y: y1)
        try await expect(image.locator(".canvas-crop")).toBeVisible()
        try await expect(roster).toHaveAttribute("data-mode", "attach")
        try await page.locator(".thread-submit").click()
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
  func arbitrationPromptsLeadBothProcessesAndAreNotRevisedOnObjects(engine: BrowserEngine) async throws {
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
        // The process after Arbitration: the overture's page's calibration,
        // filled; the epilogue's completed translation sends nothing, so it
        // has no accordion (user, 2026-10-17).
        let cases: [(String, String?, String)] = [
          (scratch.overturePath, "Calibration", "bibliographic_arbitration"),
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
            try await expect(sections.nth(index).getByText("System Prompt", exact: true)).toHaveCount(1)
            // Its task filled as sent, or its template where none can be,
            // and its autocompaction prompt, one text with no variables
            // (user, 2026-10-24); a template lists its variables.
            let titles = sections.nth(index).locator(".prompt-preview-title-words")
            try await expect(titles.filter(hasText: "Task Prompt")).toHaveCount(1)
            try await expect(titles.filter(hasText: "Template")).toHaveCount(0)
            try await expect(sections.nth(index).locator(".prompt-variables-view")).toHaveCount(filled ? 0 : 1)
            try await expect(sections.nth(index).getByText("Autocompaction Prompt", exact: true)).toHaveCount(1)
          }
          // Its Revise page holds no prompt: a process's prompts are revised
          // on a palinode of their vignette (user, 2026-10-20).
          try await page.openHydrated(path.split(separator: "?").first.map(String.init)! + "/revise")
          try await expect(page.locator(".prompt-revision-fields-view")).toHaveCount(0)
          try await expect(page.locator("textarea[name='prompt-system-\(slot)']")).toHaveCount(0)
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
