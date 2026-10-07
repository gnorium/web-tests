import Foundation

/// Two Disputorium objects waiting on a commit, owned by the test's
/// account: a pending overture, with one way to commit, and a pending
/// notation (its own overture committed, its antiphon submitted), with
/// two. Every row by its own id, removed in the order the foreign keys
/// allow—except its submission and Instance, which are submitted input and
/// frozen: the Instance is soft-deleted, as the site deletes one. Nothing here is ever committed: a test only opens and cancels.
/// The notation's metadata holds what the witness's fields require (its
/// page decodes them): the language, the source URL and its kind.
struct ScratchCommit {
  /// A IIIF manifest no one serves: `.invalid` never resolves, so the
  /// server's manifest route answers at once that it could not be fetched,
  /// and the viewer pages nothing, quietly.
  static let sourceURL = "https://web-tests.invalid/manifest.json"

  private let submissionID: String
  private let instanceID: String
  private let pendingOvertureID: String
  private let committedOvertureID: String
  private let antiphonID: String
  private let notationID: String
  private let owner: String

  var overturePath: String { "/mission-control/overtures/bibliographic/\(pendingOvertureID)" }
  var notationPath: String { "/mission-control/notations/bibliographic/\(notationID)" }

  init(owner: TestAdmin, sourceURL: String = ScratchCommit.sourceURL) throws {
    let user = try owner.column("id")
    self.owner = owner.username
    func id() -> String { UUID().uuidString.lowercased() }
    submissionID = id()
    instanceID = id()
    pendingOvertureID = id()
    committedOvertureID = id()
    antiphonID = id()
    notationID = id()
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(submissionID)', '\(user)');
      INSERT INTO bibliographic_instances (id, batch_id, source_url, language, processing_status, title, type)
        VALUES ('\(instanceID)', '\(submissionID)', '\(sourceURL)', 'eng', 'pending', 'Web tests commit \(instanceID.prefix(8))', 'report');
      INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_instance_id, source_url, language, processing_status)
        VALUES ('\(pendingOvertureID)', '\(submissionID)', '\(instanceID)', '\(sourceURL)', 'eng', 'pending');
      INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_instance_id, source_url, language, processing_status, committed_by_user_id, committed_at)
        VALUES ('\(committedOvertureID)', '\(submissionID)', '\(instanceID)', '\(sourceURL)', 'eng', 'pending', '\(user)', now());
      INSERT INTO bibliographic_antiphons (id, bibliographic_overture_id, requested_by_user_id, semblance_service_ids_json, processing_status)
        VALUES ('\(antiphonID)', '\(committedOvertureID)', '\(user)', '[]', 'submitted');
      INSERT INTO bibliographic_notations (id, thread_id, bibliographic_antiphon_id, proposed_content_json, metadata_json, processing_status)
        VALUES ('\(notationID)', '\(notationID)', '\(antiphonID)', '{"teiXml":""}', '{"language":"eng","sourceUrl":"\(sourceURL)","sourceKind":"iiif-manifest"}', 'pending');
      COMMIT;
      """)
  }

  /// Whether both objects are still uncommitted.
  func stillPending() throws -> Bool {
    let overture = try TestAdmin.query(
      "SELECT committed_at IS NULL FROM bibliographic_overtures WHERE id = '\(pendingOvertureID)'")
    let notation = try TestAdmin.query(
      "SELECT processing_status FROM bibliographic_notations WHERE id = '\(notationID)'")
    return overture == "t" && notation == "pending"
  }

  func remove() {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM bibliographic_notations WHERE id = '\(notationID)';
      DELETE FROM bibliographic_antiphons WHERE id = '\(antiphonID)';
      DELETE FROM bibliographic_overtures WHERE id IN ('\(pendingOvertureID)', '\(committedOvertureID)');
      UPDATE bibliographic_instances SET deleted_at = now(), deleted_by = '\(owner)' WHERE id = '\(instanceID)';
      COMMIT;
      """)
  }
}
