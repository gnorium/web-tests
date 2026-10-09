import Foundation

/// A scratch work's testament: its text (`tei`) as a permitted version, a
/// madrigal's, owned by the test's account, so an utterance can be anchored
/// in it and read there. Every row by its own id, removed before the work.
struct ScratchTestament {
  let reading: ScratchReading
  let versionID: String

  init(owner: TestAdmin, tei: String, sourceURL: String = "https://example.org/web-tests") throws {
    reading = try ScratchReading(owner: owner, tei: tei, sourceURL: sourceURL)
    let user = try owner.column("id")
    versionID = UUID().uuidString.lowercased()
    let work = reading.work
    _ = try TestAdmin.query(
      """
      BEGIN;
      UPDATE bibliographic_madrigals SET processing_status = 'permitted', permitted_by_user_id = '\(user)', permitted_at = now()
        WHERE id = '\(reading.madrigalID)';
      INSERT INTO biblio_record_versions (id, biblio_record_id, bibliographic_madrigal_id, metadata_json, shape_json, status, created_at)
        SELECT '\(versionID)', biblio_record_id, '\(reading.madrigalID)', metadata_json, shape_json, 1, now()
        FROM biblio_record_versions WHERE id = '\(work.versionID.lowercased())';
      COMMIT;
      """)
  }

  func remove() {
    _ = try? TestAdmin.query("DELETE FROM biblio_record_versions WHERE id = '\(versionID)';")
    reading.remove()
  }
}
