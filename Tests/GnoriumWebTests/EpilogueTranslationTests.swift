import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An epilogue's translation is read in the reader's English layer alone
/// (user, 2026-10-12): no Translation section setting the original against
/// it. A stale page rings the pane orange; its change against the
/// translation it replaces is a code diff under the reader, under Raw; and a
/// translator's note opens from the block it notes, in the gloss sheet.
@Suite("Epilogue translation", .serialized)
struct EpilogueTranslationTests {
  static let shots = ProcessInfo.processInfo.environment["GNORIUM_SHOTS"]

  @Test(arguments: [BrowserEngine.chrome])
  func theTranslationIsReadInTheEnglishLayer(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let one = fixture.baseURL + "/page-1"
    let two = fixture.baseURL + "/page-2"
    let tei = "<TEI><text><body><pb n=\"1\" facs=\"\(one)/full/max/0/default.jpg\"/><p>Regola del tre per numeri</p><pb n=\"2\" facs=\"\(two)/full/max/0/default.jpg\"/><p>Somma</p></body></text></TEI>"
    func translation(_ first: String) -> String {
      "<TEI><text><body><pb n=\"1\" facs=\"\(one)/full/max/0/default.jpg\" corresp=\"#e1\"/><p corresp=\"#p1.e2\">\(first)</p><pb n=\"2\" facs=\"\(two)/full/max/0/default.jpg\" corresp=\"#e3\"/><p corresp=\"#p2.e2\">The sum</p></body></text></TEI>"
    }
    let reading: ScratchReading
    do { reading = try ScratchReading(owner: admin, tei: tei, sourceURL: fixture.baseURL + "/manifest.json") }
    catch { try await admin.remove(after: error) }
    let earlier = UUID().uuidString.lowercased()
    let epilogue = UUID().uuidString.lowercased()
    let first = UUID().uuidString.lowercased()
    let second = UUID().uuidString.lowercased()
    func clean() {
      _ = try? TestAdmin.query("""
        DELETE FROM bibliographic_epilogues WHERE id IN ('\(epilogue)', '\(earlier)');
        DELETE FROM bibliographic_serenades WHERE id IN ('\(first)', '\(second)');
        """)
      reading.remove()
    }
    func layer(_ text: String, note: String?, stale: Bool) throws -> String {
      var segment: [String: Any] = ["key": "s1", "element": "p", "source": "Regola del tre per numeri", "translation": text]
      if let note { segment["note"] = note }
      let object: [String: Any] = [
        "sourceLanguage": "ita", "targetLanguage": "eng", "tei": translation(text), "pages": [
          ["service": one, "label": "1", "sourceDigest": "a", "segments": [segment], "stale": stale],
          ["service": two, "label": "2", "sourceDigest": "b", "segments": [
            ["key": "s1", "element": "p", "source": "Somma", "translation": "The sum"]
          ], "stale": false],
        ],
      ]
      return try String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        .replacingOccurrences(of: "'", with: "''")
    }
    do {
      let user = try admin.column("id")
      let before = try layer("Rule of three", note: nil, stale: false)
      let now = try layer("The rule of three for numbers", note: "tre is three", stale: true)
      _ = try TestAdmin.query("""
        BEGIN;
        UPDATE bibliographic_madrigals SET metadata_json =
          (metadata_json::jsonb || '{"language":"ita","sourceUrl":"\(fixture.baseURL)/manifest.json"}'::jsonb)::text
          WHERE id = '\(reading.madrigalID)';
        INSERT INTO bibliographic_serenades (id, bibliographic_madrigal_id, target_language, resemblance_service_ids_json, requested_by_user_id, processing_status)
          VALUES ('\(first)', '\(reading.madrigalID)', 'eng', '[]', '\(user)', 'submitted');
        INSERT INTO bibliographic_epilogues (id, thread_id, bibliographic_overture_id, bibliographic_serenade_id, proposed_content_json, metadata_json, translation_json, processing_status)
          SELECT '\(earlier)', '\(earlier)', '\(reading.work.overtureID.lowercased())', '\(first)', p.proposed_content_json, p.metadata_json, '\(before)', 'pending'
          FROM bibliographic_madrigals p WHERE p.id = '\(reading.madrigalID)';
        INSERT INTO bibliographic_serenades (id, bibliographic_epilogue_id, target_language, resemblance_service_ids_json, requested_by_user_id, processing_status)
          VALUES ('\(second)', '\(earlier)', 'eng', '[]', '\(user)', 'submitted');
        INSERT INTO bibliographic_epilogues (id, thread_id, bibliographic_overture_id, bibliographic_serenade_id, proposed_content_json, metadata_json, translation_json, processing_status)
          SELECT '\(epilogue)', '\(epilogue)', '\(reading.work.overtureID.lowercased())', '\(second)', p.proposed_content_json, p.metadata_json, '\(now)', 'pending'
          FROM bibliographic_madrigals p WHERE p.id = '\(reading.madrigalID)';
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/epilogues/bibliographic/\(epilogue)")
        // No Translation section: the reader alone reads the translation.
        try await expect(page.locator(".translation-layer-view")).toHaveCount(0)
        let viewer = page.locator(".epilogue-object .artifact-view")
        let pane = viewer.locator(".artifact-markup")
        // The original shown: no translation's ring.
        try await expect(pane).not.toHaveAttribute("data-diff-state", "stale")
        // The English layer shown: its page is stale, the pane ringed orange.
        try await page.locator(".apparatus-rule-language-toggle").first.click()
        try await expect(pane).toHaveAttribute("data-diff-state", "stale")
        let orange = try await page.evaluate(
          "getComputedStyle(document.documentElement).getPropertyValue('--border-color-orange').trim()", as: String.self)
        let ring = try await pane.evaluate("el => getComputedStyle(el).borderTopColor").string
        #expect(try #require(ring) == (try await page.evaluate(
          "(() => { const d = document.createElement('div'); d.style.color = '\(orange)'; document.body.appendChild(d); const c = getComputedStyle(d).color; d.remove(); return c; })()",
          as: String.self)), "the stale ring is \(ring ?? "none")")
        _ = try await viewer.evaluate("el => el.scrollIntoView({block: 'start'})")
        if let shots = Self.shots { try await page.screenshot(to: URL(fileURLWithPath: shots + "/stale-ring.png")) }
        // Under Raw, its change against the translation it replaces, code
        // against code, under the reader.
        try await viewer.locator(".artifact-raw-toggle button").first.click()
        let slot = page.locator(".testament-diff[data-active='true']")
        try await expect(slot).toBeVisible()
        try await expect(slot.locator(".testament-translation-diff")).toBeVisible()
        try await expect(slot.locator(".testament-translation-diff")).toContainText("The rule of three for numbers")
        try await expect(slot.locator(".testament-translation-diff")).toContainText("Rule of three")
        try await expect(slot.locator(".resemblance-diff-view")).toHaveCount(0)
        if let shots = Self.shots { try await page.screenshot(to: URL(fileURLWithPath: shots + "/translation-diff.png")) }
        // Raw off: no diff; the noted block opens its note in the gloss.
        try await viewer.locator(".artifact-raw-toggle button").first.click()
        try await expect(slot).toBeHidden()
        let noted = pane.locator(".tei-page[data-active='true'] [data-layer='translated-rendering'] .tei-noted")
        try await expect(noted).toHaveCount(1)
        try await noted.click()
        let note = page.locator(".gloss-sheet-view .gloss-translator-note")
        try await expect(note).toBeVisible()
        try await expect(note).toHaveText("tre is three")
        try await expect(page.locator(".gloss-sheet-view .gloss-sheet-title")).toContainText("Translator's note")
        if let shots = Self.shots {
          // The sheet's motion done.
          try await Task.sleep(for: .milliseconds(600))
          try await page.screenshot(to: URL(fileURLWithPath: shots + "/translator-note.png"))
        }
        try await page.expectNoErrors()
      }
    } catch {
      clean()
      try await admin.remove(after: error)
    }
    clean()
    try await admin.remove()
  }
}
