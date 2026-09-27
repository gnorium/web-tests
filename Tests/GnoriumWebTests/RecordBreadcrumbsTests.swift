import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A record's footer breadcrumbs walk its path (and its subpages' walk it
/// too, then their own), and every crumb before the
/// last is its prefix's page, the records list filtered to it:
/// `Biblio-records › English › {title} › {author} › Report`. From the record
/// page a reader climbs crumb by crumb — the authors' page, the title's, the
/// language's, the whole list — each page listing the record and crumbed up
/// to itself. The biblio record is a scratch work made by SQL (no account
/// owns a record) and removed after; the lexico record is the first the
/// index lists.
@Suite("Record breadcrumbs", .serialized)
struct RecordBreadcrumbsTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func climbingABiblioRecordsCrumbs(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let work = try ScratchRecord()
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await Self.climb(page, from: work.path, labels: ["English", work.title, work.author, "Report"])
      }
    } catch {
      work.remove()
      throw error
    }
    work.remove()
  }

  @Test(arguments: gnorium.engines, Layout.allCases)
  func climbingALexicoRecordsCrumbs(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      let record = try await HydrationSmokeTests.firstRecord(page, in: "/lexico-records")
      try await Self.climb(page, from: record, labels: nil)
    }
  }

  /// A record's Versions page walks the record's path, then its own crumb.
  /// With the footer's home that is seven crumbs, one past the fold: the
  /// middle (the language) folds into the overflow menu, as a link that
  /// still goes to its page; home, the list, the record and the page stay
  /// in sight.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aVersionsPageWalksItsRecordsPath(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let work = try ScratchRecord()
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated("\(work.path)/versions")
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
        let trail = page.locator("footer .footer-breadcrumbs")
        try await expect(trail.locator(".breadcrumb-item")).toHaveCount(6)
        try await expect(trail.locator(".breadcrumb-current")).toHaveText("Versions")
        let titleSlug = work.path.split(separator: "/")[2]
        let authorsSlug = work.path.split(separator: "/")[3]
        for href in [
          "/", "/biblio-records", "/biblio-records/eng/\(titleSlug)", "/biblio-records/eng/\(titleSlug)/\(authorsSlug)",
          work.path,
        ] {
          try await expect(trail.locator(".breadcrumb-item > a[href='\(href)']")).toBeVisible()
        }
        // The folded language: a link in the overflow menu.
        try await trail.locator(".breadcrumb-overflow button").click()
        let english = trail.locator(".breadcrumb-overflow a[href='/biblio-records/eng']")
        try await expect(english).toBeVisible()
        try await expect(english).toHaveText("English")
        try await english.click()
        try await expect(page).toHaveURL("/biblio-records/eng") { url in url.path == "/biblio-records/eng" }
        try await expect(page.locator("main a[href='\(work.path)']")).toHaveCount(1)
      }
    } catch {
      work.remove()
      throw error
    }
    work.remove()
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
        try await page.openHydrated("/\(titlePrefix)?q=crumbs&field=title&treatment=attributed")
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
        let lexicoTab = page.locator(".records-tabs #tab-lexico-records")
        let biblioTab = page.locator(".records-tabs #tab-biblio-records")
        try await expect(lexicoTab).toBeVisible()
        try await expect(biblioTab).toHaveAttribute("href", "/biblio-records/eng?treatment=attributed")
        try await expect(lexicoTab).toHaveAttribute("href", "/lexico-records/eng?treatment=attributed")
        try await lexicoTab.click()
        try await expect(page).toHaveURL("/lexico-records/eng?treatment=attributed") { url in
          url.path == "/lexico-records/eng" && url.query == "treatment=attributed"
        }
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
        try await expect(page.locator(".records-tabs #tab-biblio-records")).toHaveAttribute(
          "href", "/biblio-records/eng?treatment=attributed")
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
  /// itself. `labels` are the four crumbs' words, when known.
  static func climb(_ page: Page, from record: String, labels: [String]?) async throws {
    try await page.openHydrated(record)
    try await page.expectNoErrors()
    let decoded = record.removingPercentEncoding ?? record
    var segments = decoded.split(separator: "/").map(String.init)
    #expect(segments.count == 5, "not a four-segment record path: \(decoded)")
    let trail = page.locator("footer .footer-breadcrumbs")
    // Home, the list, three prefixes; the record itself current.
    try await expect(trail.locator("a")).toHaveCount(5)
    if let labels {
      try await expect(trail.locator(".breadcrumb-current")).toHaveText(labels[3])
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
/// enough for its page and its prefixes' pages.
private struct ScratchRecord {
  let title: String
  let author: String
  let path: String
  private let recordID: String
  private let personID: String
  private let authorshipID: String

  init() throws {
    recordID = UUID().uuidString.lowercased()
    personID = UUID().uuidString.lowercased()
    authorshipID = UUID().uuidString.lowercased()
    let suffix = String(recordID.prefix(8))
    title = "Web tests crumbs \(suffix)"
    author = "Web Tests Crumbs Author \(suffix)"
    let slug = "web-tests-crumbs-\(suffix)"
    let authorSlug = "web-tests-crumbs-author-\(suffix)"
    path = "/biblio-records/eng/\(slug)/\(authorSlug)/report"
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO biblio_records (id, corpus_id, title, title_slug, authors, category, language, genres, year, date_display)
        VALUES ('\(recordID)', (SELECT id FROM corpora ORDER BY created_at LIMIT 1), '\(title)', '\(slug)', '\(authorSlug)',
          'report', 'eng', '[]', 1958, 'AD 1958');
      INSERT INTO persons (id, display_name, slug) VALUES ('\(personID)', '\(author)', '\(authorSlug)');
      INSERT INTO biblio_record_authors (id, biblio_record_id, person_id, position)
        VALUES ('\(authorshipID)', '\(recordID)', '\(personID)', 0);
      COMMIT;
      """)
  }

  func remove() {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM url_histories WHERE entity_id IN ('\(recordID)', '\(personID)');
      DELETE FROM biblio_record_authors WHERE id = '\(authorshipID)';
      DELETE FROM biblio_records WHERE id = '\(recordID)';
      DELETE FROM persons WHERE id = '\(personID)';
      COMMIT;
      """)
  }
}
