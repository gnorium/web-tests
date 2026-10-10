import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Every object figure on the Watchtower opens a list exactly as long as the
/// figure, on both rows (bibliographic and lexicographic), and the list it opens is
/// filtered as the link asks from the first render: its filter bar names the
/// linked object and status, never a placeholder, and its rows are the ones
/// the filter keeps.
@Suite("Watchtower figure links")
struct WatchtowerFigureLinksTests {
  /// Every figure: an object's, opening a lifecycle list or the palinodes
  /// register, and a process's, opening the runs it counts.
  static let figureLinks = ".watchtower-object-figures-view a[href], .watchtower-process-figures a[href]"

  struct Figure: Decodable {
    let text: String
    let href: String
  }

  static func figures(_ page: Page) async throws -> [Figure] {
    try await page.evaluate(
      """
      [...document.querySelectorAll(\(jsString(figureLinks)))]
        .map(a => ({ text: a.textContent.trim(), href: a.getAttribute('href') }))
        .filter(f => /^\\d+ /.test(f.text))
      """, as: [Figure].self)
  }

  static func jsString(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: "\\'") + "'"
  }

  /// The rows a list page shows, read from its HTML as the server sent it;
  /// -1, never a length, when the server could not answer.
  static func listed(_ page: Page, _ href: String) async throws -> Int {
    try await page.evaluate(
      """
      fetch(\(jsString(href))).then(r => r.ok ? r.text() : null).then(html => {
        if (html === null) return -1
        const doc = new DOMParser().parseFromString(html, 'text/html')
        const table = doc.querySelector('[data-total-items]')
        if (table) return Number(table.getAttribute('data-total-items'))
        return doc.querySelectorAll('tbody tr[data-row-id]').length
      })
      """, as: Int.self)
  }

  /// The figure the Watchtower shows for `href`, as the server renders it
  /// now (the page's own figures follow a live stream whose figures are
  /// held for a tick).
  static func figure(_ page: Page, _ href: String) async throws -> Int? {
    try await page.evaluate(
      """
      fetch('/').then(r => r.ok ? r.text() : '').then(html => {
        const doc = new DOMParser().parseFromString(html, 'text/html')
        const link = [...doc.querySelectorAll(\(jsString(figureLinks)))]
          .find(a => a.getAttribute('href') === \(jsString(href)))
        const count = link && /^\\d+/.exec(link.textContent.trim())
        return count ? Number(count[0]) : null
      })
      """, as: Int?.self)
  }

  /// A figure and the length of its list, read again until they agree:
  /// other suites create and commit objects while this one reads, so a
  /// figure read a moment before its list can be behind it. Each retry
  /// reads the figure between two reads of its list, and they agree when
  /// the figure is the list's length at either: the list stood at that
  /// length while the figure was counted. A real disagreement outlasts the
  /// two minutes (the full parallel run writes for minutes on end) and is
  /// returned as read last.
  static func agreeing(
    _ page: Page, _ href: String, figure count: Int, listed: () async throws -> Int
  ) async throws -> (figure: Int, listed: Int) {
    var figure = count
    var last = try await listed()
    let deadline = ContinuousClock.now + .seconds(120)
    while figure != last, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(500))
      let before = try await listed()
      // A Watchtower that could not be drawn (a busy server) names no
      // figure: asked again, never compared as it last stood.
      guard let fresh = try await Self.figure(page, href) else { continue }
      guard before >= 0 else { continue }
      figure = fresh
      last = try await listed()
      if figure == before { return (figure, before) }
    }
    return (figure, last)
  }

  /// Arbitration's badge, outside the numbered sequence, wears the
  /// therefore sign as an icon centered in its disc (a text glyph's ink
  /// sits on the baseline, below the center): the icon's box and the
  /// badge's share a center, within a pixel, at both layouts.
  @Test(arguments: enginesAndLayouts)
  func theArbitrationBadgeCentersItsIcon(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/")
      let badges = page.locator(".watchtower-process-number:has(.therefore-icon-view)")
      try await expect(badges).toHaveCount(3)
      let offsets = try await page.evaluate(
        """
        [...document.querySelectorAll('.watchtower-process-number')]
          .filter(b => b.querySelector('.therefore-icon-view'))
          .map(b => {
            const badge = b.getBoundingClientRect()
            const icon = b.querySelector('.therefore-icon-view').getBoundingClientRect()
            return [Math.abs((badge.left + badge.width / 2) - (icon.left + icon.width / 2)),
                    Math.abs((badge.top + badge.height / 2) - (icon.top + icon.height / 2))]
          })
        """, as: [[Double]].self)
      for offset in offsets {
        #expect(offset[0] <= 1 && offset[1] <= 1, "the icon's center is off the badge's by \(offset)")
      }
    }
  }

  /// On every process card—the Disputorium's, the Computorium's and the
  /// nested Locution card's—the bibliographic and the lexicographic figure
  /// groups stand side by side as two equal halves at every width (user,
  /// 2026-10-09): each group's heading shares a row with the other's, and
  /// the second column starts at the midpoint, half the gap past it.
  @Test(arguments: enginesAndLayouts)
  func theTwoSidesStandSideBySide(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/")
      // Five chain objects, the entry, two palinodes and three nested cards.
      let views = page.locator(".watchtower-object-figures-view")
      try await expect(views).toHaveCount(11)
      let rows = try await page.evaluate(
        """
        [...document.querySelectorAll('.watchtower-object-figures-view')].map(view => {
          const box = view.getBoundingClientRect()
          const gap = parseFloat(getComputedStyle(view).columnGap) || 0
          const tabs = [...view.querySelectorAll('.watchtower-object-figures-tab')]
            .map(tab => tab.getBoundingClientRect())
          return [tabs.length, Math.round(tabs[0].top), Math.round(tabs[1].top),
            Math.round(tabs[1].left - (box.left + box.width / 2 + gap / 2))]
        })
        """, as: [[Int]].self)
      for row in rows {
        #expect(row[0] == 2 && row[1] == row[2], "the two sides share a row: \(row)")
        #expect(abs(row[3]) <= 1, "the second column starts at the midpoint, half the gap past it: \(row)")
      }
    }
  }

  @Test(arguments: gnorium.engines)
  func everyFigureIsTheLengthOfItsList(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated("/")
      let figures = try await Self.figures(page)
      try #require(figures.count >= 38, "the Watchtower shows \(figures.count) figure links")
      // Every process has three run links: explication's and translation's,
      // and arbitration's on each of the three Disputorium objects' nested
      // cards, whose locution figures add three on each of their two rows.
      // 6 + 9 + 18 = 33.
      let runLinks = figures.filter { $0.href.hasPrefix("/mission-control/runs/") }.count
      try #require(runLinks == 33, "the processes' and the nested Arbitration cards' run links: \(runLinks)")
      for figure in figures {
        let count = try #require(Int(figure.text.prefix { $0.isNumber }))
        // Explication's figures count both kinds' runs: the list they open
        // and the same list on the other kind's tab.
        let (shown, listed) = try await Self.agreeing(page, figure.href, figure: count) {
          let listed = try await Self.listed(page, figure.href)
          // Explication's and arbitration's process figures count both
          // kinds' runs; a locution figure, filtered to its object, one.
          guard listed >= 0,
            figure.href.contains("process=explication")
              || (figure.href.contains("process=arbitration") && !figure.href.contains("object="))
          else { return listed }
          let other = try await Self.listed(
            page,
            figure.href.replacingOccurrences(of: "/lifecycles/bibliographic", with: "/lifecycles/lexicographic")
              .replacingOccurrences(of: "/runs/bibliographic", with: "/runs/lexicographic"))
          return other < 0 ? -1 : listed + other
        }
        #expect(listed == shown, "\(figure.text) (now \(shown)) opens \(listed) rows: \(figure.href)")
      }
    }
  }

  /// The case that was broken: the sentiments' committed overtures.
  static let committedSentimentOvertures =
    "/mission-control/lifecycles/lexicographic?object=overture&status=committed&createdOn=-7d.."
  /// The testaments' pending overtures, whose list must be filtered on the
  /// first render, not only after Apply.
  static let pendingTestamentOvertures = "/mission-control/lifecycles/bibliographic?object=overture&status=pending"

  /// A process's figure opens the Runs page: its filter bar names the process
  /// and the status, with no placeholder, and it lists as many runs as the
  /// figure.
  @Test(arguments: enginesAndLayouts)
  func aProcessFigureOpensItsRuns(engine: BrowserEngine, layout: Layout) async throws {
    let href = "/mission-control/runs/bibliographic?process=explication&status=failed&createdOn=-7d.."
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/")
      let link = page.locator(".watchtower-process-figures a[href='\(href)']").first
      let phrase = try await link.textContent()
      let count = try #require(Int(phrase.prefix { $0.isNumber }), "\(href) reads \(phrase)")
      try await link.click()
      try await expect(page, timeout: .seconds(15)).toHaveURL(href)
      try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
      let fields = try await page.locator(".filter-bar-field-picker .dropdown-selected-text").allTextContents()
      #expect(fields.contains("Process") && fields.contains("Status") && !fields.contains("Show"), "fields: \(fields)")
      let values = try await page.locator(".filter-bar-value-select .dropdown-selected-text").allTextContents()
      #expect(values.contains("Explication") && values.contains("Failed"), "values: \(values)")
      let placeholders = try await page.evaluate(
        """
        [...document.querySelectorAll('.filter-bar-value-select .dropdown-selected-text')]
          .filter(e => e.getAttribute('data-selected') !== 'true').length
        """, as: Int.self)
      #expect(placeholders == 0, "\(placeholders) filter rows show a placeholder")
      // A run its worker lost is failed, not a status of its own.
      let stalled = try await page.evaluate("document.body.innerHTML.includes('Stalled')", as: Bool.self)
      #expect(!stalled, "the runs list offers a Stalled status")
      // The figure counts both kinds' explication runs: this list, and the
      // same list on the Lexicographic tab, which keeps the filters.
      let lexicographic = href.replacingOccurrences(of: "/runs/bibliographic", with: "/runs/lexicographic")
      try await expect(page.locator("a[href='\(lexicographic)']").first).toBeAttached()
      let bibliographic = count - (try await Self.listed(page, lexicographic))
      if bibliographic == 0 {
        try await expect(page.locator(".mission-control-core-empty")).toBeVisible()
      } else {
        try await expect(page.locator(".bibliographic-runs-table")).toHaveAttribute("data-total-items", "\(bibliographic)")
      }
    }
  }

  @Test(arguments: enginesAndLayouts)
  func aFigureOpensItsFilteredList(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      for (href, object, status, tab) in [
        (Self.committedSentimentOvertures, "Overture", "Committed", "lexicographic"),
        (Self.pendingTestamentOvertures, "Overture", "Pending", "bibliographic"),
      ] {
        try await page.openHydrated("/")
        let link = page.locator(".watchtower-object-figures-view a[href='\(href)']").first
        let phrase = try await link.textContent()
        let shown = try #require(Int(phrase.prefix { $0.isNumber }), "\(href) reads \(phrase)")
        try await link.click()
        try await expect(page, timeout: .seconds(15)).toHaveURL(href)
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")

        // The filter bar names what the link asked for, and no row stands
        // on a placeholder.
        let values = try await page.locator(".filter-bar-value-select .dropdown-selected-text").allTextContents()
        #expect(values.contains(object), "\(href): the filter values are \(values)")
        #expect(values.contains(status), "\(href): the filter values are \(values)")
        let placeholders = try await page.evaluate(
          """
          [...document.querySelectorAll('.filter-bar-value-select .dropdown-selected-text')]
            .filter(e => e.getAttribute('data-selected') !== 'true').length
          """, as: Int.self)
        #expect(placeholders == 0, "\(href): \(placeholders) filter rows show a placeholder")

        // The figure is the length of the list it opens (read again until
        // they agree, see `agreeing`). The rows, after hydration, are the
        // filtered ones, each a lifecycle holding the object in that status.
        let (count, listed) = try await Self.agreeing(page, href, figure: shown) {
          try await Self.listed(page, href)
        }
        #expect(listed == count, "\(href): the list holds \(listed) for the figure's \(count)")
        let table = page.locator(".\(tab)-lifecycles-table")
        let total = try await page.evaluate(
          """
          (() => {
            const table = document.querySelector('.\(tab)-lifecycles-table')
            return table ? Number(table.getAttribute('data-total-items')) : 0
          })()
          """, as: Int.self)
        if total == 0 {
          try await expect(page.locator(".mission-control-core-empty")).toBeVisible()
        } else {
          let headers = try await page.evaluate(
            """
            [...document.querySelectorAll('.\(tab)-lifecycles-table tbody tr[data-row-id]')]
              .filter(r => !r.classList.contains('table-group-child')).length
            """, as: Int.self)
          #expect(headers == min(total, 25), "\(href): \(headers) lifecycles shown for \(total)")
          let unfiltered = try await page.evaluate(
            """
            [...document.querySelectorAll('.\(tab)-lifecycles-table tbody tr[data-row-id]')]
              .filter(r => !r.classList.contains('table-group-child'))
              .filter(r => {
                const group = r.getAttribute('data-group-id')
                const rows = [...document.querySelectorAll(`.\(tab)-lifecycles-table tbody tr[data-group-id="${group}"]`)]
                return !rows.some(row => {
                  const cells = [...row.querySelectorAll('td, th')].map(c => c.textContent.trim())
                  return cells.includes('\(object)') && cells.includes('\(status)')
                })
              }).length
            """, as: Int.self)
          #expect(unfiltered == 0, "\(href): \(unfiltered) lifecycles hold no \(object) \(status)")
        }
      }
    }
  }
}
