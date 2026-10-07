import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Equivalents are a sentiment's fields, never translation's output (user,
/// 2026-10-07): typed in Disputorium or proposed by lexicographic explication,
/// and held in the record's snapshot as the sentiment's Translations. A
/// snapshot whose sentiment lists a German word shows it under the
/// sentiment's Translations ("broader sense"), and the German record lists
/// the English one back under its own Translations, read from its side
/// ("narrower sense"). Phone and desktop, nothing scrolling sideways.
@Suite("Sentiment equivalents", .serialized)
struct SentimentEquivalentsTests {
  struct Width: Decodable { let overflow: Double }
  static let overflow = "({ overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth })"

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aSnapshotsEquivalentIsListedOnBothRecords(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let english = try ScratchWord(owner: admin)
    let german = try ScratchWord(owner: admin, language: "deu")
    let snapshot = UUID().uuidString.lowercased()
    let term = #"[{"form":"\#(german.title)","languageCode":"deu","recordPath":"\#(german.path)#record-row-s-1-1","equivalence":"broader"}]"#
    do {
      // A later snapshot of the English record: its sense lists the German word.
      _ = try TestAdmin.query(
        """
        INSERT INTO lexico_record_versions (id, lexico_record_id, lexicographic_notation_id, treatment, record_json, created_at)
          SELECT '\(snapshot)', lexico_record_id, lexicographic_notation_id, treatment,
              jsonb_set(record_json::jsonb, '{senses,1,translations}', '\(term)')::text, now() + interval '1 second'
            FROM lexico_record_versions WHERE id = '\(english.versionID.lowercased())';
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        // The English record lists the German word under the sentiment's Translations.
        try await page.openHydrated(english.path)
        let own = page.locator("#record-row-s-1-1 .lexicographic-translations-view")
        try await expect(own.getByText("German")).toBeAttached()
        try await expect(own.locator("a[href='\(german.path)#record-row-s-1-1']")).toHaveText(german.title)
        try await expect(own.getByText("(broader sense)")).toBeAttached()

        // The German record lists it back, read from its side.
        try await page.openHydrated(german.path)
        let back = page.locator("#record-row-s-1-1 .lexicographic-translations-view")
        try await expect(back.getByText("English")).toBeAttached()
        try await expect(back.locator("a[href='\(english.path)#record-row-s-1-1']")).toHaveText(english.title)
        try await expect(back.getByText("(narrower sense)")).toBeAttached()
        #expect(try await page.evaluate(Self.overflow, as: Width.self).overflow <= 0)
      }
    } catch {
      remove(snapshot: snapshot, words: [english, german])
      try await admin.remove(after: error)
    }
    remove(snapshot: snapshot, words: [english, german])
    try await admin.remove()
  }

  private func remove(snapshot: String, words: [ScratchWord]) {
    _ = try? TestAdmin.query("DELETE FROM lexico_record_versions WHERE id = '\(snapshot)'")
    for word in words { word.remove() }
  }
}
