import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A record page's references: a mark beside a field's label jumps to its
/// entry at the page's end, the same reference is the same mark wherever it
/// is cited, and the entry links back to each mark as Wikipedia's Notes do
/// ("↑" for one, "↑ a b c" for several), in a References accordion that
/// following a mark opens, opening the closed accordions on
/// the way (a row, its Metadata); adjacent marks never take each other's
/// pointer; a page opened at a mark opens its way to it; nothing scrolls
/// sideways. A
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
      // An accordion framed as the Metadata one is, and closed as it is.
      let accordion = page.locator("#record-references")
      try await expect(accordion).not.toHaveAttribute("open")
      try await expect(references.locator("#reference-1")).toBeHidden()
      try await page.locator("#record-references > .accordion-summary").click()
      try await expect(accordion).toHaveAttribute("data-open-finished", "true")
      // Numbered in the page's order: the catalogue page the language, the
      // title and the manifest cite, the title's second page, the edition's.
      try await expect(references.locator(".references-view-entry")).toHaveCount(3)
      // Wikipedia's Notes: the catalogue page, cited three times, reads
      // "↑ a b c", the arrow no link and a letter back to each mark in page
      // order; an entry cited once is one "↑" link back to its mark.
      let catalogue = references.locator("#reference-1")
      try await expect(catalogue.locator("a.references-view-arrow")).toHaveCount(0)
      try await expect(catalogue.locator("span.references-view-arrow")).toHaveText("↑")
      try await expect(catalogue.locator(".references-view-letter")).toHaveCount(3)
      for letter in ["a", "b", "c"] {
        try await expect(catalogue.locator(".references-view-letter[href='#reference-1-\(letter)']"))
          .toHaveText(letter)
      }
      for number in [2, 3] {
        let arrow = references.locator("#reference-\(number) .references-view-back-link")
        try await expect(arrow).toHaveCount(1)
        try await expect(arrow).toHaveText("↑")
        try await expect(arrow).toHaveAttribute("href", "#reference-\(number)-mark")
      }
      // Small italic superscript letters in the link color.
      let letterStyle = try await catalogue.locator(".references-view-letter[href='#reference-1-a']").evaluate(
        "(el) => { const s = getComputedStyle(el); return s.fontStyle + ' ' + s.color + ' ' + parseFloat(s.fontSize) }"
      ).string ?? ""
      #expect(letterStyle.hasPrefix("italic "))
      #expect(letterStyle.hasSuffix(" 12"))
      // The catalogue page is quoted three ways, so it is just its place;
      // the others are quoted once.
      try await expect(catalogue.locator(".references-view-quote")).toHaveCount(0)
      try await expect(references.locator("#reference-2 .references-view-quote")).toHaveCount(1)

      // Letter a leads into the closed Metadata to the language's mark.
      let languageMark = page.locator("#reference-1-a")
      try await expect(languageMark).toBeHidden()
      try await catalogue.locator(".references-view-letter[href='#reference-1-a']").click()
      try await expect(languageMark).toBeVisible()
      try await inViewport(languageMark)
      try await expect(languageMark).toBeFocused()
      try await expect(page).toHaveURL("#reference-1-a", where: { $0.fragment == "reference-1-a" })
      try await expect(page.locator("#record-metadata")).toHaveAttribute("data-open-finished", "true")

      // Letter b, to the title's mark; every mark reads [N].
      let titleMark = page.locator("#reference-1-b")
      try await catalogue.locator(".references-view-letter[href='#reference-1-b']").click()
      try await inViewport(titleMark)
      try await expect(titleMark).toBeFocused()
      try await expect(titleMark).toHaveText("[1]")
      try await expect(page).toHaveURL("#reference-1-b", where: { $0.fragment == "reference-1-b" })

      // The title's two marks stand side by side, "[1][2]": each one's
      // target is its own, never its neighbor's.
      try await expect(page.locator("#reference-2-mark")).toHaveText("[2]")
      try await expectOwnTargets(page, ["reference-1-b", "reference-2-mark"])

      // A mark goes to its entry, which has no highlight of its own.
      try await titleMark.click()
      try await expect(page).toHaveURL("#reference-1", where: { $0.fragment == "reference-1" })
      try await inViewport(catalogue)
      let background = try await catalogue.evaluate("(el) => getComputedStyle(el).backgroundColor").string
      #expect(background == "rgba(0, 0, 0, 0)")

      // Letter c leads back into the manifest's closed row and its closed
      // Metadata, both opened on the way.
      let manifestMark = page.locator("#reference-1-c")
      try await expect(manifestMark).toBeHidden()
      try await catalogue.locator(".references-view-letter[href='#reference-1-c']").click()
      try await expect(manifestMark).toBeVisible()
      try await inViewport(manifestMark)
      try await expect(manifestMark).toBeFocused()
      try await expect(page).toHaveURL("#reference-1-c", where: { $0.fragment == "reference-1-c" })

      // The edition's single "↑" returns to its only mark.
      try await references.locator("#reference-3 .references-view-back-link").click()
      try await inViewport(page.locator("#reference-3-mark"))
      try await expect(page.locator("#reference-3-mark")).toBeFocused()

      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()

      // Opened at a mark, from elsewhere: the way to it opens by itself.
      try await page.openHydrated("/biblio-records")
      try await page.openHydrated(work.path + "#reference-1-c")
      try await expect(page.locator("#reference-1-c")).toBeVisible()
      try await inViewport(page.locator("#reference-1-c"))
    }
  }

  /// Adjacent marks: the element under the pointer, across each mark's own
  /// box and above and below it, is that mark and never its neighbor.
  private func expectOwnTargets(_ page: Page, _ ids: [String], file: String = #fileID, line: Int = #line)
    async throws
  {
    let list = ids.map { "'\($0)'" }.joined(separator: ",")
    let misses = try await page.evaluate(
      """
      (() => {
        const misses = [];
        for (const id of [\(list)]) {
          const r = document.getElementById(id).getBoundingClientRect();
          for (let x = Math.ceil(r.left) + 1; x < r.right - 1; x += 1) {
            for (const y of [r.top + r.height / 2, r.top - 8, r.bottom + 8]) {
              const hit = document.elementFromPoint(x, y)?.closest('.reference-mark');
              if (!hit || hit.id !== id) misses.push(id + ' at ' + Math.round(x) + ',' + Math.round(y) + ': ' + (hit ? hit.id : 'none'));
            }
          }
        }
        return misses.join('; ');
      })()
      """
    ).string ?? "no answer"
    if !misses.isEmpty { throw WebTestError("\(file):\(line): a mark's target is not its own: \(misses)") }
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
        let mark = page.locator("#reference-2-mark")
        try await expect(mark).toBeVisible()
        // The References accordion is closed; following the mark opens it.
        try await expect(page.locator("#reference-2")).toBeHidden()
        try await mark.click()
        try await expect(page.locator("#record-references")).toHaveAttribute("data-open-finished", "true")
        try await expect(page).toHaveURL("#reference-2", where: { $0.fragment == "reference-2" })
        try await inViewport(page.locator("#reference-2"))
        try await Task.sleep(for: .milliseconds(600))
        try await expect(row).not.toHaveAttribute("open")

        let titleMark = page.locator("#reference-1-mark")
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
