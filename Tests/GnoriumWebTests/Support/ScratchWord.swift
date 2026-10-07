import Foundation

/// A lexico-record with one explicated version whose snapshot holds a
/// branch sentiment and a leaf under it, owned by the test's account: the
/// record's own reference (beside its title, in its closed Metadata) and the
/// leaf's (beside its definition, in its row's heading). Every row by its own
/// id, removed in the order the foreign keys allow—except its submission and
/// Instance, which are submitted input and frozen, so they stay. Its
/// overture is committed, its antiphon submitted, and the notation that
/// antiphon made permitted. With a `distinction`,
/// the leaf's TEI holds it as its `<note type="usage" subtype="distinction">`
/// (a `{branch}` in it a `<ptr>` to the branch). With an `anchor` (a
/// testament's record, version and page, and the utterance's passage and
/// word there), the leaf is attested by an utterance in that testament.
struct ScratchWord {
  /// Its overture's, its notation's and its version's ids, as the server
  /// writes them.
  let overtureID: String
  let notationID: String
  let versionID: String
  /// The scratch record's title.
  let title: String
  let path: String
  /// Its record's id, as the server writes it: upper case.
  let recordID: String
  private let ids: [String: String]

  /// Where an utterance is in a testament: its record, version and page
  /// (image service, and its place among the version's pages), and its word
  /// by line and place in the line, with its surface, as the utterances service
  /// counts the page.
  struct Anchor {
    let recordID: String
    let versionID: String
    let canvasID: String
    let page: Int
    let line: Int
    let word: Int
    let surface: String
  }

  /// `language` is the record's (ISO 639-3): English unless named.
  /// `submitted` leaves its notation awaiting its verdict (submitted, not
  /// yet permitted), as a Modify page needs it.
  init(
    owner: TestAdmin, distinction: String? = nil, anchor: Anchor? = nil, language: String = "eng",
    submitted: Bool = false
  ) throws {
    let user = try owner.column("id")
    var ids: [String: String] = [:]
    for name in ["submission", "instance", "overture", "antiphon", "notation", "lemma", "record", "version"] {
      ids[name] = UUID().uuidString.lowercased()
    }
    overtureID = ids["overture"]!.uppercased()
    notationID = ids["notation"]!.uppercased()
    versionID = ids["version"]!.uppercased()
    self.ids = ids
    recordID = ids["record"]!.uppercased()
    title = "webtestsword\(ids["record"]!.prefix(8))"
    path = "/lexico-records/\(language)/\(title)/noun"
    let note = distinction.map {
      #"<note type=\"usage\" subtype=\"distinction\">"#
        + $0.replacingOccurrences(of: "{branch}", with: ##"<ptr target=\"#s-1\"/>"##) + "</note>"
    } ?? ""
    let utterances = anchor.map {
      (
        #"[{"biblioRecordID":"\#($0.recordID)","canvasID":"\#($0.canvasID)","end":{"line":\#($0.line),"surface":"\#($0.surface)","word":\#($0.word)},"id":"u-1","page":\#($0.page),"start":{"line":\#($0.line),"surface":"\#($0.surface)","word":\#($0.word)},"versionID":"\#($0.versionID)"}]"#,
        #"["u-1"]"#,
        #","chronology":[{"testamentTitle":"Web tests testament","text":"The scratch word stood in a sentence.","utteranceID":"u-1","year":1901,"yearEnd":1901}]"#)
    } ?? ("[]", "[]", "")
    let snapshot = """
      {"lemmaForm":{"title":"\(title)","inflections":[],"languageCode":"\(language)","origin":{"citations":[],"derivation":"","etymons":[]},\
      "partOfSpeech":"noun","sources":[{"locator":"s.v.","title":"Web tests dictionary","url":"https://dictionary.example.org/web-tests"}],\
      "spellings":[]},"quotations":\(utterances.0),"selectionRunIDs":["run"]\(utterances.2),"senses":[\
      {"definition":"A branch sense.","id":"s-1","isLeaf":false,"labels":{"domain":[],"grammar":[],"region":[],"register":[]},\
      "position":0,"quotationIDs":[],"rank":0,"relations":[],"selectionRunID":"run","tei":"<sense><def>A branch sense.</def></sense>"},\
      {"definition":"A leaf sense.","id":"s-1-1","isLeaf":true,"labels":{"domain":[],"grammar":[],"region":[],"register":[]},\
      "parentID":"s-1","position":0,"quotationIDs":\(utterances.1),"rank":1,"relations":[],"selectionRunID":"run",\
      "sources":[{"locator":"sense 2","title":"Web tests senses","url":"https://senses.example.org/web-tests"}],\
      "tei":"<sense><def>A leaf sense.</def>\(note)</sense>"}]}
      """
    // Its title form as the Submit Sentiment form writes one: a submitted
    // Instance is frozen and stays, so it must be one the Instances list can
    // read (an empty form fails the whole list).
    let titleForm = #"{"title":"\#(title)","languageCode":"\#(language)","partOfSpeech":"noun","spellings":[],"inflections":[],"origin":{"etymons":[],"citations":[],"derivation":""}}"#
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(ids["submission"]!)', '\(user)');
      INSERT INTO lemmas (id, citation_form, ascii_form, searchable_form, language_id, homograph_number, created_at, updated_at)
        VALUES ('\(ids["lemma"]!)', '\(title)', '\(title)', '\(title)', (SELECT id FROM languages WHERE iso639_3 = '\(language)'), 1, now(), now());
      INSERT INTO lexico_records (id, lemma_id, title, language_code, version, type)
        VALUES ('\(ids["record"]!)', '\(ids["lemma"]!)', '\(title)', '\(language)', 1, 'noun');
      INSERT INTO lexicographic_instances (id, batch_id, language, title_form_json, anchors_json)
        VALUES ('\(ids["instance"]!)', '\(ids["submission"]!)', '\(language)', '\(titleForm)', '[]');
      INSERT INTO lexicographic_overtures (id, lexicographic_instance_id, title_form_json, anchors_json, committed_by_user_id, committed_at)
        VALUES ('\(ids["overture"]!)', '\(ids["instance"]!)', '\(titleForm)', '[]', '\(user)', now());
      INSERT INTO lexicographic_antiphons (id, lexicographic_instance_id, lexicographic_overture_id, requested_by_user_id, processing_status, language, sentence, title_form_json)
        VALUES ('\(ids["antiphon"]!)', '\(ids["instance"]!)', '\(ids["overture"]!)', '\(user)', 'submitted', '\(language)', '\(title)', '\(titleForm)');
      INSERT INTO lexicographic_notations (id, lexicographic_antiphon_id, lexico_record_id, proposed_content_json, processing_status, permitted_by_user_id, permitted_at)
        VALUES ('\(ids["notation"]!)', '\(ids["antiphon"]!)', '\(ids["record"]!)', '{"record":\(snapshot),"homographFlags":[],"evidenceRequests":[],"reasoning":"Web tests."}', \(submitted ? "'submitted', NULL, NULL" : "'permitted', '\(user)', now()"));
      INSERT INTO lexico_record_versions (id, lexico_record_id, lexicographic_notation_id, treatment, record_json, created_at)
        VALUES ('\(ids["version"]!)', '\(ids["record"]!)', '\(ids["notation"]!)', 1, '\(snapshot)', now());
      COMMIT;
      """)
  }

  func remove() {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM lexico_record_versions WHERE id = '\(ids["version"]!)';
      DELETE FROM lexicographic_notations WHERE id = '\(ids["notation"]!)';
      DELETE FROM lexicographic_antiphons WHERE id = '\(ids["antiphon"]!)';
      DELETE FROM lexicographic_overtures WHERE id = '\(ids["overture"]!)';
      DELETE FROM url_histories WHERE entity_id = '\(ids["record"]!)';
      DELETE FROM lexico_records WHERE id = '\(ids["record"]!)';
      DELETE FROM lemmas WHERE id = '\(ids["lemma"]!)';
      COMMIT;
      """)
  }
}
