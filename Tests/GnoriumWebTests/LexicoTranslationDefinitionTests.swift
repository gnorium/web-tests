import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Lexico translation is one pipeline (user, 2026-09-29): for a record not in
/// English, the sentiment's session also writes its definition and free-text
/// labels in the record's language, filed in the same amendment. The
/// amendment's page shows the definition in German with its label,
/// confidence and reason; permitted, the record is Translated and its row carries the
/// German definition under the English one, marked as German, and the
/// label's translation beside it. An Arabic definition reads right to left.
/// Phone and desktop, nothing scrolling sideways.
@Suite("Lexico translation: the definition in the record's language", .serialized)
struct LexicoTranslationDefinitionTests {
  struct Width: Decodable { let overflow: Double }
  struct Direction: Decodable { let direction: String }
  static let overflow = "({ overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth })"

  static let german = "Ein Blatt-Sinn, der nichts weiter sagt."
  static let arabic = "معنى ورقي لا يقول شيئًا آخر."

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aGermanRecordsDefinitionIsProposedPermittedAndShownBesideTheEnglish(engine: BrowserEngine, layout: Layout)
    async throws
  {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin, language: "deu")
    let arabic = try ScratchWord(owner: admin, language: "ara")
    let amendment = UUID().uuidString.lowercased()
    let definition = #"{"confidence":"clear","definition":"\#(Self.german)","labels":[{"label":"in seafaring use","translation":"in der Seefahrt"}],"language_code":"deu","reason":"The English says it plainly."}"#
    do {
      _ = try TestAdmin.query(
        """
        BEGIN;
        UPDATE lexico_record_versions SET record_json = jsonb_set(record_json::jsonb, '{senses,1,labels,grammar}',
            '["in seafaring use"]')::text
          WHERE id = '\(word.versionID.lowercased())';
        UPDATE lexico_record_versions SET record_json = jsonb_set(record_json::jsonb, '{senses,1,definitionTranslation}',
            '{"languageCode":"ara","definition":"\(Self.arabic)","labels":{"domain":[],"grammar":[],"region":[],"register":[]}}')::text
          WHERE id = '\(arabic.versionID.lowercased())';
        INSERT INTO sentiment_amendments (id, lexico_record_id, lexico_record_version_id, sentiment_id, definition, target,
            status, submitted_by_user_id, summary, definition_translation_json)
          VALUES ('\(amendment)', '\(word.recordID.lowercased())', '\(word.versionID.lowercased())', 's-1-1',
            'A leaf sense.', 'translations', 'proposed', (SELECT id FROM users WHERE username = 'gnorium'),
            'Wrote the German definition; no other language.', '\(definition)');
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        // The amendment, proposed: the definition in German with its label and provenance.
        try await page.openHydrated("/mission-control/amendments/lexicographic/\(amendment)")
        let body = page.locator(".sentiment-amendment-body")
        try await expect(body.getByText("Definition in German")).toBeVisible()
        try await expect(body.getByText(Self.german)).toHaveAttribute("lang", "de")
        try await expect(body.getByText("in der Seefahrt")).toBeVisible()
        try await expect(body.getByText("The English says it plainly.")).toBeVisible()
        #expect(try await page.evaluate(Self.overflow, as: Width.self).overflow <= 0)

        try await page.locator("button[form='sentiment-amendment-permit']").click()
        try await expect(page.locator(".disputorium-core-header-status-chip")).toHaveText("Permitted")

        // The German record: the German definition under the English one, and the label's translation.
        try await page.openHydrated(word.path)
        let row = page.locator("#record-row-s-1-1")
        let own = row.locator(".sentiment-view-translation").first
        try await expect(own).toHaveText(Self.german)
        try await expect(own).toHaveAttribute("lang", "de")
        try await expect(own).toBeVisible()
        try await expect(row.locator(".record-row-title").first).toHaveText("A leaf sense.")
        // Attributed → Explicated → Translated: the permitted amendment's version is translated.
        try await expect(page.locator(".record-sidebar-treatment").first).toContainText("translated")
        try await expect(row.locator(".sentiment-metadata-view span[lang='de']").first).toHaveText("in der Seefahrt")
        #expect(try await page.evaluate(Self.overflow, as: Width.self).overflow <= 0)

        // Arabic reads right to left.
        try await page.openHydrated(arabic.path)
        let rtl = page.locator("#record-row-s-1-1 .sentiment-view-translation").first
        try await expect(rtl).toHaveAttribute("lang", "ar")
        let direction = try await page.evaluate(
          "(() => ({ direction: getComputedStyle(document.querySelector('#record-row-s-1-1 .sentiment-view-translation')).direction }))()",
          as: Direction.self)
        #expect(direction.direction == "rtl")
        #expect(try await page.evaluate(Self.overflow, as: Width.self).overflow <= 0)
      }
    } catch {
      remove(words: [word, arabic])
      await admin.remove()
      throw error
    }
    remove(words: [word, arabic])
    await admin.remove()
  }

  private func remove(words: [ScratchWord]) {
    let records = words.map { "'\($0.recordID.lowercased())'" }.joined(separator: ", ")
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM lexico_record_versions WHERE sentiment_amendment_id IN
        (SELECT id FROM sentiment_amendments WHERE lexico_record_id IN (\(records)));
      DELETE FROM sentiment_amendments WHERE lexico_record_id IN (\(records));
      COMMIT;
      """)
    for word in words { word.remove() }
  }
}
