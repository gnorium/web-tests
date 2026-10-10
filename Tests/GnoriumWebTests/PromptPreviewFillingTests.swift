import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An object's page shows its prompts as they would be sent (user,
/// 2026-10-10): Arbitration's and its one process's, every variable filled
/// from its data for the Evidence roster's selected item, which a row's
/// click changes. A value not knowable yet stays its slot, and the task is
/// a "Task Prompt Template" then: Arbitration's `{query}` until the
/// composer calls, filled as typed, back to `{query}` when @gnorium goes.
/// An item its process has already processed says so. Autocompaction keeps
/// its template, whose {transcript} exists mid-run.
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
        <pb n="3" facs="\(base)/page-3/full/max/0/default.jpg"/>\
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
        let arbitrationSection = page.locator(".prompt-previews-process[data-process='Arbitration']")
        let explicationSection = page.locator(".prompt-previews-process[data-process='Explication']")
        // A page unexplicated: the madrigal's one process is explication;
        // no other process shows.
        try await expect(page.locator(".prompt-previews-process")).toHaveCount(2)
        try await expect(arbitration, timeout: .seconds(20)).toContainText("Alpha page sentence.")
        try await expect(arbitration).not.toContainText("Beta page sentence.")
        // No call typed: its query is its slot, and the task a template.
        try await expect(arbitration).toContainText("{query}")
        try await expect(arbitrationSection.locator("#prompt-preview-task-arbitration .accordion-title").first)
          .toHaveText("Task Prompt Template")
        // Page 1 is explicated: explication sends nothing for it.
        try await expect(explicationSection.locator(".prompt-preview-task-notice"))
          .toContainText("This evidence item has already been explicated")

        // Page 3, unexplicated: its explication prompt, the neighbor's edge
        // sentence filled as its session fills it, no slot left.
        try await page.locator("#madrigal-canvases .roster-row .roster-label").nth(2).click()
        try await expect(page.locator("#artifact-page-input").first).toHaveValue("3")
        try await expect(explication, timeout: .seconds(20)).toContainText("Beta page sentence.")
        try await expect(explication).not.toContainText("Alpha page sentence.")
        try await expect(explicationSection.getByText("Task Prompt", exact: true)).toHaveCount(1)
        // Autocompaction's alone stays a template.
        try await expect(explicationSection.getByText("Task Prompt Template", exact: true)).toHaveCount(1)
        let slots = try await page.evaluate(
          """
          (() => {
            const left = []
            for (const task of document.querySelectorAll("[data-process='Explication'] .prompt-preview-task .prompt-text-source")) {
              for (const match of task.textContent.matchAll(/\\{[a-z_]+\\}/g)) left.push(match[0])
            }
            return left.join(' ')
          })()
          """, as: String.self)
        #expect(slots == "", "slots left: \(slots)")

        // Page 2: Arbitration's prompt for it.
        try await page.locator("#madrigal-canvases .roster-row .roster-label").nth(1).click()
        try await expect(page.locator("#artifact-page-input").first).toHaveValue("2")
        try await expect(arbitration, timeout: .seconds(20)).toContainText("Beta page sentence.")
        try await expect(arbitration).not.toContainText("Alpha page sentence.")

        // Typed into the composer, a call's query is the Arbitration task
        // prompt's as it is typed, in the same section, a prompt now;
        // @gnorium gone, its slot again.
        _ = try await page.evaluate(
          "(() => { window.__arbitrationSection = document.querySelector(\".prompt-previews-process[data-process='Arbitration']\"); return true })()",
          as: Bool.self)
        let box = page.locator("#locution-thread-locution-body")
        try await box.type("@gnorium Why is beta here?")
        try await expect(arbitration, timeout: .seconds(20)).toContainText("Why is beta here?")
        try await expect(arbitration).not.toContainText("{query}")
        try await expect(arbitration).toContainText("Beta page sentence.")
        try await expect(arbitrationSection.locator("#prompt-preview-task-arbitration .accordion-title").first)
          .toHaveText("Task Prompt")
        let kept = try await page.evaluate(
          "window.__arbitrationSection === document.querySelector(\".prompt-previews-process[data-process='Arbitration']\")",
          as: Bool.self)
        #expect(kept, "the Arbitration section was redrawn")
        try await box.fill("Why is beta here?")
        try await expect(arbitration, timeout: .seconds(20)).not.toContainText("Why is beta here?")
        try await expect(arbitration).toContainText("{query}")
        try await expect(arbitration).toContainText("Beta page sentence.")
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
