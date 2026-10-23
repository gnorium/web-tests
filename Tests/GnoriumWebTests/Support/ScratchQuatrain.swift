import Foundation

/// A quatrain over four pages of a committed overture, owned by the test's
/// account, built by SQL (dev has no model): the first page passed (with the
/// page it filed), the second failed, the third running, the fourth not
/// begun. Its status is `calibrating` or `failed`. Every row by its own id,
/// removed in the order the foreign keys allow—except its submission and
/// Figurant, which are submitted input and frozen: the Figurant is
/// soft-discarded, as the site discards one.
///
/// Its source is a PDF with a stored page list, so nothing is ever fetched.
struct ScratchQuatrain {
  /// The pages' labels, in the order the witness binds them.
  static let labels = ["1", "2", "3", "4"]

  let quatrainID: String
  let overtureID: String
  let title: String
  private let submissionID: String
  private let figurantID: String
  private let layoutID: String
  private let nocturneIDs: [String]
  private let owner: String
  private let images: [String]

  var path: String { "/mission-control/quatrains/bibliographic/\(quatrainID)" }
  var overturePath: String { "/mission-control/overtures/bibliographic/\(overtureID)" }
  /// The pages' image service ids, as the quatrain names its scope.
  var services: [String] { images.map { $0.components(separatedBy: "/full/")[0] } }

  /// `failed` leaves it needing an admin's Continue, with the sentence a
  /// failure records.
  init(owner: TestAdmin, status: String = "calibrating") throws {
    precondition(["calibrating", "failed", "submitted"].contains(status))
    self.owner = owner.username
    let user = try owner.column("id")
    func id() -> String { UUID().uuidString.lowercased() }
    submissionID = id()
    figurantID = id()
    overtureID = id()
    quatrainID = id()
    layoutID = id()
    nocturneIDs = (0..<3).map { _ in id() }
    title = "Web tests quatrain \(figurantID.prefix(8))"
    let base = "https://web-tests.invalid/iiif/\(figurantID)"
    images = (1...4).map { "\(base)/p\($0)/full/1300,/0/default.jpg" }
    let pages = Self.labels.enumerated().map { index, label in
      "{\"label\":\"\(label)\",\"imageURL\":\"\(images[index])\"}"
    }.joined(separator: ",")
    let pagesJSON = "[\(pages)]"
    let source = "https://web-tests.invalid/\(figurantID).pdf"
    let scope = "[" + images.map { "\"\($0.components(separatedBy: "/full/")[0])\"" }.joined(separator: ",") + "]"
    let error = status == "failed" ? "'Image 2 cannot be measured.'" : "NULL"
    let services = images.map { $0.components(separatedBy: "/full/")[0] }
    let measured: [[String: String]] = [
      ["type": "thinking", "content": "Measuring the first page."],
      [
        "type": "tool", "name": "measure_image", "arguments": "{}",
        "result": #"{"ok": true, "tool": "measure_image", "em": 20.5}"#, "status": "ok", "call_id": "call_1",
      ],
      ["type": "text", "content": "The first page is measured."],
    ]
    let failedTrace: [[String: String]] = [
      ["type": "thinking", "content": "Trying the second page."],
      ["type": "text", "content": "The second page cannot be measured."],
    ]
    let running: [[String: String]] = [["type": "thinking", "content": "Reading the third page."]]
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(submissionID)', '\(user)');
      INSERT INTO bibliographic_figurants (id, batch_id, source_url, source_kind, source_pages_json, language, processing_status, title, type, created_at)
        VALUES ('\(figurantID)', '\(submissionID)', '\(source)', 'pdf', '\(pagesJSON)', 'eng', 'pending', '\(title)', 'report', now());
      INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_figurant_id, source_url, source_kind, source_pages_json, language, processing_status, title, committed_by_user_id, committed_at, created_at)
        VALUES ('\(overtureID)', '\(submissionID)', '\(figurantID)', '\(source)', 'pdf', '\(pagesJSON)', 'eng', 'pending', '\(title)', '\(user)', now(), now());
      INSERT INTO bibliographic_quatrains (id, bibliographic_overture_id, requested_by_user_id, image_service_ids_json, processing_status, processing_error, created_at, updated_at)
        VALUES ('\(quatrainID)', '\(overtureID)', '\(user)', '\(scope)', '\(status)', \(error), now(), now());
      INSERT INTO bibliographic_calibration_nocturnes (id, bibliographic_quatrain_id, submission_id, process, image, instance_count)
       VALUES (md5('head:' || ('\(quatrainID)'):: text || ':' || coalesce(('\(services[0])')::text, ''))::uuid, '\(quatrainID)', '\(submissionID)', 'calibration', '\(services[0])', 1)
       ON CONFLICT (id) DO UPDATE SET instance_count = bibliographic_calibration_nocturnes.instance_count + 1;
      INSERT INTO bibliographic_calibration_nocturnes (id, bibliographic_quatrain_id, submission_id, process, image, instance_count)
       VALUES (md5('head:' || ('\(quatrainID)'):: text || ':' || coalesce(('\(services[1])')::text, ''))::uuid, '\(quatrainID)', '\(submissionID)', 'calibration', '\(services[1])', 1)
       ON CONFLICT (id) DO UPDATE SET instance_count = bibliographic_calibration_nocturnes.instance_count + 1;
      INSERT INTO bibliographic_calibration_nocturnes (id, bibliographic_quatrain_id, submission_id, process, image, instance_count)
       VALUES (md5('head:' || ('\(quatrainID)'):: text || ':' || coalesce(('\(services[2])')::text, ''))::uuid, '\(quatrainID)', '\(submissionID)', 'calibration', '\(services[2])', 1)
       ON CONFLICT (id) DO UPDATE SET instance_count = bibliographic_calibration_nocturnes.instance_count + 1;
      INSERT INTO bibliographic_calibration_nocturne_instances (id, nocturne_id, bibliographic_quatrain_id, submission_id, process, image, instance, provider, model, result, error_message, duration_ms, created_at, finished_at)
      VALUES ('\(nocturneIDs[0])', md5('head:' || ('\(quatrainID)'):: text || ':' || coalesce(('\(services[0])')::text, ''))::uuid, '\(quatrainID)', '\(submissionID)', 'calibration', '\(services[0])', 1, 'DeepSeek', 'deepseek-flash', 'passed', NULL, 1500, now(), now()),
        ('\(nocturneIDs[1])', md5('head:' || ('\(quatrainID)'):: text || ':' || coalesce(('\(services[1])')::text, ''))::uuid, '\(quatrainID)', '\(submissionID)', 'calibration', '\(services[1])', 1, 'DeepSeek', 'deepseek-flash', 'failed', 'Image 2 cannot be measured.', 900, now(), now()),
        ('\(nocturneIDs[2])', md5('head:' || ('\(quatrainID)'):: text || ':' || coalesce(('\(services[2])')::text, ''))::uuid, '\(quatrainID)', '\(submissionID)', 'calibration', '\(services[2])', 1, 'DeepSeek', 'deepseek-flash', '\(status == "submitted" ? "passed" : "running")', NULL, NULL, now(), NULL);
      INSERT INTO scan_layouts (id, image_url, fetched_url, bytes_sha256, width, height, measuring_version, layout, fetch_ms, measure_ms)
        VALUES ('\(layoutID)', '\(images[0])', '\(images[0])', '\(String(repeating: "a", count: 64))', 100, 100, '\(String(repeating: "b", count: 64))', '{}'::jsonb, 1, 1);
      INSERT INTO calibration_pages (bibliographic_calibration_nocturne_instance_id, bibliographic_overture_id, image, ordinal, label, layout_id, measuring_version, em, judgment_json, tool_hashes_json, facts_json)
        VALUES ('\(nocturneIDs[0])', '\(overtureID)', '\(services[0])', 1, '1', '\(layoutID)', '\(String(repeating: "b", count: 64))', 20.5, '{}', '{}', '{"width":2000.0,"body":45.4,"measure":55.1,"height":76.4}');
      \(try SessionTrace.append(measured, table: "bibliographic_calibration_nocturne_instances", id: nocturneIDs[0]))
      \(try SessionTrace.append(failedTrace, table: "bibliographic_calibration_nocturne_instances", id: nocturneIDs[1]))
      \(try SessionTrace.append(running, table: "bibliographic_calibration_nocturne_instances", id: nocturneIDs[2]))
      COMMIT;
      """)
  }

  /// The quatrain's status now, as stored.
  func status() throws -> String {
    try TestAdmin.query("SELECT processing_status FROM bibliographic_quatrains WHERE id = '\(quatrainID)'")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// The sentence its failure records now; empty while there is none.
  func error() throws -> String {
    try TestAdmin.query("SELECT coalesce(processing_error, '') FROM bibliographic_quatrains WHERE id = '\(quatrainID)'")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func remove() {
    let table = "bibliographic_calibration_nocturne_instances"
    _ = try? TestAdmin.query(
      """
      BEGIN;
      \(SessionTrace.delete(table: table, where: "bibliographic_quatrain_id = '\(quatrainID)'"))
      DELETE FROM calibration_observations WHERE bibliographic_calibration_nocturne_instance_id IN (SELECT id FROM \(table) WHERE bibliographic_quatrain_id = '\(quatrainID)');
      DELETE FROM calibration_pages WHERE bibliographic_overture_id = '\(overtureID)';
      DELETE FROM model_calls WHERE bibliographic_calibration_nocturne_instance_id IN (SELECT id FROM \(table) WHERE bibliographic_quatrain_id = '\(quatrainID)');
      DELETE FROM \(table) WHERE bibliographic_quatrain_id = '\(quatrainID)';
      DELETE FROM scan_layouts WHERE id = '\(layoutID)';
      DELETE FROM bibliographic_quatrains WHERE id = '\(quatrainID)';
      DELETE FROM survey_images WHERE witness_id = '\(figurantID)';
      DELETE FROM bibliographic_overtures WHERE id = '\(overtureID)';
      UPDATE bibliographic_figurants SET discarded_at = now(), discarded_by = '\(owner)' WHERE id = '\(figurantID)';
      COMMIT;
      """)
  }
}
