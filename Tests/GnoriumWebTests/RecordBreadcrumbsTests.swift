import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A record's footer breadcrumbs walk its address (and its subpages' walk it
/// too, then their own), and every crumb before the last is its prefix's
/// page, the records list filtered to it: `Biblio-records › English ›
/// {title} › report`, and where works share those three, `… › report ›
/// {author}`, the three segments the list of them. From the record page a
/// reader climbs crumb by crumb—the group's list, the title's, the
/// language's, the whole list—each page listing the record and crumbed up
/// to itself. The biblio records are scratch works made by SQL (no account
/// owns a record; a pair's qualifiers written as the server computes them)
/// and removed after; the lexico record is the first the index lists.
@Suite("Record breadcrumbs", .serialized)
struct RecordBreadcrumbsTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func climbingABiblioRecordsCrumbs(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let work = try ScratchRecord()
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await Self.climb(page, from: work.path, labels: ["English", work.title, "Report"])
      }
    } catch {
      work.remove()
      throw error
    }
    work.remove()
  }

  @Test(arguments: gnorium.engines, Layout.allCases)
  func climbingAQualifiedBiblioRecordsCrumbs(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let (work, namesake) = try ScratchRecord.pair()
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await Self.climb(page, from: work.path, labels: ["English", work.title, "Report", work.author])
        // The three segments are the list of the two.
        let group = work.path.split(separator: "/").prefix(4).joined(separator: "/")
        try await page.openHydrated("/\(group)")
        try await expect(page.locator("main a[href='\(namesake.path)']")).toHaveCount(1)
        try await expect(page.locator("main a[href='\(work.path)']")).toHaveCount(1)
      }
    } catch {
      work.remove()
      namesake.remove()
      throw error
    }
    work.remove()
    namesake.remove()
  }

  @Test(arguments: gnorium.engines, Layout.allCases)
  func climbingALexicoRecordsCrumbs(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      let record = try await HydrationSmokeTests.firstRecord(page, in: "/lexico-records")
      try await Self.climb(page, from: record, labels: nil)
    }
  }

  /// A qualified record's Snapshots page walks the record's address, then
  /// its own crumb. With the footer's home that is seven crumbs, every one in
  /// sight (no overflow menu, 2026-10-04): the language a link that goes to
  /// its page.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aSnapshotsPageWalksItsRecordsPath(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let (work, namesake) = try ScratchRecord.pair()
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated("\(work.path)/snapshots")
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
        let trail = page.locator("footer .footer-breadcrumbs")
        try await expect(trail.locator(".breadcrumb-item")).toHaveCount(7)
        try await expect(trail.locator(".breadcrumb-current")).toHaveText("Snapshots")
        let titleSlug = work.path.split(separator: "/")[2]
        for href in [
          "/", "/biblio-records", "/biblio-records/eng", "/biblio-records/eng/\(titleSlug)", "/biblio-records/eng/\(titleSlug)/report",
          work.path,
        ] {
          try await expect(trail.locator(".breadcrumb-item > a[href='\(href)']")).toBeVisible()
        }
        try await expect(trail.locator(".breadcrumb-overflow")).toHaveCount(0)
        let english = trail.locator(".breadcrumb-item > a[href='/biblio-records/eng']")
        try await expect(english).toHaveText("English")
        try await english.click()
        try await expect(page).toHaveURL("/biblio-records/eng") { url in url.path == "/biblio-records/eng" }
        try await expect(page.locator("main a[href='\(work.path)']")).toHaveCount(1)
      }
    } catch {
      work.remove()
      namesake.remove()
      throw error
    }
    work.remove()
    namesake.remove()
  }

  /// A prefix page's records tabs keep its language, nothing under it, and
  /// the treatment filter where the other half has its name; the search is
  /// each half's own and drops.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aPrefixPagesTabsKeepItsLanguage(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let work = try ScratchRecord()
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        let titlePrefix = work.path.split(separator: "/").prefix(3).joined(separator: "/")
        try await page.openHydrated("/\(titlePrefix)?title=crumbs&field=title&treatment=translated")
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
        let lexicoTab = page.locator(".records-tabs #tab-lexico-records")
        let biblioTab = page.locator(".records-tabs #tab-biblio-records")
        try await expect(lexicoTab).toBeVisible()
        try await expect(biblioTab).toHaveAttribute("href", "/biblio-records/eng?treatment=translated")
        try await expect(lexicoTab).toHaveAttribute("href", "/lexico-records/eng?treatment=translated")
        try await lexicoTab.click()
        try await expect(page).toHaveURL("/lexico-records/eng?treatment=translated") { url in
          url.path == "/lexico-records/eng" && url.query == "treatment=translated"
        }
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
        try await expect(page.locator(".records-tabs #tab-biblio-records")).toHaveAttribute(
          "href", "/biblio-records/eng?treatment=translated")
        try await expect(page.locator(".records-tabs #tab-lexico-records")).toHaveAttribute("aria-selected", "true")
      }
    } catch {
      work.remove()
      throw error
    }
    work.remove()
  }

  /// Opens `record` and climbs its crumbs to the list: each crumb links to
  /// its prefix, the page there lists the record, and its own trail ends at
  /// itself. `labels` are the crumbs' words after the list's, when known.
  static func climb(_ page: Page, from record: String, labels: [String]?) async throws {
    try await page.openHydrated(record)
    try await page.expectNoErrors()
    let decoded = record.removingPercentEncoding ?? record
    var segments = decoded.split(separator: "/").map(String.init)
    #expect(
      segments.count == 4 || segments.count == 5, "not a three- or four-segment record address: \(decoded)")
    let trail = page.locator("footer .footer-breadcrumbs")
    // Home, the list, its prefixes; the record itself current.
    try await expect(trail.locator("a")).toHaveCount(segments.count)
    if let labels, let last = labels.last {
      try await expect(trail.locator(".breadcrumb-current")).toHaveText(last)
    }
    while segments.count > 1 {
      segments.removeLast()
      let prefix = "/" + segments.joined(separator: "/")
      let crumb = trail.locator("a[href='\(prefix)']")
      try await expect(crumb).toHaveCount(1)
      try await crumb.click()
      try await expect(page).toHaveURL(prefix) { url in
        url.path == prefix
      }
      try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
      try await page.expectNoErrors()
      try await page.expectNoHorizontalOverflow()
      // A prefix's page lists the record (the whole list pages it out of
      // sight), and its trail ends at itself.
      if segments.count > 1 {
        try await expect(page.locator("main a[href='\(decoded)']")).toHaveCount(1)
      }
      try await expect(trail.locator("a")).toHaveCount(segments.count)
      if let labels, segments.count > 1 {
        try await expect(trail.locator(".breadcrumb-current")).toHaveText(labels[segments.count - 2])
      }
    }
  }
}

/// A bare biblio-record and its one author, made by SQL and removed after:
/// enough for its page and its prefixes' pages. A pair shares its title and
/// type, each qualified by its author, as the server qualifies them.
struct ScratchRecord {
  let title: String
  let author: String
  let path: String
  private let recordID: String
  private let authorshipID: String

  init(title shared: (title: String, slug: String)? = nil, qualified: Bool = false) throws {
    recordID = UUID().uuidString.lowercased()
    authorshipID = UUID().uuidString.lowercased()
    let suffix = String(recordID.prefix(8))
    title = shared?.title ?? "Web tests crumbs \(suffix)"
    author = "Web Tests Crumbs Author \(suffix)"
    let slug = shared?.slug ?? "web-tests-crumbs-\(suffix)"
    let authorSlug = "web-tests-crumbs-author-\(suffix)"
    let qualifier = qualified ? "'\(authorSlug)'" : "NULL"
    path = "/biblio-records/eng/\(slug)/report" + (qualified ? "/\(authorSlug)" : "")
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO biblio_records (id, corpus_id, title, title_slug, type, qualifier, language, genres, year, date_display)
        VALUES ('\(recordID)', (SELECT id FROM corpora ORDER BY created_at LIMIT 1), '\(title)', '\(slug)',
          'report', \(qualifier), 'eng', '[]', 1958, 'AD 1958');
      INSERT INTO biblio_record_voices (id, biblio_record_id, name, role, position)
        VALUES ('\(authorshipID)', '\(recordID)', '\(author)', 'author', 0);
      COMMIT;
      """)
  }

  /// Two works of one title and type, by two people: each at its author.
  static func pair() throws -> (ScratchRecord, ScratchRecord) {
    let suffix = String(UUID().uuidString.lowercased().prefix(8))
    let shared = (title: "Web tests pair \(suffix)", slug: "web-tests-pair-\(suffix)")
    let first = try ScratchRecord(title: shared, qualified: true)
    do {
      return (first, try ScratchRecord(title: shared, qualified: true))
    } catch {
      first.remove()
      throw error
    }
  }

  func remove() {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM url_histories WHERE entity_id = '\(recordID)';
      DELETE FROM biblio_record_voices WHERE id = '\(authorshipID)';
      DELETE FROM biblio_records WHERE id = '\(recordID)';
      COMMIT;
      """)
  }
}
