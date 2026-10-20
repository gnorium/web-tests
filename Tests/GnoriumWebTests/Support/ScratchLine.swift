import Foundation

/// A long bibliographic line, owned by the test's account: a fountain and
/// its committed overture, then `links` madrigals: the first promoted from
/// the overture (its header frozen), each after it explicated by an antiphon
/// from the one before it and each committed to the next; the last one
/// permitted. Its Pedigree lists every
/// one of them, so it runs far past one screen. Every row by its own id,
/// removed in the order the foreign keys allow—except its submission and
/// Fountain, which are submitted input and frozen: the Fountain is
/// soft-deleted, as the site deletes one.
struct ScratchLine {
  let fountainID: String
  /// The fountain's page, whose Pedigree walks the whole line.
  var path: String { "/mission-control/fountains/bibliographic/\(fountainID)" }
  private let submissionID: String
  private let overtureID: String
  private let antiphonIDs: [String]
  private let madrigalIDs: [String]
  private let owner: String

  init(owner: TestAdmin, links: Int = 60) throws {
    let user = try owner.column("id")
    self.owner = owner.username
    func id() -> String { UUID().uuidString.lowercased() }
    submissionID = id()
    fountainID = id()
    overtureID = id()
    antiphonIDs = (0..<links).map { _ in id() }
    madrigalIDs = (0..<links).map { _ in id() }
    var sql = """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(submissionID)', '\(user)');
      INSERT INTO bibliographic_fountains (id, batch_id, source_url, language, processing_status, title, type, created_at)
        VALUES ('\(fountainID)', '\(submissionID)', 'https://example.org/web-tests', 'eng', 'pending', 'Web tests pedigree \(fountainID.prefix(8))', 'report', now());
      INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_fountain_id, source_url, language, processing_status, committed_by_user_id, committed_at, created_at)
        VALUES ('\(overtureID)', '\(submissionID)', '\(fountainID)', 'https://example.org/web-tests', 'eng', 'pending', '\(user)', now(), now());

      """
    for index in 0..<links {
      // The first madrigal is the overture's promotion; each after it is
      // made by an antiphon that answers the madrigal before it.
      let producer: (column: String, id: String)
      if index == 0 {
        producer = ("bibliographic_overture_id", overtureID)
      } else {
        producer = ("bibliographic_antiphon_id", antiphonIDs[index])
        sql += """
          INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, resemblance_service_ids_json, processing_status, created_at, updated_at)
            VALUES ('\(antiphonIDs[index])', '\(madrigalIDs[index - 1])', '\(user)', '[]', 'submitted', now(), now());

          """
      }
      let last = index == links - 1
      let act = last ? "'permitted', '\(user)', now()" : "'committed', NULL, NULL"
      sql += """
        INSERT INTO bibliographic_madrigals (id, thread_id, \(producer.column), proposed_content_json, metadata_json, processing_status, permitted_by_user_id, permitted_at, created_at, updated_at)
          VALUES ('\(madrigalIDs[index])', '\(madrigalIDs[0])', '\(producer.id)', '{"teiXml":""}', '{}', \(act), now(), now());

        """
      if index == 0 {
        sql += """
          INSERT INTO bibliographic_headers (bibliographic_overture_id, header_tei, bibliographic_madrigal_id, frozen_by_user_id, analysis_versions_json, page_count)
            VALUES ('\(overtureID)', '<teiHeader/>', '\(madrigalIDs[0])', '\(user)', '[]', 1);

          """
      }
    }
    sql += "COMMIT;"
    _ = try TestAdmin.query(sql)
  }

  func remove() {
    // Each antiphon names the madrigal before it, and each madrigal after
    // the first its antiphon: newest first, the header before the first.
    var sql = "BEGIN;\nDELETE FROM bibliographic_headers WHERE bibliographic_overture_id = '\(overtureID)';\n"
    for index in madrigalIDs.indices.reversed() {
      sql += "DELETE FROM bibliographic_madrigals WHERE id = '\(madrigalIDs[index])';\n"
      sql += "DELETE FROM bibliographic_antiphons WHERE id = '\(antiphonIDs[index])';\n"
    }
    sql += """
      DELETE FROM bibliographic_overtures WHERE id = '\(overtureID)';
      UPDATE bibliographic_fountains SET deleted_at = now(), deleted_by = '\(owner)' WHERE id = '\(fountainID)';
      COMMIT;
      """
    _ = try? TestAdmin.query(sql)
  }
}
