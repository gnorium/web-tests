import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A person has no page (user, 2026-09-27): they filter the records lists.
/// A record page's sidebar lists its Voices, each a link to the list
/// filtered to them (`voice=`, their key, never an id); the list's filter
/// bar then shows a "Voice" filter naming them, cleared as any filter is (its
/// value picked again, then Apply), and the tabs keep it. An old person
/// address answers nothing. A throwaway admin owns a scratch work, removed
/// after.
@Suite("Voice filter", .serialized)
struct VoiceFilterTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aVoiceIsAFilterOnTheRecordsList(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    do {
      try await run(engine: engine, viewport: layout.viewport(for: engine), work: work)
    } catch {
      work.remove()
      await admin.remove()
      throw error
    }
    work.remove()
    await admin.remove()
  }

  private func run(engine: BrowserEngine, viewport: Viewport, work: ScratchWork) async throws {
    try await withPage(engine, gnorium, viewport: viewport) { page in
      try await page.openHydrated(work.path)
      // The sidebar is drawn once, and again in the phone's menu.
      let link = page.locator(".record-sidebar-view a").filter(hasText: "\(work.author) (author)").first
      try await expect(link).toBeAttached()
      let href = try await link.getAttribute("href") ?? ""
      #expect(href.hasPrefix("/biblio-records?voice="), "\(href)")
      #expect(!href.contains(work.recordID), "the key is no id: \(href)")

      try await page.openHydrated(href)
      try await expect(page.locator(".records-count-view")).toHaveText("1 biblio-record")
      try await expect(page.locator(".records-results-view")).toContainText(work.title)
      let filter = page.locator(".filter-bar-view")
      try await expect(filter).toContainText("Voice")
      try await expect(filter.locator(".filter-bar-value-select .dropdown-selected-text")).toHaveText(work.author)
      // The tabs keep it.
      let lexico = try await page.locator("#tab-lexico-records").getAttribute("href") ?? ""
      #expect(lexico.contains("voice="), "\(lexico)")
      let overflow = try await page.evaluate("document.documentElement.scrollWidth > window.innerWidth").bool
      #expect(overflow == false)

      // Cleared as any filter is: every record again.
      try await filter.locator(".filter-bar-value-select .dropdown-trigger").click()
      try await filter.locator(".filter-bar-value-select .dropdown-option").filter(hasText: work.author, exact: true)
        .click()
      try await filter.locator(".filter-bar-apply").click()
      try await expect(page.locator(".records-count-view")).not.toHaveText("1 biblio-record")
      let cleared = try await page.url()
      #expect(cleared.contains("voice=&") || cleared.hasSuffix("voice="), "\(cleared)")

      // No person page.
      let status = try await page.evaluate(
        "fetch('/persons/nobody/unknown/unknown', { redirect: 'manual' }).then((r) => r.status)"
      ).double
      #expect(status == 404)
    }
  }
}
