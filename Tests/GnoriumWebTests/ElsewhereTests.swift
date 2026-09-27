import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A record page's "Elsewhere": after the References, an accordion framed
/// as they are, closed until opened, listing the same word or work in other
/// dictionaries and catalogs one line each: verified links first (the
/// source's name, to the entry), then search links ("Search <source> for
/// <title>", to the source's search), a subscription noted. The same on both
/// sides. Scratch records by SQL, removed after; the word's verified
/// Wiktionary entry is a cached finding written by SQL, not a real check.
@Suite("Elsewhere", .serialized)
struct ElsewhereTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWordsDictionaries(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    let entry = "https://en.wiktionary.org/wiki/\(word.title)#English"
    // Found, and not due again for a month: the checker leaves it be.
    _ = try TestAdmin.query(
      """
      INSERT INTO elsewhere_checks (id, record_kind, record_id, source, method, status, url, attempts, checked_at, next_check_at)
        SELECT gen_random_uuid(), 'lexico', id, 'wiktionary', 'wiktionary', 'found', '\(entry)', 0, now(), now() + interval '30 days'
        FROM lexico_records WHERE title = '\(word.title)';
      """)
    func remove() async {
      _ = try? TestAdmin.query(
        "DELETE FROM elsewhere_checks WHERE record_id IN (SELECT id FROM lexico_records WHERE title = '\(word.title)');")
      word.remove()
      await admin.remove()
    }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(word.path)
        let elsewhere = try await open(page)
        let entries = elsewhere.locator(".elsewhere-view-entry")
        // Verified first: Wiktionary's entry, by name.
        try await expect(entries.nth(0)).toHaveAttribute("data-kind", "verified")
        #expect(try await linkText(entries.nth(0).locator("a")) == "Wiktionary")
        try await expect(entries.nth(0).locator("a")).toHaveAttribute("href", entry)
        // Then the searches in the registry's order, each worded as one.
        let oed = entries.nth(1)
        try await expect(oed).toHaveAttribute("data-kind", "search")
        #expect(try await linkText(oed.locator("a")) == "Search Oxford English Dictionary for \(word.title)")
        try await expect(oed.locator("a")).toHaveAttribute(
          "href", "https://www.oed.com/search/dictionary/?scope=Entries&q=\(word.title)")
        try await expect(oed).toContainText("(subscription)")
        #expect(try await linkText(entries.nth(2).locator("a")) == "Search Middle English Dictionary for \(word.title)")
        #expect(try await linkText(entries.nth(3).locator("a")) == "Search Merriam-Webster for \(word.title)")
        try await expect(entries.nth(3).locator("a")).toHaveAttribute(
          "href", "https://www.merriam-webster.com/dictionary/\(word.title)")
        #expect(try await linkText(entries.nth(4).locator("a")) == "Search Wikidata for \(word.title)")
        try await expect(entries.nth(4).locator("a")).toHaveAttribute(
          "href", "https://www.wikidata.org/w/index.php?search=\(word.title)&ns146=1")
        try await expect(entries).toHaveCount(5)
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      await remove()
      throw error
    }
    await remove()
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWorksCatalogs(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let query = work.title.replacingOccurrences(of: " ", with: "%20")
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(work.path)
        let elsewhere = try await open(page)
        let search = elsewhere.locator(".elsewhere-view-entry[data-kind='search'] a")
        let texts = try await page.evaluate(
          "[...document.querySelectorAll(\"#record-elsewhere .elsewhere-view-entry[data-kind='search'] a\")].map(\(Self.ownText))",
          as: [String].self)
        for (name, href) in [
          ("British Library", "https://catalogue.bl.uk/nde/search?query=\(query)&vid=44BL_MAIN:BLL01_NDE"),
          ("Library of Congress", "https://www.loc.gov/books/?q=\(query)"),
          ("WorldCat", "https://search.worldcat.org/search?q=\(query)"),
          ("Internet Archive", "https://archive.org/search?query=\(query)"),
        ] {
          let index = try #require(texts.firstIndex(of: "Search \(name) for \(work.title)"))
          try await expect(search.nth(index)).toHaveAttribute("href", href)
        }
        // Every search is worded as one; nothing unverified is named bare.
        for text in texts {
          #expect(text.hasPrefix("Search ") && text.hasSuffix(" for \(work.title)"))
        }
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      work.remove()
      await admin.remove()
      throw error
    }
    work.remove()
    await admin.remove()
  }

  /// A link's own words, without the external arrow LinkView adds.
  static let ownText =
    "(el) => [...el.childNodes].filter((n) => n.nodeType === 3).map((n) => n.textContent).join('')"

  private func linkText(_ link: Locator) async throws -> String {
    try await link.evaluate(Self.ownText).string ?? ""
  }

  /// The accordion, after the References and closed as they are, opened.
  private func open(_ page: Page) async throws -> Locator {
    let accordion = page.locator("#record-elsewhere")
    try await expect(accordion).not.toHaveAttribute("open")
    try await expect(page.locator("#references + #elsewhere, #references ~ #elsewhere")).toHaveCount(1)
    try await expect(accordion.locator(".accordion-summary")).toContainText("Elsewhere")
    try await expect(accordion.locator(".elsewhere-view-entry").nth(0)).toBeHidden()
    try await page.locator("#record-elsewhere > .accordion-summary").click()
    try await expect(accordion).toHaveAttribute("data-open-finished", "true")
    try await expect(accordion.locator(".elsewhere-view-entry").nth(0)).toBeVisible()
    // Framed gray as the References are.
    let references = try await page.locator("#record-references").evaluate(
      "(el) => getComputedStyle(el).backgroundColor"
    ).string
    let own = try await accordion.evaluate("(el) => getComputedStyle(el).backgroundColor").string
    #expect(own == references)
    return accordion
  }
}
