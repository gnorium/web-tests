import Foundation

/// A work with one formulated version whose tree holds one edition and its
/// manifest, owned by the test's account. Every row by its own id, removed
/// in the order the foreign keys allow—except its submission and Instance,
/// which are submitted input and frozen: the Instance is soft-deleted, as
/// the site deletes one, and both stay.
///
/// With `references`, its overture carries a madrigal's formulations for
/// the values the version still has, which the overture's page lists under
/// each field (the record's page lists none): one catalog page for the
/// language, the title and the manifest's formulation statement, a second
/// page for the title too, and a third for the edition.
///
/// Its author is a typed name, as every voice is.
struct ScratchWork {
  let title: String
  let author: String
  /// What makes its title and author unique: a search finds it by this.
  let suffix: String
  let recordID: String
  let versionID: String
  /// Its overture's id, as the server writes it: upper case.
  let overtureID: String
  /// The madrigal its overture answers (submitted), lower case.
  var madrigalID: String { ids["madrigal"]! }
  let path: String
  private let ids: [String: String]
  private let owner: String

  /// `sourceURL` is its Instance's and baseline's source URL, fixed at
  /// submission (a submitted Instance can't be changed).
  init(owner: TestAdmin, references: Bool = false, sourceURL: String = "https://example.org/web-tests") throws {
    self.owner = owner.username
    let user = try owner.column("id")
    var ids: [String: String] = [:]
    for name in [
      "submission", "instance", "baseline", "madrigal", "record", "overture", "version", "authorship",
    ] {
      ids[name] = UUID().uuidString.lowercased()
    }
    let suffix = String(ids["record"]!.prefix(8))
    self.suffix = suffix
    title = "Web tests placement \(suffix)"
    let slug = "web-tests-placement-\(suffix)"
    author = "Web Tests Author \(suffix)"
    path = "/biblio-records/eng/\(slug)/report"
    // As the server writes them: upper case.
    recordID = ids["record"]!.uppercased()
    versionID = ids["version"]!.uppercased()
    overtureID = ids["overture"]!.uppercased()
    self.ids = ids
    let instance = ids["instance"]!.uppercased()
    let statement = references ? #""attribution":"Courtesy of the web tests","# : ""
    let metadata = """
      {"sourceUrl":"https://example.org/web-tests","sourceKind":"iiif-manifest","title":"\(title)",\
      "voices":[{"name":"\(author)","role":"author"}],\
      "language":"eng","category":"report","edition":"First edition","year":1958,"genres":[],"isTranslation":false,\
      \(statement)"translationChain":[],"activityStatements":[],"citations":[]}
      """
    let shape = """
      {"edition-\(instance)":{"parent":"work","position":0},"manifest-\(instance)":{"parent":"edition-\(instance)","position":0},"work":{"parent":null,"position":0}}
      """
    // Each value as the madrigal wrote it, and as the version still has it
    // (`MadrigalLabel.display`), with its references.
    func formulation(_ field: String, _ value: String, _ urls: String...) -> String {
      let referencesJSON =
        "["
        + urls.map {
          #"{"kind":"url","quote":"\#(value)","retrievedAt":"2026-09-01T00:00:00Z","url":"\#($0)","verified":true}"#
        }.joined(separator: ",") + "]"
      return """
        INSERT INTO field_references (id, bibliographic_madrigal_id, bibliographic_overture_id, field, value, reasoning, references_json, created_at)
          VALUES ('\(UUID().uuidString.lowercased())', '\(ids["madrigal"]!)', '\(ids["overture"]!)', '\(field)', '\(value)', 'Read there.', '\(referencesJSON)', now());
        """
    }
    let formulations =
      references
      ? [
        formulation("language", "English", "https://catalogue.example.org/web-tests"),
        formulation(
          "title", title, "https://catalogue.example.org/web-tests", "https://titles.example.org/web-tests"),
        formulation("edition", "First edition", "https://editions.example.org/web-tests"),
        formulation("attribution", "Courtesy of the web tests", "https://catalogue.example.org/web-tests"),
      ].joined(separator: "\n") : ""
    let voice = """
      INSERT INTO biblio_record_voices (id, biblio_record_id, name, role, position)
        VALUES ('\(ids["authorship"]!)', '\(ids["record"]!)', '\(author)', 'author', 0);
      """
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(ids["submission"]!)', '\(user)');
      INSERT INTO bibliographic_instances (id, batch_id, source_url, language, processing_status, title, type, edition, year)
        VALUES ('\(ids["instance"]!)', '\(ids["submission"]!)', '\(sourceURL)', 'eng', 'pending', '\(title)', 'report', 'First edition', 1958);
      INSERT INTO bibliographic_baselines (id, batch_id, bibliographic_instance_id, source_url, language, processing_status)
        VALUES ('\(ids["baseline"]!)', '\(ids["submission"]!)', '\(ids["instance"]!)', '\(sourceURL)', 'eng', 'pending');
      INSERT INTO bibliographic_madrigals (id, bibliographic_baseline_id, requested_by_user_id, processing_status)
        VALUES ('\(ids["madrigal"]!)', '\(ids["baseline"]!)', '\(user)', 'submitted');
      INSERT INTO biblio_records (id, corpus_id, title, title_slug, type, language, genres, year, date_display)
        VALUES ('\(ids["record"]!)', (SELECT id FROM corpora ORDER BY created_at LIMIT 1), '\(title)', '\(slug)',
          'report', 'eng', '[]', 1958, 'AD 1958');
      \(voice)
      INSERT INTO bibliographic_overtures (id, thread_id, bibliographic_baseline_id, bibliographic_madrigal_id, biblio_record_id, metadata_json, processing_status, permitted_by_user_id, permitted_at)
        VALUES ('\(ids["overture"]!)', '\(ids["overture"]!)', '\(ids["baseline"]!)', '\(ids["madrigal"]!)', '\(ids["record"]!)', '\(metadata)', 'permitted', '\(user)', now());
      \(formulations)
      INSERT INTO biblio_record_versions (id, biblio_record_id, bibliographic_overture_id, metadata_json, shape_json, treatment, created_at)
        VALUES ('\(ids["version"]!)', '\(ids["record"]!)', '\(ids["overture"]!)', '\(metadata)', '\(shape)', 1, now());
      COMMIT;
      """)
  }

  func remove() {
    // An amendment submitted against it is a frozen Instance naming its
    // record and version (no foreign key): then the work stays whole, or
    // the Instance would name nothing and every page loading it would fail.
    let amended = "EXISTS (SELECT 1 FROM bibliographic_amendment_instances WHERE biblio_record_id = '\(ids["record"]!)')"
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM biblio_record_versions WHERE id = '\(ids["version"]!)' AND NOT \(amended);
      DELETE FROM field_references WHERE bibliographic_overture_id = '\(ids["overture"]!)' AND NOT \(amended);
      DELETE FROM bibliographic_overtures WHERE id = '\(ids["overture"]!)' AND NOT \(amended);
      DELETE FROM bibliographic_madrigals WHERE id = '\(ids["madrigal"]!)' AND NOT \(amended);
      DELETE FROM url_histories WHERE entity_id = '\(ids["record"]!)' AND NOT \(amended);
      DELETE FROM biblio_record_voices WHERE id = '\(ids["authorship"]!)' AND NOT \(amended);
      DELETE FROM biblio_records WHERE id = '\(ids["record"]!)' AND NOT \(amended);
      DELETE FROM bibliographic_baselines WHERE id = '\(ids["baseline"]!)' AND NOT \(amended);
      UPDATE bibliographic_instances SET deleted_at = now(), deleted_by = '\(owner)' WHERE id = '\(ids["instance"]!)';
      COMMIT;
      """)
  }
}
