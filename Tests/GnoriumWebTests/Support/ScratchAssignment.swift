import Foundation

/// A word of a scratch testament assigned to a scratch word's leaf, as a
/// first pass assigns it (gnorium-server 0e5d7c67, 2026-10-20): stand-off,
/// by the word's (or phrase's) `xml:id`, in a reading—a page session of
/// the testament's work—that the testament's version lays at the page
/// (`page_readings_json`). The leaf is a sentiment row of its own. Owned by
/// the test's account; every row by its own id, removed before the word
/// and the testament.
struct ScratchAssignment {
  let antiphonID: String
  let nocturneID: String
  let word: ScratchWord
  let wordClass: String

  init(
    owner: TestAdmin, testament: ScratchTestament, word: ScratchWord, image: String, wordID: String,
    surface: String, lemma: String, wordClass: String
  ) throws {
    antiphonID = UUID().uuidString.lowercased()
    nocturneID = UUID().uuidString.lowercased()
    self.word = word
    self.wordClass = wordClass
    let work = testament.reading.work
    let user = try owner.column("id")
    let leaf = word.leaf.lowercased()
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, image_service_ids_json, processing_status)
        VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
      INSERT INTO bibliographic_explication_nocturnes (id, bibliographic_antiphon_id, submission_id, process, image, instance_count)
       VALUES (md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid, '\(antiphonID)', (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'), 'explication', '1', 1)
       ON CONFLICT (id) DO UPDATE SET instance_count = bibliographic_explication_nocturnes.instance_count + 1;
      INSERT INTO bibliographic_explication_nocturne_instances (id, nocturne_id, submission_id, process, image, instance, provider, model, result, nocturne_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
      VALUES ('\(nocturneID)', md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid, (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'), 'explication', '1', 1, 'DeepSeek', 'deepseek-flash', 'passed', gen_random_uuid(), '\(antiphonID)', 1200, now());
      INSERT INTO sentiment_inventories (language_code, lemma, class, version) VALUES ('eng', '\(word.title)', '\(wordClass)', 1);
      INSERT INTO sentiments (uuid, lexico_record_id, language_code, lemma, class, inventory_version, definition_text, definition_key, provisional)
        VALUES ('\(leaf)', '\(word.recordID.lowercased())', 'eng', '\(word.title)', '\(wordClass)', 1,
          'A leaf sense.', 'a leaf sense', false);
      INSERT INTO sentiment_assignments (reading_id, image, word_id, surface, language_code, lemma, class, sentiment_uuid, assigned_by)
        VALUES ('\(nocturneID)', '\(image)', '\(wordID)', '\(surface)', 'eng', '\(lemma)', '\(wordClass)', '\(leaf)',
          'bibliographic_explication');
      UPDATE biblio_record_versions SET page_readings_json = '{"\(image)": "\(nocturneID)"}' WHERE id = '\(testament.versionID)';
      COMMIT;
      """)
  }

  func remove() {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM sentiment_assignments WHERE reading_id = '\(nocturneID)';
      DELETE FROM sentiments WHERE uuid = '\(word.leaf.lowercased())';
      DELETE FROM sentiment_inventories WHERE language_code = 'eng' AND lemma = '\(word.title)' AND class = '\(wordClass)';
      \(SessionTrace.delete(table: "bibliographic_explication_nocturne_instances", where: "id='\(nocturneID)'"))
      DELETE FROM bibliographic_explication_nocturnes WHERE id IN (SELECT nocturne_id FROM bibliographic_explication_nocturne_instances WHERE id = '\(nocturneID)');
      DELETE FROM bibliographic_antiphons WHERE id = '\(antiphonID)';
      COMMIT;
      """)
  }
}
