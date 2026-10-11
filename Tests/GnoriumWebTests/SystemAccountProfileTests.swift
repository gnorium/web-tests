import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The system account's public profile (user, 2026-10-12): labeled as the
/// system account, no contribution counts—contributions are people's
/// accepted outcomes—but its work in the order it does it, Locutions,
/// Antiphons, Serenades, each count linked per kind to its Mission Control
/// list filtered by Created by gnorium.
@Suite("System account profile", .serialized)
struct SystemAccountProfileTests {
  @Test(arguments: [BrowserEngine.chrome])
  func itShowsItsWorkNotContributions(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: .desktop) { page in
      try await page.openHydrated("/users/gnorium")
      try await expect(page.locator(".user-profile-system-chip")).toHaveText("System account")
      try await expect(page.locator(".user-profile-stats-bar")).toHaveCount(0)
      try await expect(page.getByText("Contributions", exact: true)).toHaveCount(0)
      let rows = page.locator(".user-profile-machine-activity .datum-label")
      try await expect(rows).toHaveCount(3)
      try await expect(rows.nth(0)).toContainText("Locutions")
      try await expect(rows.nth(1)).toContainText("Antiphons")
      try await expect(rows.nth(2)).toContainText("Serenades")
      for list in ["locutions", "antiphons", "serenades"] {
        for kind in ["bibliographic", "lexicographic"] {
          try await expect(page.locator(".user-profile-machine-activity a[href='/mission-control/\(list)/\(kind)?createdBy=gnorium']"))
            .toHaveCount(1)
        }
      }
      try await page.expectNoErrors()
    }
  }
}
