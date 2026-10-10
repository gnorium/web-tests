import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An object's page shows its prompts as they would be sent (user,
/// 2026-10-10): "Task Prompt", every variable filled from its data for the
/// Evidence roster's selected item, which a row's click changes;
/// Arbitration's query the composer's as typed, empty while it calls none.
/// Its autocompaction keeps its template, whose {transcript} exists mid-run.
@Suite("Prompt preview filling", .serialized)
struct PromptPreviewFillingTests {
  @Test(arguments: [BrowserEngine.chrome])
  func aMadrigalsPromptsAreFilledForTheSelectedCanvas(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let scratch: ScratchCommit
    do { scratch = try ScratchCommit(owner: contributor, sourceURL: fixture.baseURL + "/manifest.json") }
    catch { try await contributor.remove(after: error) }
    do {
      let base = fixture.baseURL
      let tei = """
        <TEI xmlns="http://www.tei-c.org/ns/1.0"><text><body>\
        <pb n="1" facs="\(base)/page-1/full/max/0/default.jpg"/><p><s>Alpha page sentence.</s></p>\
        <pb n="2" facs="\(base)/page-2/full/max/0/default.jpg"/><p><s>Beta page sentence.</s></p>\
        <pb n="3" facs="\(base)/page-3/full/max/0/default.jpg"/><p><s>Gamma page sentence.</s></p>\
        </body></text></TEI>
        """
      let content = String(decoding: try JSONSerialization.data(withJSONObject: ["teiXml": tei]), as: UTF8.self)
      _ = try TestAdmin.query("""
        UPDATE bibliographic_madrigals SET proposed_content_json = '\(content.replacingOccurrences(of: "'", with: "''"))'
        WHERE id = '\(scratch.madrigalID)'
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated(scratch.madrigalPath)
        let slot = page.locator(".prompt-previews-slot")
        try await expect(slot, timeout: .seconds(20)).toHaveAttribute("aria-busy", "false")
        let arbitration = page.locator("[data-process='Arbitration'] .prompt-preview-task .prompt-text-source").first
        let explication = page.locator("[data-process='Explication'] .prompt-preview-task .prompt-text-source").first
        try await expect(arbitration, timeout: .seconds(20)).toContainText("Alpha page sentence.")
        try await expect(arbitration).not.toContainText("{query}")
        try await expect(arbitration).not.toContainText("Beta page sentence.")
        // The neighbor's edge sentence, filled as its session fills it.
        try await expect(explication).toContainText("Beta page sentence.")
        for process in ["Arbitration", "Explication"] {
          let section = page.locator(".prompt-previews-process[data-process='\(process)']")
          try await expect(section.getByText("Task Prompt", exact: true)).toHaveCount(1)
          // Autocompaction's alone stays a template.
          try await expect(section.getByText("Task Prompt Template", exact: true)).toHaveCount(1)
        }
        // No variable left but autocompaction's {transcript}.
        let slots = try await page.evaluate(
          """
          (() => {
            const left = []
            for (const process of document.querySelectorAll('.prompt-previews-process')) {
              for (const task of process.querySelectorAll('.prompt-preview-task .prompt-text-source')) {
                for (const match of task.textContent.matchAll(/\\{[a-z_]+\\}/g)) left.push(process.dataset.process + match[0])
              }
            }
            return left.join(' ')
          })()
          """, as: String.self)
        #expect(slots == "", "slots left: \(slots)")

        // Another row: its prompts.
        try await page.locator("#madrigal-canvases .roster-row .roster-label").nth(2).click()
        try await expect(page.locator("#artifact-page-input").first).toHaveValue("3")
        try await expect(arbitration, timeout: .seconds(20)).toContainText("Gamma page sentence.")
        try await expect(arbitration).not.toContainText("Alpha page sentence.")
        try await expect(explication).toContainText("Beta page sentence.")
        try await expect(explication).not.toContainText("Alpha page sentence.")

        // Typed into the composer, a call's query is the Arbitration task
        // prompt's as it is typed, in the same section; @gnorium gone, the
        // empty query's again.
        _ = try await page.evaluate(
          "(() => { window.__arbitrationSection = document.querySelector(\".prompt-previews-process[data-process='Arbitration']\"); return true })()",
          as: Bool.self)
        let box = page.locator("#locution-thread-locution-body")
        try await box.type("@gnorium Why is gamma here?")
        try await expect(arbitration, timeout: .seconds(20)).toContainText("Why is gamma here?")
        try await expect(arbitration).toContainText("Gamma page sentence.")
        let kept = try await page.evaluate(
          "window.__arbitrationSection === document.querySelector(\".prompt-previews-process[data-process='Arbitration']\")",
          as: Bool.self)
        #expect(kept, "the Arbitration section was redrawn")
        try await box.fill("Why is gamma here?")
        try await expect(arbitration, timeout: .seconds(20)).not.toContainText("Why is gamma here?")
        try await expect(arbitration).toContainText("Gamma page sentence.")
        try await page.expectNoErrors()
      }
    } catch {
      scratch.remove()
      try await contributor.remove(after: error)
    }
    scratch.remove()
    try await contributor.remove()
  }
}
