import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The Watchtower on the home page links each permitted status to the
/// records it shows, and that page's filter names the same status.
@Suite("Watchtower")
struct WatchtowerTests {
  /// The Watchtower's links into the public records.
  static let permitLinks = "a.watchtower-routes-name[href*='-records?']"

  @Test(arguments: gnorium.engines)
  func permitLinksOpenMatchingFilters(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated("/")
      let links = page.locator(Self.permitLinks)
      let count = try await links.count()
      try #require(count > 0, "the Watchtower shows no permit links")

      for index in 0..<count {
        if index > 0 { try await page.openHydrated("/") }
        let link = page.locator(Self.permitLinks).nth(index)
        let phrase = try await link.textContent()
        let href = try #require(try await link.getAttribute("href"))

        try await link.click()
        try await expect(page, timeout: .seconds(15)).toHaveURL(href)
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")

        // The filter row whose field is the status filter, however it is
        // labeled today.
        // The process the link filters by (its `status`), as the filter
        // names it: a permit link is named by what it lists ("biblio-record").
        let status = try #require(
          URLComponents(string: href)?.queryItems?.first { $0.name == "status" }?.value, "\(phrase) filters no status")
        let row = try await Self.statusRow(page)
        let selected = row.locator(".filter-bar-value-select .dropdown-selected-text")
        try await expect(selected).not.toHaveText("")
        let shown = try await selected.textContent()
        #expect(shown.lowercased().contains(status), "\(phrase): the filter reads \(shown), not \(status)")
      }
    }
  }

  /// Each process card carries its group's place in the flow (user,
  /// 2026-09-29): explication 1, translation 2; explication, of both kinds,
  /// and translation show one process and one card each.
  @Test(arguments: gnorium.engines)
  func processCardsCarryTheirGroupsNumber(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated("/")
      for (process, numbers) in [
        ("Explication", ["1"]), ("Translation", ["2"]),
      ] {
        let card = page.locator(".watchtower-processes-view[data-process='\(process)']").first
        try await expect(card.locator(".watchtower-process-number")).toHaveTexts(numbers)
      }
      // No heading over a process's block: the block names its process.
      try await expect(page.locator(".watchtower-group-name")).toHaveCount(0)
      try await expect(page.locator(".watchtower-process-name")).toHaveTexts(
        ["ARBITRATION", "EXPLICATION", "ARBITRATION", "TRANSLATION", "ARBITRATION"])
    }
  }

  @Test(arguments: gnorium.engines)
  func nestedLocutionsAreCommittedOnce(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated("/")
      let cards = page.locator(".watchtower-object-view:has(> .watchtower-object-header .watchtower-object-name-link)")
      let routes = try await page.evaluate("""
        [...document.querySelectorAll('.watchtower-object-name-link')]
          .filter(e => e.textContent === 'Locution')
          .map(e => [...e.closest('.watchtower-object-view').querySelectorAll(':scope > .watchtower-routes-view')]
            .map(r => [...r.querySelectorAll('.watchtower-routes-row > span')].map(s => s.textContent.trim()).join(' ')).join('|')).join('\\n')
        """, as: String.self)
      #expect(routes.split(separator: "\n").map(String.init) == Array(repeating: "commit ← locution|submit → locution", count: 3))
      #expect(try await cards.count() > 0)
    }
  }

  static let statusLabels = ["Status"]

  static func statusRow(_ page: Page) async throws -> Locator {
    let rows = page.locator(".filter-bar-row")
    try await expect(rows.first).toBeVisible()
    var labels: [String] = []
    for row in try await rows.all() {
      let label = try await row.locator(".filter-bar-field-picker .dropdown-selected-text").textContent()
      if statusLabels.contains(label) { return row }
      labels.append(label)
    }
    throw WebTestError("No filter row is labeled \(statusLabels.joined(separator: " or ")); the rows are \(labels).")
  }
}
