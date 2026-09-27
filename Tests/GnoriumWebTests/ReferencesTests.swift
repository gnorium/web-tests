import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A record page's references (user, 2026-09-27): no mark anywhere in the
/// page's prose, headings or labels; the References accordion at the page's
/// end, closed until opened, lists each place once, linked, with where it is
/// served from, never the facts it supports; nothing scrolls
/// sideways. A throwaway admin owns a scratch work whose hallmark carries
/// attributions, and a scratch word with research references, made by SQL
/// and removed after.
@Suite("References", .serialized)
struct ReferencesTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWorksReferencesAreListedAtItsEnd(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin, references: true)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(work.path)
        try await expect(page.locator(".reference-mark, .reference-marks-view")).toHaveCount(0)
        try await expect(page.locator("a[href^='#reference-']")).toHaveCount(0)

        let accordion = page.locator("#record-references")
        try await expect(accordion).not.toHaveAttribute("open")
        try await page.locator("#record-references > .accordion-summary").click()
        try await expect(accordion).toHaveAttribute("data-open-finished", "true")

        // In the page's order: the catalogue page (the language, the title
        // and the copy's credit line), the title's second page, the
        // edition's.
        let entries = page.locator("#references .references-view-entry")
        try await expect(entries).toHaveCount(3)
        let catalogue = entries.nth(0)
        try await expect(catalogue.locator(".references-view-place a"))
          .toHaveAttribute("href", "https://catalogue.example.org/web-tests")
        try await expect(catalogue.locator(".references-view-source")).toHaveText("catalogue.example.org")
        // Quoted three ways: just its place.
        try await expect(catalogue.locator(".references-view-quote")).toHaveCount(0)
        try await expect(entries.nth(1).locator(".references-view-place a"))
          .toHaveAttribute("href", "https://titles.example.org/web-tests")
        // No line naming the facts a place supports.
        try await expect(page.locator("#references")).not.toContainText("Supports")
        try await expect(entries.nth(2).locator(".references-view-quote")).toHaveText("First edition")
        // Plain: no numbers, arrows or letters.
        #expect(!(try await page.locator("#references").textContent()).contains("↑"))

        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      work.remove()
      await admin.remove()
      throw error
    }
    work.remove()
    await admin.remove()
  }

  /// A lexico-record: nothing beside a sentiment's definition in its row's
  /// heading, or beside the title; its references are listed at its end.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWordsReferencesAreListedAtItsEnd(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(word.path)
        try await expect(page.locator(".reference-mark, .reference-marks-view")).toHaveCount(0)
        try await expect(page.locator("#record-row-s-1-1 .record-row-title sup")).toHaveCount(0)

        try await page.locator("#record-references > .accordion-summary").click()
        try await expect(page.locator("#record-references")).toHaveAttribute("data-open-finished", "true")
        let entries = page.locator("#references .references-view-entry")
        try await expect(entries).toHaveCount(2)
        try await expect(entries.nth(0).locator(".references-view-place a")).toContainText("Web tests dictionary")
        try await expect(page.locator("#references")).not.toContainText("Supports")
        try await expect(entries.nth(1).locator(".references-view-place a")).toContainText("Web tests senses")
        try await expect(entries.nth(1).locator(".references-view-source")).toHaveText("senses.example.org")
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      word.remove()
      await admin.remove()
      throw error
    }
    word.remove()
    await admin.remove()
  }
}
