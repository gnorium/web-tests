import Testing
import WebTests
import WebTestsTesting

@Suite("Labels reference", .serialized)
struct LabelsTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func catalogHasEveryAxisAndFitsTheViewport(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/labels")
      try await expect(page.locator(".page-heading")).toHaveText("Labels")
      for (axis, name) in [
        ("grammar", "Grammar"), ("register", "Register"), ("domain", "Domain"),
        ("region", "Region"), ("currency", "Currency"),
      ] {
        try await expect(page.locator("#labels-\(axis) h2")).toHaveText(name)
      }
      try await expect(page.locator("#labels-region")).toContainText("English")
      try await expect(page.locator(".labels-content")).toContainText("utterance evidence")
      try await page.expectNoHorizontalOverflow()
    }
  }
}
