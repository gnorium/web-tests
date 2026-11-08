import Foundation

/// A work with one explicated version whose tree holds one edition and its
/// manifest, owned by the test's account: its overture committed, its
/// quatrain, halftone and the antiphon that halftone's Commit made
/// (`ScratchChain`), the antiphon's madrigal permitted. Every
/// row by its own id, removed in the order the foreign keys allow—except
/// its submission and Figurant, which are submitted input and frozen: the
/// Figurant is soft-discarded, as the site discards one, and both stay.
///
/// Its author is a typed name, as every voice is.
struct ScratchWork {
  let title: String
  let author: String
  /// What makes its title and author unique: a search finds it by this.
  let suffix: String
  let recordID: String
  let versionID: String
  /// Its overture's id (committed).
  let overtureID: String
  /// The madrigal its version was permitted from.
  let madrigalID: String
  let path: String
  private let ids: [String: String]
  private let chain = ScratchChain()
  private let owner: String

  /// The corpus every permitted work joins, made as the server makes it on
  /// the first permit (`BiblioRecord.findOrCreateDefaultCorpus`): a fresh
  /// run's database has none, and a record without one fails to load. Kept,
  /// as the server keeps it.
  static let corpus = """
    INSERT INTO corpora (id, name, slug, description, language_period, work_count, word_count, created_at, updated_at)
      VALUES (gen_random_uuid(), 'Uncategorized Sources', 'uncategorized-sources',
        'Works permitted from evidence not yet assigned to a curated corpus', 'contemporary', 0, 0, now(), now())
      ON CONFLICT (slug) DO NOTHING;
    """
  /// Its id, for a record's `corpus_id`.
  static let corpusID = "(SELECT id FROM corpora WHERE slug = 'uncategorized-sources')"

  /// Its madrigal's document: one image, its page with markup, so its
  /// version is explicated (`NodeLevels.testament`: every page has markup;
  /// a document with no pages is only calibrated).
  static let document = #"{"teiXml":"<TEI><text><body><pb n=\"1\" facs=\"https://web-tests.invalid/iiif/p1/full/1300,/0/default.jpg\"/><div><p>Web tests line</p></div></body></text></TEI>"}"#

  /// `sourceURL` is its Figurant's and overture's source URL, fixed at
  /// submission (a submitted Figurant can't be changed).
  /// `coauthor`, where given, is a second voice, an author after the first.
  init(owner: TestAdmin, sourceURL: String = "https://example.org/web-tests", coauthor: String? = nil) throws {
    self.owner = owner.username
    let user = try owner.column("id")
    var ids: [String: String] = [:]
    for name in [
      "submission", "figurant", "overture", "record", "madrigal", "version", "authorship",
    ] {
      ids[name] = UUID().uuidString
    }
    // Text, not an id: the title's and the slug's lower-case hex.
    let suffix = ids["record"]!.prefix(8).lowercased()
    self.suffix = suffix
    title = "Web tests placement \(suffix)"
    let slug = "web-tests-placement-\(suffix)"
    author = "Web Tests Author \(suffix)"
    path = "/biblio-records/eng/\(slug)/report"
    recordID = ids["record"]!
    versionID = ids["version"]!
    overtureID = ids["overture"]!
    madrigalID = ids["madrigal"]!
    self.ids = ids
    let figurant = ids["figurant"]!
    let metadata = """
      {"sourceUrl":"https://example.org/web-tests","sourceKind":"iiif-manifest","title":"\(title)",\
      "voices":[{"name":"\(author)","role":"author"}\(coauthor.map { #",{"name":"\#($0)","role":"author"}"# } ?? "")],\
      "language":"eng","category":"report","edition":"First edition","year":1958,"genres":[],"isTranslation":false,\
      "translationChain":[],"activityStatements":[],"citations":[]}
      """
    // Every node with its own UUID, as the server gives one
    // (design-notes/node-uuids.md).
    let node = { UUID().uuidString }
    let shape = """
      {"edition-\(figurant)":{"parent":"work","position":0,"uuid":"\(node())"},\
      "manifest-\(figurant)":{"parent":"edition-\(figurant)","position":0,"uuid":"\(node())"},\
      "work":{"parent":null,"position":0,"uuid":"\(node())"}}
      """
    let voice = """
      INSERT INTO biblio_record_voices (id, biblio_record_id, name, role, position)
        VALUES ('\(ids["authorship"]!)', '\(ids["record"]!)', '\(author)', 'author', 0);
      """ + (coauthor.map { """

      INSERT INTO biblio_record_voices (id, biblio_record_id, name, role, position)
        VALUES (gen_random_uuid(), '\(ids["record"]!)', '\($0)', 'author', 1);
      """ } ?? "")
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(ids["submission"]!)', '\(user)');
      INSERT INTO bibliographic_figurants (id, batch_id, source_url, language, processing_status, title, type, edition, year, created_at)
        VALUES ('\(ids["figurant"]!)', '\(ids["submission"]!)', '\(sourceURL)', 'eng', 'pending', '\(title)', 'report', 'First edition', 1958, now());
      INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_figurant_id, source_url, language, processing_status, committed_by_user_id, committed_at, created_at)
        VALUES ('\(ids["overture"]!)', '\(ids["submission"]!)', '\(ids["figurant"]!)', '\(sourceURL)', 'eng', 'pending', '\(user)', now(), now());
      \(Self.corpus)
      INSERT INTO biblio_records (id, corpus_id, title, title_slug, type, language, genres, year, date_display, created_at, updated_at)
        VALUES ('\(ids["record"]!)', \(Self.corpusID), '\(title)', '\(slug)',
          'report', 'eng', '[]', 1958, 'AD 1958', now(), now());
      \(voice)
      \(chain.insert(overture: ids["overture"]!, user: user, metadata: metadata))
      INSERT INTO bibliographic_madrigals (id, thread_id, bibliographic_antiphon_id, biblio_record_id, proposed_content_json, metadata_json, shape_json, processing_status, permitted_by_user_id, permitted_at, created_at, updated_at)
        VALUES ('\(ids["madrigal"]!)', '\(ids["madrigal"]!)', '\(chain.antiphonID)', '\(ids["record"]!)', '\(Self.document)', '\(metadata)', '\(shape)', 'permitted', '\(user)', now(), now(), now());
      INSERT INTO biblio_record_versions (id, biblio_record_id, bibliographic_madrigal_id, metadata_json, shape_json, status, created_at)
        VALUES ('\(ids["version"]!)', '\(ids["record"]!)', '\(ids["madrigal"]!)', '\(metadata)', '\(shape)', 1, now());
      COMMIT;
      """)
  }

  func remove() {
    // An amendment submitted against it is a frozen Figurant naming its
    // record and version (no foreign key): then the work stays whole, or
    // the Figurant would name nothing and every page loading it would fail.
    let amended = "EXISTS (SELECT 1 FROM bibliographic_palinodes WHERE biblio_record_id = '\(ids["record"]!)')"
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM biblio_record_versions WHERE id = '\(ids["version"]!)' AND NOT \(amended);
      DELETE FROM bibliographic_headers WHERE bibliographic_madrigal_id = '\(ids["madrigal"]!)' AND NOT \(amended);
      DELETE FROM bibliographic_madrigals WHERE id = '\(ids["madrigal"]!)' AND NOT \(amended);
      DELETE FROM bibliographic_antiphons WHERE id = '\(chain.antiphonID)' AND NOT \(amended);
      DELETE FROM bibliographic_halftones WHERE id = '\(chain.halftoneID)' AND NOT \(amended);
      DELETE FROM bibliographic_quatrains WHERE id = '\(chain.quatrainID)' AND NOT \(amended);
      DELETE FROM url_histories WHERE entity_id = '\(ids["record"]!)' AND NOT \(amended);
      DELETE FROM biblio_record_voices WHERE biblio_record_id = '\(ids["record"]!)' AND NOT \(amended);
      DELETE FROM biblio_records WHERE id = '\(ids["record"]!)' AND NOT \(amended);
      DELETE FROM bibliographic_overtures WHERE id = '\(ids["overture"]!)' AND NOT \(amended);
      UPDATE bibliographic_figurants SET discarded_at = now(), discarded_by = '\(owner)' WHERE id = '\(ids["figurant"]!)';
      COMMIT;
      """)
  }
}
