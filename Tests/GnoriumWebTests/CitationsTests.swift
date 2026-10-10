import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The citation graph (user, 2026-09-28). A cited work's page says how many
/// works cite it and lists them in its "Citations"; a Disputorium object
/// shows the same of the record it lands in. Phone and desktop, Chrome
/// headless.
@Suite("Citations", .serialized)
struct CitationsTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aCitedWorkSaysHowManyWorksCiteItAndListsThem(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let cited = try ScratchWork(owner: admin)
    let citing = try ScratchWork(owner: admin)
    // A citation of the one by the other's version, as a permit's reading
    // leaves it: standoff, resolved.
    let citation = UUID().uuidString.lowercased()
    let extraction = UUID().uuidString.lowercased()
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO citations (id, biblio_record_version_id, biblio_record_id, testament_id, permitted_at, resemblance_id, page,
        start_line, start_word, start_surface, end_line, end_word, end_surface, element, kind, surface, parts_json,
        language_code, status, cited_biblio_record_id, resolved_at, created_at)
        VALUES ('\(citation)', '\(citing.versionID.lowercased())', '\(citing.recordID.lowercased())', '\(citing.recordID.lowercased())',
          now(), 'c', 1, 1, 1, 'Report', 1, 1, 'Report', 'bibl', 'work', 'Report', '{}', 'eng', 'resolved',
          '\(cited.recordID.lowercased())', now(), now());
      INSERT INTO citation_extractions (id, biblio_record_version_id, testament_id, permitted_at, citations_version, count, extracted_at)
        VALUES ('\(extraction)', '\(citing.versionID.lowercased())', '\(citing.recordID.lowercased())', now(), 'tei-bibl-ref-mentioned-v3', 1, now());
      COMMIT;
      """)
    func cleanUp() async throws {
      _ = try? TestAdmin.query(
        "DELETE FROM citations WHERE id = '\(citation)'; DELETE FROM citation_extractions WHERE id = '\(extraction)';")
      citing.remove()
      cited.remove()
      try await admin.remove()
    }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(cited.path)
        // Its Citations: the citing work, with how many.
        let citations = page.locator("#record-citations")
        try await citations.locator(".accordion-summary").first.click()
        let row = citations.locator(".citations-work")
        try await expect(row.locator("a[href='\(citing.path)']")).toHaveCount(1)
        try await expect(row.locator(".citations-count")).toHaveText("1 citation")
        let metadata = page.locator("#record-metadata")
        try await metadata.locator(".accordion-summary").first.click()
        let datum = metadata.locator(".datum-view").filter(hasText: "Citations")
        try await expect(datum.locator(".datum-value")).toHaveText("1 work")
        try await page.expectNoHorizontalOverflow()
        // The citing work cites; nothing cites it.
        try await page.openHydrated(citing.path)
        let own = page.locator("#record-metadata")
        try await own.locator(".accordion-summary").first.click()
        try await expect(own.locator(".datum-view").filter(hasText: "Citations").locator(".datum-value")).toHaveText("0 works")
      }
    } catch {
      do { try await cleanUp() } catch let removal {
        throw WebTestError("\(error)\n…and cleaning up failed too: \(removal)")
      }
      throw error
    }
    try await cleanUp()
  }

  /// A Disputorium object shows what other works say of the record it lands
  /// in (user, 2026-10-07): the record page's own Entries, then its
  /// Citations, after the work—each only when there is one, never an empty
  /// accordion.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aMadrigalShowsItsRecordsEntriesAndCitations(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reading = try ScratchReading(
      owner: admin,
      tei: """
        <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt><title>t</title></titleStmt></fileDesc></teiHeader><text><body>
        <pb n="1" facs="https://example.org/iiif/web-tests-incoming/full/1300,/0/default.jpg"/>
        <p><w lemma="report" type="noun">Report</w><lb/></p>
        </body></text></TEI>
        """)
    let catalog = try ScratchWork(owner: admin)
    func cleanUp() async throws {
      _ = try? TestAdmin.query(EntriesAndCitationsTests.clean([catalog]))
      reading.remove()
      catalog.remove()
      try await admin.remove()
    }
    do {
      // Nothing says anything of the record yet: neither.
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(reading.path)
        try await expect(page.locator(".disputorium-core-view")).toHaveCount(1)
        try await expect(page.locator("#record-entries")).toHaveCount(0)
        try await expect(page.locator("#record-citations")).toHaveCount(0)
      }
      // A catalog's entry for it, and two citations of it in the catalog.
      let catalogPath = try EntriesAndCitationsTests.retype(catalog, "catalog")
      let workID = reading.work.recordID.lowercased()
      _ = try TestAdmin.query(
        "BEGIN;\n" + EntriesAndCitationsTests.read(catalog)
          + EntriesAndCitationsTests.entry(in: catalog, heading: "WEB TESTS HEADING", work: workID)
          + EntriesAndCitationsTests.cite(2, by: catalog, work: workID) + "\nCOMMIT;")
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(reading.path)
        // After the work, Entries above Citations.
        let order = try await page.evaluate(
          "(() => { const w = document.querySelector('.disputorium-core-work'), e = document.querySelector('.disputorium-core-view #record-entries'), c = document.querySelector('.disputorium-core-view #record-citations'); return w && e && c && (w.compareDocumentPosition(e) & Node.DOCUMENT_POSITION_FOLLOWING) && (e.compareDocumentPosition(c) & Node.DOCUMENT_POSITION_FOLLOWING) ? 'in order' : 'out of order'; })()"
        ).string
        #expect(order == "in order")
        let entries = page.locator("#record-entries")
        try await entries.locator(".accordion-summary").first.click()
        let row = entries.locator(".entries-entry")
        try await expect(row).toHaveCount(1)
        try await expect(row.locator("a[href='\(catalogPath)']")).toHaveCount(1)
        try await expect(row).toContainText("WEB TESTS HEADING")
        let citations = page.locator("#record-citations")
        try await citations.locator(".accordion-summary").first.click()
        let work = citations.locator(".citations-work")
        try await expect(work).toHaveCount(1)
        try await expect(work.locator("a[href='\(catalogPath)']")).toHaveCount(1)
        try await expect(work.locator(".citations-count")).toHaveText("2 citations")
        try await page.expectNoHorizontalOverflow()
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
