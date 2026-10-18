import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The system account's public profile (user, 2026-10-12): no role chip
/// and no contribution counts—contributions are people's accepted
/// outcomes—but its work, per kind behind Bibliographic and Lexicographic
/// tabs in the card's header: a row for each object it works on, in
/// lifetime order, saying only what it does there—"9 locutions" on a
/// Disputorium object, "291 nocturnes" on a Computorium one—the phrase one
/// link to that list filtered by the object. Its picture is always the
/// logo.
@Suite("System account profile", .serialized)
struct SystemAccountProfileTests {
  /// Each object, and its count's noun.
  static let rows = [
    ("overture", "locution"), ("antiphon", "nocturne"), ("madrigal", "locution"), ("serenade", "nocturne"),
    ("epilogue", "locution"),
  ]

  @Test(arguments: [BrowserEngine.chrome])
  func itShowsItsWorkNotContributions(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: .desktop) { page in
      try await page.openHydrated("/users/gnorium")
      try await expect(page.locator(".user-profile-chips")).toHaveCount(0)
      try await expect(page.getByText("System account", exact: true)).toHaveCount(0)
      try await expect(page.locator(".user-profile-stats-bar")).toHaveCount(0)
      try await expect(page.locator(".user-profile-header-ruled")).toHaveCount(0)
      try await expect(page.locator(".user-profile-header .avatar-image[src='/images/logo.png']")).toHaveCount(1)
      try await expect(page.locator(".user-profile-header .user-profile-work [role='tab']")).toHaveCount(2)
      for kind in ["bibliographic", "lexicographic"] {
        try await page.locator(".user-profile-work #tab-\(kind)").click()
        let panel = page.locator(".user-profile-work #panel-\(kind)")
        try await expect(panel).toBeVisible()
        let labels = panel.locator(".datum-label")
        try await expect(labels).toHaveCount(Self.rows.count)
        for (index, (object, noun)) in Self.rows.enumerated() {
          try await expect(labels.nth(index)).toContainText("\(object.prefix(1).uppercased())\(object.dropFirst())s")
          let href =
            noun == "locution"
            ? "/mission-control/locutions/\(kind)?object=\(kind)_\(object)&createdBy=gnorium"
            : "/mission-control/nocturnes/\(kind)?object=\(object)"
          let link = panel.locator("a[href='\(href)']")
          try await expect(link).toHaveCount(1)
          // "1 locution", "9 locutions": number first, the noun agreeing.
          let text = try await link.innerText().trimmingCharacters(in: .whitespacesAndNewlines)
          let parts = text.split(separator: " ")
          let count = parts.first.flatMap { Int($0) }
          #expect(count != nil && parts.count == 2, "\(kind) \(object): \(text)")
          #expect(parts.last.map(String.init) == (count == 1 ? noun : noun + "s"), "\(kind) \(object): \(text)")
        }
      }
      try await page.expectNoErrors()
    }
  }
}
