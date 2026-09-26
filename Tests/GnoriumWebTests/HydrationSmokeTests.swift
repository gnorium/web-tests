import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Every main page loads, hydrates, logs no error, has no same-origin request
/// fail, and does not scroll sideways, on a phone and on a desktop.
@Suite("Hydration smoke")
struct HydrationSmokeTests {
  static let pages = ["/", "/biblio-records", "/lexico-records", "biblio-record", "lexico-record", "/auth/sign-in"]

  @Test(arguments: gnorium.engines, Layout.allCases)
  func pagesHydrateCleanly(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      var failures: [String] = []
      for path in Self.pages {
        do {
          let target =
            path == "biblio-record" ? try await Self.firstRecord(page, in: "/biblio-records")
            : path == "lexico-record" ? try await Self.firstRecord(page, in: "/lexico-records") : path
          try await page.clearDiagnostics()
          try await page.openHydrated(target)
          try await page.expectNoErrors()
          try await page.expectNoHorizontalOverflow()
        } catch {
          failures.append("\(path): \(error)")
        }
      }
      if !failures.isEmpty {
        throw WebTestError(failures.joined(separator: "\n\n"))
      }
    }
  }

  /// A record page, found the way a reader would: the first record the
  /// index lists.
  static func firstRecord(_ page: Page, in index: String) async throws -> String {
    try await page.goto(index)
    let link = page.locator("a[href^='\(index)/']").first
    guard let href = try await link.getAttribute("href") else {
      throw WebTestError("\(index) lists no record to open.")
    }
    return href
  }
}
