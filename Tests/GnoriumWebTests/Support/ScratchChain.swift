import Foundation

/// The rows an overture's Commit leaves on the way to its first madrigal
/// (user, 2026-10-21): the quatrain it made (submitted), the halftone that
/// quatrain submitted (committed, calibrated), and the antiphon the
/// halftone's Commit for explication made (submitted), holding the frozen
/// header, the skeleton and the fields. The first madrigal names the
/// antiphon. Inserted and deleted as SQL inside a fixture's own transaction.
struct ScratchChain {
  let quatrainID = UUID().uuidString.lowercased()
  let halftoneID = UUID().uuidString.lowercased()
  let antiphonID = UUID().uuidString.lowercased()

  /// The statements that make the chain under `overture`, committed by
  /// `user`; `metadata` (a JSON object, quotes doubled) the halftone's
  /// fields, which the antiphon carries.
  func insert(overture: String, user: String, metadata: String = "{}") -> String {
    """
    INSERT INTO bibliographic_quatrains (id, bibliographic_overture_id, requested_by_user_id, image_service_ids_json, processing_status, created_at, updated_at, completed_at)
      VALUES ('\(quatrainID)', '\(overture)', '\(user)', '[]', 'submitted', now() - interval '3 minutes', now(), now());
    INSERT INTO bibliographic_halftones (id, bibliographic_overture_id, bibliographic_quatrain_id, metadata_json, committed_by_user_id, committed_at, created_at, updated_at)
      VALUES ('\(halftoneID)', '\(overture)', '\(quatrainID)', '\(metadata)', '\(user)', now() - interval '1 minute', now() - interval '2 minutes', now());
    INSERT INTO bibliographic_antiphons (id, bibliographic_halftone_id, document_json, header_json, metadata_json, requested_by_user_id, image_service_ids_json, processing_status, created_at, updated_at)
      VALUES ('\(antiphonID)', '\(halftoneID)', '{"teiXml":""}', '{}', '\(metadata)', '\(user)', '[]', 'submitted', now() - interval '1 minute', now());

    """
  }

  /// The statements that remove it, once the madrigals naming the antiphon
  /// are gone.
  var delete: String {
    """
    DELETE FROM bibliographic_antiphons WHERE id = '\(antiphonID)';
    DELETE FROM bibliographic_halftones WHERE id = '\(halftoneID)';
    DELETE FROM bibliographic_quatrains WHERE id = '\(quatrainID)';

    """
  }
}
