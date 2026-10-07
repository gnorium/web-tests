import Foundation

/// A long bibliographic line, owned by the test's account: an instance and
/// its committed overture, then `links` notations, each recognized by an
/// antiphon from the one before it (the first, from the overture) and each
/// committed to the next; the last one permitted. Its Pedigree lists every
/// one of them, so it runs far past one screen. Every row by its own id,
/// removed in the order the foreign keys allow—except its submission and
/// Instance, which are submitted input and frozen: the Instance is
/// soft-deleted, as the site deletes one.
struct ScratchLine {
  let instanceID: String
  /// The instance's page, whose Pedigree walks the whole line.
  var path: String { "/mission-control/instances/bibliographic/\(instanceID)" }
  private let submissionID: String
  private let overtureID: String
  private let antiphonIDs: [String]
  private let notationIDs: [String]
  private let owner: String

  init(owner: TestAdmin, links: Int = 60) throws {
    let user = try owner.column("id")
    self.owner = owner.username
    func id() -> String { UUID().uuidString.lowercased() }
    submissionID = id()
    instanceID = id()
    overtureID = id()
    antiphonIDs = (0..<links).map { _ in id() }
    notationIDs = (0..<links).map { _ in id() }
    var sql = """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(submissionID)', '\(user)');
      INSERT INTO bibliographic_instances (id, batch_id, source_url, language, processing_status, title, type)
        VALUES ('\(instanceID)', '\(submissionID)', 'https://example.org/web-tests', 'eng', 'pending', 'Web tests pedigree \(instanceID.prefix(8))', 'report');
      INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_instance_id, source_url, language, processing_status, committed_by_user_id, committed_at)
        VALUES ('\(overtureID)', '\(submissionID)', '\(instanceID)', 'https://example.org/web-tests', 'eng', 'pending', '\(user)', now());

      """
    for index in 0..<links {
      // The first antiphon answers the overture; each after it, the
      // notation before it.
      let column = index == 0 ? "bibliographic_overture_id" : "bibliographic_notation_id"
      let antecedent = index == 0 ? overtureID : notationIDs[index - 1]
      sql += """
        INSERT INTO bibliographic_antiphons (id, \(column), requested_by_user_id, semblance_service_ids_json, processing_status)
          VALUES ('\(antiphonIDs[index])', '\(antecedent)', '\(user)', '[]', 'submitted');

        """
      let last = index == links - 1
      let act = last ? "'permitted', '\(user)', now()" : "'committed', NULL, NULL"
      sql += """
        INSERT INTO bibliographic_notations (id, thread_id, bibliographic_antiphon_id, proposed_content_json, metadata_json, processing_status, permitted_by_user_id, permitted_at)
          VALUES ('\(notationIDs[index])', '\(notationIDs[0])', '\(antiphonIDs[index])', '{"teiXml":""}', '{}', \(act));

        """
    }
    sql += "COMMIT;"
    _ = try TestAdmin.query(sql)
  }

  func remove() {
    // Each antiphon after the first names the notation before it, and each
    // notation its antiphon: newest first.
    var sql = "BEGIN;\n"
    for index in notationIDs.indices.reversed() {
      sql += "DELETE FROM bibliographic_notations WHERE id = '\(notationIDs[index])';\n"
      sql += "DELETE FROM bibliographic_antiphons WHERE id = '\(antiphonIDs[index])';\n"
    }
    sql += """
      DELETE FROM bibliographic_overtures WHERE id = '\(overtureID)';
      UPDATE bibliographic_instances SET deleted_at = now(), deleted_by = '\(owner)' WHERE id = '\(instanceID)';
      COMMIT;
      """
    _ = try? TestAdmin.query(sql)
  }
}
