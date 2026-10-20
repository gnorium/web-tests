import Foundation

/// A scratch work's text: a pending madrigal explicated again from its
/// permitted one, holding `tei` (one page, its facsimile on example.org),
/// owned by the test's account. Every row by its own id, removed before the work.
struct ScratchReading {
  let work: ScratchWork
  let path: String
  private let antiphonID: String
  let madrigalID: String
  private let ownerID: String
  /// The serenade `translation(to:)` committed the madrigal to.
  private let serenadeID = UUID().uuidString.lowercased()

  init(owner: TestAdmin, tei: String, sourceURL: String = "https://example.org/web-tests") throws {
    work = try ScratchWork(owner: owner, sourceURL: sourceURL)
    let user = try owner.column("id")
    ownerID = user
    antiphonID = UUID().uuidString.lowercased()
    madrigalID = UUID().uuidString.lowercased()
    path = "/mission-control/madrigals/bibliographic/\(madrigalID)"
    let content = try String(
      decoding: JSONSerialization.data(withJSONObject: ["teiXml": tei]), as: UTF8.self
    ).replacingOccurrences(of: "'", with: "''")
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, image_service_ids_json, processing_status, created_at, updated_at)
        VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted', now(), now());
      INSERT INTO bibliographic_madrigals (id, proposed_content_json, processing_status, biblio_record_id, bibliographic_antiphon_id, thread_id, metadata_json, created_at, updated_at)
        VALUES ('\(madrigalID)', '\(content)', 'pending', '\(work.recordID.lowercased())', '\(antiphonID)', '\(madrigalID)',
          (SELECT metadata_json FROM biblio_record_versions WHERE id = '\(work.versionID.lowercased())'), now(), now());
      COMMIT;
      """)
  }

  /// The statements of the madrigal's Commit for translation, for a test's
  /// own transaction: the madrigal committed, its serenade (submitted), and
  /// the first epilogue `epilogue` it submitted (its thread's first), which
  /// carries the madrigal's document and fields as they stand and an empty
  /// translation of its language into English. A serenade answers that
  /// epilogue. `remove` deletes them, after whatever answers it.
  func translation(to epilogue: String) -> String {
    """
    UPDATE bibliographic_madrigals SET processing_status = 'committed' WHERE id = '\(madrigalID)';
    INSERT INTO bibliographic_serenades (id, bibliographic_madrigal_id, target_language, image_service_ids_json, requested_by_user_id, processing_status)
      VALUES ('\(serenadeID)', '\(madrigalID)', 'eng', '[]', '\(ownerID)', 'submitted');
    INSERT INTO bibliographic_epilogues (id, thread_id, bibliographic_overture_id, bibliographic_serenade_id,
      biblio_record_id, proposed_content_json, metadata_json, shape_json, translation_json, processing_status)
      SELECT '\(epilogue)', '\(epilogue)', '\(work.overtureID.lowercased())', '\(serenadeID)', p.biblio_record_id,
        p.proposed_content_json, p.metadata_json, p.shape_json,
        json_build_object('sourceLanguage', p.metadata_json::jsonb->>'language', 'targetLanguage', 'eng', 'tei', '', 'pages', '[]'::json)::text,
        'pending'
      FROM bibliographic_madrigals p WHERE p.id = '\(madrigalID)';
    """
  }

  func remove() {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM bibliographic_epilogues WHERE bibliographic_serenade_id = '\(serenadeID)';
      DELETE FROM bibliographic_serenades WHERE id = '\(serenadeID)';
      DELETE FROM bibliographic_madrigals WHERE id = '\(madrigalID)';
      DELETE FROM bibliographic_antiphons WHERE id = '\(antiphonID)';
      COMMIT;
      """)
    work.remove()
  }
}
