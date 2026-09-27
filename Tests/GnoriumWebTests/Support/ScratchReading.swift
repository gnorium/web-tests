import Foundation

/// A scratch work's text: a pending proposal recognized from its hallmark,
/// holding `tei` (one page, its facsimile on example.org), owned by the
/// test's account. Every row by its own id, removed before the work.
struct ScratchReading {
  let work: ScratchWork
  let path: String
  private let antiphonID: String
  private let proposalID: String

  init(owner: TestAdmin, tei: String) throws {
    work = try ScratchWork(owner: owner)
    let user = try owner.column("id")
    antiphonID = UUID().uuidString.lowercased()
    proposalID = UUID().uuidString.lowercased()
    path = "/mission-control/proposals/bibliographic/\(proposalID)"
    let content = try String(
      decoding: JSONSerialization.data(withJSONObject: ["teiXml": tei]), as: UTF8.self
    ).replacingOccurrences(of: "'", with: "''")
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO bibliographic_antiphons (id, bibliographic_hallmark_id, requested_by_user_id, semblance_service_ids_json, processing_status)
        VALUES ('\(antiphonID)', (SELECT bibliographic_hallmark_id FROM biblio_record_versions WHERE id = '\(work.versionID.lowercased())'),
          '\(user)', '[]', 'submitted');
      INSERT INTO bibliographic_proposals (id, proposed_content_json, processing_status, biblio_record_id, bibliographic_antiphon_id, thread_id, metadata_json)
        VALUES ('\(proposalID)', '\(content)', 'pending', '\(work.recordID.lowercased())', '\(antiphonID)', '\(proposalID)',
          (SELECT metadata_json FROM biblio_record_versions WHERE id = '\(work.versionID.lowercased())'));
      COMMIT;
      """)
  }

  func remove() {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM bibliographic_proposals WHERE id = '\(proposalID)';
      DELETE FROM bibliographic_antiphons WHERE id = '\(antiphonID)';
      COMMIT;
      """)
    work.remove()
  }
}
