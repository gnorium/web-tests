import Foundation

/// An overture of four pages at a stage of its calibration (BUILD-PLAN U2),
/// owned by the test's account and built by SQL (dev has no model): sealed by
/// its first Commit or not, with the first `calibrated` pages filed by a
/// submitted quatrain, and, when `promoted`, the madrigal its Commit made
/// with the header it froze. Every row by its own id, removed in the order
/// the foreign keys allow—except its submission and Fountain, which are
/// submitted input and frozen: the Fountain is soft-deleted, as the site
/// deletes one.
///
/// Its source is a PDF with a stored page list, so nothing is ever fetched.
struct ScratchOverture {
  /// The pages' labels, in the order the witness binds them.
  static let labels = ["1", "2", "3", "4"]

  let overtureID: String
  let madrigalID: String
  let title: String
  private let submissionID: String
  private let fountainID: String
  private let quatrainID: String
  private let layoutID: String
  private let nocturneIDs: [String]
  private let owner: String
  private let images: [String]

  var path: String { "/mission-control/overtures/bibliographic/\(overtureID)" }
  var madrigalPath: String { "/mission-control/madrigals/bibliographic/\(madrigalID)" }
  /// The pages' image service ids, as the overture's roster names them.
  var services: [String] { images.map { $0.components(separatedBy: "/full/")[0] } }

  init(owner: TestAdmin, sealed: Bool = true, calibrated: Int = 0, promoted: Bool = false) throws {
    precondition((0...4).contains(calibrated) && (!promoted || calibrated == 4))
    self.owner = owner.username
    let user = try owner.column("id")
    func id() -> String { UUID().uuidString.lowercased() }
    submissionID = id()
    fountainID = id()
    overtureID = id()
    madrigalID = id()
    quatrainID = id()
    layoutID = id()
    nocturneIDs = (0..<4).map { _ in id() }
    title = "Web tests overture \(fountainID.prefix(8))"
    let base = "https://web-tests.invalid/iiif/\(fountainID)"
    images = (1...4).map { "\(base)/p\($0)/full/1300,/0/default.jpg" }
    let pages = Self.labels.enumerated().map { index, label in
      "{\"label\":\"\(label)\",\"imageURL\":\"\(images[index])\"}"
    }.joined(separator: ",")
    let pagesJSON = "[\(pages)]"
    let source = "https://web-tests.invalid/\(fountainID).pdf"
    let services = images.map { $0.components(separatedBy: "/full/")[0] }
    let scope = "[" + services.prefix(calibrated).map { "\"\($0)\"" }.joined(separator: ",") + "]"
    let sealing = sealed || calibrated > 0 || promoted
    let committed = sealing ? "'\(user)', now()" : "NULL, NULL"
    var statements = """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(submissionID)', '\(user)');
      INSERT INTO bibliographic_fountains (id, batch_id, source_url, source_kind, source_pages_json, language, processing_status, title, type, created_at)
        VALUES ('\(fountainID)', '\(submissionID)', '\(source)', 'pdf', '\(pagesJSON)', 'eng', 'pending', '\(title)', 'report', now());
      INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_fountain_id, source_url, source_kind, source_pages_json, language, processing_status, title, committed_by_user_id, committed_at, created_at)
        VALUES ('\(overtureID)', '\(submissionID)', '\(fountainID)', '\(source)', 'pdf', '\(pagesJSON)', 'eng', 'pending', '\(title)', \(committed), now());
      """
    if calibrated > 0 {
      statements += """

        INSERT INTO bibliographic_quatrains (id, bibliographic_overture_id, requested_by_user_id, resemblance_service_ids_json, processing_status, created_at, updated_at)
          VALUES ('\(quatrainID)', '\(overtureID)', '\(user)', '\(scope)', 'submitted', now(), now());
        INSERT INTO scan_layouts (id, image_url, fetched_url, bytes_sha256, width, height, analysis_version, layout, fetch_ms, measure_ms)
          VALUES ('\(layoutID)', '\(images[0])', '\(images[0])', '\(String(repeating: "a", count: 64))', 100, 100, '\(String(repeating: "b", count: 64))', '{}'::jsonb, 1, 1);
        """
      for index in 0..<calibrated {
        statements += """

          INSERT INTO bibliographic_calibration_nocturnes (id, bibliographic_quatrain_id, submission_id, process, resemblance, instance, provider, model, result, duration_ms, created_at, finished_at)
            VALUES ('\(nocturneIDs[index])', '\(quatrainID)', '\(submissionID)', 'calibration', '\(services[index])', 1, 'DeepSeek', 'deepseek-flash', 'passed', 1500, now() - interval '1 minute', now() - interval '1 minute');
          INSERT INTO calibration_pages (bibliographic_calibration_nocturne_id, bibliographic_overture_id, resemblance, ordinal, label, layout_id, analysis_version, em, judgment_json, tool_hashes_json, facts_json, created_at)
            VALUES ('\(nocturneIDs[index])', '\(overtureID)', '\(services[index])', \(index + 1), '\(index + 1)', '\(layoutID)', '\(String(repeating: "b", count: 64))', 20.5, '{}', '{}', '{"width":2000.0,"body":45.4,"measure":55.1,"height":76.4}', now() - interval '1 minute');
          """
      }
    }
    if promoted {
      let tei = "<TEI><text><body>"
        + images.enumerated().map { "<pb n=\"\($0.offset + 1)\" facs=\"\($0.element)\"/>" }.joined() + "</body></text></TEI>"
      let content = String(decoding: try JSONSerialization.data(withJSONObject: ["teiXml": tei]), as: UTF8.self)
        .replacingOccurrences(of: "'", with: "''")
      statements += """

        INSERT INTO bibliographic_madrigals (id, thread_id, bibliographic_overture_id, proposed_content_json, metadata_json, processing_status, created_at, updated_at)
          VALUES ('\(madrigalID)', '\(madrigalID)', '\(overtureID)', '\(content)', '{"language":"eng","sourceUrl":"\(source)","sourceKind":"pdf"}', 'pending', now(), now());
        INSERT INTO bibliographic_headers (bibliographic_overture_id, header_tei, bibliographic_madrigal_id, frozen_by_user_id, analysis_versions_json, page_count)
          VALUES ('\(overtureID)', '<teiHeader/>', '\(madrigalID)', '\(user)', '[]', 4);
        """
    }
    statements += "\nCOMMIT;"
    _ = try TestAdmin.query(statements)
  }

  func remove() {
    let table = "bibliographic_calibration_nocturnes"
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM bibliographic_headers WHERE bibliographic_overture_id = '\(overtureID)';
      DELETE FROM bibliographic_madrigals WHERE id = '\(madrigalID)';
      \(SessionTrace.delete(table: table, where: "bibliographic_quatrain_id = '\(quatrainID)'"))
      DELETE FROM calibration_observations WHERE bibliographic_calibration_nocturne_id IN (SELECT id FROM \(table) WHERE bibliographic_quatrain_id = '\(quatrainID)');
      DELETE FROM calibration_pages WHERE bibliographic_overture_id = '\(overtureID)';
      DELETE FROM model_calls WHERE bibliographic_calibration_nocturne_id IN (SELECT id FROM \(table) WHERE bibliographic_quatrain_id = '\(quatrainID)');
      DELETE FROM \(table) WHERE bibliographic_quatrain_id = '\(quatrainID)';
      DELETE FROM scan_layouts WHERE id = '\(layoutID)';
      DELETE FROM bibliographic_quatrains WHERE id = '\(quatrainID)';
      DELETE FROM survey_images WHERE witness_id = '\(fountainID)';
      DELETE FROM bibliographic_overtures WHERE id = '\(overtureID)';
      UPDATE bibliographic_fountains SET deleted_at = now(), deleted_by = '\(owner)' WHERE id = '\(fountainID)';
      COMMIT;
      """)
  }
}
