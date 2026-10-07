import Foundation

/// Two Disputorium objects waiting on a commit, owned by the test's
/// account: a pending baseline, with one way to commit, and a pending
/// overture (its own baseline committed, its madrigal submitted), with
/// two. Every row by its own id, removed in the order the foreign keys
/// allow—except its submission and Instance, which are submitted input and
/// frozen: the Instance is soft-deleted, as the site deletes one. Nothing here is ever committed: a test only opens and cancels.
/// The overture's metadata holds what the witness's fields require (its
/// page decodes them): the language, the source URL and its kind.
struct ScratchCommit {
  /// A IIIF manifest no one serves: `.invalid` never resolves, so the
  /// server's manifest route answers at once that it could not be fetched,
  /// and the viewer pages nothing, quietly.
  static let sourceURL = "https://web-tests.invalid/manifest.json"

  private let submissionID: String
  private let instanceID: String
  private let pendingBaselineID: String
  private let committedBaselineID: String
  private let madrigalID: String
  private let overtureID: String
  private let owner: String

  var baselinePath: String { "/mission-control/baselines/bibliographic/\(pendingBaselineID)" }
  var overturePath: String { "/mission-control/overtures/bibliographic/\(overtureID)" }

  init(owner: TestAdmin, sourceURL: String = ScratchCommit.sourceURL) throws {
    let user = try owner.column("id")
    self.owner = owner.username
    func id() -> String { UUID().uuidString.lowercased() }
    submissionID = id()
    instanceID = id()
    pendingBaselineID = id()
    committedBaselineID = id()
    madrigalID = id()
    overtureID = id()
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(submissionID)', '\(user)');
      INSERT INTO bibliographic_instances (id, batch_id, source_url, language, processing_status, title, type)
        VALUES ('\(instanceID)', '\(submissionID)', '\(sourceURL)', 'eng', 'pending', 'Web tests commit \(instanceID.prefix(8))', 'report');
      INSERT INTO bibliographic_baselines (id, batch_id, bibliographic_instance_id, source_url, language, processing_status)
        VALUES ('\(pendingBaselineID)', '\(submissionID)', '\(instanceID)', '\(sourceURL)', 'eng', 'pending');
      INSERT INTO bibliographic_baselines (id, batch_id, bibliographic_instance_id, source_url, language, processing_status, committed_by_user_id, committed_at)
        VALUES ('\(committedBaselineID)', '\(submissionID)', '\(instanceID)', '\(sourceURL)', 'eng', 'pending', '\(user)', now());
      INSERT INTO bibliographic_madrigals (id, bibliographic_baseline_id, requested_by_user_id, processing_status)
        VALUES ('\(madrigalID)', '\(committedBaselineID)', '\(user)', 'submitted');
      INSERT INTO bibliographic_overtures (id, thread_id, bibliographic_baseline_id, bibliographic_madrigal_id, metadata_json, processing_status)
        VALUES ('\(overtureID)', '\(overtureID)', '\(committedBaselineID)', '\(madrigalID)', '{"language":"eng","sourceUrl":"\(sourceURL)","sourceKind":"iiif-manifest"}', 'pending');
      COMMIT;
      """)
  }

  /// Whether both objects are still uncommitted.
  func stillPending() throws -> Bool {
    let baseline = try TestAdmin.query(
      "SELECT committed_at IS NULL FROM bibliographic_baselines WHERE id = '\(pendingBaselineID)'")
    let overture = try TestAdmin.query(
      "SELECT processing_status FROM bibliographic_overtures WHERE id = '\(overtureID)'")
    return baseline == "t" && overture == "pending"
  }

  func remove() {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM bibliographic_overtures WHERE id = '\(overtureID)';
      DELETE FROM bibliographic_madrigals WHERE id = '\(madrigalID)';
      DELETE FROM bibliographic_baselines WHERE id IN ('\(pendingBaselineID)', '\(committedBaselineID)');
      UPDATE bibliographic_instances SET deleted_at = now(), deleted_by = '\(owner)' WHERE id = '\(instanceID)';
      COMMIT;
      """)
  }
}
