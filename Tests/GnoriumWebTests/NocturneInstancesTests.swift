import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A nocturne holds its instances (user, 2026-10-23): its Drumroll lines say
/// "instance n" for every instance, and the page shows that word only once
/// the nocturne holds a second. Chrome headless.
@Suite("Nocturne instances", .serialized)
struct NocturneInstancesTests {
  /// An antiphon with one nocturne (page "1") of `instances` finished
  /// instances; each instance word its Drumroll thread draws is hidden or not
  /// (`hidden`).
  private func check(instances: Int, hidden: Bool, engine: BrowserEngine) async throws {
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphonID = UUID().uuidString.lowercased()
    let instanceIDs = (0..<instances).map { _ in UUID().uuidString.lowercased() }
    let head = "md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid"
    let batch = "(SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())')"
    func cleanUp() async throws {
      for id in instanceIDs {
        _ = try? TestAdmin.query(SessionTrace.delete(table: "bibliographic_explication_nocturne_instances", where: "id='\(id)'"))
      }
      _ = try? TestAdmin.query(
        "DELETE FROM bibliographic_explication_nocturnes WHERE id = \(head); DELETE FROM bibliographic_antiphons WHERE id='\(antiphonID)';")
      work.remove()
      try await admin.remove()
    }
    do {
      let user = try admin.column("id")
      var statements = """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, image_service_ids_json, processing_status)
          VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO bibliographic_explication_nocturnes (id, bibliographic_antiphon_id, submission_id, process, image, instance_count)
          VALUES (\(head), '\(antiphonID)', \(batch), 'explication', '1', \(instances));
        """
      for (index, id) in instanceIDs.enumerated() {
        statements += """

          INSERT INTO bibliographic_explication_nocturne_instances (id, nocturne_id, submission_id, process, image, instance, provider, model, result, nocturne_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
            VALUES ('\(id)', \(head), \(batch), 'explication', '1', \(index + 1), 'DeepSeek', 'deepseek-flash', 'passed', gen_random_uuid(), '\(antiphonID)', 300, now() - interval '\(instances - index) minutes');
          \(try SessionTrace.append([["type": "text", "content": "Instance \(index + 1)."]], table: "bibliographic_explication_nocturne_instances", id: id))
          """
      }
      _ = try TestAdmin.query(statements + "\nCOMMIT;")
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/antiphons/bibliographic/\(antiphonID)")
        let words = page.locator(".thread-event-instance")
        try await expect(words).toHaveCount(instances)
        let shown = try await page.evaluate(
          "[...document.querySelectorAll('.thread-event-instance')].map(w => getComputedStyle(w).display)",
          as: [String].self)
        #expect(shown.count == instances)
        #expect(shown.allSatisfy { ($0 == "none") == hidden }, "\(shown)")
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

  @Test(arguments: [BrowserEngine.chrome])
  func aNocturneWithOneInstanceSaysNone(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    try await check(instances: 1, hidden: true, engine: engine)
  }

  @Test(arguments: [BrowserEngine.chrome])
  func aSecondInstanceRevealsTheWordOnEveryLine(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    try await check(instances: 2, hidden: false, engine: engine)
  }
}
