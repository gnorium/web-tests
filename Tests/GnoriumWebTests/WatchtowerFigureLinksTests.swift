import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Every object figure on the Watchtower opens a list exactly as long as the
/// figure, on both rows (testaments and sentiments), and the list it opens is
/// filtered as the link asks from the first render: its filter bar names the
/// linked object and status, never a placeholder, and its rows are the ones
/// the filter keeps.
@Suite("Watchtower figure links")
struct WatchtowerFigureLinksTests {
  /// Every figure: an object's, opening a lifecycle list or the rebuttals
  /// register, and a stage's, opening the runs it counts.
  static let figureLinks = ".watchtower-object-figures-view a[href], .watchtower-stage-figures a[href]"

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

  /// The rows a list page shows, read from its HTML as the server sent it.
  static func listed(_ page: Page, _ href: String) async throws -> Int {
    try await page.evaluate(
      """
      fetch(\(jsString(href))).then(r => r.text()).then(html => {
        const doc = new DOMParser().parseFromString(html, 'text/html')
        const table = doc.querySelector('[data-total-items]')
        if (table) return Number(table.getAttribute('data-total-items'))
        return doc.querySelectorAll('tbody tr[data-row-id]').length
      })
      """, as: Int.self)
  }

  @Test(arguments: gnorium.engines)
  func everyFigureIsTheLengthOfItsList(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated("/")
      let figures = try await Self.figures(page)
      try #require(figures.count >= 58, "the Watchtower shows \(figures.count) figure links")
      try #require(figures.filter { $0.href.contains("show=runs") }.count == 12, "every stage has three run links")
      for figure in figures {
        let count = try #require(Int(figure.text.prefix { $0.isNumber }))
        let listed = try await Self.listed(page, figure.href)
        #expect(listed == count, "\(figure.text) opens \(listed) rows: \(figure.href)")
      }
    }
  }

  /// The case that was broken: the sentiments' committed overtures.
  static let committedSentimentOvertures =
    "/mission-control/lifecycles?tab=lexicographic&object=overture&status=committed&since=1w"
  /// The testaments' pending overtures, whose list must be filtered on the
  /// first render, not only after Apply.
  static let pendingTestamentOvertures = "/mission-control/lifecycles?tab=bibliographic&object=overture&status=pending"

  /// A stage's figure opens the runs list: its filter bar names the stage,
  /// the status and "Runs", with no placeholder, and it lists as many runs as
  /// the figure.
  @Test(arguments: enginesAndLayouts)
  func aStageFigureOpensItsRuns(engine: BrowserEngine, layout: Layout) async throws {
    let href = "/mission-control/lifecycles?tab=bibliographic&status=failed&stage=recognition&since=1w&show=runs"
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/")
      let link = page.locator(".watchtower-stage-figures a[href='\(href)']").first
      let phrase = try await link.textContent()
      let count = try #require(Int(phrase.prefix { $0.isNumber }), "\(href) reads \(phrase)")
      try await link.click()
      try await expect(page, timeout: .seconds(15)).toHaveURL(href)
      try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
      let fields = try await page.locator(".filter-bar-field-picker .dropdown-selected-text").allTextContents()
      #expect(fields.contains("Stage") && fields.contains("Status") && fields.contains("Show"), "fields: \(fields)")
      let values = try await page.locator(".filter-bar-value-select .dropdown-selected-text").allTextContents()
      #expect(values.contains("Recognition") && values.contains("Failed") && values.contains("Runs"), "values: \(values)")
      let placeholders = try await page.evaluate(
        """
        [...document.querySelectorAll('.filter-bar-value-select .dropdown-selected-text')]
          .filter(e => e.getAttribute('data-selected') !== 'true').length
        """, as: Int.self)
      #expect(placeholders == 0, "\(placeholders) filter rows show a placeholder")
      // A run its worker lost is failed, not a status of its own.
      let stalled = try await page.evaluate("document.body.innerHTML.includes('Stalled')", as: Bool.self)
      #expect(!stalled, "the runs list offers a Stalled status")
      if count == 0 {
        try await expect(page.locator(".mission-control-core-empty")).toBeVisible()
      } else {
        try await expect(page.locator(".bibliographic-runs-table")).toHaveAttribute("data-total-items", "\(count)")
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
        let count = try #require(Int(phrase.prefix { $0.isNumber }), "\(href) reads \(phrase)")
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

        // The rows, after hydration, are the filtered ones: as many as the
        // figure, each a lifecycle holding the object in that status.
        let table = page.locator(".\(tab)-lifecycles-table")
        if count == 0 {
          try await expect(page.locator(".mission-control-core-empty")).toBeVisible()
        } else {
          try await expect(table).toHaveAttribute("data-total-items", "\(count)")
          let headers = try await page.evaluate(
            """
            [...document.querySelectorAll('.\(tab)-lifecycles-table tbody tr[data-row-id]')]
              .filter(r => !r.classList.contains('table-group-child')).length
            """, as: Int.self)
          #expect(headers == min(count, 25), "\(href): \(headers) lifecycles shown for \(count)")
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
