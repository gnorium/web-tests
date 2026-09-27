import Foundation

/// A work with one attributed version whose tree holds one edition and its
/// manifest, owned by the test's account. Every row by its own id, removed
/// in the order the foreign keys allow.
///
/// With `references`, its hallmark carries a concerto's attributions for
/// the values the version still has, so its page marks them: the language
/// and the title from one catalogue page (one entry, two letters), the
/// edition from another, and the manifest's attribution statement from a
/// third, which sits in the manifest's row, closed until opened.
struct ScratchWork {
  let title: String
  let author: String
  /// What makes its title and author unique: a search finds it by this.
  let suffix: String
  let recordID: String
  let versionID: String
  let path: String
  private let ids: [String: String]

  init(owner: TestAdmin, references: Bool = false) throws {
    let user = try owner.column("id")
    var ids: [String: String] = [:]
    for name in [
      "submission", "evidence", "overture", "concerto", "record", "hallmark", "version", "person", "authorship",
    ] {
      ids[name] = UUID().uuidString.lowercased()
    }
    let suffix = String(ids["record"]!.prefix(8))
    self.suffix = suffix
    title = "Web tests placement \(suffix)"
    let slug = "web-tests-placement-\(suffix)"
    author = "Web Tests Author \(suffix)"
    let authorSlug = "web-tests-author-\(suffix)"
    path = "/biblio-records/eng/\(slug)/\(authorSlug)/report"
    // As the server writes them: upper case.
    recordID = ids["record"]!.uppercased()
    versionID = ids["version"]!.uppercased()
    self.ids = ids
    let evidence = ids["evidence"]!.uppercased()
    let statement = references ? #""attribution":"Courtesy of the web tests","# : ""
    let metadata = """
      {"sourceUrl":"https://example.org/web-tests","sourceKind":"iiif-manifest","title":"\(title)","authors":[],\
      "language":"eng","category":"report","edition":"First edition","year":1958,"genres":[],"isTranslation":false,\
      \(statement)"translationChain":[],"activityStatements":[],"formerOwners":[],"citations":[]}
      """
    let shape = """
      {"edition-\(evidence)":{"parent":"work","position":0},"manifest-\(evidence)":{"parent":"edition-\(evidence)","position":0},"work":{"parent":null,"position":0}}
      """
    // Each value as the concerto wrote it, and as the version still has it
    // (`ConcertoLabel.display`), with one reference.
    func attribution(_ field: String, _ value: String, _ url: String) -> String {
      let referencesJSON = """
        [{"kind":"url","quote":"\(value)","retrievedAt":"2026-09-01T00:00:00Z","url":"\(url)","verified":true}]
        """
      return """
        INSERT INTO field_attributions (id, bibliographic_concerto_id, bibliographic_hallmark_id, field, value, reasoning, references_json, created_at)
          VALUES ('\(UUID().uuidString.lowercased())', '\(ids["concerto"]!)', '\(ids["hallmark"]!)', '\(field)', '\(value)', 'Read there.', '\(referencesJSON)', now());
        """
    }
    let attributions =
      references
      ? [
        attribution("language", "English", "https://catalogue.example.org/web-tests"),
        attribution("title", title, "https://catalogue.example.org/web-tests"),
        attribution("edition", "First edition", "https://editions.example.org/web-tests"),
        attribution("attribution", "Courtesy of the web tests", "https://manifests.example.org/web-tests"),
      ].joined(separator: "\n") : ""
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(ids["submission"]!)', '\(user)');
      INSERT INTO bibliographic_evidences (id, batch_id, source_url, language, processing_status, title, category, edition, year)
        VALUES ('\(ids["evidence"]!)', '\(ids["submission"]!)', 'https://example.org/web-tests', 'eng', 'pending', '\(title)', 'report', 'First edition', 1958);
      INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_evidence_id, source_url, language, processing_status)
        VALUES ('\(ids["overture"]!)', '\(ids["submission"]!)', '\(ids["evidence"]!)', 'https://example.org/web-tests', 'eng', 'pending');
      INSERT INTO bibliographic_concertos (id, bibliographic_overture_id, requested_by_user_id, processing_status)
        VALUES ('\(ids["concerto"]!)', '\(ids["overture"]!)', '\(user)', 'submitted');
      INSERT INTO biblio_records (id, corpus_id, title, title_slug, authors, category, language, genres, year, date_display)
        VALUES ('\(ids["record"]!)', (SELECT id FROM corpora ORDER BY created_at LIMIT 1), '\(title)', '\(slug)', '\(authorSlug)',
          'report', 'eng', '[]', 1958, 'AD 1958');
      INSERT INTO persons (id, display_name, slug) VALUES ('\(ids["person"]!)', '\(author)', '\(authorSlug)');
      INSERT INTO biblio_record_authors (id, biblio_record_id, person_id, position)
        VALUES ('\(ids["authorship"]!)', '\(ids["record"]!)', '\(ids["person"]!)', 0);
      INSERT INTO bibliographic_hallmarks (id, thread_id, bibliographic_overture_id, bibliographic_concerto_id, biblio_record_id, metadata_json, processing_status, permitted_by_user_id, permitted_at)
        VALUES ('\(ids["hallmark"]!)', '\(ids["hallmark"]!)', '\(ids["overture"]!)', '\(ids["concerto"]!)', '\(ids["record"]!)', '\(metadata)', 'permitted', '\(user)', now());
      \(attributions)
      INSERT INTO biblio_record_versions (id, biblio_record_id, bibliographic_hallmark_id, metadata_json, shape_json, treatment, created_at)
        VALUES ('\(ids["version"]!)', '\(ids["record"]!)', '\(ids["hallmark"]!)', '\(metadata)', '\(shape)', 1, now());
      COMMIT;
      """)
  }

  func remove() {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM biblio_record_versions WHERE id = '\(ids["version"]!)';
      DELETE FROM field_attributions WHERE bibliographic_hallmark_id = '\(ids["hallmark"]!)';
      DELETE FROM bibliographic_hallmarks WHERE id = '\(ids["hallmark"]!)';
      DELETE FROM bibliographic_concertos WHERE id = '\(ids["concerto"]!)';
      DELETE FROM url_histories WHERE entity_id = '\(ids["record"]!)';
      DELETE FROM biblio_record_authors WHERE id = '\(ids["authorship"]!)';
      DELETE FROM biblio_records WHERE id = '\(ids["record"]!)';
      DELETE FROM url_histories WHERE entity_id = '\(ids["person"]!)';
      DELETE FROM persons WHERE id = '\(ids["person"]!)';
      DELETE FROM bibliographic_overtures WHERE id = '\(ids["overture"]!)';
      DELETE FROM bibliographic_evidences WHERE id = '\(ids["evidence"]!)';
      DELETE FROM submissions WHERE id = '\(ids["submission"]!)';
      COMMIT;
      """)
  }
}
