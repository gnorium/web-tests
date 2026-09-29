import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A record's Entries and its Cited by (user, 2026-09-29). A canon is a
/// reference work — a biblio-record whose type is a reference type — and a
/// record's entries in canons are its "Entries" (each referred to as a record
/// is: language, title, type; the heading as printed; the page); the works
/// citing it in running text are its "Cited by", one row per work with how
/// many, the count opening every citation between the two, a page at a time.
/// The biblio-records sidebar's "Canons" is the list filtered to the
/// reference types. A reader's Find bar searches its whole transcript. Phone
/// and desktop, Chrome headless.
@Suite("Entries and Cited by", .serialized)
struct EntriesAndCitedByTests {
  /// A scratch work retyped (a catalog, a dictionary…): its address moves
  /// with its type.
  static func retype(_ work: ScratchWork, _ type: String) throws -> String {
    _ = try TestAdmin.query("UPDATE biblio_records SET type = '\(type)' WHERE id = '\(work.recordID.lowercased())';")
    return work.path.replacingOccurrences(of: "/report", with: "/\(type)")
  }

  /// A work's version read for its citations: the one its citations count from.
  static func read(_ work: ScratchWork) -> String {
    """
    INSERT INTO citation_extractions (id, biblio_record_version_id, testament_id, permitted_at, citations_version, count, extracted_at)
      VALUES (gen_random_uuid(), '\(work.versionID.lowercased())', '\(work.recordID.lowercased())', now(), 'tei-bibl-ref-mentioned-v3', 0, now());
    """
  }

  /// `count` citations of `cited` (a work, or a word) by `citing`'s version, in running text.
  static func cite(_ count: Int, by citing: ScratchWork, work: String? = nil, word: String? = nil, entry: String? = nil)
    -> String
  {
    (1...count).map { line in
      """
      INSERT INTO citations (id, biblio_record_version_id, biblio_record_id, testament_id, permitted_at, canvas_id, page,
        start_line, start_word, start_surface, end_line, end_word, end_surface, element, kind, surface, parts_json,
        language_code, status, decided_by, cited_biblio_record_id, cited_lexico_record_id, confidence, basis,
        resolver_version, resolved_at, created_at, entry_headword, entry_head)
        VALUES (gen_random_uuid(), '\(citing.versionID.lowercased())', '\(citing.recordID.lowercased())',
          '\(citing.recordID.lowercased())', now(), 'c', 2, \(line), 1, 'Cited', \(line), 1, 'Cited',
          '\(word == nil ? "bibl" : "mentioned")', '\(word == nil ? "work" : "word")', 'Cited \(line)', '{}', 'eng',
          'resolved', 'resolver', \(work.map { "'\($0)'" } ?? "NULL"), \(word.map { "'\($0)'" } ?? "NULL"), 0.7, 'title',
          'citation-resolver-v3', now(), now(), \(entry.map { "'\($0)'" } ?? "NULL"), false);
      """
    }.joined(separator: "\n")
  }

  /// `canon`'s entry for a work or a word, headed `heading`, on page 3.
  static func entry(in canon: ScratchWork, heading: String, work: String? = nil, word: String? = nil) -> String {
    """
    INSERT INTO record_entries (id, biblio_record_version_id, work_record_id, testament_id, permitted_at, canvas_id, page,
      start_line, start_word, start_surface, end_line, end_word, end_surface, kind, heading, parts_json, language_code,
      status, decided_by, lexico_record_id, biblio_record_id, resolver_version, resolved_at, created_at)
      VALUES (gen_random_uuid(), '\(canon.versionID.lowercased())', '\(canon.recordID.lowercased())',
        '\(canon.recordID.lowercased())', now(), 'c', 3, 1, 1, '\(heading)', 1, 1, '\(heading)',
        '\(word == nil ? "bibliographic" : "lexicographic")', '\(heading)', '{}', 'eng', 'resolved', 'resolver',
        \(word.map { "'\($0)'" } ?? "NULL"), \(work.map { "'\($0)'" } ?? "NULL"), 'citation-resolver-v3', now(), now());
    """
  }

  static func clean(_ works: [ScratchWork]) -> String {
    let versions = works.map { "'\($0.versionID.lowercased())'" }.joined(separator: ",")
    return """
      DELETE FROM record_entries WHERE biblio_record_version_id IN (\(versions));
      DELETE FROM citations WHERE biblio_record_version_id IN (\(versions));
      DELETE FROM citation_extractions WHERE biblio_record_version_id IN (\(versions));
      """
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWorksEntriesAndCitedByAndTheirPairsPage(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let cited = try ScratchWork(owner: admin)
    let catalog = try ScratchWork(owner: admin)
    let letters = try ScratchWork(owner: admin)
    let works = [cited, catalog, letters]
    func cleanUp() async {
      _ = try? TestAdmin.query(Self.clean(works))
      for work in works { work.remove() }
      await admin.remove()
    }
    do {
      let catalogPath = try Self.retype(catalog, "catalog")
      let citedID = cited.recordID.lowercased()
      _ = try TestAdmin.query(
        "BEGIN;\n" + Self.read(catalog) + Self.read(letters)
          + Self.entry(in: catalog, heading: "WEB TESTS HEADING", work: citedID)
          + Self.cite(1, by: catalog, work: citedID, entry: "ANOTHER HEADING") + Self.cite(3, by: letters, work: citedID)
          + "\nCOMMIT;")
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(cited.path)
        // Its entries in canons: the catalog's, referred to as a record is.
        let entries = page.locator("#record-entries")
        try await entries.locator(".accordion-summary").first.click()
        let row = entries.locator(".entries-view-entry")
        try await expect(row).toHaveCount(1)
        try await expect(row).toContainText("English")
        try await expect(row.locator("a[href='\(catalogPath)']")).toHaveCount(1)
        try await expect(row).toContainText("Catalog")
        try await expect(row).toContainText("WEB TESTS HEADING")
        try await expect(row.locator("a[href='\(catalogPath)/versions/\(catalog.versionID)?semblance=2']")).toHaveCount(1)
        try await expect(row).not.toContainText("Canon")
        // The works citing it in running text, one row each with how many.
        let citedBy = page.locator("#record-cited-by")
        try await citedBy.locator(".accordion-summary").first.click()
        let rows = citedBy.locator(".cited-by-view-work")
        try await expect(rows).toHaveCount(2)
        try await expect(citedBy.locator(".filter-bar-view")).toHaveCount(1)
        let lettersRow = rows.filter(hasText: letters.title)
        try await expect(lettersRow.locator(".cited-by-view-count")).toHaveText("3 citations")
        try await expect(rows.filter(hasText: catalog.title).locator(".cited-by-view-count")).toHaveText("1 citation")
        // Its Metadata counts them.
        let metadata = page.locator("#record-metadata")
        try await metadata.locator(".accordion-summary").first.click()
        try await expect(metadata.locator(".datum-view").filter(hasText: "Cited by").locator(".datum-value"))
          .toHaveText("2 works")
        try await page.expectNoHorizontalOverflow()

        // Filtered by type: the catalog alone.
        try await page.openHydrated("\(cited.path)?type=catalog#record-cited-by")
        try await expect(page.locator("#record-cited-by .cited-by-view-work")).toHaveCount(1)
        try await expect(page.locator("#record-cited-by .cited-by-view-work")).toContainText(catalog.title)

        // The pair's page: every citation between the two, the catalog's in the entry it stands in.
        try await page.openHydrated(
          "\(cited.path)/citations?work=\(catalog.recordID.lowercased())&direction=cited-by")
        try await expect(page.locator("h1")).toHaveText("Cited by \(catalog.title)")
        let table = page.locator(".record-citations-view-table")
        try await expect(table).toContainText("ANOTHER HEADING")
        try await expect(table).toContainText("Cited 1")
        try await expect(table).toContainText("Resolved by gnorium")
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      await cleanUp()
      throw error
    }
    await cleanUp()
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWordsEntriesAreItsHeadwordEntriesInCanonsAndTheCanonsLinkListsReferenceWorks(
    engine: BrowserEngine, layout: Layout
  ) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let dictionary = try ScratchWork(owner: admin)
    let letters = try ScratchWork(owner: admin)
    let word = try ScratchWord(owner: admin)
    func cleanUp() async {
      _ = try? TestAdmin.query(Self.clean([dictionary, letters]))
      word.remove()
      dictionary.remove()
      letters.remove()
      await admin.remove()
    }
    do {
      let dictionaryPath = try Self.retype(dictionary, "dictionary")
      let wordID = word.recordID.lowercased()
      _ = try TestAdmin.query(
        "BEGIN;\n" + Self.read(dictionary) + Self.read(letters)
          + Self.entry(in: dictionary, heading: word.title.uppercased(), word: wordID)
          + Self.cite(2, by: letters, word: wordID) + "\nCOMMIT;")
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(word.path)
        let entries = page.locator("#record-entries")
        try await entries.locator(".accordion-summary").first.click()
        let row = entries.locator(".entries-view-entry")
        try await expect(row).toHaveCount(1)
        try await expect(row.locator("a[href='\(dictionaryPath)']")).toHaveCount(1)
        try await expect(row).toContainText("Dictionary")
        try await expect(row).toContainText(word.title.uppercased())
        let citedBy = page.locator("#record-cited-by")
        try await citedBy.locator(".accordion-summary").first.click()
        try await expect(citedBy.locator(".cited-by-view-work")).toHaveCount(1)
        try await expect(citedBy.locator(".cited-by-view-count")).toHaveText("2 citations")
        try await page.expectNoHorizontalOverflow()

        // The biblio-records sidebar's Canons: the list filtered to the reference types.
        try await page.openHydrated("/biblio-records")
        let canons = page.locator(".sidebar-canon-link a").first
        try await expect(canons).toHaveText("Canons")
        let href = try await canons.getAttribute("href") ?? ""
        #expect(href.contains("type=dictionary") && href.contains("type=catalog") && href.contains("type=gazetteer"))
        try await page.openHydrated(href)
        let results = page.locator(".records-results-view")
        try await expect(results.locator("a[href='\(dictionaryPath)']")).toHaveCount(1)
        try await expect(results.locator("a[href='\(letters.path)']")).toHaveCount(0)
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      await cleanUp()
      throw error
    }
    await cleanUp()
  }

  /// Two pages of text: "scratchfind" once on the first, twice on the second.
  static let tei = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt><title>t</title></titleStmt></fileDesc></teiHeader><text><body>
    <pb n="1" facs="https://example.org/iiif/web-tests-find-1/full/1300,/0/default.jpg"/>
    <p>The scratchfind stood here.<lb/>Nothing else.<lb/></p>
    <pb n="2" facs="https://example.org/iiif/web-tests-find-2/full/1300,/0/default.jpg"/>
    <p>A Scratchfind again.<lb/>And scratchfind once more.<lb/></p>
    </body></text></TEI>
    """

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aReadersFindBarSearchesEveryPageAndMarksTheMatchUntilClosed(engine: BrowserEngine, layout: Layout)
    async throws
  {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch = try ScratchTestament(owner: admin, tei: Self.tei)
    func cleanUp() async {
      scratch.remove()
      await admin.remove()
    }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(scratch.reading.work.path)
        _ = try await page.evaluate(
          """
          (() => { document.querySelector("[data-reader-url*='\(scratch.versionID)' i]").closest('.record-row')
            .querySelector(':scope > .accordion-details > .accordion-summary').click(); return true; })()
          """)
        let viewer = page.locator(".artifact-view").first
        let bar = viewer.locator(".testament-find-view")
        try await expect(bar).toBeHidden()
        try await viewer.locator(".testament-find-button").click()
        try await expect(bar).toBeVisible()
        try await bar.locator("input").fill("scratchfind")
        let count = bar.locator(".testament-find-count")
        try await expect(count).toHaveText("1 of 3")
        let marked = viewer.locator(".tei-line[data-find-current='true']")
        try await expect(marked).toHaveCount(1)
        try await expect(marked).toContainText("The scratchfind stood here.")
        // Enter: the next match, on the next page, which the reader turns to.
        try await bar.locator("input").press("Enter")
        try await expect(count).toHaveText("2 of 3")
        try await expect(marked).toContainText("A Scratchfind again.")
        try await expect(marked).toBeVisible()
        try await bar.locator("input").press("Enter")
        try await expect(count).toHaveText("3 of 3")
        // Shift+Enter and the previous button go back.
        try await bar.locator("input").press("Shift+Enter")
        try await expect(count).toHaveText("2 of 3")
        try await bar.locator(".testament-find-previous").click()
        try await expect(count).toHaveText("1 of 3")
        try await page.expectNoHorizontalOverflow()
        // Esc closes the bar and clears the mark.
        try await bar.locator("input").press("Escape")
        try await expect(bar).toBeHidden()
        try await expect(viewer.locator(".tei-line[data-find-current='true']")).toHaveCount(0)
      }
    } catch {
      await cleanUp()
      throw error
    }
    await cleanUp()
  }
}
