import Foundation

/// A scratch work's text: a pending notation recognized again from its
/// permitted one, holding `tei` (one page, its facsimile on example.org),
/// owned by the test's account. Every row by its own id, removed before the work.
struct ScratchReading {
  let work: ScratchWork
  let path: String
  private let antiphonID: String
  let notationID: String

  init(owner: TestAdmin, tei: String, sourceURL: String = "https://example.org/web-tests") throws {
    work = try ScratchWork(owner: owner, sourceURL: sourceURL)
    let user = try owner.column("id")
    antiphonID = UUID().uuidString.lowercased()
    notationID = UUID().uuidString.lowercased()
    path = "/mission-control/notations/bibliographic/\(notationID)"
    let content = try String(
      decoding: JSONSerialization.data(withJSONObject: ["teiXml": tei]), as: UTF8.self
    ).replacingOccurrences(of: "'", with: "''")
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO bibliographic_antiphons (id, bibliographic_notation_id, requested_by_user_id, semblance_service_ids_json, processing_status)
        VALUES ('\(antiphonID)', '\(work.notationID.lowercased())', '\(user)', '[]', 'submitted');
      INSERT INTO bibliographic_notations (id, proposed_content_json, processing_status, biblio_record_id, bibliographic_antiphon_id, thread_id, metadata_json)
        VALUES ('\(notationID)', '\(content)', 'pending', '\(work.recordID.lowercased())', '\(antiphonID)', '\(notationID)',
          (SELECT metadata_json FROM biblio_record_versions WHERE id = '\(work.versionID.lowercased())'));
      COMMIT;
      """)
  }

  func remove() {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM bibliographic_notations WHERE id = '\(notationID)';
      DELETE FROM bibliographic_antiphons WHERE id = '\(antiphonID)';
      COMMIT;
      """)
    work.remove()
  }
}
