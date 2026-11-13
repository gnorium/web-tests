import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A pending quote whose sentence crosses two images (user, 2026-11-01): an
/// origin's evidence names it by its testament's Source URL, images 1 and 2
/// and its sentence, before that testament is permitted. Its madrigal's
/// Permit indexes the version in the quotes service, and the quote is found
/// as its opening on image 1 and the rest on image 2: one anchor over both
/// (`endImageID`), no longer pending.
///
/// Needs the quotes service the server under test reads
/// (`GNORIUM_QUOTES_URL`, default http://127.0.0.1:8006); cancelled when
/// none answers. A throwaway admin owns every scratch row, removed after.
@Suite("Pending quote resolution", .serialized)
struct PendingQuoteResolutionTests {
  static let opening = "Hamlet revenge cried the"
  static let rest = "ghost at the gate"

  /// Two pages, the sentence split over the page break.
  static func tei(_ first: String, _ second: String) -> String {
    #"<TEI><text><body><pb n="1" facs="\#(first)/full/1300,/0/default.jpg"/><p><s>A night of watching.</s> <s part="I">\#(opening)</s></p>"#
      + #"<pb n="2" facs="\#(second)/full/1300,/0/default.jpg"/><p><s part="F">\#(rest)</s> <s>Then silence.</s></p></body></text></TEI>"#
  }

  @Test(arguments: [BrowserEngine.chrome])
  func aSentenceOverTwoImagesResolvesToOneAnchor(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    guard await OriginEvidenceTests.post("/forms", ["forms": ["x"], "language_code": "eng"]) != nil else {
      try Test.cancel("No quotes service answers at \(OriginEvidenceTests.quotesURL) (GNORIUM_QUOTES_URL).")
    }
    let suffix = String(UUID().uuidString.prefix(8)).lowercased()
    let first = "https://web-tests.invalid/iiif/pending-\(suffix)-p1"
    let second = "https://web-tests.invalid/iiif/pending-\(suffix)-p2"
    let source = "https://web-tests.invalid/pending-\(suffix).json"
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    var reading: ScratchReading?
    var holder: ScratchOverture?
    func clean() {
      if let holder { holder.remove() }
      if let reading {
        let record = reading.work.recordID
        _ = try? TestAdmin.query(
          """
          BEGIN;
          DELETE FROM survey_frames WHERE witness_id = (SELECT bibliographic_figurant_id FROM bibliographic_overtures
            WHERE id = '\(reading.work.overtureID)');
          DELETE FROM inferred_citation_jobs WHERE record_id = '\(record)';
          DELETE FROM biblio_record_versions WHERE biblio_record_id = '\(record)'
            AND id <> '\(reading.work.versionID)';
          COMMIT;
          """)
        reading.remove()
      }
    }
    do {
      // The testament, not permitted yet: its images numbered by its
      // survey, read by its madrigal.
      let scratch = try ScratchReading(owner: admin, tei: Self.tei(first, second), sourceURL: source)
      reading = scratch
      let witness = try TestAdmin.query(
        "SELECT upper(bibliographic_figurant_id::text) FROM bibliographic_overtures WHERE id = '\(scratch.work.overtureID)';"
      ).trimmingCharacters(in: .whitespacesAndNewlines)
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO survey_frames (id, witness_id, ordinal, label, frame_url) VALUES
          (gen_random_uuid(), '\(witness)', 1, '1', '\(first)/full/1300,/0/default.jpg'),
          (gen_random_uuid(), '\(witness)', 2, '2', '\(second)/full/1300,/0/default.jpg');
        UPDATE bibliographic_madrigals SET page_readings_json = '{"\(first)": "web-tests", "\(second)": "web-tests"}'
          WHERE id = '\(scratch.madrigalID)';
        COMMIT;
        """)

      // The quote pending on another object's origin: images 1 and 2.
      let other = try ScratchOverture(owner: admin, sealed: false)
      holder = other
      // Its evidence its incoming supports, each claiming the step
      // (user, 2026-11-03).
      let step = UUID().uuidString
      let pending =
        #"[{"id":"\#(step)","relations":["based_on"],"typed":{"title":"Web tests source","voices":[]},"origins":[],"#
        + #""outgoingCitations":[{"id":"\#(UUID().uuidString)","claim":{"field":"origin","row":"\#(step)"},"#
        + #""quotes":[{"id":"\#(UUID().uuidString)","anchors":[],"#
        + #""pending":{"sourceURL":"\#(source)","images":[1,2],"text":"\#(Self.opening) \#(Self.rest)"}}]}]}]"#
      _ = try TestAdmin.query(
        "UPDATE bibliographic_overtures SET origins_json = '\(pending)' WHERE id = '\(other.overtureID)';")

      // Permitted: its version indexed, the quote looked for on its images.
      try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine), cookies: [admin.cookie]) {
        page in
        try await page.openHydrated(scratch.path)
        try await page.locator("button[form='madrigal-permit']").click()
        try await expect(page.locator(".mission-control-object-header-status-chip"), timeout: .seconds(15))
          .toHaveText("Permitted")
      }
      var stored = ""
      for _ in 0..<60 {
        stored = try TestAdmin.query("SELECT origins_json FROM bibliographic_overtures WHERE id = '\(other.overtureID)';")
        if !stored.contains("\"pending\"") { break }
        try await Task.sleep(for: .milliseconds(500))
      }
      #expect(!stored.contains("\"pending\""), "still pending: \(stored)")
      #expect(!stored.contains("flagged"), "flagged: \(stored)")
      // One anchor: its first word on image 1, its last on image 2.
      let anchors = try TestAdmin.query(
        """
        SELECT e -> 'anchors' FROM bibliographic_overtures,
          jsonb_array_elements(origins_json::jsonb -> 0 -> 'evidence') e WHERE id = '\(other.overtureID)';
        """
      )
      let decoded = try JSONSerialization.jsonObject(with: Data(anchors.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
      let list = decoded as? [[String: Any]] ?? []
      #expect(list.count == 1, "\(anchors)")
      let anchor = list.first ?? [:]
      #expect(anchor["imageID"] as? String == first, "\(anchors)")
      #expect(anchor["endImageID"] as? String == second, "\(anchors)")
      #expect((anchor["start"] as? [String: Any])?["surface"] as? String == "Hamlet", "\(anchors)")
      #expect((anchor["end"] as? [String: Any])?["surface"] as? String == "gate", "\(anchors)")
    } catch {
      clean()
      try await admin.remove(after: error)
    }
    clean()
    try await admin.remove()
  }
}
