import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A record's footer breadcrumbs walk its address (and its subpages' walk it
/// too, then their own), and every crumb before the last is its prefix's
/// page, the records list filtered to it: `Biblio-records › English ›
/// {title} › report`; where works share those three, `… › report ›
/// {author}`, the three segments the list of them; and where they share the
/// voice names too, `… › {author} › 1`, the voice names the list of the
/// homographs. From the record page a reader climbs crumb by crumb—the
/// homographs' list, the group's, the title's, the language's, the whole
/// list—each page listing the record and crumbed up to itself. The biblio
/// records are scratch works made by SQL (no account owns a record; a
/// pair's voice names and homograph numbers written as the server computes
/// them) and removed after; the lexico record is the first the index lists.
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
  func climbingAVoicedBiblioRecordsCrumbs(engine: BrowserEngine, layout: Layout) async throws {
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

  /// Homographs: two works of one title, class and author, each at its
  /// number under its voice names, which list the two.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func climbingAHomographsCrumbs(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let (first, second) = try ScratchRecord.homographs()
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await Self.climb(page, from: second.path, labels: ["English", second.title, "Report", second.author, "2"])
        let voiceNames = second.path.split(separator: "/").prefix(5).joined(separator: "/")
        try await page.openHydrated("/\(voiceNames)")
        try await expect(page.locator("main a[href='\(first.path)']")).toHaveCount(1)
        try await expect(page.locator("main a[href='\(second.path)']")).toHaveCount(1)
        // The list filtered by Language, Title, Class and Voice names.
        try await expect(page.locator(".filter-bar-view input[name='voice-names']")).toHaveCount(1)
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      first.remove()
      second.remove()
      throw error
    }
    first.remove()
    second.remove()
  }

  @Test(arguments: gnorium.engines, Layout.allCases)
  func climbingALexicoRecordsCrumbs(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      let record = try await HydrationSmokeTests.firstRecord(page, in: "/lexico-records")
      try await Self.climb(page, from: record, labels: nil)
    }
  }

  /// A voiced record's Vignettes page walks the record's address, then
  /// its own crumb. With the footer's home that is seven crumbs, every one in
  /// sight (no overflow menu, 2026-10-04): the language a link that goes to
  /// its page.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aVignettesPageWalksItsRecordsPath(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let (work, namesake) = try ScratchRecord.pair()
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated("\(work.path)/vignettes")
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
        let trail = page.locator("footer .footer-breadcrumbs")
        try await expect(trail.locator(".breadcrumb-item")).toHaveCount(7)
        try await expect(trail.locator(".breadcrumb-current")).toHaveText("Vignettes")
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
  /// the status filter where the other half has its name; the search is
  /// each half's own and drops.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aPrefixPagesTabsKeepItsLanguage(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let work = try ScratchRecord()
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        let titlePrefix = work.path.split(separator: "/").prefix(3).joined(separator: "/")
        try await page.openHydrated("/\(titlePrefix)?title=crumbs&field=title&status=translated")
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
        let lexicoTab = page.locator(".records-tabs #tab-lexico-records")
        let biblioTab = page.locator(".records-tabs #tab-biblio-records")
        try await expect(lexicoTab).toBeVisible()
        // A tab is a large control (user, 2026-10-10): 12 around the 22px
        // line inside a 1px transparent border, 48.
        let tabHeight = try #require(try await lexicoTab.boundingBox()).height
        #expect(abs(tabHeight - 48) < 0.5, "a records tab is \(tabHeight)px tall, not 48")
        try await expect(biblioTab).toHaveAttribute("href", "/biblio-records/eng?status=translated")
        try await expect(lexicoTab).toHaveAttribute("href", "/lexico-records/eng?status=translated")
        try await lexicoTab.click()
        try await expect(page).toHaveURL("/lexico-records/eng?status=translated") { url in
          url.path == "/lexico-records/eng" && url.query == "status=translated"
        }
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
        try await expect(page.locator(".records-tabs #tab-biblio-records")).toHaveAttribute(
          "href", "/biblio-records/eng?status=translated")
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
      (4...6).contains(segments.count), "not a record address: \(decoded)")
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
/// class, each at its author's name; homographs share the author too, each
/// at its number under it, as the server addresses them.
struct ScratchRecord {
  let title: String
  let author: String
  let path: String
  private let recordID: String
  private let authorshipID: String

  init(
    title shared: (title: String, slug: String)? = nil, author sharedAuthor: String? = nil, voiced: Bool = false,
    homograph: Int? = nil
  ) throws {
    recordID = UUID().uuidString.lowercased()
    authorshipID = UUID().uuidString.lowercased()
    let suffix = String(recordID.prefix(8))
    title = shared?.title ?? "Web tests crumbs \(suffix)"
    author = sharedAuthor ?? "Web Tests Crumbs Author \(suffix)"
    let slug = shared?.slug ?? "web-tests-crumbs-\(suffix)"
    let authorSlug = author.lowercased().replacingOccurrences(of: " ", with: "-")
    let voiceNames = voiced ? "'\(authorSlug)'" : "NULL"
    path = "/biblio-records/eng/\(slug)/report" + (voiced ? "/\(authorSlug)" : "") + (homograph.map { "/\($0)" } ?? "")
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO biblio_records (id, corpus_id, title, title_slug, type, voice_names_segment, homograph, language, genres, year, date_display)
        VALUES ('\(recordID)', (SELECT id FROM corpora ORDER BY created_at LIMIT 1), '\(title)', '\(slug)',
          'report', \(voiceNames), \(homograph.map(String.init) ?? "NULL"), 'eng', '[]', 1958, 'AD 1958');
      INSERT INTO biblio_record_voices (id, biblio_record_id, name, role, position)
        VALUES ('\(authorshipID)', '\(recordID)', '\(author)', 'author', 0);
      COMMIT;
      """)
  }

  /// Two works of one title and type, by two people: each at its author.
  static func pair() throws -> (ScratchRecord, ScratchRecord) {
    let suffix = String(UUID().uuidString.lowercased().prefix(8))
    let shared = (title: "Web tests pair \(suffix)", slug: "web-tests-pair-\(suffix)")
    let first = try ScratchRecord(title: shared, voiced: true)
    do {
      return (first, try ScratchRecord(title: shared, voiced: true))
    } catch {
      first.remove()
      throw error
    }
  }

  /// Two works of one title, class and author: each at its number under
  /// the author's name.
  static func homographs() throws -> (ScratchRecord, ScratchRecord) {
    let suffix = String(UUID().uuidString.lowercased().prefix(8))
    let shared = (title: "Web tests homographs \(suffix)", slug: "web-tests-homographs-\(suffix)")
    let author = "Web Tests Homographs Author \(suffix)"
    let first = try ScratchRecord(title: shared, author: author, voiced: true, homograph: 1)
    do {
      return (first, try ScratchRecord(title: shared, author: author, voiced: true, homograph: 2))
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
