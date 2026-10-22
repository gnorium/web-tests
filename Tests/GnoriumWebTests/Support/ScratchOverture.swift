import Foundation

/// An overture of four pages at a stage of its chain (user, 2026-10-21),
/// owned by the test's account and built by SQL (dev has no model): committed
/// or not; when `calibrated` > 0, its Commit's quatrain (submitted) with the
/// first `calibrated` pages filed and the halftone it submitted; when
/// `explicationCommitted` (every page calibrated), that halftone committed
/// and the antiphon its Commit made, holding the frozen header. Every row by
/// its own id, removed in the order the foreign keys allow—except its
/// submission and Figurant, which are submitted input and frozen: the
/// Figurant is soft-discarded, as the site discards one.
///
/// Its source is a PDF with a stored page list, so nothing is ever fetched.
struct ScratchOverture {
  /// The pages' labels, in the order the witness binds them.
  static let labels = ["1", "2", "3", "4"]

  let overtureID: String
  let quatrainID: String
  let halftoneID: String
  let antiphonID: String
  let title: String
  private let submissionID: String
  private let figurantID: String
  private let layoutID: String
  private let nocturneIDs: [String]
  private let owner: String
  private let images: [String]

  var path: String { "/mission-control/overtures/bibliographic/\(overtureID)" }
  var quatrainPath: String { "/mission-control/quatrains/bibliographic/\(quatrainID)" }
  var halftonePath: String { "/mission-control/halftones/bibliographic/\(halftoneID)" }
  var antiphonPath: String { "/mission-control/antiphons/bibliographic/\(antiphonID)" }
  /// The pages' image service ids, as the roster names them.
  var services: [String] { images.map { $0.components(separatedBy: "/full/")[0] } }

  init(owner: TestAdmin, sealed: Bool = true, calibrated: Int = 0, explicationCommitted: Bool = false) throws {
    precondition((0...4).contains(calibrated) && (!explicationCommitted || calibrated == 4))
    self.owner = owner.username
    let user = try owner.column("id")
    func id() -> String { UUID().uuidString.lowercased() }
    submissionID = id()
    figurantID = id()
    overtureID = id()
    quatrainID = id()
    halftoneID = id()
    antiphonID = id()
    layoutID = id()
    nocturneIDs = (0..<4).map { _ in id() }
    title = "Web tests overture \(figurantID.prefix(8))"
    let base = "https://web-tests.invalid/iiif/\(figurantID)"
    images = (1...4).map { "\(base)/p\($0)/full/1300,/0/default.jpg" }
    let pages = Self.labels.enumerated().map { index, label in
      "{\"label\":\"\(label)\",\"imageURL\":\"\(images[index])\"}"
    }.joined(separator: ",")
    let pagesJSON = "[\(pages)]"
    let source = "https://web-tests.invalid/\(figurantID).pdf"
    let services = images.map { $0.components(separatedBy: "/full/")[0] }
    let scope = "[" + services.map { "\"\($0)\"" }.joined(separator: ",") + "]"
    let committed = sealed || calibrated > 0 ? "'\(user)', now()" : "NULL, NULL"
    let fields = #"{"title":"\#(title)","language":"eng","sourceUrl":"\#(source)","sourceKind":"pdf","type":"report"}"#
    var statements = """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(submissionID)', '\(user)');
      INSERT INTO bibliographic_figurants (id, batch_id, source_url, source_kind, source_pages_json, language, processing_status, title, type, created_at)
        VALUES ('\(figurantID)', '\(submissionID)', '\(source)', 'pdf', '\(pagesJSON)', 'eng', 'pending', '\(title)', 'report', now());
      INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_figurant_id, source_url, source_kind, source_pages_json, language, processing_status, title, committed_by_user_id, committed_at, created_at)
        VALUES ('\(overtureID)', '\(submissionID)', '\(figurantID)', '\(source)', 'pdf', '\(pagesJSON)', 'eng', 'pending', '\(title)', \(committed), now());
      """
    if calibrated > 0 {
      // The overture's Commit made one quatrain over every page; it filed
      // `calibrated` of them and submitted the halftone.
      statements += """

        INSERT INTO bibliographic_quatrains (id, bibliographic_overture_id, requested_by_user_id, image_service_ids_json, processing_status, created_at, updated_at)
          VALUES ('\(quatrainID)', '\(overtureID)', '\(user)', '\(scope)', 'submitted', now(), now());
        INSERT INTO scan_layouts (id, image_url, fetched_url, bytes_sha256, width, height, measuring_version, layout, fetch_ms, measure_ms)
          VALUES ('\(layoutID)', '\(images[0])', '\(images[0])', '\(String(repeating: "a", count: 64))', 100, 100, '\(String(repeating: "b", count: 64))', '{}'::jsonb, 1, 1);
        """
      for index in 0..<calibrated {
        statements += """

          INSERT INTO bibliographic_calibration_nocturnes (id, bibliographic_quatrain_id, submission_id, process, image, instance, provider, model, result, duration_ms, created_at, finished_at)
            VALUES ('\(nocturneIDs[index])', '\(quatrainID)', '\(submissionID)', 'calibration', '\(services[index])', 1, 'DeepSeek', 'deepseek-flash', 'passed', 1500, now() - interval '1 minute', now() - interval '1 minute');
          INSERT INTO calibration_pages (bibliographic_calibration_nocturne_id, bibliographic_overture_id, image, ordinal, label, layout_id, measuring_version, em, judgment_json, tool_hashes_json, facts_json, created_at)
            VALUES ('\(nocturneIDs[index])', '\(overtureID)', '\(services[index])', \(index + 1), '\(index + 1)', '\(layoutID)', '\(String(repeating: "b", count: 64))', 20.5, '{}', '{}', '{"width":2000.0,"body":45.4,"measure":55.1,"height":76.4}', now() - interval '1 minute');
          """
      }
      let closed = explicationCommitted ? "'\(user)', now()" : "NULL, NULL"
      statements += """

        INSERT INTO bibliographic_halftones (id, bibliographic_overture_id, bibliographic_quatrain_id, metadata_json, committed_by_user_id, committed_at, created_at, updated_at)
          VALUES ('\(halftoneID)', '\(overtureID)', '\(quatrainID)', '\(fields)', \(closed), now(), now());
        """
    }
    if explicationCommitted {
      let tei = "<TEI><teiHeader/><text><body>"
        + images.enumerated().map { "<pb n=\"\($0.offset + 1)\" facs=\"\($0.element)\"/>" }.joined() + "</body></text></TEI>"
      let content = String(decoding: try JSONSerialization.data(withJSONObject: ["teiXml": tei]), as: UTF8.self)
        .replacingOccurrences(of: "'", with: "''")
      let header = #"{"header_tei":"<teiHeader/>","face":null,"measuring_versions":[],"page_count":4,"fitted":[]}"#
      statements += """

        INSERT INTO bibliographic_antiphons (id, bibliographic_halftone_id, document_json, header_json, metadata_json, requested_by_user_id, image_service_ids_json, processing_status, created_at, updated_at)
          VALUES ('\(antiphonID)', '\(halftoneID)', '\(content)', '\(header)', '\(fields)', '\(user)', '\(scope)', 'submitted', now(), now());
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
      DELETE FROM bibliographic_antiphons WHERE id = '\(antiphonID)';
      DELETE FROM bibliographic_halftones WHERE id = '\(halftoneID)';
      \(SessionTrace.delete(table: table, where: "bibliographic_quatrain_id = '\(quatrainID)'"))
      DELETE FROM calibration_observations WHERE bibliographic_calibration_nocturne_id IN (SELECT id FROM \(table) WHERE bibliographic_quatrain_id = '\(quatrainID)');
      DELETE FROM calibration_pages WHERE bibliographic_overture_id = '\(overtureID)';
      DELETE FROM model_calls WHERE bibliographic_calibration_nocturne_id IN (SELECT id FROM \(table) WHERE bibliographic_quatrain_id = '\(quatrainID)');
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
