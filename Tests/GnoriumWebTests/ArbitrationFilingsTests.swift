import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A call to gnorium files figurants and palinodes (user, 2026-11-02): each
/// filing is a line in the call's thread, in the thread's own event words,
/// bylined by gnorium: "gnorium submitted figurant {id} creating overture
/// {id}", each id linked to its page (a lexico-record's amendment's overture
/// to its own). The filings are seeded as their rows; no model or provider
/// is called.
@Suite("Arbitration filings")
struct ArbitrationFilingsTests {
  @Test(arguments: [BrowserEngine.chrome])
  func eachFilingIsALineInTheCallsThread(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reading = try ScratchReading(
      owner: admin,
      tei: #"<TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt><title>t</title></titleStmt></fileDesc></teiHeader><text><body><pb n="1"/><p>Filed from a call.</p></body></text></TEI>"#)
    let object = reading.madrigalID
    let figurant = UUID(), overture = UUID(), palinode = UUID(), amendment = UUID()
    func remove() {
      _ = try? TestAdmin.query("DELETE FROM arbitration_filings WHERE locutable_id = '\(object)';")
      reading.remove()
    }
    do {
      func row(_ filed: String, _ kind: String, _ id: UUID, _ type: String, _ created: UUID, _ at: String) -> String {
        """
        INSERT INTO arbitration_filings (id, locution_id, arbitration_session_id, locutable_type, locutable_id, filed,
          kind, filed_id, created_type, created_id, filed_at)
          VALUES ('\(UUID().uuidString)', '\(UUID().uuidString)', '\(UUID().uuidString)',
            'bibliographic_madrigal', '\(object)', '\(filed)', '\(kind)', '\(id.uuidString)', '\(type)',
            '\(created.uuidString)', \(at));
        """
      }
      _ = try TestAdmin.query(
        "BEGIN;\n" + row("figurant", "bibliographic", figurant, "bibliographicOverture", overture, "now() - interval '2 minutes'")
          + row("palinode", "lexicographic", palinode, "lexicographicRecordOverture", amendment, "now() - interval '1 minute'")
          + "\nCOMMIT;")
      try await withPage(engine, gnorium, cookies: [admin.cookie]) { page in
        try await page.openHydrated(reading.path)
        let filed = page.locator(".thread-event-line")
          .filter(hasText: "submitted figurant \(figurant.uuidString) creating overture \(overture.uuidString)")
        try await expect(filed, timeout: .seconds(15)).toHaveCount(1)
        try await expect(filed).toContainText("gnorium")
        try await expect(filed.locator("a[href='/mission-control/figurants/bibliographic/\(figurant.uuidString)']"))
          .toHaveCount(1)
        try await expect(filed.locator("a[href='/mission-control/overtures/bibliographic/\(overture.uuidString)']"))
          .toHaveCount(1)
        let amended = page.locator(".thread-event-line")
          .filter(hasText: "submitted palinode \(palinode.uuidString) creating overture \(amendment.uuidString)")
        try await expect(amended).toHaveCount(1)
        try await expect(amended.locator("a[href='/mission-control/palinodes/lexicographic/\(palinode.uuidString)']"))
          .toHaveCount(1)
        try await expect(
          amended.locator("a[href='/mission-control/overtures/lexicographic/amendments/\(amendment.uuidString)']")
        ).toHaveCount(1)
        // In thread order: the figurant first, filed first.
        let order = try await page.evaluate(
          "[...document.querySelectorAll('.thread-event-line')].map((l) => l.textContent).filter((t) => t.includes('submitted figurant') || t.includes('submitted palinode')).map((t) => t.includes('figurant') ? 'f' : 'p').join('')"
        ).string
        #expect(order == "fp", "thread order: \(String(describing: order))")
        try await page.expectNoErrors()
      }
    } catch {
      remove()
      try await admin.remove(after: error)
    }
    remove()
    try await admin.remove()
  }
}
