import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A record with no treatment (user, 2026-09-29): a citation naming a work
/// Gnorium had no record of made one—its identity, its Citations, no
/// version. Its page says "—" for what it has undergone and what made it
/// ("Created by gnorium from the citation … in [work], page N"), lists the
/// work citing it, and is not indexed; a treated record's page is. Phone
/// and desktop, Chrome headless.
@Suite("Untreated records", .serialized)
struct UntreatedRecordsTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aRecordACitationMadeHasNoTreatmentSaysWhatMadeItAndIsNotIndexed(engine: BrowserEngine, layout: Layout)
    async throws
  {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let citing = try ScratchWork(owner: admin)
    let made = UUID().uuidString.lowercased()
    let suffix = String(made.prefix(8))
    let title = "Web tests untreated \(suffix)"
    let path = "/biblio-records/eng/web-tests-untreated-\(suffix)/journal"
    func cleanUp() async throws {
      _ = try? TestAdmin.query(
        EntriesAndCitationsTests.clean([citing])
          + """
          DELETE FROM record_provenances WHERE biblio_record_id = '\(made)';
          DELETE FROM url_histories WHERE entity_id = '\(made)';
          DELETE FROM biblio_records WHERE id = '\(made)';
          """)
      citing.remove()
      try await admin.remove()
    }
    do {
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO biblio_records (id, corpus_id, title, title_slug, type, language, genres, date_display)
          VALUES ('\(made)', (SELECT id FROM corpora ORDER BY created_at LIMIT 1), '\(title)',
            'web-tests-untreated-\(suffix)', 'journal', 'eng', '[]', '');
        INSERT INTO record_provenances (id, biblio_record_id, source, work_record_id, biblio_record_version_id, page, printed, created_at)
          VALUES (gen_random_uuid(), '\(made)', 'citation', '\(citing.recordID.lowercased())',
            '\(citing.versionID.lowercased())', 2, 'Web tests Journ.', now());
        """ + EntriesAndCitationsTests.read(citing) + EntriesAndCitationsTests.cite(2, by: citing, work: made)
          + "\nCOMMIT;")
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(path)
        try await expect(page.locator("h1")).toContainText(title)
        // Not indexed while it has no treatment.
        let robots = try await page.locator("meta[name='robots']").getAttribute("content")
        #expect(robots == "noindex, follow")
        // What it has undergone: nothing, "—"; then what made it.
        let sidebar = page.locator(".record-sidebar-view").first
        try await expect(sidebar.locator(".record-sidebar-treatment")).toHaveText("—")
        let provenance = sidebar.locator(".record-provenance-view")
        try await expect(provenance).toHaveText(
          "Created by gnorium from the citation “Web tests Journ.” in \(citing.title), page 2.")
        try await expect(provenance.locator("a[href='\(citing.path)']")).toHaveCount(1)
        try await expect(provenance.locator("a").filter(hasText: "page 2")).toHaveCount(1)
        // Its Citations: the work that made it.
        let citations = page.locator("#record-citations")
        try await citations.locator(".accordion-summary").first.click()
        try await expect(citations.locator(".citations-view-work")).toHaveCount(1)
        try await expect(citations.locator(".citations-view-count")).toHaveText("2 citations")
        try await page.expectNoHorizontalOverflow()

        // A treated record is indexed and says what it has undergone.
        try await page.openHydrated(citing.path)
        let treated = try await page.locator("meta[name='robots']").getAttribute("content")
        #expect(treated == "index, follow")
        try await expect(page.locator(".record-sidebar-view").first.locator(".record-sidebar-treatment")).toHaveText("Explicated.")
        try await expect(page.locator(".record-sidebar-view").first.locator(".record-provenance-view")).toHaveCount(0)
      }
    } catch {
      do { try await cleanUp() } catch let removal {
        throw WebTestError("\(error)\n…and cleaning up failed too: \(removal)")
      }
      throw error
    }
    try await cleanUp()
  }
}
