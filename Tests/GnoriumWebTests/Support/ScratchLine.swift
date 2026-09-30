import Foundation

/// A long bibliographic line, owned by the test's account: an evidence, its
/// overture and concerto, then `links` hallmarks, each committed to a
/// concerto that submitted the next; the last one permitted. Its Pedigree
/// lists every one of them, so it runs far past one screen. Every row by its
/// own id, removed in the order the foreign keys allow.
struct ScratchLine {
  let evidenceID: String
  /// The evidence's page, whose Pedigree walks the whole line.
  var path: String { "/mission-control/evidence/bibliographic/\(evidenceID)" }
  private let submissionID: String
  private let overtureID: String
  private let concertoIDs: [String]
  private let hallmarkIDs: [String]

  init(owner: TestAdmin, links: Int = 60) throws {
    let user = try owner.column("id")
    func id() -> String { UUID().uuidString.lowercased() }
    submissionID = id()
    evidenceID = id()
    overtureID = id()
    concertoIDs = (0..<links).map { _ in id() }
    hallmarkIDs = (0..<links).map { _ in id() }
    var sql = """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(submissionID)', '\(user)');
      INSERT INTO bibliographic_evidences (id, batch_id, source_url, language, processing_status, title, type)
        VALUES ('\(evidenceID)', '\(submissionID)', 'https://example.org/web-tests', 'eng', 'pending', 'Web tests pedigree \(evidenceID.prefix(8))', 'report');
      INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_evidence_id, source_url, language, processing_status)
        VALUES ('\(overtureID)', '\(submissionID)', '\(evidenceID)', 'https://example.org/web-tests', 'eng', 'pending');

      """
    for index in 0..<links {
      // The first concerto answers the overture; each after it, the
      // hallmark before it.
      let column = index == 0 ? "bibliographic_overture_id" : "bibliographic_hallmark_id"
      let antecedent = index == 0 ? overtureID : hallmarkIDs[index - 1]
      sql += """
        INSERT INTO bibliographic_concertos (id, \(column), requested_by_user_id, processing_status)
          VALUES ('\(concertoIDs[index])', '\(antecedent)', '\(user)', 'submitted');

        """
      let last = index == links - 1
      let act =
        last
        ? "'permitted', NULL, NULL, '\(user)', now()"
        : "'committed', '\(user)', now(), NULL, NULL"
      sql += """
        INSERT INTO bibliographic_hallmarks (id, thread_id, bibliographic_overture_id, bibliographic_concerto_id, metadata_json, processing_status, committed_by_user_id, committed_at, permitted_by_user_id, permitted_at)
          VALUES ('\(hallmarkIDs[index])', '\(hallmarkIDs[0])', '\(overtureID)', '\(concertoIDs[index])', '{}', \(act));

        """
    }
    sql += "COMMIT;"
    _ = try TestAdmin.query(sql)
  }

  func remove() {
    // Each concerto after the first names the hallmark before it, and each
    // hallmark its concerto: newest first.
    var sql = "BEGIN;\n"
    for index in hallmarkIDs.indices.reversed() {
      sql += "DELETE FROM bibliographic_hallmarks WHERE id = '\(hallmarkIDs[index])';\n"
      sql += "DELETE FROM bibliographic_concertos WHERE id = '\(concertoIDs[index])';\n"
    }
    sql += """
      DELETE FROM bibliographic_overtures WHERE id = '\(overtureID)';
      DELETE FROM bibliographic_evidences WHERE id = '\(evidenceID)';
      DELETE FROM submissions WHERE id = '\(submissionID)';
      COMMIT;
      """
    _ = try? TestAdmin.query(sql)
  }
}
