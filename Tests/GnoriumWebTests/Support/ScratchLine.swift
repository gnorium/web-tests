import Foundation

/// A long bibliographic line, owned by the test's account: a figurant and
/// its committed overture, its quatrain, halftone and the antiphon that
/// halftone's Commit made (`ScratchChain`), then `links` madrigals: the first
/// that antiphon's, each after it explicated by an antiphon from the one
/// before it and each committed to the next; the last one permitted. Its Pedigree lists every
/// one of them, so it runs far past one screen. Every row by its own id,
/// removed in the order the foreign keys allow—except its submission and
/// Figurant, which are submitted input and frozen: the Figurant is
/// soft-discarded, as the site discards one.
struct ScratchLine {
  let figurantID: String
  /// The figurant's page, whose Pedigree walks the whole line.
  var path: String { "/mission-control/figurants/bibliographic/\(figurantID)" }
  private let submissionID: String
  private let overtureID: String
  private let chain = ScratchChain()
  private let antiphonIDs: [String]
  private let madrigalIDs: [String]
  private let owner: String

  init(owner: TestAdmin, links: Int = 60) throws {
    let user = try owner.column("id")
    self.owner = owner.username
    func id() -> String { UUID().uuidString.lowercased() }
    submissionID = id()
    figurantID = id()
    overtureID = id()
    antiphonIDs = (0..<links).map { _ in id() }
    madrigalIDs = (0..<links).map { _ in id() }
    var sql = """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(submissionID)', '\(user)');
      INSERT INTO bibliographic_figurants (id, batch_id, source_url, language, processing_status, title, type, created_at)
        VALUES ('\(figurantID)', '\(submissionID)', 'https://example.org/web-tests', 'eng', 'pending', 'Web tests pedigree \(figurantID.prefix(8))', 'report', now());
      INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_figurant_id, source_url, language, processing_status, committed_by_user_id, committed_at, created_at)
        VALUES ('\(overtureID)', '\(submissionID)', '\(figurantID)', 'https://example.org/web-tests', 'eng', 'pending', '\(user)', now(), now());

      """ + chain.insert(overture: overtureID, user: user)
    for index in 0..<links {
      // The first madrigal is the chain's antiphon's; each after it is
      // made by an antiphon that answers the madrigal before it.
      let producer: (column: String, id: String)
      if index == 0 {
        producer = ("bibliographic_antiphon_id", chain.antiphonID)
      } else {
        producer = ("bibliographic_antiphon_id", antiphonIDs[index])
        sql += """
          INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, image_service_ids_json, processing_status, created_at, updated_at)
            VALUES ('\(antiphonIDs[index])', '\(madrigalIDs[index - 1])', '\(user)', '[]', 'submitted', now(), now());

          """
      }
      let last = index == links - 1
      let act = last ? "'permitted', '\(user)', now()" : "'committed', NULL, NULL"
      sql += """
        INSERT INTO bibliographic_madrigals (id, thread_id, \(producer.column), proposed_content_json, metadata_json, processing_status, permitted_by_user_id, permitted_at, created_at, updated_at)
          VALUES ('\(madrigalIDs[index])', '\(madrigalIDs[0])', '\(producer.id)', '{"teiXml":""}', '{}', \(act), now(), now());

        """
    }
    sql += "COMMIT;"
    _ = try TestAdmin.query(sql)
  }

  func remove() {
    // Each antiphon names the madrigal before it, and each madrigal after
    // the first the chain's: newest first, the chain after the first.
    var sql = "BEGIN;\n"
    for index in madrigalIDs.indices.reversed() {
      sql += "DELETE FROM bibliographic_madrigals WHERE id = '\(madrigalIDs[index])';\n"
      sql += "DELETE FROM bibliographic_antiphons WHERE id = '\(antiphonIDs[index])';\n"
    }
    sql += chain.delete + """
      DELETE FROM bibliographic_overtures WHERE id = '\(overtureID)';
      UPDATE bibliographic_figurants SET discarded_at = now(), discarded_by = '\(owner)' WHERE id = '\(figurantID)';
      COMMIT;
      """
    _ = try? TestAdmin.query(sql)
  }
}
