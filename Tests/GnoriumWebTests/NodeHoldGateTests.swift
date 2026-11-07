import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Two objects never hold one node (user, 2026-11-06), and a page never
/// offers what would be refused: an action that would open a second object
/// on a held node—a discarded amendment's Recover beside the open one
/// holding its digitization—stays enabled, and pressed, says why in an
/// alert above the actions, the holder's whole UUID linked to its page, and
/// posts nothing (`ActionGateView`); a Commit or Permit refused for a hold
/// says the same. Sent without the client, the server's refusal opens the
/// page on that alert (`#refused-<id>-<verb>`), never an error page. The
/// scratch work's digitization is the node, held by an amendment's open
/// madrigal; the other amendment's madrigal on it was discarded.
@Suite("Node hold gate", .serialized)
struct NodeHoldGateTests {
  @Test(arguments: [BrowserEngine.chrome])
  func anActionOnAHeldNodeSaysWhyAndPostsNothing(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let user = try admin.column("id")
    let holder = UUID().uuidString
    let discarded = UUID().uuidString
    let holderPath = "/mission-control/madrigals/bibliographic/\(holder)"
    let discardedPath = "/mission-control/madrigals/bibliographic/\(discarded)"
    func clean() {
      // Its Palinodes are submitted input, frozen: they stay.
      _ = try? TestAdmin.query(
        """
        DELETE FROM bibliographic_madrigals WHERE id IN ('\(holder)', '\(discarded)');
        """)
    }
    do {
      // Two amendments of the digitization, each reopening the version as a
      // madrigal as Submit Amendment does (`MissionControlController
      // .reopen`): one open, one discarded.
      let digitization = """
        (SELECT (e.value ->> 'uuid')::uuid FROM biblio_record_versions v
          CROSS JOIN LATERAL jsonb_each(v.shape_json::jsonb) e
          WHERE v.id = '\(work.versionID)' AND e.key LIKE 'manifest-%')
        """
      func reopening(_ id: String, discarded: Bool) -> String {
        let palinode = UUID().uuidString
        let state = discarded ? "'discarded', now(), '\(admin.username)'" : "'pending', NULL, NULL"
        return """
          INSERT INTO bibliographic_palinodes (id, biblio_record_id, biblio_record_version_id, submitted_by_user_id, shape_json, metadata_json, created_at)
            SELECT '\(palinode)', v.biblio_record_id, v.id, '\(user)', v.shape_json, v.metadata_json, now()
            FROM biblio_record_versions v WHERE v.id = '\(work.versionID)';
          INSERT INTO bibliographic_madrigals (id, thread_id, bibliographic_palinode_id, biblio_record_id, proposed_content_json, metadata_json, shape_json, held_testament_uuid, processing_status, discarded_at, discarded_by, created_at, updated_at)
            SELECT '\(id)', '\(id)', '\(palinode)', v.biblio_record_id, m.proposed_content_json, v.metadata_json, v.shape_json, \(digitization), \(state), now(), now()
            FROM biblio_record_versions v JOIN bibliographic_madrigals m ON m.id = v.bibliographic_madrigal_id
            WHERE v.id = '\(work.versionID)';
          """
      }
      _ = try TestAdmin.query(
        "BEGIN;\n" + reopening(holder, discarded: false) + reopening(discarded, discarded: true) + "COMMIT;")
      let held = "Its testament is held by open madrigal \(holder): permit, commit or discard that one first."
      func status(_ id: String) throws -> String {
        try TestAdmin.query("SELECT processing_status FROM bibliographic_madrigals WHERE id = '\(id)'")
          .trimmingCharacters(in: .whitespacesAndNewlines)
      }

      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        // Its Recover: enabled, its alert hidden until pressed; pressed, the
        // alert names the holder, linked, and nothing is posted.
        try await page.openHydrated(discardedPath)
        let recover = page.locator("button[form='madrigal-recover']")
        let alert = page.locator(".action-gate-alert").filter(hasText: held)
        try await expect(recover).toBeEnabled()
        try await expect(alert).toBeHidden()
        try await recover.click()
        try await expect(alert).toBeVisible()
        try await expect(alert.locator("a")).toHaveAttribute("href", holderPath)
        try await expect(alert.locator("a")).toHaveText(holder)
        #expect(try status(discarded) == "discarded", "nothing posted")
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
      }
      // Without the client (the form sent as a browser sends it): the
      // server refuses, and answers with the page at that alert.
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated(discardedPath)
        _ = try await page.evaluate(
          "(() => { HTMLFormElement.prototype.submit.call(document.getElementById('madrigal-recover')); return 1 })()",
          as: Int.self)
        let alert = page.locator("#refused-\(discarded)-recover")
        try await expect(alert, timeout: .seconds(15)).toBeVisible()
        try await expect(alert).toContainText(held)
        let at = try await page.url()
        #expect(at.hasSuffix("\(discardedPath)#refused-\(discarded)-recover"), "At the alert: \(at)")
        #expect(try status(discarded) == "discarded", "nothing recovered")
      }

      // Two open on it (as dev's pair were, opened before the rule): the
      // holder's Permit names the other, and posts nothing; sent anyway,
      // the page opens at the alert.
      _ = try TestAdmin.query(
        """
        UPDATE bibliographic_madrigals SET processing_status = 'pending', discarded_at = NULL, discarded_by = NULL
          WHERE id = '\(discarded)';
        """)
      let other = "Its testament is held by open madrigal \(discarded): permit, commit or discard that one first."
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated(holderPath)
        let permit = page.locator("button[form='madrigal-permit']")
        // Commit and Permit are both gated by the hold: Permit's own alert.
        let alert = page.locator("#refused-\(holder)-permit")
        try await expect(permit).toBeEnabled()
        try await expect(alert).toBeHidden()
        try await permit.click()
        try await expect(alert).toBeVisible()
        try await expect(alert).toContainText(other)
        try await expect(alert.locator("a")).toHaveAttribute("href", discardedPath)
        #expect(try status(holder) == "pending", "nothing posted")
        _ = try await page.evaluate(
          "(() => { HTMLFormElement.prototype.submit.call(document.getElementById('madrigal-permit')); return 1 })()",
          as: Int.self)
        let landed = page.locator("#refused-\(holder)-permit")
        try await expect(landed, timeout: .seconds(15)).toBeVisible()
        try await expect(landed).toContainText(other)
        #expect(try status(holder) == "pending", "nothing permitted")
        try await page.expectNoErrors()
      }
    } catch {
      clean()
      work.remove()
      try await admin.remove(after: error)
    }
    clean()
    work.remove()
    try await admin.remove()
  }
}
