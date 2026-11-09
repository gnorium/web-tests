import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An object's Drumrolls as they happen (user, 2026-11-09: "drumrolls dont
/// update live, went from 774 to 847 on reload"): while an antiphon's page
/// session runs, what it files into the Disputorium—a figurant creating its
/// overture—posts its line and moves the Drumrolls count with no reload,
/// from the watch stream's own word (`DrumrollSignal`, `Drumrolls.tally`).
/// Chrome headless.
@Suite("Drumrolls live", .serialized)
struct DrumrollsLiveTests {
  @Test(arguments: [BrowserEngine.chrome])
  func aSessionsFilingPostsItsLineAndCountLive(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphonID = UUID().uuidString
    let instanceID = UUID().uuidString
    let submission = UUID().uuidString
    let figurant = UUID().uuidString
    let overture = UUID().uuidString
    let head = "md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid"
    let batch = "(SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID)')"
    func cleanUp() async throws {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM lexicographic_overtures WHERE id = '\(overture)';
        UPDATE lexicographic_figurants SET discarded_at = now(), discarded_by = '\(admin.username)'
          WHERE id = '\(figurant)' AND discarded_at IS NULL;
        COMMIT;
        """)
      _ = try? TestAdmin.query(
        SessionTrace.delete(table: "bibliographic_explication_nocturne_instances", where: "id='\(instanceID)'"))
      _ = try? TestAdmin.query(
        "DELETE FROM bibliographic_explication_nocturnes WHERE id = \(head); DELETE FROM bibliographic_antiphons WHERE id='\(antiphonID)';")
      work.remove()
      try await admin.remove()
    }
    do {
      let user = try admin.column("id")
      // Running, its lease held, so its page watches it and no worker of the
      // test's server takes it up; one page session running.
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, image_service_ids_json,
          processing_status, claimed_until, claimed_by)
          VALUES ('\(antiphonID)', '\(work.madrigalID)', '\(user)', '[]', 'explicating', now() + interval '10 minutes',
            'web-tests');
        INSERT INTO bibliographic_explication_nocturnes (id, bibliographic_antiphon_id, submission_id, process, frame, instance_count)
          VALUES (\(head), '\(antiphonID)', \(batch), 'explication', '1', 1);
        INSERT INTO bibliographic_explication_nocturne_instances (id, nocturne_id, instance, provider, model, result, nocturne_batch_id, created_at)
          VALUES ('\(instanceID)', \(head), 1, 'DeepSeek', 'deepseek-flash', 'running', gen_random_uuid(), now());
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/antiphons/bibliographic/\(antiphonID)")
        let count = page.locator(".thread-count[data-events-only='true']")
        try await expect(count).toBeAttached()
        let before = try await count.textContent()
        let line = page.locator("[id='drumroll-submitted-\(overture)']")
        try await expect(line).toHaveCount(0)

        // The session files a sentiment: its figurant and the overture it creates.
        let form = #"{"title":"webtestslive","languageCode":"eng","class":"noun","origin":{"etymons":[],"citations":[],"derivation":""}}"#
        _ = try TestAdmin.query(
          """
          BEGIN;
          INSERT INTO submissions (id, user_id) VALUES ('\(submission)', '\(user)');
          INSERT INTO lexicographic_figurants (id, batch_id, language, order_in_batch, processing_status,
            title_form_json, anchors_json, explication_nocturne_instance_id, created_at)
            VALUES ('\(figurant)', '\(submission)', 'eng', 0, 'pending', '\(form)', '[]', '\(instanceID)', now());
          INSERT INTO lexicographic_overtures (id, lexicographic_figurant_id, title_form_json, anchors_json, created_at)
            VALUES ('\(overture)', '\(figurant)', '\(form)', '[]', now());
          COMMIT;
          """)
        // Its line and the count, with no reload.
        try await expect(line, timeout: .seconds(15)).toHaveCount(1)
        try await expect(line).toContainText("submitted")
        try await expect(count).not.toHaveText(before)
        try await page.expectNoErrors()
      }
      try await cleanUp()
    } catch {
      do { try await cleanUp() } catch let removal {
        throw WebTestError("\(error)\n…and cleaning up failed too: \(removal)")
      }
      throw error
    }
  }
}
