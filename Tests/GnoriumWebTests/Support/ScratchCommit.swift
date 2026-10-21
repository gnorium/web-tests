import Foundation

/// Two Disputorium objects waiting on a commit, owned by the test's
/// account: a pending overture, with one way to commit, and a pending
/// madrigal (its own overture committed, its quatrain's halftone committed
/// for explication, `ScratchChain`, whose antiphon submitted it) holding
/// one page not read yet, so its one process is explication (user,
/// 2026-10-10). Every row by its own id, removed in the order the foreign keys
/// allow—except its submission and Figurant, which are submitted input and
/// frozen: the Figurant is soft-discarded, as the site discards one. Nothing here is ever committed: a test only opens and cancels.
/// The madrigal's metadata holds what the witness's fields require (its
/// page decodes them): the language, the source URL and its kind.
struct ScratchCommit {
  /// A IIIF manifest no one serves: `.invalid` never resolves, so the
  /// server's manifest route answers at once that it could not be fetched,
  /// and the viewer pages nothing, quietly.
  static let sourceURL = "https://web-tests.invalid/manifest.json"

  private let submissionID: String
  private let figurantID: String
  private let pendingOvertureID: String
  private let committedOvertureID: String
  let madrigalID: String
  private let owner: String
  private let chain = ScratchChain()
  /// The serenade `addEpilogue` committed the madrigal to.
  private let serenadeID = UUID().uuidString.lowercased()

  /// The work's title, which its objects' rows are titled by.
  var title: String { "Web tests commit \(figurantID.prefix(8))" }
  var overturePath: String { "/mission-control/overtures/bibliographic/\(pendingOvertureID)" }
  var madrigalPath: String { "/mission-control/madrigals/bibliographic/\(madrigalID)" }

  /// The committed overture is the Figurant's first, so its chain (down to
  /// the madrigal) is the Figurant's lifetime.
  init(owner: TestAdmin, sourceURL: String = ScratchCommit.sourceURL) throws {
    let user = try owner.column("id")
    self.owner = owner.username
    func id() -> String { UUID().uuidString.lowercased() }
    submissionID = id()
    figurantID = id()
    pendingOvertureID = id()
    committedOvertureID = id()
    madrigalID = id()
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(submissionID)', '\(user)');
      INSERT INTO bibliographic_figurants (id, batch_id, source_url, language, processing_status, title, type, created_at)
        VALUES ('\(figurantID)', '\(submissionID)', '\(sourceURL)', 'eng', 'pending', 'Web tests commit \(figurantID.prefix(8))', 'report', now());
      INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_figurant_id, source_url, language, processing_status, created_at)
        VALUES ('\(pendingOvertureID)', '\(submissionID)', '\(figurantID)', '\(sourceURL)', 'eng', 'pending', now());
      INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_figurant_id, source_url, language, processing_status, committed_by_user_id, committed_at, created_at)
        VALUES ('\(committedOvertureID)', '\(submissionID)', '\(figurantID)', '\(sourceURL)', 'eng', 'pending', '\(user)', now(), now() - interval '1 minute');
      \(chain.insert(overture: committedOvertureID, user: user))
      INSERT INTO bibliographic_madrigals (id, thread_id, bibliographic_antiphon_id, proposed_content_json, metadata_json, processing_status, created_at, updated_at)
        VALUES ('\(madrigalID)', '\(madrigalID)', '\(chain.antiphonID)', '{"teiXml":"<TEI><text><body><pb n=\\"1\\" facs=\\"\(sourceURL.replacingOccurrences(of: "/manifest.json", with: ""))/page-1/full/max/0/default.jpg\\"/></body></text></TEI>"}', '{"language":"eng","sourceUrl":"\(sourceURL)","sourceKind":"iiif-manifest"}', 'pending', now(), now());
      COMMIT;
      """)
  }

  /// Whether both objects are still uncommitted.
  /// The first epilogue: the madrigal committed for translation, its
  /// serenade (submitted) having translated a page of the three for each
  /// service in `translated` (the services are the manifest's `page-1` to
  /// `page-3`), the rest stale where named.
  func addEpilogue(base: String, translated: [Int], stale: [Int] = []) throws {
    let id = UUID().uuidString.lowercased()
    let pages: [[String: Any]] = translated.map { number in
      [
        "service": "\(base)/page-\(number)", "label": "\(number)", "sourceDigest": "d",
        "segments": [["key": "s1", "element": "p", "source": "Alpha", "translation": "Alpha, translated"]],
        "stale": stale.contains(number),
      ]
    }
    let layer: [String: Any] = ["sourceLanguage": "ita", "targetLanguage": "eng", "tei": "", "pages": pages]
    let json = String(decoding: try JSONSerialization.data(withJSONObject: layer), as: UTF8.self)
      .replacingOccurrences(of: "'", with: "''")
    let user = try TestAdmin.query("SELECT id FROM users WHERE username = '\(owner)'")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    _ = try TestAdmin.query(
      """
      BEGIN;
      UPDATE bibliographic_madrigals SET processing_status = 'committed' WHERE id = '\(madrigalID)';
      INSERT INTO bibliographic_serenades (id, bibliographic_madrigal_id, target_language, image_service_ids_json, requested_by_user_id, processing_status)
        VALUES ('\(serenadeID)', '\(madrigalID)', 'eng', '[]', '\(user)', 'submitted') ON CONFLICT (id) DO NOTHING;
      INSERT INTO bibliographic_epilogues (id, thread_id, bibliographic_overture_id, bibliographic_serenade_id, proposed_content_json, metadata_json, translation_json, processing_status)
        SELECT '\(id)', '\(id)', '\(committedOvertureID)', '\(serenadeID)', p.proposed_content_json, p.metadata_json, '\(json)', 'pending'
        FROM bibliographic_madrigals p WHERE p.id = '\(madrigalID)';
      COMMIT;
      """)
  }

  /// The epilogues `addEpilogue` made, gone, so the next is the serenade's one.
  func removeEpilogues() throws {
    _ = try TestAdmin.query("DELETE FROM bibliographic_epilogues WHERE bibliographic_serenade_id = '\(serenadeID)'")
  }

  /// The epilogue `addEpilogue` made last.
  func epiloguePath() throws -> String {
    let id = try TestAdmin.query(
      "SELECT id FROM bibliographic_epilogues WHERE bibliographic_serenade_id = '\(serenadeID)'")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return "/mission-control/epilogues/bibliographic/\(id)"
  }

  /// A revision filed on the madrigal, still open (pending); its id.
  func addOpenRevision() throws -> String {
    let id = UUID().uuidString.lowercased()
    let user = try TestAdmin.query("SELECT id FROM users WHERE username = '\(owner)'")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    _ = try TestAdmin.query("""
      INSERT INTO revisions (id, revisable_type, revisable_id, prompt_changes_json, status, requested_by_user_id, created_at)
      VALUES ('\(id)', 'bibliographicMadrigal', '\(madrigalID)', '[]', 'pending', '\(user)', now())
      """)
    return id
  }

  func stillPending() throws -> Bool {
    let overture = try TestAdmin.query(
      "SELECT committed_at IS NULL FROM bibliographic_overtures WHERE id = '\(pendingOvertureID)'")
    let madrigal = try TestAdmin.query(
      "SELECT processing_status FROM bibliographic_madrigals WHERE id = '\(madrigalID)'")
    return overture == "t" && madrigal == "pending"
  }

  func remove() {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM revisions WHERE revisable_id IN ('\(madrigalID)', '\(pendingOvertureID)');
      DELETE FROM bibliographic_epilogues WHERE bibliographic_serenade_id = '\(serenadeID)';
      DELETE FROM bibliographic_serenades WHERE id = '\(serenadeID)';
      DELETE FROM bibliographic_madrigals WHERE id = '\(madrigalID)';
      \(chain.delete)
      DELETE FROM bibliographic_overtures WHERE id IN ('\(pendingOvertureID)', '\(committedOvertureID)');
      UPDATE bibliographic_figurants SET discarded_at = now(), discarded_by = '\(owner)' WHERE id = '\(figurantID)';
      COMMIT;
      """)
  }
}
