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
/// initially, switching definitions while the usage stays as it is. An Arabic
/// definition reads right to left.
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
            status, submitted_by_user_id, summary, definition_translation_json, evaluated_at, evaluated_by_user_id)
          VALUES ('\(arabicAmendment)', '\(arabic.recordID.lowercased())', '\(arabic.versionID.lowercased())', 's-1-1',
            '<sense><def>A leaf sense.</def></sense>', 'definition', 'permitted', (SELECT id FROM users WHERE username = 'gnorium'),
            'Wrote the Arabic definition.', '{"languageCode":"ara","tei":"<def xml:lang=\\"ar\\">\(Self.arabic)</def>","confidence":"clear","reason":"Web tests."}', now(),
            (SELECT id FROM users WHERE username = 'gnorium'));
        INSERT INTO lexico_record_versions (id, lexico_record_id, lexicographic_epilogue_id, status, record_json, created_at)
          SELECT gen_random_uuid(), lexico_record_id, '\(arabicAmendment)', 2,
              jsonb_set(record_json::jsonb, '{senses,1,tei}',
                '"<sense><def>A leaf sense.</def><def xml:lang=\\"ar\\">\(Self.arabic)</def></sense>"')::text,
              now() + interval '1 second'
            FROM lexico_record_versions WHERE id = '\(arabic.versionID.lowercased())';
        INSERT INTO lexicographic_epilogues (id, lexico_record_id, lexico_record_version_id, sentiment_id, tei, target,
            status, submitted_by_user_id, summary, definition_translation_json)
          VALUES ('\(amendment)', '\(word.recordID.lowercased())', '\(word.versionID.lowercased())', 's-1-1',
            '<sense><def>A leaf sense.</def></sense>', 'definition', 'committed', (SELECT id FROM users WHERE username = 'gnorium'),
            'Wrote the German definition.', '\(definition)');
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        // The amendment, committed: the definition in German with its provenance; no usage translated.
        try await page.openHydrated("/mission-control/epilogues/lexicographic/\(amendment)")
        let body = page.locator(".lexicographic-epilogue-body")
        try await expect(body.getByText("Definition in German")).toBeVisible()
        try await expect(body.getByText(Self.german)).toHaveAttribute("lang", "de")
        try await expect(body.getByText("in der Seefahrt")).toHaveCount(0)
        try await expect(body.getByText("The English says it plainly.")).toBeVisible()
        #expect(try await page.evaluate(Self.overflow, as: Width.self).overflow <= 0)

        try await page.locator("button[form='lexicographic-epilogue-permit']").click()
        try await expect(page.locator(".disputorium-core-header-status-chip")).toHaveText("Permitted")

        // One record-level English toggle, selected initially.
        try await page.openHydrated(word.path)
        let row = page.locator("#record-row-s-1-1")
        let english = page.locator(".apparatus-rule-language-toggle")
        try await expect(english).toHaveAttribute("aria-pressed", "true")
        try await expect(row.locator(".record-row-title").first).toHaveText("A leaf sense.")
        // Its definition in its box (user, 2026-10-10): the English `<def>`
        // while English is on; the `<def xml:lang>` once it is off, as the
        // label; the box's own Raw turns that box alone to its XML.
        let box = row.locator(".sentiment-definition-view").first
        let branch = page.locator("#record-row-s-1 .sentiment-definition-view").first
        try await expect(box.locator("[data-definition-layer='english']")).toBeVisible()
        try await expect(box.locator("[data-definition-layer='english'] .sentiment-definition-text")).toHaveText("A leaf sense.")
        try await expect(box.locator("[data-definition-layer='native']")).toBeHidden()
        try await expect(box.locator("[data-definition-layer='raw']")).toBeHidden()
        // Raw, medium, on its bottom legend: 36 below, 16 elsewhere (user, 2026-10-10).
        #expect(try await page.evaluate(
          "(() => { const s = getComputedStyle(document.querySelector('#record-row-s-1-1 .sentiment-definition-view')); return [s.paddingTop, s.paddingInlineStart, s.paddingInlineEnd, s.paddingBottom].join(' '); })()",
          as: String.self) == "16px 16px 16px 36px")
        try await english.click()
        try await expect(box.locator("[data-definition-layer='native']")).toBeVisible()
        try await expect(box.locator("[data-definition-layer='native'] .sentiment-definition-text")).toHaveText(Self.german)
        try await expect(box.locator("[data-definition-layer='native'] .sentiment-definition-text")).toHaveAttribute("lang", "de")
        try await expect(box.locator("[data-definition-layer='english']")).toBeHidden()
        // A sentiment not translated keeps its English words.
        try await expect(branch.locator("[data-definition-layer='english']")).toBeVisible()
        try await box.locator(".sentiment-definition-raw-toggle").click()
        try await expect(box.locator("[data-definition-layer='raw']")).toBeVisible()
        try await expect(box.locator("[data-definition-layer='raw']")).toContainText("<sense>")
        try await expect(box.locator("[data-definition-layer='native']")).toBeHidden()
        try await expect(branch.locator("[data-definition-layer='raw']")).toBeHidden()
        try await expect(branch.locator(".sentiment-definition-raw-toggle")).toHaveAttribute("aria-pressed", "false")
        try await box.locator(".sentiment-definition-raw-toggle").click()
        try await expect(box.locator("[data-definition-layer='native']")).toBeVisible()
        try await expect(row.locator(".record-row-title").first).toHaveText(Self.german)
        try await expect(row.locator(".record-row-title").first).toHaveAttribute("lang", "de")
        try await expect(page.locator(".record-sidebar-status").first).toContainText("translated")
        // Usage is schema: the same in every language.
        try await expect(row.locator(".sentiment-metadata-view").first).toContainText("in seafaring use")
        try await expect(row.locator(".sentiment-metadata-view").getByText("in der Seefahrt")).toHaveCount(0)
        try await english.click()
        try await expect(row.locator(".record-row-title").first).toHaveText("A leaf sense.")
        #expect(try await page.evaluate(Self.overflow, as: Width.self).overflow <= 0)

        // Arabic reads right to left.
        try await page.openHydrated(arabic.path)
        try await page.locator(".apparatus-rule-language-toggle").click()
        let rtl = page.locator("#record-row-s-1-1 .record-row-title").first
        try await expect(rtl).toHaveAttribute("lang", "ar")
        let direction = try await page.evaluate(
          "(() => ({ direction: getComputedStyle(document.querySelector('#record-row-s-1-1 .record-row-title')).direction }))()",
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
