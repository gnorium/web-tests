import Foundation
import Testing
import WebTests
import WebTestsTesting

/// No paid commit: intercept form.submit after exercising the real dialog,
/// checkbox, cloned phone sidebar, and artifact navigation.
@Suite("Attribution evidence roster", .serialized)
struct AttributionEvidenceRosterTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func scopeIsExplicitAndRecognitionIndependent(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.attributionManifest()
    defer { fixture.stop() }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch = try ScratchCommit(owner: admin, sourceURL: fixture.baseURL + "/manifest.json")
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        for path in [scratch.overturePath, scratch.hallmarkPath] {
          try await page.openHydrated(path)
          try await expect(page.locator("#artifact-page-total")).toHaveText("3")
          _ = try await page.evaluate("""
            window.__evidenceSubmit = null;
            HTMLFormElement.prototype.submit = function() {
              window.__evidenceSubmit = { pipeline: new FormData(this).get('pipeline'),
                canvases: new FormData(this).getAll('evidence_canvas[]') };
            };
            true;
            """, as: Bool.self)
          let rosterRoot: String
          if layout == .phone {
            try await page.locator(".sidebar-menu-btn").click()
            rosterRoot = "#navbar-slide-sidebar-slot .attribution-evidence-roster"
          } else {
            rosterRoot = ".mission-control-sidebar-view .attribution-evidence-roster"
          }
          // Scope remains empty at first; an identical printed title page can
          // still be selected by its own canonical ID.
          let roster = page.locator(rosterRoot).nth(0)
          try await expect(roster.locator("input[name='evidence_canvas[]']")).toHaveCount(3)
          try await roster.locator(".roster-row").nth(1).locator("label").click()
          let selected = try await page.evaluate("document.querySelectorAll(\"input[name='evidence_canvas[]']:checked\").length", as: Int.self)
          #expect(selected == 1)
          if layout == .phone { try await page.locator(".navbar-slide-close-btn").click() }
          try await expect(page.locator("#artifact-page-input")).toHaveValue("2")
          _ = try await page.evaluate("document.querySelectorAll(\"input[name='evidence_canvas[]']\").forEach(input => input.checked = false); true", as: Bool.self)
          if path == scratch.overturePath {
            try await page.locator(".commit-view-trigger").click()
          } else {
            try await page.locator(".commit-view-menu .menu-button-trigger button").click()
            try await page.locator(".commit-view-menu [data-menu-item='true'][data-value='attribution']").click()
          }
          let dialog = page.locator(".commit-view-option[data-pipeline='attribution'] .commit-view-dialog")
          try await dialog.locator(".dialog-primary-button button").click()
          try await expect(dialog.locator(".commit-evidence-warning")).toHaveAttribute("data-visible", "true")
          let blocked = try await page.evaluate("window.__evidenceSubmit === null", as: Bool.self)
          #expect(blocked, "no paid job is created from an empty selection")
          _ = try await page.evaluate("""
            const input = document.querySelector(".mission-control-sidebar-view input[value='\(fixture.baseURL)/canvas/2']");
            input.checked = true;
            true;
            """, as: Bool.self)
          try await dialog.locator(".dialog-primary-button button").click()
          let payload = try await page.evaluate("JSON.stringify(window.__evidenceSubmit)", as: String.self)
          #expect(payload.contains(fixture.baseURL + "/canvas/2"))
          #expect(!payload.contains(fixture.baseURL + "/page-2"), "commit carries canonical canvas IDs, not image services")
          try await dialog.locator(".dialog-default-button button").click()
          try await page.expectNoHorizontalOverflow()
          try await page.expectNoErrors()
        }
      }
      #expect(try scratch.stillPending())
    } catch {
      scratch.remove()
      try await admin.remove(after: error)
    }
    scratch.remove()
    try await admin.remove()
  }
}
