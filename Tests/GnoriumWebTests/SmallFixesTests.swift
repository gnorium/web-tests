import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Small fixes (user, 2026-10-24): a testament's citation numbers are headed
/// "Reference numbers"; a seeded vignette reads "Permitted" by gnorium in its
/// Pedigree.
/// Written, not run, with the change.
@Suite("Small fixes", .serialized)
struct SmallFixesTests {
  @Test(arguments: [BrowserEngine.chrome])
  func aTestamentsCitationNumbersAreHeadedReferenceNumbers(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/submit/bibliographic/testament")
        let legends = try await page.evaluate(
          "[...document.querySelectorAll('.submit-testament-form .section-legend')].map(l => l.textContent.trim())",
          as: [String].self)
        #expect(legends.contains("Reference numbers"), "\(legends)")
        #expect(!legends.contains { $0.contains("Citation") })
        try await page.expectNoErrors()
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }

  @Test(arguments: [BrowserEngine.chrome])
  func aSeededVignettesPedigreeReadsPermittedByGnorium(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let id = try TestAdmin.query(
      """
      SELECT v.id FROM prompt_vignettes v
      JOIN prompt_activations a ON a.vignette_id = v.id
      WHERE v.committed_at IS NULL AND v.committed_object_id IS NULL AND v.is_proprietary_content = false
      LIMIT 1
      """)
    if id.isEmpty { try Test.cancel("No seeded prompt vignette on this database.") }
    try await withPage(engine, gnorium, viewport: .desktop) { page in
      try await page.openHydrated("/mission-control/prompts/vignettes/\(id)")
      let labels = page.locator(".pedigree-view .datum-label")
      try await expect(labels.first).toHaveText("Vignette ID")
      try await expect(labels.nth(1)).toHaveText("Permitted")
      try await expect(page.locator(".pedigree-view .byline-view").first).toContainText("gnorium")
      try await expect(page.getByText("Submitted")).toHaveCount(0)
    }
  }
}
