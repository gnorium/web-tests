import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An object's page shows its prompts as they would be sent (user,
/// 2026-10-10): Arbitration's for what a call ticks (nothing until it
/// ticks), its one process's for the Evidence roster's selected item, which
/// a row's click changes; a prompt accordion's box ticks it for the call,
/// a process's every part under it (user, 2026-10-16). A value not knowable
/// yet stays its slot, the task titled "Task Prompt" all the same (user,
/// 2026-10-17): Arbitration's `{query}` until the
/// composer calls, filled as typed, back to `{query}` when @gnorium goes.
/// A call with nothing ticked is its template, every slot left, never an
/// empty state; an item its process will never send a prompt for (one
/// already processed) is not shown, nor a process with nothing to send
/// (user, 2026-10-17). Autocompaction keeps its template, whose
/// {transcript} exists mid-run.
@Suite("Prompt preview filling", .serialized)
struct PromptPreviewFillingTests {
  @Test(arguments: [BrowserEngine.chrome])
  func aMadrigalsPromptsAreFilledForTheSelectedImage(engine: BrowserEngine) async throws {
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
        // Page 1 is explicated: explication sends nothing for it, and its
        // accordion is not shown; no other process shows (user, 2026-10-17).
        try await expect(page.locator(".prompt-previews-process")).toHaveCount(1)
        try await expect(explicationSection).toHaveCount(0)
        // Nothing ticked, nothing a call would read (user, 2026-10-15):
        // its template, every slot left, never an empty state (user,
        // 2026-10-17).
        let taskTitle = arbitrationSection.locator("#prompt-preview-task-arbitration .prompt-preview-title-words").first
        try await expect(taskTitle, timeout: .seconds(20)).toHaveText("Task Prompt")
        try await expect(arbitration).toContainText("{evidence}")
        try await expect(arbitration).toContainText("{query}")
        try await expect(page.locator(".prompt-previews-content .empty-section-view")).toHaveCount(0)
        // Its variables listed above it, as its Revise form lists them;
        // a prompt filled whole lists none (user, 2026-10-17).
        let variables = page.locator("#prompt-preview-task-arbitration .prompt-variables-view .datum-view")
        try await expect(variables).toHaveCount(3)
        try await expect(variables.first.locator(".datum-text")).toHaveText("{evidence}")

        // Page 3, unexplicated: the madrigal's one process, explication, and
        // its prompt, the neighbor's edge sentence filled as its session
        // fills it, no slot left.
        try await page.locator("#madrigal-images .roster-row .roster-label").nth(2).click()
        try await expect(page.locator("#artifact-page-input").first).toHaveValue("3")
        try await expect(explication, timeout: .seconds(20)).toContainText("Beta page sentence.")
        try await expect(page.locator(".prompt-previews-process")).toHaveCount(2)
        try await expect(explication).not.toContainText("Alpha page sentence.")
        // Its own task's accordion, titled by its heading's words.
        try await expect(explicationSection.locator("#prompt-preview-task .prompt-preview-title-words").first)
          .toHaveText("Task Prompt")
        // Its page image a line-high chip where it is attached, opening
        // the lightbox (user, 2026-10-17): a prompt read as Markdown, never
        // full size as the model received it.
        let pageImage = explicationSection.locator(
          ".prompt-preview-task .prompt-preview-images .expandable-attachment-view[data-presentation='line']")
        try await expect(pageImage).toHaveCount(1)
        try await expect(pageImage).toHaveAttribute("data-attachment-hydrated", "true")
        try await expect(pageImage.locator(".expandable-attachment-trigger")).toHaveCount(1)
        try await expect(explicationSection.locator(".expandable-attachment-view[data-presentation='received']"))
          .toHaveCount(0)
        // Autocompaction's alone stays a template, its variables listed;
        // both headings say "Task Prompt", the autocompaction's under its
        // own accordion (user, 2026-10-17).
        try await expect(explicationSection.locator(".prompt-preview-title-words").filter(hasText: "Task Prompt"))
          .toHaveCount(2)
        try await expect(explicationSection.locator(".prompt-variables-view")).toHaveCount(1)
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

        // Page 2 ticked for a call: Arbitration's prompt for it, its query
        // its slot and the task a template while no call is typed.
        let box = page.locator("#locution-thread-locution-body")
        try await box.focus()
        try await page.locator("#madrigal-images .roster-row").nth(1).locator("input").click()
        try await expect(arbitration, timeout: .seconds(20)).toContainText("Beta page sentence.")
        try await expect(arbitration).not.toContainText("Alpha page sentence.")
        try await expect(arbitration).toContainText("{query}")
        try await expect(taskTitle).toHaveText("Task Prompt")
        try await expect(variables).toHaveCount(1)
        try await expect(variables.first.locator(".datum-text")).toHaveText("{query}")

        // Arbitration's own box ticks every part of its prompts; one part
        // unticked leaves it partly ticked; the parts are read as sent.
        try await arbitrationSection.locator(".accordion-summary").first.click()
        let process = page.locator("#prompt-tick-bibliographic_arbitration")
        try await process.click()
        try await expect(process).toBeChecked()
        try await expect(page.locator("#prompt-tick-system-bibliographic_arbitration")).toBeChecked()
        try await expect(page.locator("#prompt-tick-task-bibliographic_arbitration_continuation")).toBeChecked()
        try await expect(page.locator("#prompt-tick-system-bibliographic_arbitration_autocompaction")).toBeChecked()
        try await expect(arbitration, timeout: .seconds(20)).toContainText("Arbitration › System Prompt")
        try await page.locator("#prompt-tick-system-bibliographic_arbitration").click()
        let partly = try await page.evaluate(
          "document.getElementById('prompt-tick-bibliographic_arbitration').indeterminate", as: Bool.self)
        #expect(partly, "one part unticked leaves its process partly ticked")
        try await expect(arbitration, timeout: .seconds(20)).not.toContainText("Arbitration › System Prompt")
        try await expect(page.locator("#prompt-tick-task-bibliographic_arbitration")).toBeChecked()
        // Partly ticked, its box ticks every part again; again, none.
        try await page.locator("#prompt-tick-bibliographic_arbitration").click()
        try await expect(page.locator("#prompt-tick-system-bibliographic_arbitration")).toBeChecked()
        try await page.locator("#prompt-tick-bibliographic_arbitration").click()
        try await expect(page.locator("#prompt-tick-task-bibliographic_arbitration")).toBeChecked(false)

        // Typed into the composer, a call's query is the Arbitration task
        // prompt's as it is typed, in the same section, a prompt now;
        // @gnorium gone, its slot again.
        _ = try await page.evaluate(
          "(() => { window.__arbitrationSection = document.querySelector(\".prompt-previews-process[data-process='Arbitration']\"); return true })()",
          as: Bool.self)
        try await box.type("@gnorium Why is beta here?")
        try await expect(arbitration, timeout: .seconds(20)).toContainText("Why is beta here?")
        try await expect(arbitration).not.toContainText("{query}")
        try await expect(arbitration).toContainText("Beta page sentence.")
        try await expect(taskTitle).toHaveText("Task Prompt")
        try await expect(variables).toHaveCount(0)
        let kept = try await page.evaluate(
          "window.__arbitrationSection === document.querySelector(\".prompt-previews-process[data-process='Arbitration']\")",
          as: Bool.self)
        #expect(kept, "the Arbitration section was redrawn")
        try await box.fill("Why is beta here?")
        try await expect(arbitration, timeout: .seconds(20)).not.toContainText("Why is beta here?")
        try await expect(arbitration).toContainText("{query}")
        try await expect(arbitration).toContainText("Beta page sentence.")

        // Called again, page 2 unticked: nothing ticked, the template whole
        // again—its query a slot too, never half filled—and its images gone.
        try await box.fill("@gnorium Why is beta here?")
        try await expect(taskTitle, timeout: .seconds(20)).toHaveText("Task Prompt")
        let images = arbitrationSection.locator(
          ".prompt-preview-task .prompt-preview-images .expandable-attachment-view[data-presentation='line']")
        let sent = try await images.count()
        try await page.locator("#madrigal-images .roster-row").nth(1).locator("input").click()
        try await expect(taskTitle, timeout: .seconds(20)).toHaveText("Task Prompt")
        try await expect(arbitration).toContainText("{evidence}")
        try await expect(arbitration).toContainText("{query}")
        try await expect(arbitration).not.toContainText("Beta page sentence.")
        try await expect(arbitration).not.toContainText("Why is beta here?")
        try await expect(images).toHaveCount(0)
        try await expect(arbitrationSection.locator(".empty-section-view")).toHaveCount(0)
        // A prompt part ticked alone, in place: the prompt filled whole; unticked,
        // its template again, the section never redrawn. The System Prompt:
        // the process's box would attach its Task Prompt too, whose
        // text keeps its `{evidence}` as written, never filled.
        _ = try await page.evaluate(
          "(() => { window.__arbitrationSection = document.querySelector(\".prompt-previews-process[data-process='Arbitration']\"); return true })()",
          as: Bool.self)
        try await page.locator("#prompt-tick-system-bibliographic_arbitration").click()
        try await expect(taskTitle, timeout: .seconds(20)).toHaveText("Task Prompt")
        try await expect(arbitration).toContainText("Arbitration › System Prompt")
        try await expect(arbitration).toContainText("Why is beta here?")
        try await expect(arbitration).not.toContainText("{evidence}")
        try await expect(variables).toHaveCount(0)
        try await page.locator("#prompt-tick-system-bibliographic_arbitration").click()
        try await expect(taskTitle, timeout: .seconds(20)).toHaveText("Task Prompt")
        try await expect(arbitration).toContainText("{evidence}")
        try await expect(variables).toHaveCount(3)
        try await expect(arbitration).not.toContainText("Arbitration › System Prompt")
        let swapped = try await page.evaluate(
          "window.__arbitrationSection === document.querySelector(\".prompt-previews-process[data-process='Arbitration']\")",
          as: Bool.self)
        #expect(swapped, "the Arbitration section was redrawn")
        // Page 2 ticked again: its prompt, and the images it sends.
        try await page.locator("#madrigal-images .roster-row").nth(1).locator("input").click()
        try await expect(taskTitle, timeout: .seconds(20)).toHaveText("Task Prompt")
        try await expect(arbitration).toContainText("Beta page sentence.")
        try await expect(images).toHaveCount(sent)
        // Swapped in place, drawn and bound as the first were: line-high
        // chips opening the lightbox, never full size (user, 2026-10-17).
        #expect(sent > 0, "page 2 sends its image")
        try await expect(images.first).toHaveAttribute("data-attachment-hydrated", "true")
        try await expect(images.first.locator(".expandable-attachment-trigger")).toHaveCount(1)
        try await expect(arbitrationSection.locator(".expandable-attachment-view[data-presentation='received']"))
          .toHaveCount(0)
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
