import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The site's search offers a record as every record field does, in two rows:
/// its language › its title or lemma, a breadcrumb with BreadcrumbView's own
/// chevron, the name in link blue; then its progenitors and its category or
/// part of speech, "—" each when unknown, and no language. The navbar's
/// search menu on both tabs. Each record is found the way a reader would: the
/// first its index lists.
///
/// The records pages' sidebar search offers nothing under its bar: it filters
/// the page's table as it is typed.
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

      }
    }
  }

  /// The sidebar's search on the records pages, the whole list and a
  /// prefix's (the first record's language): no menu under the bar; typing
  /// swaps the table, its count and the address (the page's own path, what
  /// is typed, the field); an empty box is the whole list again. On a phone
  /// the sidebar is the slide menu's copy.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func sidebarSearchFiltersTheTable(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      for (index, parameter, field, noun) in [
        ("/biblio-records", "q", "title", "biblio-records"),
        ("/lexico-records", "lemma", "lemma", "lexico-records"),
      ] {
        let name = try await Self.firstName(page, in: index)
        let href = try await page.locator("a[href^='\(index)/']").first.getAttribute("href") ?? ""
        let language = "/" + href.split(separator: "/").prefix(2).joined(separator: "/")
        for list in [index, language] {
          try await page.openHydrated(list)
          let count = page.locator(".records-count-view")
          let whole = try await count.textContent().trimmingCharacters(in: .whitespacesAndNewlines)
          if layout == .phone {
            try await page.locator(".sidebar-menu-btn").click()
          }
          let form = page.locator("[data-records-search='true']").filter(visible: true).first
          let input = form.locator(".search-bar-input")
          try await expect(input).toBeVisible()
          try await expect(form.locator(".search-bar-dropdown")).toHaveCount(0)

          // Nothing matches: the empty table, counted.
          try await input.fill("zzqxj")
          try await expect(count).toHaveText("0 \(noun)")
          try await expect(page.locator(".records-results-view tbody a[href^='\(index)/']")).toHaveCount(0)
          try await Self.expectAddress(page, list, [parameter: "zzqxj", "field": field])
          try await expect(page.locator(".search-bar-suggestion-item")).toHaveCount(0)

          // The first record's name: its rows, every one of that name.
          try await input.fill(name)
          try await Self.expectAddress(page, list, [parameter: name, "field": field])
          let rows = page.locator(".records-results-view tbody a[href^='\(index)/']")
          try await expect(rows.first).toBeVisible()
          let named = try await page.evaluate(
            """
            [...document.querySelectorAll(".records-results-view tbody a[href^='\(index)/']")]
              .every((a) => a.textContent.trim().toLowerCase().includes(\(Self.quoted(name.lowercased()))))
            """)
          #expect(named.bool == true, "\(list): a row does not hold \(name)")
          try await expect(page.locator(".search-bar-suggestion-item")).toHaveCount(0)

          // Cleared: the whole list, at its own address.
          try await input.fill("")
          try await expect(count).toHaveText(whole)
          try await expect(page).toHaveURL(list)
          try await page.expectNoHorizontalOverflow()
          try await page.expectNoErrors()
        }
      }
    }
  }

  /// The address the search left: the list's own path, and exactly
  /// `query` (in any order).
  private static func expectAddress(_ page: Page, _ path: String, _ query: [String: String]) async throws {
    try await expect(page).toHaveURL("\(path)?\(query)") { url in
      let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
      var found: [String: String] = [:]
      for item in parts?.queryItems ?? [] { found[item.name] = item.value ?? "" }
      return parts?.percentEncodedPath.removingPercentEncoding == path && found == query
    }
  }

  private static func quoted(_ text: String) -> String {
    String(data: (try? JSONEncoder().encode(text)) ?? Data(), encoding: .utf8) ?? "\"\""
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
