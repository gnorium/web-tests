import Foundation

/// A lexico-record with one attributed version whose snapshot holds a
/// branch sentiment and a leaf under it, owned by the test's account: the
/// record's own reference (beside its lemma, in its closed Metadata) and the
/// leaf's (beside its definition, in its row's heading). Every row by its own
/// id, removed in the order the foreign keys allow.
struct ScratchWord {
  let lemma: String
  let path: String
  private let ids: [String: String]

  init(owner: TestAdmin) throws {
    let user = try owner.column("id")
    var ids: [String: String] = [:]
    for name in ["submission", "evidence", "overture", "concerto", "lemma", "record", "hallmark", "version"] {
      ids[name] = UUID().uuidString.lowercased()
    }
    self.ids = ids
    lemma = "webtestsword\(ids["record"]!.prefix(8))"
    path = "/lexico-records/eng/\(lemma)/%E2%80%94/noun"
    let snapshot = """
      {"lemmaForm":{"headword":"\(lemma)","inflections":[],"languageCode":"eng","origin":{"citations":[],"derivation":"","etymons":[]},\
      "partOfSpeech":"noun","sources":[{"locator":"s.v.","title":"Web tests dictionary","url":"https://dictionary.example.org/web-tests"}],\
      "spellings":[]},"quotations":[],"selectionRunIDs":["run"],"senses":[\
      {"definition":"A branch sense.","id":"s-1","isLeaf":false,"labels":{"domain":[],"grammar":[],"region":[],"register":[]},\
      "position":0,"quotationIDs":[],"rank":0,"relations":[],"selectionRunID":"run","tei":"<sense><def>A branch sense.</def></sense>"},\
      {"definition":"A leaf sense.","id":"s-1-1","isLeaf":true,"labels":{"domain":[],"grammar":[],"region":[],"register":[]},\
      "parentID":"s-1","position":0,"quotationIDs":[],"rank":1,"relations":[],"selectionRunID":"run",\
      "sources":[{"locator":"sense 2","title":"Web tests senses","url":"https://senses.example.org/web-tests"}],\
      "tei":"<sense><def>A leaf sense.</def></sense>"}]}
      """
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(ids["submission"]!)', '\(user)');
      INSERT INTO lemmas (id, citation_form, ascii_form, searchable_form, language_id, homograph_number, created_at, updated_at)
        VALUES ('\(ids["lemma"]!)', '\(lemma)', '\(lemma)', '\(lemma)', (SELECT id FROM languages WHERE iso639_3 = 'eng'), 1, now(), now());
      INSERT INTO lexico_records (id, lemma_id, citation_form, language_code, version, part_of_speech)
        VALUES ('\(ids["record"]!)', '\(ids["lemma"]!)', '\(lemma)', 'eng', 1, 'noun');
      INSERT INTO lexicographic_evidences (id, batch_id, language, lemma_form_json, anchors_json)
        VALUES ('\(ids["evidence"]!)', '\(ids["submission"]!)', 'eng', '{}', '[]');
      INSERT INTO lexicographic_overtures (id, lexicographic_evidence_id, lemma_form_json, anchors_json)
        VALUES ('\(ids["overture"]!)', '\(ids["evidence"]!)', '{}', '[]');
      INSERT INTO lexicographic_hallmarks (id, thread_id, lexicographic_overture_id, lexicographic_concerto_id, lexico_record_id, record_json, processing_status, permitted_by_user_id, permitted_at)
        VALUES ('\(ids["hallmark"]!)', '\(ids["hallmark"]!)', '\(ids["overture"]!)', '\(ids["concerto"]!)', '\(ids["record"]!)', '\(snapshot)', 'permitted', '\(user)', now());
      INSERT INTO lexico_record_versions (id, lexico_record_id, lexicographic_hallmark_id, treatment, record_json, created_at)
        VALUES ('\(ids["version"]!)', '\(ids["record"]!)', '\(ids["hallmark"]!)', 1, '\(snapshot)', now());
      COMMIT;
      """)
  }

  func remove() {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM lexico_record_versions WHERE id = '\(ids["version"]!)';
      DELETE FROM lexicographic_hallmarks WHERE id = '\(ids["hallmark"]!)';
      DELETE FROM lexicographic_overtures WHERE id = '\(ids["overture"]!)';
      DELETE FROM lexicographic_evidences WHERE id = '\(ids["evidence"]!)';
      DELETE FROM url_histories WHERE entity_id = '\(ids["record"]!)';
      DELETE FROM lexico_records WHERE id = '\(ids["record"]!)';
      DELETE FROM lemmas WHERE id = '\(ids["lemma"]!)';
      DELETE FROM submissions WHERE id = '\(ids["submission"]!)';
      COMMIT;
      """)
  }
}
