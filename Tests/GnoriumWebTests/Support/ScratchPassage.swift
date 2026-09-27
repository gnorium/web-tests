import Foundation

/// A work with one permitted, text-bearing version (a proposal's TEI, one
/// page) indexed in the dev concordance, owned by the test's account, and
/// two passages cited in it: what Submit Sentiment resolves its utterances
/// from. The work was made in AD 1976 at Oxford by its one author. Every row
/// by its own id, removed in the order the foreign keys allow; the
/// concordance's rows removed from its SQLite file.
struct ScratchPassage {
  let title: String
  let author: String
  let recordID: String
  let versionID: String
  let canvasID: String
  /// The two passages' anchors, as the form's `anchors=` takes them.
  let anchorsJSON: String
  let anchorIDs: [String]
  private let ids: [String: String]

  /// The dev concordance (`make python-concordance`) and its SQLite file.
  static let concordanceURL = URL(string: ProcessInfo.processInfo.environment["GNORIUM_CONCORDANCE_URL"] ?? "http://127.0.0.1:8006")!
  static let concordanceDB =
    ProcessInfo.processInfo.environment["GNORIUM_CONCORDANCE_DB"]
    ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("gnorium-python/data/concordance.sqlite3").path

  /// Why the suite can't run: no concordance to resolve the passages.
  static func unavailableReason() async -> String? {
    var request = URLRequest(url: concordanceURL.appendingPathComponent("health"))
    request.timeoutInterval = 3
    guard let (_, response) = try? await URLSession.shared.data(for: request),
      (response as? HTTPURLResponse)?.statusCode == 200
    else { return "The concordance is not running at \(concordanceURL) (make python-concordance)." }
    return FileManager.default.fileExists(atPath: concordanceDB) ? nil : "No concordance file at \(concordanceDB)."
  }

  init(owner: TestAdmin) async throws {
    let user = try owner.column("id")
    var ids: [String: String] = [:]
    for name in [
      "submission", "evidence", "overture", "concerto", "record", "proposal", "version", "person", "voice",
    ] {
      ids[name] = UUID().uuidString.lowercased()
    }
    self.ids = ids
    let suffix = String(ids["record"]!.prefix(8))
    title = "Web tests passage \(suffix)"
    let slug = "web-tests-passage-\(suffix)"
    author = "Web Tests Voice \(suffix)"
    recordID = ids["record"]!.uppercased()
    versionID = ids["version"]!.uppercased()
    canvasID = "https://example.org/iiif/web-tests-\(suffix)"
    let tei =
      #"<TEI xmlns=\"http://www.tei-c.org/ns/1.0\"><text><body><pb n=\"192\" facs=\"\#(canvasID)/full/full/0/default.jpg\"/><p>We need a name for the new replicator. The meme is a unit of cultural transmission.</p></body></text></TEI>"#
    let metadata = """
      {"sourceUrl":"https://example.org/web-tests","sourceKind":"iiif-manifest","title":"\(title)",\
      "voices":[{"name":"\(author)","role":"author"}],\
      "language":"eng","category":"book","year":1976,"place":"Oxford","genres":[],"isTranslation":false,\
      "translationChain":[],"activityStatements":[],"citations":[]}
      """
    let shape = #"{"work":{"parent":null,"position":0}}"#
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(ids["submission"]!)', '\(user)');
      INSERT INTO bibliographic_evidences (id, batch_id, source_url, language, processing_status, title, type, year)
        VALUES ('\(ids["evidence"]!)', '\(ids["submission"]!)', 'https://example.org/web-tests', 'eng', 'pending', '\(title)', 'book', 1976);
      INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_evidence_id, source_url, language, processing_status)
        VALUES ('\(ids["overture"]!)', '\(ids["submission"]!)', '\(ids["evidence"]!)', 'https://example.org/web-tests', 'eng', 'pending');
      INSERT INTO bibliographic_concertos (id, bibliographic_overture_id, requested_by_user_id, processing_status)
        VALUES ('\(ids["concerto"]!)', '\(ids["overture"]!)', '\(user)', 'submitted');
      INSERT INTO biblio_records (id, corpus_id, title, title_slug, type, language, genres, year, date_display)
        VALUES ('\(ids["record"]!)', (SELECT id FROM corpora ORDER BY created_at LIMIT 1), '\(title)', '\(slug)',
          'book', 'eng', '[]', 1976, 'AD 1976');
      INSERT INTO persons (id, display_name, slug) VALUES ('\(ids["person"]!)', '\(author)', 'web-tests-voice-\(suffix)');
      INSERT INTO biblio_record_voices (id, biblio_record_id, person_id, role, position)
        VALUES ('\(ids["voice"]!)', '\(ids["record"]!)', '\(ids["person"]!)', 'author', 0);
      INSERT INTO bibliographic_proposals (id, proposed_content_json, processing_status, biblio_record_id, thread_id, metadata_json, bibliographic_concerto_id, permitted_by_user_id, permitted_at)
        VALUES ('\(ids["proposal"]!)', '{"teiXml":"\(tei)"}', 'permitted', '\(ids["record"]!)', '\(ids["proposal"]!)', '\(metadata)', '\(ids["concerto"]!)', '\(user)', now());
      INSERT INTO biblio_record_versions (id, biblio_record_id, bibliographic_proposal_id, metadata_json, shape_json, treatment, created_at)
        VALUES ('\(ids["version"]!)', '\(ids["record"]!)', '\(ids["proposal"]!)', '\(metadata)', '\(shape)', 2, now());
      COMMIT;
      """)
    // The page's text, indexed as the permit indexes it.
    let formatter = ISO8601DateFormatter()
    let index: [String: Any] = [
      "biblio_record_id": ids["record"]!, "version_id": ids["version"]!, "language_code": "eng",
      "permitted_at": formatter.string(from: Date()), "permitter_id": user.lowercased(),
      "canvases": [
        [
          "canvas_id": canvasID,
          "tei_xml":
            #"<TEI xmlns="http://www.tei-c.org/ns/1.0"><text><body><pb n="192" facs="\#(canvasID)/full/full/0/default.jpg"/><p>We need a name for the new replicator. The meme is a unit of cultural transmission.</p></body></text></TEI>"#,
          "date_start": 1976, "date_end": 1976,
        ]
      ],
    ]
    var request = URLRequest(url: Self.concordanceURL.appendingPathComponent("index"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: index)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw NSError(
        domain: "ScratchPassage", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Indexing failed: \(String(decoding: data, as: UTF8.self))"])
    }
    // The whole sentence, and a shorter span of it; "meme" in both.
    anchorIDs = ["web-tests-\(suffix)-1", "web-tests-\(suffix)-2"]
    let anchors: [[String: Any]] = [
      [
        "id": anchorIDs[0], "biblioRecordID": recordID, "versionID": versionID, "canvasID": canvasID,
        "charStart": 1, "charEnd": 84, "headwordStart": 44, "headwordEnd": 48,
      ],
      [
        "id": anchorIDs[1], "biblioRecordID": recordID, "versionID": versionID, "canvasID": canvasID,
        "charStart": 40, "charEnd": 84, "headwordStart": 44, "headwordEnd": 48,
      ],
    ]
    anchorsJSON = String(decoding: try JSONSerialization.data(withJSONObject: anchors), as: UTF8.self)
  }

  /// The form's address with the two passages cited.
  var formPath: String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-_.~")
    return "/mission-control/submit/lexicographic/evidence-sentiment?anchors="
      + (anchorsJSON.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
  }

  func remove() {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM biblio_record_versions WHERE id = '\(ids["version"]!)';
      DELETE FROM bibliographic_proposals WHERE id = '\(ids["proposal"]!)';
      DELETE FROM bibliographic_concertos WHERE id = '\(ids["concerto"]!)';
      DELETE FROM url_histories WHERE entity_id = '\(ids["record"]!)';
      DELETE FROM biblio_record_voices WHERE id = '\(ids["voice"]!)';
      DELETE FROM biblio_records WHERE id = '\(ids["record"]!)';
      DELETE FROM url_histories WHERE entity_id = '\(ids["person"]!)';
      DELETE FROM persons WHERE id = '\(ids["person"]!)';
      DELETE FROM bibliographic_overtures WHERE id = '\(ids["overture"]!)';
      DELETE FROM bibliographic_evidences WHERE id = '\(ids["evidence"]!)';
      DELETE FROM submissions WHERE id = '\(ids["submission"]!)';
      COMMIT;
      """)
    let sqlite = Process()
    sqlite.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    let version = ids["version"]!
    sqlite.arguments = [
      Self.concordanceDB,
      "DELETE FROM tokens WHERE version_id = '\(version)'; DELETE FROM canvases WHERE version_id = '\(version)'; DELETE FROM versions WHERE version_id = '\(version)';",
    ]
    try? sqlite.run()
    sqlite.waitUntilExit()
  }
}
