import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A voice is a SENTIMENT (user, 2026-09-29): a work's author is the
/// sentiment of a proper-noun lexico-record that is them. A record page's
/// sidebar lists its Voices, a linked one a link to that sentiment on its
/// record's page, which lists the sentiment's Works by role ("Authored"),
/// each linked back. The records lists no longer filter by a voice (user,
/// 2026-10-03): the sidebar's Author search finds one. There are no person
/// pages. A throwaway admin owns a scratch work, removed after.
@Suite("Voice filter", .serialized)
struct VoiceFilterTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aVoiceIsASentimentThatListsItsWorks(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin, linked: true)
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
      // The sidebar is drawn once, and again in the phone's menu.
      let link = page.locator(".record-sidebar-view a").filter(hasText: "\(work.author) (author)").first
      try await expect(link).toBeAttached()
      let href = try await link.getAttribute("href") ?? ""
      #expect(href == "\(work.referentPath)#\(work.sentimentID)", "\(href)")

      // The sentiment on its record's page: its definition, and its Works.
      try await page.openHydrated(work.referentPath)
      let works = page.locator(".sentiment-view-works")
      try await expect(works).toContainText("Works")
      try await expect(works).toContainText("Authored")
      let back = works.locator("a").filter(hasText: work.title)
      try await expect(back).toHaveAttribute("href", work.path)
      try await expect(page.locator(".record-row-view").first).toContainText("A person (AD 1901 – AD 1971).")
      var overflow = try await page.evaluate("document.documentElement.scrollWidth > window.innerWidth").bool
      #expect(overflow == false)

      // The records lists filter by no voice (user, 2026-10-03): the
      // sidebar's Author search finds one. The bar offers no Voice field.
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
