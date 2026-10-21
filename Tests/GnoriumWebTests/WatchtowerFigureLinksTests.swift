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
  /// Every figure: an object's, opening its object's own list (user,
  /// 2026-10-10)—Fountains, Overtures, Quatrains, Halftones, Antiphons,
  /// Madrigals, Serenades, Epilogues, Palinodes—and a process's, opening the
  /// nocturnes it counts on its kind (arbitration's, the calls' locutions by
  /// their Status).
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

  /// On every card's figures and every process box—the Disputorium's, the
  /// Computorium's and the nested Locution card's—the bibliographic and the
  /// lexicographic figure columns stand side by side as two equal halves at
  /// every width (user, 2026-10-09; process boxes 2026-10-21): each
  /// column's heading shares a row with the other's, and the second column
  /// starts at the midpoint, half the gap past it.
  @Test(arguments: enginesAndLayouts)
  func theTwoSidesStandSideBySide(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/")
      // The entry, seven chain objects, four palinodes (one before each
      // Disputorium object) and three nested cards' figures; six process
      // boxes (calibration, explication, translation, three arbitrations).
      let views = page.locator(".watchtower-figure-columns-view")
      try await expect(views).toHaveCount(21)
      let rows = try await page.evaluate(
        """
        [...document.querySelectorAll('.watchtower-figure-columns-view')].map(view => {
          const box = view.getBoundingClientRect()
          const gap = parseFloat(getComputedStyle(view).columnGap) || 0
          const tabs = [...view.querySelectorAll('.watchtower-figure-columns-tab')]
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
      // Objects: four Disputorium objects of three figures, three machines
      // of four (pending first), the fountain and four palinodes of one, on
      // both sides: 58; processes and arbitrations below: 52 (no nullified).
      try #require(figures.count >= 104, "the Watchtower shows \(figures.count) figure links")
      // Calibration, explication and translation have three nocturne links
      // on each kind (18), and a pending link to their object's list, its
      // objects waiting for a worker (6).
      let processPending = figures.filter { figure in
        figure.text.hasSuffix(" pending") && figure.href.hasSuffix("?status=pending")
          && ["quatrains", "antiphons", "serenades"].contains { figure.href.hasPrefix("/mission-control/\($0)/") }
      }.count
      try #require(processPending == 12, "the machines' and their processes' pending links, 6 each: \(processPending)")
      let nocturneLinks = figures.filter { $0.href.hasPrefix("/mission-control/nocturnes/") }.count
      try #require(nocturneLinks == 18, "the processes' nocturne links: \(nocturneLinks)")
      // Arbitration's open the Locutions list (an arbitration session is no
      // nocturne): its calls by Status, gnorium's replies by Created by.
      // Each nested Locution card: its process box four a kind (pending,
      // running, passed, failed) and its call's figures four a kind
      // (pending, running, submitted, failed; neither nullified nor
      // hidden is a figure): 16 a card (user, 2026-10-21).
      let cards = try await page.evaluate(
        "[...document.querySelectorAll('.watchtower-object-name-link')].filter(e => e.textContent.trim() === 'Locution').length",
        as: Int.self)
      let arbitrationLinks = figures.filter {
        $0.href.hasPrefix("/mission-control/locutions/")
      }.count
      try #require(cards > 0 && arbitrationLinks == cards * 16, "the nested Arbitration cards' locution links: \(arbitrationLinks) on \(cards) cards")
      #expect(!figures.contains { $0.text.hasSuffix(" hidden") || $0.text.hasSuffix(" nullified") },
        "neither hidden nor nullified is a figure")
      // An object's figure opens its own list, never the lifetimes.
      let lifetimes = figures.filter { $0.href.contains("/lifetimes/") }.map(\.href)
      #expect(lifetimes.isEmpty, "object figures open the lifetimes: \(lifetimes)")
      for figure in figures {
        let count = try #require(Int(figure.text.prefix { $0.isNumber }))
        // Every figure counts its own kind's column alone, a process's
        // too: the list it opens.
        let (shown, listed) = try await Self.agreeing(page, figure.href, figure: count) {
          try await Self.listed(page, figure.href)
        }
        #expect(listed == shown, "\(figure.text) (now \(shown)) opens \(listed) rows: \(figure.href)")
      }
    }
  }

  /// The page stands on `href`. A link whose query counts the reader's days
  /// (`createdOn=-7d..`) is followed with the reader's zone (`&tz=`, added
  /// by the client when it is followed: nothing is stored), so the address
  /// is `href` plus that zone; one that counts none is `href` as it was.
  static func expectOpened(_ page: Page, _ href: String) async throws {
    let zone = try await page.evaluate("Intl.DateTimeFormat().resolvedOptions().timeZone", as: String.self)
    let zoned = href.contains("-7d..")
    try await expect(page, timeout: .seconds(15)).toHaveURL(zoned ? "\(href)&tz=\(zone)" : href) { url in
      let wanted = URLComponents(string: href)?.queryItems ?? []
      var items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      if zoned {
        guard items.contains(where: { $0.name == "tz" && $0.value == zone }) else { return false }
        items.removeAll { $0.name == "tz" }
      }
      return url.path == URLComponents(string: href)?.path && items == wanted
    }
  }

  /// The sentiments' overtures waiting on a Commit or Permit, counted in
  /// the testaments' words: pending.
  static let pendingSentimentOvertures = "/mission-control/overtures/lexicographic?status=pending"
  /// The testaments' pending overtures, whose list must be filtered on the
  /// first render, not only after Apply.
  static let pendingTestamentOvertures = "/mission-control/overtures/bibliographic?status=pending"
  /// The testaments' pending halftones, listed as overtures are.
  static let pendingTestamentHalftones = "/mission-control/halftones/bibliographic?status=pending"
  /// A machine's objects committed and waiting for a worker, not yet
  /// running (user, 2026-10-21): its object's figure and its process's
  /// open the same list.
  static let pendingTestamentQuatrains = "/mission-control/quatrains/bibliographic?status=pending"
  static let pendingSentimentAntiphons = "/mission-control/antiphons/lexicographic?status=pending"
  static let pendingTestamentSerenades = "/mission-control/serenades/bibliographic?status=pending"

  /// A process's figure opens the Nocturnes page: its filter bar names the
  /// process and the status, with no placeholder, and it lists as many
  /// nocturnes as the figure.
  @Test(arguments: enginesAndLayouts)
  func aProcessFigureOpensItsNocturnes(engine: BrowserEngine, layout: Layout) async throws {
    let href = "/mission-control/nocturnes/bibliographic?process=explication&status=failed&createdOn=-7d.."
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/")
      let link = page.locator(".watchtower-process-figures a[href='\(href)']").first
      let phrase = try await link.textContent()
      let count = try #require(Int(phrase.prefix { $0.isNumber }), "\(href) reads \(phrase)")
      try await link.click()
      try await Self.expectOpened(page, href)
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
      // A nocturne its worker lost is failed, not a status of its own.
      let stalled = try await page.evaluate("document.body.innerHTML.includes('Stalled')", as: Bool.self)
      #expect(!stalled, "the nocturnes list offers a Stalled status")
      // The figure is the bibliographic column's: this list alone.
      let bibliographic = count
      if bibliographic == 0 {
        try await expect(page.locator(".mission-control-core-empty")).toBeVisible()
      } else {
        try await expect(page.locator(".bibliographic-nocturnes-table")).toHaveAttribute("data-total-items", "\(bibliographic)")
      }
    }
  }

  @Test(arguments: enginesAndLayouts)
  func aFigureOpensItsFilteredList(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      for (href, status, tab, table) in [
        (Self.pendingSentimentOvertures, "Pending", "lexicographic", "overtures"),
        (Self.pendingTestamentOvertures, "Pending", "bibliographic", "overtures"),
        (Self.pendingTestamentHalftones, "Pending", "bibliographic", "halftones"),
        // A machine's objects committed and waiting for a worker.
        (Self.pendingTestamentQuatrains, "Pending", "bibliographic", "quatrains"),
        (Self.pendingSentimentAntiphons, "Pending", "lexicographic", "antiphons"),
        (Self.pendingTestamentSerenades, "Pending", "bibliographic", "serenades"),
      ] {
        try await page.openHydrated("/")
        let link = page.locator(".watchtower-object-figures-view a[href='\(href)']").first
        let phrase = try await link.textContent()
        let shown = try #require(Int(phrase.prefix { $0.isNumber }), "\(href) reads \(phrase)")
        try await link.click()
        try await Self.expectOpened(page, href)
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")

        // The filter bar names what the link asked for, and no row stands
        // on a placeholder.
        let values = try await page.locator(".filter-bar-value-select .dropdown-selected-text").allTextContents()
        #expect(values.contains(status), "\(href): the filter values are \(values)")
        let placeholders = try await page.evaluate(
          """
          [...document.querySelectorAll('.filter-bar-value-select .dropdown-selected-text')]
            .filter(e => e.getAttribute('data-selected') !== 'true').length
          """, as: Int.self)
        #expect(placeholders == 0, "\(href): \(placeholders) filter rows show a placeholder")

        // The figure is the length of the list it opens (read again until
        // they agree, see `agreeing`). The rows, after hydration, are the
        // filtered ones: objects in that status.
        let (count, listed) = try await Self.agreeing(page, href, figure: shown) {
          try await Self.listed(page, href)
        }
        #expect(listed == count, "\(href): the list holds \(listed) for the figure's \(count)")
        let total = try await page.evaluate(
          """
          (() => {
            const table = document.querySelector('.\(tab)-\(table)-table')
            return table ? Number(table.getAttribute('data-total-items')) : 0
          })()
          """, as: Int.self)
        if total > 0 {
          let statuses = try await page.evaluate(
            """
            (() => {
              const table = document.querySelector('.\(tab)-\(table)-table')
              const column = [...table.querySelectorAll('thead th')].findIndex(th => th.textContent.trim() === 'Status')
              return [...table.querySelectorAll('tbody tr[data-row-id]')]
                .map(row => row.children[column]?.textContent.trim() ?? '')
            })()
            """, as: [String].self)
          // A page holds 100 rows (PaginationView.perPage).
          #expect(statuses.count == min(total, 100), "\(href): \(statuses.count) rows shown for \(total)")
          #expect(statuses.allSatisfy { $0 == status }, "\(href): the rows' statuses are \(statuses)")
        }
      }
    }
  }
}
