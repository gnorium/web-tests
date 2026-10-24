import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A process's prompt vignette holds a subagent prompt (user, 2026-10-24):
/// the system prompt of the subagents its agents spawn, one text, a node
/// like the others. Its page lists it with System, Task, Continuation and
/// Autocompaction, as an accordion under the same heading pattern. Chrome.
@Suite("Subagent prompt node", .serialized)
struct SubagentPromptNodeTests {
  @Test(arguments: [BrowserEngine.chrome])
  func theComparePageListsTheSubagentNodeLikeTheOthers(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let vignettes = try ScratchVignettes()
    defer { try? vignettes.remove() }
    try await withPage(engine, gnorium, viewport: .desktop) { page in
      try await page.openHydrated(vignettes.path)
      let titles = try await page.evaluate(
        "[...document.querySelectorAll('.prompt-compare-content .prompt-section')].slice(0, 5).map(s => s.id).join(' ')",
        as: String.self)
      #expect(
        titles == "system-prompt task-prompt continuation-prompt autocompaction-prompt subagent-prompt",
        "The five nodes in order: \(titles)")
      try await expect(page.locator("#subagent-prompt .accordion-title").first).toHaveText("Subagent Prompt")
      try await page.expectNoErrors()
    }
  }
}
