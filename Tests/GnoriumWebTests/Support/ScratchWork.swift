import Foundation

/// A work with one explicated version whose tree holds one edition and its
/// manifest, owned by the test's account: its overture committed, its
/// antiphon submitted, and the madrigal that antiphon made permitted. Every
/// row by its own id, removed in the order the foreign keys allow—except
/// its submission and Folksong, which are submitted input and frozen: the
/// Folksong is soft-deleted, as the site deletes one, and both stay.
///
/// Its author is a typed name, as every voice is.
struct ScratchWork {
  let title: String
  let author: String
  /// What makes its title and author unique: a search finds it by this.
  let suffix: String
  let recordID: String
  let versionID: String
  /// Its overture's id (committed), as the server writes it: upper case.
  let overtureID: String
  /// The madrigal its version was permitted from, as the server writes it:
  /// upper case.
  let madrigalID: String
  let path: String
  private let ids: [String: String]
  private let owner: String

  /// `sourceURL` is its Folksong's and overture's source URL, fixed at
  /// submission (a submitted Folksong can't be changed).
  init(owner: TestAdmin, sourceURL: String = "https://example.org/web-tests") throws {
    self.owner = owner.username
    let user = try owner.column("id")
    var ids: [String: String] = [:]
    for name in [
      "submission", "folksong", "overture", "antiphon", "record", "madrigal", "version", "authorship",
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
    madrigalID = ids["madrigal"]!.uppercased()
    self.ids = ids
    let folksong = ids["folksong"]!.uppercased()
    let metadata = """
      {"sourceUrl":"https://example.org/web-tests","sourceKind":"iiif-manifest","title":"\(title)",\
      "voices":[{"name":"\(author)","role":"author"}],\
      "language":"eng","category":"report","edition":"First edition","year":1958,"genres":[],"isTranslation":false,\
      "translationChain":[],"activityStatements":[],"citations":[]}
      """
    let shape = """
      {"edition-\(folksong)":{"parent":"work","position":0},"manifest-\(folksong)":{"parent":"edition-\(folksong)","position":0},"work":{"parent":null,"position":0}}
      """
    let voice = """
      INSERT INTO biblio_record_voices (id, biblio_record_id, name, role, position)
        VALUES ('\(ids["authorship"]!)', '\(ids["record"]!)', '\(author)', 'author', 0);
      """
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(ids["submission"]!)', '\(user)');
      INSERT INTO bibliographic_folksongs (id, batch_id, source_url, language, processing_status, title, type, edition, year, created_at)
        VALUES ('\(ids["folksong"]!)', '\(ids["submission"]!)', '\(sourceURL)', 'eng', 'pending', '\(title)', 'report', 'First edition', 1958, now());
      INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_folksong_id, source_url, language, processing_status, committed_by_user_id, committed_at, created_at)
        VALUES ('\(ids["overture"]!)', '\(ids["submission"]!)', '\(ids["folksong"]!)', '\(sourceURL)', 'eng', 'pending', '\(user)', now(), now());
      INSERT INTO bibliographic_antiphons (id, bibliographic_overture_id, requested_by_user_id, canvas_service_ids_json, processing_status, created_at, updated_at)
        VALUES ('\(ids["antiphon"]!)', '\(ids["overture"]!)', '\(user)', '[]', 'submitted', now(), now());
      INSERT INTO biblio_records (id, corpus_id, title, title_slug, type, language, genres, year, date_display, created_at, updated_at)
        VALUES ('\(ids["record"]!)', (SELECT id FROM corpora ORDER BY created_at LIMIT 1), '\(title)', '\(slug)',
          'report', 'eng', '[]', 1958, 'AD 1958', now(), now());
      \(voice)
      INSERT INTO bibliographic_madrigals (id, thread_id, bibliographic_antiphon_id, biblio_record_id, proposed_content_json, metadata_json, shape_json, processing_status, permitted_by_user_id, permitted_at, created_at, updated_at)
        VALUES ('\(ids["madrigal"]!)', '\(ids["madrigal"]!)', '\(ids["antiphon"]!)', '\(ids["record"]!)', '{"teiXml":""}', '\(metadata)', '\(shape)', 'permitted', '\(user)', now(), now(), now());
      INSERT INTO biblio_record_versions (id, biblio_record_id, bibliographic_madrigal_id, metadata_json, shape_json, status, created_at)
        VALUES ('\(ids["version"]!)', '\(ids["record"]!)', '\(ids["madrigal"]!)', '\(metadata)', '\(shape)', 1, now());
      COMMIT;
      """)
  }

  func remove() {
    // An amendment submitted against it is a frozen Folksong naming its
    // record and version (no foreign key): then the work stays whole, or
    // the Folksong would name nothing and every page loading it would fail.
    let amended = "EXISTS (SELECT 1 FROM bibliographic_palinodes WHERE biblio_record_id = '\(ids["record"]!)')"
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM biblio_record_versions WHERE id = '\(ids["version"]!)' AND NOT \(amended);
      DELETE FROM bibliographic_madrigals WHERE id = '\(ids["madrigal"]!)' AND NOT \(amended);
      DELETE FROM bibliographic_antiphons WHERE id = '\(ids["antiphon"]!)' AND NOT \(amended);
      DELETE FROM url_histories WHERE entity_id = '\(ids["record"]!)' AND NOT \(amended);
      DELETE FROM biblio_record_voices WHERE id = '\(ids["authorship"]!)' AND NOT \(amended);
      DELETE FROM biblio_records WHERE id = '\(ids["record"]!)' AND NOT \(amended);
      DELETE FROM bibliographic_overtures WHERE id = '\(ids["overture"]!)' AND NOT \(amended);
      UPDATE bibliographic_folksongs SET deleted_at = now(), deleted_by = '\(owner)' WHERE id = '\(ids["folksong"]!)';
      COMMIT;
      """)
  }
}
