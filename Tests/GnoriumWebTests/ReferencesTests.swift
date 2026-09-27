import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A record page's references: a mark beside a field's label jumps to its
/// entry at the page's end, and the entry's back-link returns to the mark,
/// opening the closed accordions on the way (a row, its Metadata); a page
/// opened at a mark opens its way to it; nothing scrolls sideways. A
/// throwaway admin owns a scratch work whose hallmark carries attributions,
/// made by SQL and removed after.
@Suite("References", .serialized)
struct ReferencesTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func marksAndBackLinks(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin, references: true)
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
      let references = page.locator("#references")
      // Numbered in the page's order: the catalogue page the language and
      // the title cite, the edition's, the manifest's.
      try await expect(references.locator(".references-view-entry")).toHaveCount(3)
      try await expect(references.locator("#reference-1 .references-view-back-link")).toHaveCount(2)
      try await expect(references.locator("#reference-3 .references-view-back-link")).toHaveText("↑")

      // The work's mark, in its Metadata: opened, the mark goes to its entry.
      try await page.locator("#record-metadata > .accordion-summary").click()
      // Opened all the way: an accordion still growing moves what is below it.
      try await expect(page.locator("#record-metadata")).toHaveAttribute("data-open-finished", "true")
      let mark = page.locator("#reference-1-a")
      try await expect(mark).toBeVisible()
      try await expect(mark).toHaveText("[1]")
      try await mark.click()
      try await expect(page).toHaveURL("#reference-1", where: { $0.fragment == "reference-1" })
      try await inViewport(page.locator("#reference-1"))

      // The manifest's entry leads back into its closed row and its closed
      // Metadata, both opened on the way.
      let manifestMark = page.locator("#reference-3-a")
      try await expect(manifestMark).toBeHidden()
      try await references.locator("#reference-3 .references-view-back-link").click()
      try await expect(manifestMark).toBeVisible()
      try await inViewport(manifestMark)
      try await expect(manifestMark).toBeFocused()
      try await expect(page).toHaveURL("#reference-3-a", where: { $0.fragment == "reference-3-a" })

      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()

      // Opened at the mark, from elsewhere: the way to it opens by itself.
      try await page.openHydrated("/biblio-records")
      try await page.openHydrated(work.path + "#reference-3-a")
      try await expect(page.locator("#reference-3-a")).toBeVisible()
      try await inViewport(page.locator("#reference-3-a"))
    }
  }

  /// A lexico-record: a mark beside a sentiment's definition, in its row's
  /// heading, goes to its entry and never opens or closes the row; the
  /// record's own entry leads back into the closed root Metadata.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func sentimentHeadingMarks(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(word.path)
        let row = page.locator("#record-row-s-1-1")
        try await expect(row).not.toHaveAttribute("open")
        let mark = page.locator("#reference-2-a")
        try await expect(mark).toBeVisible()
        try await mark.click()
        try await expect(page).toHaveURL("#reference-2", where: { $0.fragment == "reference-2" })
        try await inViewport(page.locator("#reference-2"))
        try await Task.sleep(for: .milliseconds(600))
        try await expect(row).not.toHaveAttribute("open")

        let titleMark = page.locator("#reference-1-a")
        try await expect(titleMark).toBeHidden()
        try await page.locator("#reference-1 .references-view-back-link").click()
        try await expect(titleMark).toBeVisible()
        try await inViewport(titleMark)
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

  /// The element within the viewport, once scrolling has settled.
  private func inViewport(_ locator: Locator, file: String = #fileID, line: Int = #line) async throws {
    for _ in 0..<50 {
      let within = try await locator.evaluate(
        "(el) => { const r = el.getBoundingClientRect(); return r.bottom > 0 && r.top < innerHeight && r.height > 0 }"
      ).bool ?? false
      if within { return }
      try await Task.sleep(for: .milliseconds(100))
    }
    throw WebTestError("\(file):\(line): the element is not within the viewport.")
  }
}
