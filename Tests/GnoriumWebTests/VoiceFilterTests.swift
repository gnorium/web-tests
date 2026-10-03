import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A voice is a role and a name, typed (user, 2026-10-03): no metadata
/// field links to a record. A record page's sidebar lists its Voices, each
/// its role and its name as plain text, never a link. The records lists do
/// not filter by a voice: the sidebar's Author search finds one. There are
/// no person pages. A throwaway admin owns a scratch work, removed after.
@Suite("Voice filter", .serialized)
struct VoiceFilterTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aVoiceIsPlainText(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    do {
      try await run(engine: engine, viewport: layout.viewport(for: engine), work: work)
    } catch {
      work.remove()
      try await admin.remove(after: error)
    }
    work.remove()
    try await admin.remove()
  }

  private func run(engine: BrowserEngine, viewport: Viewport, work: ScratchWork) async throws {
    try await withPage(engine, gnorium, viewport: viewport) { page in
      try await page.openHydrated(work.path)
      // The sidebar is drawn once, and again in the phone's menu: its
      // Voices a role and a name, no link among them.
      let voices = page.locator(".record-sidebar-section").filter(hasText: "Voices").first
      try await expect(voices).toContainText("Author")
      try await expect(voices).toContainText(work.author)
      try await expect(voices.locator("a")).toHaveCount(0)
      // Nowhere on the page is a voice's name a link.
      try await expect(page.locator("a").filter(hasText: work.author)).toHaveCount(0)
      var overflow = try await page.evaluate("document.documentElement.scrollWidth > window.innerWidth").bool
      #expect(overflow == false)

      // The records lists filter by no voice: the sidebar's Author search
      // finds one. The bar offers no Voice field.
      try await page.openHydrated("/biblio-records")
      let filter = page.locator(".filter-bar-view")
      try await expect(filter.locator(".filter-bar-field-picker .dropdown-option")).not.toHaveCount(0)
      try await expect(filter.locator(".filter-bar-field-picker .dropdown-option").filter(hasText: "Voice", exact: true))
        .toHaveCount(0)
      try await expect(filter.locator("input[name='voice']")).toHaveCount(0)
      overflow = try await page.evaluate("document.documentElement.scrollWidth > window.innerWidth").bool
      #expect(overflow == false)

      // No person page: an address nobody held is the normal 404.
      let status = try await page.evaluate(
        "fetch('/persons/nobody/unknown/unknown', { redirect: 'manual' }).then((r) => r.status)"
      ).double
      #expect(status == 404)
    }
  }
}
