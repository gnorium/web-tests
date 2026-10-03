import Foundation

/// Two Disputorium objects waiting on a commit, owned by the test's
/// account: a pending overture, with one way to commit, and a pending
/// hallmark (its own overture committed, its concerto submitted), with
/// two. Every row by its own id, removed in the order the foreign keys
/// allow. Nothing here is ever committed: a test only opens and cancels.
/// The hallmark's metadata holds what the witness's fields require (its
/// page decodes them): the language, the source URL and its kind.
struct ScratchCommit {
  /// A IIIF manifest no one serves: `.invalid` never resolves, so the
  /// server's manifest route answers at once that it could not be fetched,
  /// and the viewer pages nothing, quietly.
  static let sourceURL = "https://web-tests.invalid/manifest.json"

  private let submissionID: String
  private let evidenceID: String
  private let pendingOvertureID: String
  private let committedOvertureID: String
  private let concertoID: String
  private let hallmarkID: String

  var overturePath: String { "/mission-control/overtures/bibliographic/\(pendingOvertureID)" }
  var hallmarkPath: String { "/mission-control/hallmarks/bibliographic/\(hallmarkID)" }

  init(owner: TestAdmin) throws {
    let user = try owner.column("id")
    func id() -> String { UUID().uuidString.lowercased() }
    submissionID = id()
    evidenceID = id()
    pendingOvertureID = id()
    committedOvertureID = id()
    concertoID = id()
    hallmarkID = id()
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(submissionID)', '\(user)');
      INSERT INTO bibliographic_evidences (id, batch_id, source_url, language, processing_status, title, type)
        VALUES ('\(evidenceID)', '\(submissionID)', '\(Self.sourceURL)', 'eng', 'pending', 'Web tests commit \(evidenceID.prefix(8))', 'report');
      INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_evidence_id, source_url, language, processing_status)
        VALUES ('\(pendingOvertureID)', '\(submissionID)', '\(evidenceID)', '\(Self.sourceURL)', 'eng', 'pending');
      INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_evidence_id, source_url, language, processing_status, committed_by_user_id, committed_at)
        VALUES ('\(committedOvertureID)', '\(submissionID)', '\(evidenceID)', '\(Self.sourceURL)', 'eng', 'pending', '\(user)', now());
      INSERT INTO bibliographic_concertos (id, bibliographic_overture_id, requested_by_user_id, processing_status)
        VALUES ('\(concertoID)', '\(committedOvertureID)', '\(user)', 'submitted');
      INSERT INTO bibliographic_hallmarks (id, thread_id, bibliographic_overture_id, bibliographic_concerto_id, metadata_json, processing_status)
        VALUES ('\(hallmarkID)', '\(hallmarkID)', '\(committedOvertureID)', '\(concertoID)', '{"language":"eng","sourceUrl":"\(Self.sourceURL)","sourceKind":"iiif-manifest"}', 'pending');
      COMMIT;
      """)
  }

  /// Whether both objects are still uncommitted.
  func stillPending() throws -> Bool {
    let overture = try TestAdmin.query(
      "SELECT committed_at IS NULL FROM bibliographic_overtures WHERE id = '\(pendingOvertureID)'")
    let hallmark = try TestAdmin.query(
      "SELECT processing_status FROM bibliographic_hallmarks WHERE id = '\(hallmarkID)'")
    return overture == "t" && hallmark == "pending"
  }

  func remove() {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM bibliographic_hallmarks WHERE id = '\(hallmarkID)';
      DELETE FROM bibliographic_concertos WHERE id = '\(concertoID)';
      DELETE FROM bibliographic_overtures WHERE id IN ('\(pendingOvertureID)', '\(committedOvertureID)');
      DELETE FROM bibliographic_evidences WHERE id = '\(evidenceID)';
      DELETE FROM submissions WHERE id = '\(submissionID)';
      COMMIT;
      """)
  }
}
