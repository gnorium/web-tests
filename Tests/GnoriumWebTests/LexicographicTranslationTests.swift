import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Lexicographic translation (user, 2026-09-29): a sentiment's equivalents in other
/// languages, found by one session per sentiment and filed as gnorium's
/// amendment of it. The amendment's page shows the sentiment, the
/// Translations proposed and each equivalent's relation, confidence, reason
/// and evidence, with Permit and Reject; permitted, the English record lists
/// the German word under the sentiment's Translations ("broader sense"), and
/// the German record lists the English one back under its own Translations,
/// read from its side ("narrower sense"). The translation's page lists its
/// session per sentiment, and the Madrigals register's Lexicographic tab
/// lists the translation. Phone and desktop, nothing scrolling sideways.
@Suite("Lexicographic translation", .serialized)
struct LexicographicTranslationTests {
  struct Width: Decodable { let overflow: Double }
  static let overflow = "({ overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth })"

  static func trace(german: ScratchWord) throws -> String {
    let equivalent = #"{"citations":[{"id":"s-1-1","kind":"sentiment","record_id":"\#(german.recordID.lowercased())"}],"confidence":"clear","language_code":"deu","reason":"The German word names more.","record_id":"\#(german.recordID.lowercased())","relation":"broader","sentiment_id":"s-1-1","title":"\#(german.title)","type":"Noun"}"#
    let blocks: [[String: String]] = [
      ["type": "thinking", "content": "The sense is a leaf; German has a word for it."],
      [
        "type": "tool", "name": "propose_equivalent",
        "arguments": #"{"language":"deu","relation":"broader"}"#,
        "result": #"{"ok": true, "key": "deu"}"#, "status": "ok", "call_id": "call_1",
      ],
      ["type": "equivalent", "key": "deu:\(german.recordID.lowercased()):s-1-1", "content": equivalent],
      ["type": "text", "content": "German, broader; no other language."],
    ]
    return String(decoding: try JSONSerialization.data(withJSONObject: blocks), as: UTF8.self)
      .replacingOccurrences(of: "'", with: "''")
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aSentimentsEquivalentIsAmendedPermittedAndListedOnBothRecords(engine: BrowserEngine, layout: Layout)
    async throws
  {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let english = try ScratchWord(owner: admin)
    let german = try ScratchWord(owner: admin, language: "deu")
    let translation = UUID().uuidString.lowercased()
    let run = UUID().uuidString.lowercased()
    let amendment = UUID().uuidString.lowercased()
    do {
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO lexicographic_translations (id, lexico_record_id, lexico_record_version_id, processing_status)
          VALUES ('\(translation)', '\(english.recordID.lowercased())', '\(english.versionID.lowercased())', 'submitted');
        INSERT INTO lexicographic_translation_runs (id, lexicographic_translation_id, sentiment_id, attempt, provider, model,
            output, result, duration_ms, created_at)
          VALUES ('\(run)', '\(translation)', 's-1-1', 1, 'openrouter', 'qwen/qwen3.8-max-0902',
            '\(try Self.trace(german: german))', 'passed', 900, now());
        INSERT INTO sentiment_amendments (id, lexico_record_id, lexico_record_version_id, sentiment_id, definition, target,
            status, submitted_by_user_id, lexicographic_translation_id, lexicographic_translation_run_id, summary)
          VALUES ('\(amendment)', '\(english.recordID.lowercased())', '\(english.versionID.lowercased())', 's-1-1',
            'A leaf sense.', 'translations', 'proposed', (SELECT id FROM users WHERE username = 'gnorium'),
            '\(translation)', '\(run)', 'German, broader; no other language.');
        INSERT INTO sentiment_equivalents (id, sentiment_amendment_id, position, language_code, target_lexico_record_id,
            target_sentiment_id, title, type, relation, confidence, reason, citations_json)
          VALUES (gen_random_uuid(), '\(amendment)', 0, 'deu', '\(german.recordID.lowercased())', 's-1-1',
            '\(german.title)', 'Noun', 'broader', 'clear', 'The German word names more.',
            '[{"kind":"sentiment","id":"s-1-1","record_id":"\(german.recordID.lowercased())"}]');
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        // The amendment, proposed: its equivalent with its provenance, and the verdicts.
        try await page.openHydrated("/mission-control/amendments/lexicographic/\(amendment)")
        let body = page.locator(".sentiment-amendment-body")
        try await expect(page.locator(".disputorium-core-title")).toHaveText("Sentiment amendment")
        try await expect(page.locator(".pedigree-view a[href='/users/gnorium']").first).toBeAttached()
        try await expect(body.getByText("A leaf sense.").first).toBeVisible()
        try await expect(body.getByText("Translations proposed")).toBeVisible()
        try await expect(body.getByText("German · \(german.title)")).toBeVisible()
        try await expect(body.getByText("broader sense").first).toBeVisible()
        try await expect(body.getByText("The German word names more.")).toBeVisible()
        try await expect(body.getByText("\(german.title) 1.1: A leaf sense.")).toBeVisible()
        #expect(try await page.evaluate(Self.overflow, as: Width.self).overflow <= 0)

        try await page.locator("button[form='sentiment-amendment-permit']").click()
        try await expect(page.locator(".disputorium-core-header-status-chip")).toHaveText("Permitted")
        try await expect(page.locator("button[form='sentiment-amendment-permit']")).toHaveCount(0)
        try await expect(page.getByText("Permitted version")).toBeAttached()

        // The English record lists the German word under the sentiment's Translations.
        try await page.openHydrated(english.path)
        let ownTranslations = page.locator("#record-row-s-1-1 .lexicographic-translations-view")
        try await expect(ownTranslations.getByText("German")).toBeAttached()
        try await expect(ownTranslations.locator("a[href='\(german.path)#record-row-s-1-1']")).toHaveText(german.title)
        try await expect(ownTranslations.getByText("(broader sense)")).toBeAttached()

        // The German record lists it back, read from its side.
        try await page.openHydrated(german.path)
        let back = page.locator("#record-row-s-1-1 .lexicographic-translations-view")
        try await expect(back.getByText("English")).toBeAttached()
        try await expect(back.locator("a[href='\(english.path)#record-row-s-1-1']")).toHaveText(english.title)
        try await expect(back.getByText("(narrower sense)")).toBeAttached()
        #expect(try await page.evaluate(Self.overflow, as: Width.self).overflow <= 0)

        // The translation: one session per sentiment, its trace.
        try await page.openHydrated("/mission-control/translations/lexicographic/\(translation)")
        try await expect(page.locator(".pipeline-container")).toHaveAttribute("data-item-order", "Sentiment 1.1")
        try await expect(page.locator(".session-view").getByText("propose_equivalent").first).toBeAttached()
        try await expect(page.locator(".session-view").getByText("German, broader; no other language.")).toBeAttached()

        // Listed on the Madrigals register's Lexicographic tab, and the amendment on Amendments.
        try await page.openHydrated("/mission-control/madrigals?tab=lexicographic")
        try await expect(page.locator("a[href='/mission-control/translations/lexicographic/\(translation.uppercased())']"))
          .toBeAttached()
        try await page.openHydrated("/mission-control/amendments?tab=lexicographic")
        try await expect(page.locator("a[href='/mission-control/amendments/lexicographic/\(amendment)']")).toBeAttached()
        #expect(try await page.evaluate(Self.overflow, as: Width.self).overflow <= 0)
      }
    } catch {
      remove(translation: translation, words: [english, german])
      await admin.remove()
      throw error
    }
    remove(translation: translation, words: [english, german])
    await admin.remove()
  }

  private func remove(translation: String, words: [ScratchWord]) {
    let records = words.map { "'\($0.recordID.lowercased())'" }.joined(separator: ", ")
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM lexico_record_versions WHERE sentiment_amendment_id IN
        (SELECT id FROM sentiment_amendments WHERE lexico_record_id IN (\(records)));
      DELETE FROM sentiment_amendments WHERE lexico_record_id IN (\(records));
      DELETE FROM lexicographic_translations WHERE id = '\(translation)';
      COMMIT;
      """)
    for word in words { word.remove() }
  }
}
