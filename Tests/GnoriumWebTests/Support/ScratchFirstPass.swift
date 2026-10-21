import Foundation

/// A first pass's new sentiment as gnorium submits it (server 0174
/// `SentimentsArePending`, user 2026-10-20): a bibliographic antiphon of a
/// scratch work and its page session (page "1"), and from that session a
/// lexicographic figurant and its pending overture holding one sentiment
/// of its own, no record yet. Owned by the test's account; every row by its
/// own id, removed in the order the foreign keys allow—what a Permit of
/// the overture made (the record, its lemma, its postulated version)
/// included. The figurant is soft-discarded, as the site discards one.
struct ScratchFirstPass {
  let work: ScratchWork
  let antiphonID: String
  let nocturneID: String
  let figurantID: String
  let overtureID: String
  let sentimentID: String
  /// The word: a unique English noun.
  let title: String
  let owner: String

  init(owner: TestAdmin) throws {
    self.owner = owner.username
    let user = try owner.column("id")
    work = try ScratchWork(owner: owner)
    antiphonID = UUID().uuidString.lowercased()
    nocturneID = UUID().uuidString.lowercased()
    figurantID = UUID().uuidString.lowercased()
    overtureID = UUID().uuidString.lowercased()
    sentimentID = UUID().uuidString.lowercased()
    let submission = UUID().uuidString.lowercased()
    title = "webtestsfirstpass\(antiphonID.prefix(8))"
    let form = #"{"title":"\#(title)","languageCode":"eng","class":"noun","spellings":[],"inflections":[],"origin":{"etymons":[],"citations":[],"derivation":""}}"#
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, image_service_ids_json, processing_status)
        VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
      INSERT INTO bibliographic_explication_nocturnes (id, submission_id, process, image, instance, provider, model, result, nocturne_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
        VALUES ('\(nocturneID)', (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'),
          'explication', '1', 1, 'DeepSeek', 'deepseek-flash', 'passed', gen_random_uuid(), '\(antiphonID)', 1200, now());
      INSERT INTO submissions (id, user_id) VALUES ('\(submission)', '\(user)');
      INSERT INTO lexicographic_figurants (id, batch_id, language, order_in_batch, processing_status,
        title_form_json, anchors_json, bibliographic_explication_nocturne_id, created_at)
        VALUES ('\(figurantID)', '\(submission)', 'eng', 0, 'pending', '\(form)', '[]', '\(nocturneID)', now());
      INSERT INTO lexicographic_overtures (id, lexicographic_figurant_id, title_form_json, anchors_json, created_at)
        VALUES ('\(overtureID)', '\(figurantID)', '\(form)', '[]', now());
      INSERT INTO sentiment_inventories (language_code, lemma, class, version) VALUES ('eng', '\(title)', 'noun', 1);
      INSERT INTO sentiments (uuid, lexicographic_overture_id, language_code, lemma, class, inventory_version,
        definition_text, definition_key, provisional)
        VALUES ('\(sentimentID)', '\(overtureID)', 'eng', '\(title)', 'noun', 1,
          'A scratch sense of the web tests.', 'a scratch sense of the web tests', true);
      COMMIT;
      """)
  }

  /// The record a Permit made, by its title; "" while there is none.
  func recordID() throws -> String {
    try TestAdmin.query("SELECT coalesce(max(id::text), '') FROM lexico_records WHERE title = '\(title)';")
  }

  func remove() {
    let record = (try? recordID()) ?? ""
    let records = record.isEmpty ? "" : """
      DELETE FROM url_histories WHERE entity_id = '\(record)';
      DELETE FROM lexico_records WHERE id = '\(record)';
      """
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM lexico_record_versions WHERE lexicographic_overture_id = '\(overtureID)';
      DELETE FROM sentiments WHERE uuid = '\(sentimentID)';
      DELETE FROM sentiment_inventories WHERE language_code = 'eng' AND lemma = '\(title)' AND class = 'noun';
      \(records)
      DELETE FROM lemmas WHERE citation_form = '\(title)';
      DELETE FROM locutions WHERE locutable_type = 'lexicographic_overture' AND locutable_id = '\(overtureID)';
      DELETE FROM lexicographic_overtures WHERE id = '\(overtureID)';
      UPDATE lexicographic_figurants SET discarded_at = now(), discarded_by = '\(owner)'
        WHERE id = '\(figurantID)' AND discarded_at IS NULL;
      \(SessionTrace.delete(table: "bibliographic_explication_nocturnes", where: "id='\(nocturneID)'"))
      DELETE FROM bibliographic_explication_nocturnes WHERE id = '\(nocturneID)';
      DELETE FROM bibliographic_antiphons WHERE id = '\(antiphonID)';
      COMMIT;
      """)
    work.remove()
  }
}
