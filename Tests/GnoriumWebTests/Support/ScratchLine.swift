import Foundation

/// A long bibliographic line, owned by the test's account: an instance, its
/// baseline and madrigal, then `links` overtures, each committed to a
/// madrigal that submitted the next; the last one permitted. Its Pedigree
/// lists every one of them, so it runs far past one screen. Every row by its
/// own id, removed in the order the foreign keys allow—except its submission
/// and Instance, which are submitted input and frozen: the Instance is
/// soft-deleted, as the site deletes one.
struct ScratchLine {
  let instanceID: String
  /// The instance's page, whose Pedigree walks the whole line.
  var path: String { "/mission-control/instances/bibliographic/\(instanceID)" }
  private let submissionID: String
  private let baselineID: String
  private let madrigalIDs: [String]
  private let overtureIDs: [String]
  private let owner: String

  init(owner: TestAdmin, links: Int = 60) throws {
    let user = try owner.column("id")
    self.owner = owner.username
    func id() -> String { UUID().uuidString.lowercased() }
    submissionID = id()
    instanceID = id()
    baselineID = id()
    madrigalIDs = (0..<links).map { _ in id() }
    overtureIDs = (0..<links).map { _ in id() }
    var sql = """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(submissionID)', '\(user)');
      INSERT INTO bibliographic_instances (id, batch_id, source_url, language, processing_status, title, type)
        VALUES ('\(instanceID)', '\(submissionID)', 'https://example.org/web-tests', 'eng', 'pending', 'Web tests pedigree \(instanceID.prefix(8))', 'report');
      INSERT INTO bibliographic_baselines (id, batch_id, bibliographic_instance_id, source_url, language, processing_status)
        VALUES ('\(baselineID)', '\(submissionID)', '\(instanceID)', 'https://example.org/web-tests', 'eng', 'pending');

      """
    for index in 0..<links {
      // The first madrigal answers the baseline; each after it, the
      // overture before it.
      let column = index == 0 ? "bibliographic_baseline_id" : "bibliographic_overture_id"
      let antecedent = index == 0 ? baselineID : overtureIDs[index - 1]
      sql += """
        INSERT INTO bibliographic_madrigals (id, \(column), requested_by_user_id, processing_status)
          VALUES ('\(madrigalIDs[index])', '\(antecedent)', '\(user)', 'submitted');

        """
      let last = index == links - 1
      let act =
        last
        ? "'permitted', NULL, NULL, '\(user)', now()"
        : "'committed', '\(user)', now(), NULL, NULL"
      sql += """
        INSERT INTO bibliographic_overtures (id, thread_id, bibliographic_baseline_id, bibliographic_madrigal_id, metadata_json, processing_status, committed_by_user_id, committed_at, permitted_by_user_id, permitted_at)
          VALUES ('\(overtureIDs[index])', '\(overtureIDs[0])', '\(baselineID)', '\(madrigalIDs[index])', '{}', \(act));

        """
    }
    sql += "COMMIT;"
    _ = try TestAdmin.query(sql)
  }

  func remove() {
    // Each madrigal after the first names the overture before it, and each
    // overture its madrigal: newest first.
    var sql = "BEGIN;\n"
    for index in overtureIDs.indices.reversed() {
      sql += "DELETE FROM bibliographic_overtures WHERE id = '\(overtureIDs[index])';\n"
      sql += "DELETE FROM bibliographic_madrigals WHERE id = '\(madrigalIDs[index])';\n"
    }
    sql += """
      DELETE FROM bibliographic_baselines WHERE id = '\(baselineID)';
      UPDATE bibliographic_instances SET deleted_at = now(), deleted_by = '\(owner)' WHERE id = '\(instanceID)';
      COMMIT;
      """
    _ = try? TestAdmin.query(sql)
  }
}
