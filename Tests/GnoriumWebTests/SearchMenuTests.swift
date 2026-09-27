import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The site's search offers a record as every record field does, in two rows:
/// its language › its title or lemma, a breadcrumb with BreadcrumbView's own
/// chevron, the name in link blue; then its progenitors and its category or
/// part of speech, "—" each when unknown, and no language. The navbar's
/// search menu on both tabs, and (on a desktop, where the sidebar shows) the
/// lexico-records sidebar's search bar. Each record is found the way a reader
/// would: the first its index lists.
@Suite("Search menu")
struct SearchMenuTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func recordsAreOfferedUnderTheirLanguage(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      for (tab, index, endpoint, field) in [
        ("biblio-records", "/biblio-records", "/biblio-records/search", "q"),
        ("lexico-records", "/lexico-records", "/lexico-records/search", "lemma"),
      ] {
        let name = try await Self.firstName(page, in: index)
        let expected = try await Self.answer(page, endpoint: endpoint, field: field, name: name)

        try await page.openHydrated(index)
        try await page.locator("[data-search-trigger='true']").first.click()
        try await page.locator(".search-menu-tabs [data-tab-name='\(tab)']").click()
        try await page.locator(".search-menu-typeahead input").fill(name)
        let rows = page.locator(".search-menu-typeahead .search-menu-result")
        try await expect(rows.first).toBeVisible()
        try await Self.expectOffered(
          rows.first, label: ".search-menu-result-label", detail: ".search-menu-result-detail", expected)
        let blue = try await rows.first.locator(".breadcrumb-label-text").evaluate(
          "(el) => getComputedStyle(el).color === getComputedStyle(el.closest('.search-menu-result-label')).color")
        #expect(blue.bool == true, "the name lost the row's link colour")
        // The chevron is the page breadcrumb's, in its colour.
        let chevron = try await rows.first.locator(".breadcrumb-separator-view").evaluate(
          """
          (el) => {
            const trail = document.querySelector('.breadcrumb-view .breadcrumb-separator-view');
            return trail ? getComputedStyle(el).color === getComputedStyle(trail).color : true;
          }
          """)
        #expect(chevron.bool == true, "the chevron is not the breadcrumb's colour")
        // Reached with the arrow keys: solid blue, every part inverted.
        try await page.locator(".search-menu-typeahead input").press("ArrowDown")
        try await expect(rows.first).toHaveAttribute("aria-selected", "true")
        let lit = try await rows.first.evaluate(Self.solidBlue)
        #expect(lit.bool == true, "the highlighted row is not solid blue with inverted text")
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()

        // The sidebar's search bar, where it shows: the same two rows.
        if layout == .desktop && tab == "lexico-records" {
          try await page.openHydrated(index)
          let bar = page.locator(".search-bar-view.in-sidebar").filter(visible: true).first
          try await bar.locator("input").fill(name)
          let suggestion = bar.locator(".search-bar-suggestion-item").first
          try await expect(suggestion).toBeVisible()
          try await Self.expectOffered(
            suggestion, label: ".search-bar-suggestion-text", detail: ".search-bar-suggestion-detail", expected)
          // It leads to the record's own page.
          let href = try await suggestion.locator("a").getAttribute("href") ?? ""
          #expect(href == expected.path, "\(href)")
          // Reached with the arrow keys: solid blue, every part inverted.
          try await bar.locator("input").press("ArrowDown")
          let link = suggestion.locator("a.active")
          try await expect(link).toHaveCount(1)
          let lit = try await link.evaluate(Self.solidBlue)
          #expect(lit.bool == true, "the highlighted suggestion is not solid blue with inverted text")
        }
      }
    }
  }

  /// Whether a row is drawn as DropdownView's highlighted option: the blue
  /// background token, and every part of it (name, language, chevron,
  /// second row) in the inverted text token.
  static let solidBlue = """
    (el) => {
      const probe = document.createElement('div');
      probe.style.background = 'var(--background-color-blue)';
      probe.style.color = 'var(--color-inverted-fixed)';
      document.body.appendChild(probe);
      const blue = getComputedStyle(probe).backgroundColor, white = getComputedStyle(probe).color;
      probe.remove();
      const parts = [...el.querySelectorAll('.breadcrumb-label-context, .breadcrumb-separator-view, .breadcrumb-label-text')];
      const second = el.querySelector('.search-menu-result-detail, .search-bar-suggestion-detail');
      return getComputedStyle(el).backgroundColor === blue && parts.length === 3
        && [...parts, second].every((p) => getComputedStyle(p).color === white);
    }
    """

  /// What the search answers first for `name`: its language, its
  /// progenitors, its category and its path, as the JSON gives them.
  private struct Answer {
    let name: String
    let language: String
    let progenitors: String
    let category: String
    let path: String
  }

  private static func expectOffered(_ row: Locator, label: String, detail: String, _ expected: Answer)
    async throws
  {
    let crumb = row.locator("\(label) .breadcrumb-label-view")
    try await expect(crumb.locator(".breadcrumb-label-context")).toHaveText(expected.language)
    try await expect(crumb.locator(".breadcrumb-separator-view .next-icon-view")).toHaveCount(1)
    try await expect(crumb.locator(".breadcrumb-label-text")).toHaveText(expected.name)
    try await expect(row.locator(detail)).toHaveText("\(expected.progenitors) · \(expected.category)")
    // The chevron on the language's line, after it.
    let line = try await crumb.evaluate(
      """
      (el) => {
        const box = (s) => el.querySelector(s).getBoundingClientRect();
        const context = box('.breadcrumb-label-context'), chevron = box('.breadcrumb-separator-view');
        return Math.abs((chevron.top + chevron.bottom) / 2 - (context.top + context.bottom) / 2) < 8
          && chevron.left >= context.right;
      }
      """)
    #expect(line.bool == true, "the chevron left the language's line")
  }

  /// The first record's title or lemma as its index lists it.
  private static func firstName(_ page: Page, in index: String) async throws -> String {
    try await page.goto(index)
    let link = page.locator("a[href^='\(index)/']").first
    let name = try await link.textContent().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { throw WebTestError("\(index) lists no record to search for.") }
    return name
  }

  private static func answer(_ page: Page, endpoint: String, field: String, name: String) async throws -> Answer {
    let quoted = String(data: try JSONEncoder().encode(name), encoding: .utf8) ?? "\"\""
    let found = try await page.evaluate(
      """
      fetch('\(endpoint)?\(field)=' + encodeURIComponent(\(quoted)))
        .then((r) => r.json())
        .then((j) => [...j.exact, ...j.partial].find((r) => r.text === \(quoted)) ?? null)
      """)
    guard let language = found["language"].string else {
      throw WebTestError("\(endpoint) finds no record named \(name).")
    }
    return Answer(
      name: name, language: language, progenitors: found["qualifier"].string ?? "—",
      category: found["category"].string ?? "—", path: found["url"].string ?? "")
  }
}
