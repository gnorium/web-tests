import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A record's footer breadcrumbs walk its path, and every crumb before the
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
