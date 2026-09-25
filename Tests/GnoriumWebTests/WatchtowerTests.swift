import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The Watchtower on the home page links each permitted treatment to the
/// records it shows, and that page's filter names the same treatment.
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

        // The filter row whose field is the treatment filter, however it is
        // labelled today.
        let row = try await Self.treatmentRow(page)
        try await expect(row.locator(".filter-bar-value-select .dropdown-selected-text")).toHaveText(phrase)
      }
    }
  }

  static let treatmentLabels = ["Treatment", "Pipelines"]

  static func treatmentRow(_ page: Page) async throws -> Locator {
    let rows = page.locator(".filter-bar-row")
    try await expect(rows.first).toBeVisible()
    var labels: [String] = []
    for row in try await rows.all() {
      let label = try await row.locator(".filter-bar-field-picker .dropdown-selected-text").textContent()
      if treatmentLabels.contains(label) { return row }
      labels.append(label)
    }
    throw WebTestError("No filter row is labelled \(treatmentLabels.joined(separator: " or ")); the rows are \(labels).")
  }
}
