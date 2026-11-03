import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Lexicographic translation is only English ↔ the record's own language (user,
/// 2026-10-07): for a record not in English, the sentiment's session writes its
/// definition in the record's language, filed as its epilogue; its usage is
/// schema, never translated (user, 2026-10-09). The amendment's page shows the
/// definition in German with its confidence and reason; permitted, the record is
/// Translated and its row carries the record-level English toggle, selected
/// initially, switching definitions (each its sentiment's value, its
/// heading's box) while the usage stays as it is, and the record rule's XML
/// switch shows its `<sense>`. An Arabic definition reads right to left.
/// Phone and desktop, nothing scrolling sideways.
@Suite("Lexicographic translation: the definition in the record's language", .serialized)
struct LexicographicTranslationDefinitionTests {
  struct Width: Decodable { let overflow: Double }
  struct Direction: Decodable { let direction: String }
  static let overflow = "({ overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth })"

  static let german = "Ein Blatt-Sinn, der nichts weiter sagt."
  static let arabic = "معنى ورقي لا يقول شيئًا آخر."

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aGermanRecordsDefinitionIsProposedPermittedAndSwitchedFromEnglish(engine: BrowserEngine, layout: Layout)
    async throws
  {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin, language: "deu")
    let arabic = try ScratchWord(owner: admin, language: "ara")
    let amendment = UUID().uuidString.lowercased()
    let arabicAmendment = UUID().uuidString.lowercased()
    let definition = #"{"confidence":"clear","tei":"<def xml:lang=\"de\">\#(Self.german)</def>","languageCode":"deu","reason":"The English says it plainly."}"#
    do {
      _ = try TestAdmin.query(
        """
        BEGIN;
        UPDATE lexico_record_versions SET record_json = jsonb_set(record_json::jsonb, '{senses,1,usage,grammar}',
            '["in seafaring use"]')::text
          WHERE id = '\(word.versionID.lowercased())';
        -- The Arabic record translated: a version (status 2) permitted
        -- from a lexicographic epilogue, as the antecedent check requires.
        INSERT INTO lexicographic_epilogues (id, lexico_record_id, lexico_record_version_id, sentiment_id, tei, target,
            status, submitted_by_user_id, summary, value_translation_json, evaluated_at, evaluated_by_user_id)
          VALUES ('\(arabicAmendment)', '\(arabic.recordID.lowercased())', '\(arabic.versionID.lowercased())', '\(arabic.leaf)',
            '<sense><def>A leaf sense.</def></sense>', 'value', 'permitted', (SELECT id FROM users WHERE username = 'gnorium'),
            'Wrote the Arabic definition.', '{"languageCode":"ara","tei":"<def xml:lang=\\"ar\\">\(Self.arabic)</def>","confidence":"clear","reason":"Web tests."}', now(),
            (SELECT id FROM users WHERE username = 'gnorium'));
        INSERT INTO lexico_record_versions (id, lexico_record_id, lexicographic_epilogue_id, status, record_json, created_at)
          SELECT gen_random_uuid(), lexico_record_id, '\(arabicAmendment)', 2,
              jsonb_set(record_json::jsonb, '{senses,1,tei}',
                '"<sense><def>A leaf sense.</def><def xml:lang=\\"ar\\">\(Self.arabic)</def></sense>"')::text,
              now() + interval '1 second'
            FROM lexico_record_versions WHERE id = '\(arabic.versionID.lowercased())';
        INSERT INTO lexicographic_epilogues (id, lexico_record_id, lexico_record_version_id, sentiment_id, tei, target,
            status, submitted_by_user_id, summary, value_translation_json)
          VALUES ('\(amendment)', '\(word.recordID.lowercased())', '\(word.versionID.lowercased())', '\(word.leaf)',
            '<sense><def>A leaf sense.</def></sense>', 'value', 'committed', (SELECT id FROM users WHERE username = 'gnorium'),
            'Wrote the German definition.', '\(definition)');
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        // The amendment, committed: the definition in German with its
        // provenance, under its node's value's name (a sentiment's
        // definition is its value, user 2026-10-28); no usage translated.
        try await page.openHydrated("/mission-control/epilogues/lexicographic/\(amendment)")
        let body = page.locator(".lexicographic-epilogue-body")
        try await expect(body.getByText("Value in German")).toBeVisible()
        try await expect(body.getByText(Self.german)).toHaveAttribute("lang", "de")
        try await expect(body.getByText("in der Seefahrt")).toHaveCount(0)
        try await expect(body.getByText("The English says it plainly.")).toBeVisible()
        #expect(try await page.evaluate(Self.overflow, as: Width.self).overflow <= 0)

        try await page.locator("button[form='lexicographic-epilogue-permit']").click()
        try await expect(page.locator(".disputorium-core-header-status-chip")).toHaveText("Permitted")

        // One record-level English toggle, selected initially.
        try await page.openHydrated(word.path)
        let row = page.locator("#record-row-\(word.leaf)")
        let english = page.locator(".apparatus-rule-language-toggle")
        try await expect(english).toHaveAttribute("aria-pressed", "true")
        // Its definition is its value, its heading's one box (user,
        // 2026-10-28; 2026-11-02): the English `<def>` while English is on;
        // the `<def xml:lang>` once it is off; the rule's XML switch shows
        // its whole `<sense>` in its place.
        let value = row.locator(".record-node-heading .node-value-text:not([hidden])").first
        let branch = page.locator("#record-row-\(word.branch) .record-node-heading .node-value-text:not([hidden])").first
        try await expect(value).toHaveText("A leaf sense.")
        try await expect(branch).toHaveText("A branch sense.")
        try await english.click()
        try await expect(english).toHaveAttribute("aria-pressed", "false")
        try await expect(value).toHaveText(Self.german)
        try await expect(value).toHaveAttribute("lang", "de")
        // A sentiment not translated keeps its English words.
        try await expect(branch).toHaveText("A branch sense.")
        // The XML: its `<sense>`, the German `<def>` in it, while the
        // switch stands pressed, and none once it is let go.
        let xml = row.locator(".sentiment-sense-xml").first
        try await expect(xml).toBeHidden()
        let xmlSwitch = page.locator(".apparatus-rule-xml-toggle")
        try await xmlSwitch.click()
        try await expect(xmlSwitch).toHaveAttribute("aria-pressed", "true")
        try await expect(xml).toBeVisible()
        try await expect(xml).toContainText("<sense>")
        try await expect(xml).toContainText(Self.german)
        try await xmlSwitch.click()
        try await expect(xmlSwitch).toHaveAttribute("aria-pressed", "false")
        try await expect(xml).toBeHidden()
        try await expect(value).toHaveText(Self.german)
        try await expect(value).toHaveAttribute("lang", "de")
        // No single level (user, 2026-10-20): its sentiments counted per
        // level, the branch explicated, the leaf translated.
        let counts = page.locator(".record-level-counts-view").first
        try await expect(counts.locator("[data-level='explicated']")).toHaveText("1 explicated")
        try await expect(counts.locator("[data-level='translated']")).toHaveText("1 translated")
        // Usage is schema: the same in every language.
        try await expect(row.locator(".sentiment-metadata-view").first).toContainText("in seafaring use")
        try await expect(row.locator(".sentiment-metadata-view").getByText("in der Seefahrt")).toHaveCount(0)
        try await english.click()
        try await expect(row.locator(".record-node-heading .node-value-text:not([hidden])").first).toHaveText("A leaf sense.")
        #expect(try await page.evaluate(Self.overflow, as: Width.self).overflow <= 0)

        // Arabic reads right to left.
        try await page.openHydrated(arabic.path)
        try await page.locator(".apparatus-rule-language-toggle").click()
        let rtl = page.locator("#record-row-\(arabic.leaf) .record-node-heading .node-value-text:not([hidden])").first
        try await expect(rtl).toHaveAttribute("lang", "ar")
        let direction = try await page.evaluate(
          "(() => ({ direction: getComputedStyle(document.querySelector('#record-row-\(arabic.leaf) .record-node-heading .node-value-text:not([hidden])')).direction }))()",
          as: Direction.self)
        #expect(direction.direction == "rtl")
        #expect(try await page.evaluate(Self.overflow, as: Width.self).overflow <= 0)
      }
    } catch {
      remove(words: [word, arabic])
      try await admin.remove(after: error)
    }
    remove(words: [word, arabic])
    try await admin.remove()
  }

  private func remove(words: [ScratchWord]) {
    let records = words.map { "'\($0.recordID.lowercased())'" }.joined(separator: ", ")
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM lexico_record_versions WHERE lexicographic_epilogue_id IN
        (SELECT id FROM lexicographic_epilogues WHERE lexico_record_id IN (\(records)));
      DELETE FROM lexicographic_epilogues WHERE lexico_record_id IN (\(records));
      COMMIT;
      """)
    for word in words { word.remove() }
  }
}
