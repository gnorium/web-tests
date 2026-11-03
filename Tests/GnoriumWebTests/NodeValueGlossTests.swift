import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A read row's value box holds rich text (user, 2026-11-03): drawn as a
/// disabled field is (its ground, border, radius, inset and not-allowed
/// cursor), each term of the value that names a record a gloss trigger, the
/// control an origin sentence's term is: a click opens the record's preview
/// in the gloss sheet (a popover on a wide screen, the sheet on a narrow
/// one), the help cursor over it, never navigating and never opening or
/// closing the row; a click elsewhere in the box opens the row. A value
/// with no link stays plain. A throwaway admin's scratch word, its leaf's
/// `<def>` pointing at a scratch work's record, removed after.
@Suite("Node value gloss", .serialized)
struct NodeValueGlossTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aLinkedTermInAReadValueOpensItsGloss(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let word = try ScratchWord(owner: admin)
    do {
      _ = try TestAdmin.query(
        """
        UPDATE lexico_record_versions
          SET record_json = replace(record_json, '<def>A leaf sense.</def>',
            '<def>A leaf sense, as in <ref target=\\"\(work.path)\\">\(work.title)</ref>.</def>')
          WHERE id = '\(word.versionID)';
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(word.path)
        // The leaf's row: its accordion's <details>, by its UUID.
        let leaf = page.locator("#record-row-\(word.leaf)")
        let box = leaf.locator(".record-node-heading .node-value-box").first
        try await expect(box.locator(".node-value-text:not([data-native])")).toHaveText(
          "A leaf sense, as in \(work.title).")
        // The term, a gloss trigger previewing the work's record.
        let term = box.locator("button[data-gloss-preview]")
        try await expect(term).toHaveCount(1)
        try await expect(term).toHaveText(work.title)
        try await expect(term).toHaveAttribute("data-gloss-preview", "\(work.path)/preview")
        try await expect(term).toHaveAttribute("aria-haspopup", "dialog")
        try await expect(term).toHaveCSS("cursor", "help")
        // A value with no link stays plain.
        let branch = page.locator("#record-row-\(word.branch) .record-node-heading .node-value-box").first
        try await expect(branch.locator(".node-value-text:not([data-native])")).toHaveText("A branch sense.")
        try await expect(branch.locator("button")).toHaveCount(0)
        // The box is a disabled field's (`TextAreaView`'s disabled input):
        // the same ground, border, radius, inset, color, type and cursor.
        let look = try await page.evaluate(
          """
          (() => {
            const box = document.querySelector('#record-row-\(word.leaf) .record-node-heading .node-value-box');
            const probe = document.createElement('div');
            probe.style.cssText = 'background-color: var(--background-color-disabled); '
              + 'border: var(--border-width-base) solid var(--border-color-disabled); '
              + 'border-radius: var(--border-radius-base); padding: var(--spacing-12); color: var(--color-base); '
              + 'font-size: var(--font-size-medium-16); line-height: var(--line-height-small-22); '
              + 'cursor: var(--cursor-not-allowed)';
            document.body.append(probe);
            const keys = ['backgroundColor', 'borderTopColor', 'borderTopWidth', 'borderTopStyle',
              'borderTopLeftRadius', 'paddingTop', 'paddingInlineStart', 'color', 'fontSize', 'lineHeight', 'cursor'];
            const of = (el) => keys.map((k) => getComputedStyle(el)[k]).join('|');
            const look = { box: of(box), field: of(probe) };
            probe.remove();
            return look;
          })()
          """)
        #expect(look["box"].string == look["field"].string, "\(look)")

        try await expect(leaf).toHaveAttribute("data-expanded", "false")
        let sheet = page.locator(".gloss-sheet")
        let wide = try await page.evaluate("innerWidth >= 769").bool == true
        // A click on the term opens its gloss only: the row stays closed,
        // the page where it is.
        try await term.click()
        try await expect(sheet).toHaveAttribute("data-state", "open")
        try await expect(sheet).toHaveAttribute("data-placement", wide ? "popover" : "viewport")
        try await expect(term).toHaveAttribute("aria-expanded", "true")
        try await expect(sheet.locator(".gloss-sheet-title")).toContainText(work.title)
        try await expect(sheet.locator(".gloss-sheet-title a.record-preview-heading")).toHaveAttribute("href", work.path)
        try await expect(leaf).toHaveAttribute("data-expanded", "false")
        #expect(try await page.evaluate("location.pathname").string == word.path)
        if wide {
          let size = try await sheet.evaluate(
            "(sheet) => { const p = sheet.querySelector('.sheet-panel').getBoundingClientRect(); return { width: p.width, height: p.height }; }")
          #expect((size["width"].double ?? 0) >= 320 && (size["height"].double ?? 0) <= 320, "\(size)")
        }
        try await page.keyboard.press("Escape")
        try await expect(sheet).toHaveAttribute("data-state", "closed")
        try await expect(leaf).toHaveAttribute("data-expanded", "false")
        // A click elsewhere in the box opens the row, as before.
        let corner = try await page.evaluate(
          """
          (() => {
            const r = document.querySelector('#record-row-\(word.leaf) .record-node-heading .node-value-box').getBoundingClientRect();
            return { x: r.left + 4, y: r.top + 4 };
          })()
          """)
        try await page.mouse.click(x: corner["x"].double ?? 0, y: corner["y"].double ?? 0)
        try await expect(leaf).toHaveAttribute("data-expanded", "true")
        try await expect(sheet).toHaveAttribute("data-state", "closed")
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      word.remove()
      work.remove()
      try await admin.remove(after: error)
    }
    word.remove()
    work.remove()
    try await admin.remove()
  }
}
