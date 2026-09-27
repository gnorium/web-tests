import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The site's search offers a record as every record field does, in two rows:
/// its language › its title, a breadcrumb with BreadcrumbView's own
/// chevron, the name in the link's color; then a work's voices and its type,
/// "—" each when unknown (a word, its type alone), and no language. The navbar's
/// search menu on both tabs. A row is a link, never a dropdown option: a
/// link's hover under the pointer, nothing left when it goes; the arrow
/// keys make it the active row (aria-selected, the input's
/// aria-activedescendant) in LinkView's keyboard focus ring, never filled;
/// Enter follows it, Esc closes the menu.
///
/// The records pages' sidebar search offers nothing under its bar: it filters
/// the page's table as it is typed.
///
/// Every test searches for its own scratch work and word (a throwaway admin
/// owns them, made by SQL and removed after), by names no other row has, so
/// other suites' scratch rows, made and removed meanwhile, change nothing
/// it asserts.
@Suite("Search menu")
struct SearchMenuTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func recordsAreOfferedUnderTheirLanguage(engine: BrowserEngine, layout: Layout) async throws {
    try await Self.withScratch { work, word in
      try await Self.recordsAreOffered(engine: engine, layout: layout, work: work, word: word)
    }
  }

  private static func recordsAreOffered(engine: BrowserEngine, layout: Layout, work: ScratchWork, word: ScratchWord)
    async throws
  {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      for (tab, index, endpoint, field, name) in [
        ("biblio-records", "/biblio-records", "/biblio-records/search", "q", work.title),
        ("lexico-records", "/lexico-records", "/lexico-records/search", "title", word.title),
      ] {
        try await page.goto(index)
        let expected = try await Self.answer(page, endpoint: endpoint, field: field, name: name)

        try await page.openHydrated(index)
        try await page.locator("[data-search-trigger='true']").first.click()
        try await page.locator(".search-menu-tabs [data-tab-name='\(tab)']").click()
        try await page.locator(".search-menu-typeahead input").fill(name)
        let rows = page.locator(".search-menu-typeahead .search-menu-result")
        try await expect(rows.first).toBeVisible()
        try await Self.expectOffered(
          rows.first, label: ".search-menu-result-label", detail: ".search-menu-result-detail", expected)
        let row = rows.first
        let title = row.locator(".breadcrumb-label-text")
        let input = page.locator(".search-menu-typeahead input")
        // The title in the link's color, as LinkView's.
        try await Self.expectColor(title, "--color-link", "the title is not in the link's color")
        // The chevron is the page breadcrumb's, in its color.
        let chevron = try await row.locator(".breadcrumb-separator-view").evaluate(
          """
          (el) => {
            const trail = document.querySelector('.breadcrumb-view .breadcrumb-separator-view');
            return trail ? getComputedStyle(el).color === getComputedStyle(trail).color : true;
          }
          """)
        #expect(chevron.bool == true, "the chevron is not the breadcrumb's color")
        // Hovered: a link's hover, no fill, not the active row; the pointer
        // gone, nothing stays.
        try await row.hover()
        try await Self.expectColor(title, "--color-link-hover", "the hovered title is not the link's hover color")
        try await Self.expectUnfilled(row)
        try await expect(row).not.toHaveAttribute("aria-selected", "true")
        try await input.hover()
        try await Self.expectColor(title, "--color-link", "the title kept its hover color after the pointer left")
        try await Self.expectUnfilled(row)
        // Reached with the arrow keys: the active row, named by the input,
        // in LinkView's keyboard focus ring, still unfilled; it stays so
        // after the pointer crosses it and leaves.
        try await input.press("ArrowDown")
        try await expect(row).toHaveAttribute("aria-selected", "true")
        let rowID = try await row.getAttribute("id") ?? ""
        #expect(!rowID.isEmpty, "the active row has no id")
        try await expect(input).toHaveAttribute("aria-activedescendant", rowID)
        try await Self.expectFocusRing(row)
        try await Self.expectUnfilled(row)
        try await row.hover()
        try await input.hover()
        try await expect(row).toHaveAttribute("aria-selected", "true")
        try await Self.expectFocusRing(row)
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
        // Enter follows the active row.
        try await input.press("Enter")
        try await expect(page, timeout: .seconds(10)).toHaveURL(expected.path) { $0.path == expected.path }
        // Esc closes the menu.
        try await page.openHydrated(index)
        try await page.locator("[data-search-trigger='true']").first.click()
        try await expect(page.locator(".search-menu-view")).toHaveAttribute("data-state", "open")
        try await page.keyboard.press("Escape")
        try await expect(page.locator(".search-menu-view")).toHaveAttribute("data-state", "closed")
      }
    }
  }

  /// The sidebar's search on the records pages, the whole list and a
  /// prefix's (the scratch rows' language, English): no menu under the bar;
  /// typing swaps the table, its count and the address (the page's own path,
  /// what is typed, the field); an empty box is the whole list again. On a
  /// phone the sidebar is the slide menu's copy.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func sidebarSearchFiltersTheTable(engine: BrowserEngine, layout: Layout) async throws {
    try await Self.withScratch { work, word in
      try await Self.sidebarSearch(engine: engine, layout: layout, work: work, word: word)
    }
  }

  private static func sidebarSearch(engine: BrowserEngine, layout: Layout, work: ScratchWork, word: ScratchWord)
    async throws
  {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      for (index, parameter, field, noun, name, path) in [
        ("/biblio-records", "q", "title", "biblio-records", work.title, work.path),
        ("/lexico-records", "title", "title", "lexico-records", word.title, word.path),
      ] {
        for list in [index, "\(index)/eng"] {
          try await page.openHydrated(list)
          let count = page.locator(".records-count-view")
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

          // The scratch row's name, no other row's: that row alone.
          try await input.fill(name)
          try await Self.expectAddress(page, list, [parameter: name, "field": field])
          try await expect(count).toHaveText("1 \(noun.dropLast())")
          let rows = page.locator(".records-results-view tbody a[href^='\(index)/']")
          try await expect(rows).toHaveCount(1)
          try await expect(rows.first).toHaveText(name)
          // The page writes "—" as it is; the scratch path is percent-encoded.
          try await expect(rows.first).toHaveAttribute("href", path.removingPercentEncoding ?? path)
          try await expect(page.locator(".search-bar-suggestion-item")).toHaveCount(0)

          // Cleared: the whole list, at its own address.
          try await Self.expectClearedToTheWholeList(page, input, list) {
            try await input.fill(name)
            try await Self.expectAddress(page, list, [parameter: name, "field": field])
          }
          try await page.expectNoHorizontalOverflow()
          try await page.expectNoErrors()
        }
      }
    }
  }

  /// A sort after a live search keeps the search. The lexico list sorts on
  /// the server: its header goes to the page's own path with what is typed,
  /// the field, the sort and page one, and the list stays filtered; a second
  /// click turns it descending. The biblio list sorts in the browser: the
  /// address and the filtered rows stay as they are.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func sortingKeepsTheLiveSearch(engine: BrowserEngine, layout: Layout) async throws {
    try await Self.withScratch { work, word in
      try await Self.sorting(engine: engine, layout: layout, work: work, word: word)
    }
  }

  private static func sorting(engine: BrowserEngine, layout: Layout, work: ScratchWork, word: ScratchWord)
    async throws
  {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      for (index, parameter, field, column, serverSorted, name) in [
        ("/lexico-records", "title", "title", "title", true, word.title),
        ("/biblio-records", "q", "title", "title", false, work.title),
      ] {
        try await page.openHydrated(index)
        if layout == .phone {
          try await page.locator(".sidebar-menu-btn").click()
        }
        let form = page.locator("[data-records-search='true']").filter(visible: true).first
        let input = form.locator(".search-bar-input")
        try await input.fill(name)
        let searched = [parameter: name, "field": field]
        try await Self.expectAddress(page, index, searched)
        let count = page.locator(".records-count-view")
        let filtered = index == "/lexico-records" ? "1 lexico-record" : "1 biblio-record"
        try await expect(count).toHaveText(filtered)
        if layout == .phone {
          try await page.locator(".navbar-slide-close-btn").click()
        }
        // No voice or etymon column: the sidebar's fields find records by them.
        try await expect(
          page.locator(
            ".records-results-view [data-table-column-id='author'], .records-results-view [data-table-column-id='etymon']"
          )
        ).toHaveCount(0)

        let header = page.locator(".records-results-view .table-sort-button[data-column-id='\(column)']")
        try await header.click()
        if serverSorted {
          try await Self.expectAddress(
            page, index, searched.merging(["sort": column, "order": "asc", "page": "1"]) { $1 })
          try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
          try await page.locator(".records-results-view .table-sort-button[data-column-id='\(column)']").click()
          try await Self.expectAddress(
            page, index, searched.merging(["sort": column, "order": "desc", "page": "1"]) { $1 })
          try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
          // The reloaded sidebar still holds the search.
          if layout == .phone {
            try await page.locator(".sidebar-menu-btn").click()
          }
          try await expect(
            page.locator("[data-records-search='true']").filter(visible: true).first.locator(".search-bar-input")
          ).toHaveValue(name)
        } else {
          try await Self.expectAddress(page, index, searched)
        }
        try await expect(count).toHaveText(filtered)
        let named = try await page.evaluate(
          """
          [...document.querySelectorAll(".records-results-view tbody a[href^='\(index)/']")]
            .every((a) => a.textContent.trim().toLowerCase().includes(\(Self.quoted(name.lowercased()))))
          """)
        #expect(named.bool == true, "\(index): sorting dropped the search for \(name)")
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
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

  /// A JavaScript function that checks `check` until it holds, for up to
  /// two seconds: the rows ease between states.
  private static let settled = """
    (async (check) => {
      for (let i = 0; i < 40; i++) {
        if (check()) return true;
        await new Promise((r) => setTimeout(r, 50));
      }
      return check();
    })
    """

  /// `locator`'s text color is the color token `token` (a custom property).
  private static func expectColor(_ locator: Locator, _ token: String, _ message: String) async throws {
    let same = try await locator.evaluate(
      """
      async (el) => {
        const probe = document.createElement('span');
        probe.style.color = 'var(\(token))';
        document.body.appendChild(probe);
        const want = getComputedStyle(probe).color;
        probe.remove();
        return \(settled)(() => getComputedStyle(el).color === want);
      }
      """)
    #expect(same.bool == true, "\(message)")
  }

  /// A search menu row is a link, never a dropdown option: no fill, and
  /// every part of it in its own color, none inverted.
  private static func expectUnfilled(_ row: Locator) async throws {
    let unfilled = try await row.evaluate(
      """
      async (el) => {
        const probe = document.createElement('span');
        probe.style.color = 'var(--color-inverted-fixed)';
        document.body.appendChild(probe);
        const inverted = getComputedStyle(probe).color;
        probe.remove();
        const parts = [...el.querySelectorAll('.breadcrumb-label-context, .breadcrumb-label-text, .search-menu-result-detail')];
        return \(settled)(() => {
          const bg = getComputedStyle(el).backgroundColor;
          return (bg === 'rgba(0, 0, 0, 0)' || bg === 'transparent') && parts.length === 3
            && parts.every((p) => getComputedStyle(p).color !== inverted);
        });
      }
      """)
    #expect(unfilled.bool == true, "the row is filled or its text inverted, as a dropdown option")
  }

  /// LinkView's keyboard focus ring: a thick solid outline in the blue
  /// border token, 2px inside.
  private static func expectFocusRing(_ row: Locator) async throws {
    let ring = try await row.evaluate(
      """
      async (el) => {
        const probe = document.createElement('span');
        probe.style.outline = 'var(--border-width-thick) solid var(--border-color-blue)';
        document.body.appendChild(probe);
        const want = getComputedStyle(probe);
        const color = want.outlineColor, width = want.outlineWidth;
        probe.remove();
        return \(settled)(() => {
          const s = getComputedStyle(el);
          return s.outlineStyle === 'solid' && s.outlineColor === color && s.outlineWidth === width
            && s.outlineOffset === '-2px';
        });
      }
      """)
    #expect(ring.bool == true, "the active row does not wear LinkView's focus ring")
  }

  /// What the search answers first for `name`: its language, its
  /// voices, its type and its path, as the JSON gives them.
  private struct Answer {
    let name: String
    let language: String
    let voices: String
    let type: String
    let path: String
  }

  private static func expectOffered(_ row: Locator, label: String, detail: String, _ expected: Answer)
    async throws
  {
    let crumb = row.locator("\(label) .breadcrumb-label-view")
    try await expect(crumb.locator(".breadcrumb-label-context")).toHaveText(expected.language)
    try await expect(crumb.locator(".breadcrumb-separator-view .next-icon-view")).toHaveCount(1)
    try await expect(crumb.locator(".breadcrumb-label-text")).toHaveText(expected.name)
    // A word has no voices part: its row reads its type alone.
    try await expect(row.locator(detail))
      .toHaveText(expected.voices.isEmpty ? expected.type : "\(expected.voices) · \(expected.type)")
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

  /// A throwaway admin's scratch work and word for `body`, removed after
  /// whatever it does. Skipped where no admin can be made.
  private static func withScratch(_ body: (ScratchWork, ScratchWord) async throws -> Void) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work: ScratchWork
    let word: ScratchWord
    do {
      work = try ScratchWork(owner: admin)
      do {
        word = try ScratchWord(owner: admin)
      } catch {
        work.remove()
        throw error
      }
    } catch {
      await admin.remove()
      throw error
    }
    do {
      try await body(work, word)
    } catch {
      word.remove()
      work.remove()
      await admin.remove()
      throw error
    }
    word.remove()
    work.remove()
    await admin.remove()
  }

  /// Cleared, the box shows the whole list at the list's own address: its
  /// count is the whole list's as the server counted it just before or just
  /// after the page asked. Other suites add and remove scratch rows
  /// meanwhile, so a count that moved under the page is tried again, from
  /// the search `retype` puts back.
  private static func expectClearedToTheWholeList(
    _ page: Page, _ input: Locator, _ list: String, retype: () async throws -> Void
  ) async throws {
    var tried: [String] = []
    for attempt in 1...3 {
      let before = try await wholeCount(page, list)
      try await input.fill("")
      // The address changes after the table is swapped: the count is final.
      try await expect(page).toHaveURL(list)
      let shown = try await page.locator(".records-count-view").textContent()
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let after = try await wholeCount(page, list)
      if shown == before || shown == after { return }
      tried.append("\"\(shown)\" (the whole list \"\(before)\", then \"\(after)\")")
      if attempt < 3 { try await retype() }
    }
    Issue.record("\(list): cleared, the count read \(tried.joined(separator: "; "))")
  }

  /// The whole list's count as the server gives it now.
  private static func wholeCount(_ page: Page, _ list: String) async throws -> String {
    try await page.evaluate(
      """
      fetch('\(list)?fragment=results', { headers: { Accept: 'text/html' } })
        .then((r) => r.text())
        .then((html) => new DOMParser().parseFromString(html, 'text/html')
          .querySelector('.records-count-view')?.textContent.trim() ?? '')
      """
    ).string ?? ""
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
      name: name, language: language, voices: found["qualifier"].string ?? "",
      type: found["type"].string ?? "—", path: found["url"].string ?? "")
  }
}
