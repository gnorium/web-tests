import Foundation

/// A scratch work's text: a pending madrigal explicated again from its
/// permitted one, holding `tei` (one page, its facsimile on example.org),
/// owned by the test's account. Every row by its own id, removed before the work.
struct ScratchReading {
  let work: ScratchWork
  let path: String
  private let antiphonID: String
  let madrigalID: String

  init(owner: TestAdmin, tei: String, sourceURL: String = "https://example.org/web-tests") throws {
    work = try ScratchWork(owner: owner, sourceURL: sourceURL)
    let user = try owner.column("id")
    antiphonID = UUID().uuidString.lowercased()
    madrigalID = UUID().uuidString.lowercased()
    path = "/mission-control/madrigals/bibliographic/\(madrigalID)"
    let content = try String(
      decoding: JSONSerialization.data(withJSONObject: ["teiXml": tei]), as: UTF8.self
    ).replacingOccurrences(of: "'", with: "''")
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, canvas_service_ids_json, processing_status, created_at, updated_at)
        VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted', now(), now());
      INSERT INTO bibliographic_madrigals (id, proposed_content_json, processing_status, biblio_record_id, bibliographic_antiphon_id, thread_id, metadata_json, created_at, updated_at)
        VALUES ('\(madrigalID)', '\(content)', 'pending', '\(work.recordID.lowercased())', '\(antiphonID)', '\(madrigalID)',
          (SELECT metadata_json FROM biblio_record_versions WHERE id = '\(work.versionID.lowercased())'), now(), now());
      COMMIT;
      """)
  }

  func remove() {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM bibliographic_madrigals WHERE id = '\(madrigalID)';
      DELETE FROM bibliographic_antiphons WHERE id = '\(antiphonID)';
      COMMIT;
      """)
    work.remove()
  }
}
