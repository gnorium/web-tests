import Foundation

/// A long bibliographic line, owned by the test's account: a folksong and
/// its committed overture, then `links` madrigals, each explicated by an
/// antiphon from the one before it (the first, from the overture) and each
/// committed to the next; the last one permitted. Its Pedigree lists every
/// one of them, so it runs far past one screen. Every row by its own id,
/// removed in the order the foreign keys allow—except its submission and
/// Folksong, which are submitted input and frozen: the Folksong is
/// soft-deleted, as the site deletes one.
struct ScratchLine {
  let folksongID: String
  /// The folksong's page, whose Pedigree walks the whole line.
  var path: String { "/mission-control/folksongs/bibliographic/\(folksongID)" }
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
    folksongID = id()
    overtureID = id()
    antiphonIDs = (0..<links).map { _ in id() }
    madrigalIDs = (0..<links).map { _ in id() }
    var sql = """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(submissionID)', '\(user)');
      INSERT INTO bibliographic_folksongs (id, batch_id, source_url, language, processing_status, title, type, created_at)
        VALUES ('\(folksongID)', '\(submissionID)', 'https://example.org/web-tests', 'eng', 'pending', 'Web tests pedigree \(folksongID.prefix(8))', 'report', now());
      INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_folksong_id, source_url, language, processing_status, committed_by_user_id, committed_at, created_at)
        VALUES ('\(overtureID)', '\(submissionID)', '\(folksongID)', 'https://example.org/web-tests', 'eng', 'pending', '\(user)', now(), now());

      """
    for index in 0..<links {
      // The first antiphon answers the overture; each after it, the
      // madrigal before it.
      let column = index == 0 ? "bibliographic_overture_id" : "bibliographic_madrigal_id"
      let antecedent = index == 0 ? overtureID : madrigalIDs[index - 1]
      sql += """
        INSERT INTO bibliographic_antiphons (id, \(column), requested_by_user_id, canvas_service_ids_json, processing_status, created_at, updated_at)
          VALUES ('\(antiphonIDs[index])', '\(antecedent)', '\(user)', '[]', 'submitted', now(), now());

        """
      let last = index == links - 1
      let act = last ? "'permitted', '\(user)', now()" : "'committed', NULL, NULL"
      sql += """
        INSERT INTO bibliographic_madrigals (id, thread_id, bibliographic_antiphon_id, proposed_content_json, metadata_json, processing_status, permitted_by_user_id, permitted_at, created_at, updated_at)
          VALUES ('\(madrigalIDs[index])', '\(madrigalIDs[0])', '\(antiphonIDs[index])', '{"teiXml":""}', '{}', \(act), now(), now());

        """
    }
    sql += "COMMIT;"
    _ = try TestAdmin.query(sql)
  }

  func remove() {
    // Each antiphon after the first names the madrigal before it, and each
    // madrigal its antiphon: newest first.
    var sql = "BEGIN;\n"
    for index in madrigalIDs.indices.reversed() {
      sql += "DELETE FROM bibliographic_madrigals WHERE id = '\(madrigalIDs[index])';\n"
      sql += "DELETE FROM bibliographic_antiphons WHERE id = '\(antiphonIDs[index])';\n"
    }
    sql += """
      DELETE FROM bibliographic_overtures WHERE id = '\(overtureID)';
      UPDATE bibliographic_folksongs SET deleted_at = now(), deleted_by = '\(owner)' WHERE id = '\(folksongID)';
      COMMIT;
      """
    _ = try? TestAdmin.query(sql)
  }
}
