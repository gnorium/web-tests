import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A testament's reader is headed by the work it witnesses (user,
/// 2026-10-08): its full title, semibold, and on a line under it "by" the
/// names of all its voices—a translator's too, as the record's address lists
/// them (user, 2026-10-09)—in the subtle color, in sight however long the
/// title; the semblance's label in the footer. On every reader—the record
/// page's and a Disputorium object's alike.
///
/// The title fades where it runs past the header, and its fade opens it
/// whole in a sheet over the reader (`data-edge-fade="sheet"`), at every
/// width: wrapped at its spaces, never a word broken, announced as a dialog,
/// its close button focused, closed by Esc or the button with the focus back
/// on the title. Wrapped in place, a phone's header made it a column a word
/// wide that covered the reader. A throwaway admin owns a scratch work with a
/// permitted testament, made by SQL and removed after.
@Suite("Reader title", .serialized)
struct ReaderTitleTests {
  static let service = "https://example.org/iiif/webtests-title"
  static let tei = """
    <TEI><text><body><pb n="1" facs="\(service)/full/1300,/0/default.jpg"/>\
    <p><s><w>The</w> <w>title</w> <w>page</w><pc>.</pc></s></p>\
    </body></text></TEI>
    """
  /// Long enough to run past the header at any width.
  static let longTitle =
    "A Discourse Concerning the Original and Progress of Satire, Addressed to the Right Honourable Charles Earl of Dorset and Middlesex, Lord Chamberlain of His Majesty's Household, Knight of the Most Noble Order of the Garter, Together with Translations of Juvenal and Persius"
  /// A voice in no author's role: named in the byline all the same.
  static let translator = "Web Tests Translator"

  struct Header: Decodable {
    let title: String
    let byline: String
    let mode: String
    let overflowing: Bool
    /// Whether the byline's line begins in sight: inside the header's
    /// block, its first words clear of the fade. A long title before it on
    /// one line faded it out entirely.
    let bylineInSight: Bool
  }

  static func header(_ page: Page) async throws -> Header {
    try await page.evaluate(
      """
      (() => {
        const view = document.querySelector('.artifact-view')
        const block = view.querySelector('.artifact-title-block')
        return {
          title: view.querySelector('.artifact-title-primary').textContent.trim(),
          byline: (view.querySelector('.artifact-title-subtitle')?.textContent ?? '').trim(),
          mode: block.getAttribute('data-edge-fade'),
          overflowing: block.getAttribute('data-overflowing') === 'true',
          bylineInSight: (() => {
            const by = view.querySelector('.artifact-title-subtitle')
            if (!by) return false
            const range = document.createRange()
            range.selectNodeContents(by)
            const b = block.getBoundingClientRect(), r = range.getBoundingClientRect()
            return r.height > 0 && r.top >= b.top - 1 && r.bottom <= b.bottom + 1
              && r.left >= b.left - 1 && r.left + 48 <= b.right - 32
          })(),
        }
      })()
      """, as: Header.self)
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func theTitleHeadsTheReaderAndItsFadeOpensASheet(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    var testament: ScratchTestament?
    func clean() async throws {
      testament?.remove()
      try await admin.remove()
    }
    do {
      let scratch = try ScratchTestament(owner: admin, tei: Self.tei)
      testament = scratch
      let work = scratch.reading.work
      _ = try TestAdmin.query(
        """
        UPDATE biblio_record_versions
          SET metadata_json = jsonb_set(
            jsonb_set(metadata_json::jsonb, '{title}', '"\(Self.longTitle.replacingOccurrences(of: "'", with: "''"))"'),
            '{voices}', '[{"name": "\(work.author)", "role": "author"}, {"name": "\(Self.translator)", "role": "translator"}]')::text
          WHERE id = '\(scratch.versionID)';
        """)
      let byline = "by \(work.author) and \(Self.translator)"
      let viewport = layout.viewport(for: engine)
      try await withPage(engine, gnorium, viewport: viewport) { page in
        // A Disputorium object's reader: the work as its record stands
        // (the scratch testament's version, the latest).
        try await page.openHydrated(scratch.reading.path)
        try await expect(page.locator(".artifact-view .artifact-title-primary").first).toHaveText(Self.longTitle)
        try await expect(page.locator(".artifact-view .artifact-title-subtitle").first).toHaveText(byline)
        #expect(try await Self.header(page).bylineInSight, "the byline is faded out of sight")
        try await expect(page.locator(".artifact-view .artifact-title-subtitle").first)
          .toHaveCSS("color", try await page.locator(".artifact-view .artifact-canvas-label").first.evaluate(
            "(el) => getComputedStyle(el).color").string ?? "")

        // The record page's reader, fetched into its row.
        try await page.openHydrated(work.path)
        _ = try await page.evaluate(
          """
          (() => { document.querySelector("[data-reader-url*='\(scratch.versionID)' i]").closest('.record-row')
            .querySelector(':scope > .accordion-details > .accordion-summary').click(); return true; })()
          """)
        let view = page.locator(".artifact-view").first
        try await expect(view.locator(".artifact-title-primary")).toHaveText(Self.longTitle)
        try await expect(view.locator(".artifact-title-block")).toHaveAttribute("data-overflowing", "true")
        let header = try await Self.header(page)
        #expect(header.mode == "sheet")
        #expect(header.byline == byline)
        #expect(header.bylineInSight, "the byline is faded out of sight")
        // The canvas label's place: the footer's start, before the pager.
        let order = try await view.evaluate(
          """
          (el) => [...el.querySelector('.artifact-footer').children].map((c) => c.className.split(' ')[0])
          """)
        #expect(order.jsonText.contains("artifact-canvas-label"), "the footer has no canvas label: \(order)")

        // The fade's tail opens the sheet over the reader.
        let block = view.locator(".artifact-title-block")
        // Its fade's tail, where it stands now (a focus scrolls the page).
        func tapTail() async throws {
          let box = try await block.evaluate(
            """
            (el) => { el.scrollIntoView({ block: 'center' });
              const r = el.getBoundingClientRect(); return [r.right - 6, r.top + r.height / 2] }
            """)
          let point = box.array ?? []
          let x = point.first?.double ?? 0
          let y = point.last?.double ?? 0
          if viewport.touch {
            try await page.driver.tap(x: x, y: y)
          } else {
            try await page.mouse.click(x: x, y: y)
          }
        }
        try await tapTail()
        let sheet = view.locator(".edge-fade-sheet")
        try await expect(sheet).toHaveAttribute("data-state", "open")
        // Wrapped in place, never: the header keeps its one row.
        try await expect(block).not.toHaveAttribute("data-edge-fade-expanded", "true")
        let dialog = sheet.locator("[role='dialog']")
        try await expect(dialog).toHaveAttribute("aria-modal", "true")
        try await expect(dialog).toHaveAttribute("aria-label", "\(Self.longTitle) \(byline)")
        let title = sheet.locator(".dialog-sheet-title")
        try await expect(title).toHaveText("\(Self.longTitle) \(byline)")
        try await expect(title.locator("[id]")).toHaveCount(0)
        try await expect(sheet.locator(".dialog-sheet-close")).toBeFocused()
        // Over the whole reader, wrapped as prose: many lines, each wider
        // than a word, no word broken.
        let layoutReport = try await view.evaluate(
          """
          async (el) => {
            await new Promise((r) => setTimeout(r, 400));
            const v = el.getBoundingClientRect(), p = el.querySelector('.edge-fade-sheet .sheet-panel').getBoundingClientRect();
            const t = el.querySelector('.edge-fade-sheet .dialog-sheet-title');
            const s = getComputedStyle(t);
            return {
              covers: Math.abs(p.top - v.top) <= 1 && Math.abs(p.height - el.clientHeight) <= 1,
              width: t.getBoundingClientRect().width,
              room: p.width - 120,
              lines: Math.round(t.getBoundingClientRect().height / parseFloat(s.lineHeight)),
              wrap: s.overflowWrap,
              wordBreak: s.wordBreak,
            }
          }
          """)
        let report = layoutReport.object ?? [:]
        #expect(report["covers"]?.bool == true, "the sheet does not cover the reader: \(layoutReport)")
        // The panel's width, its padding and close button aside.
        #expect((report["width"]?.double ?? 0) >= (report["room"]?.double ?? 0), "the sheet's title is a narrow column: \(layoutReport)")
        #expect((report["lines"]?.double ?? 0) >= 2, "the sheet's title is not wrapped: \(layoutReport)")
        #expect(report["wrap"]?.string != "anywhere", "the sheet's title breaks anywhere: \(layoutReport)")
        #expect(report["wordBreak"]?.string != "break-all", "the sheet's title breaks words: \(layoutReport)")
        if let folder = ProcessInfo.processInfo.environment["READER_TITLE_SCREENSHOTS"] {
          _ = try await view.evaluate("(el) => el.scrollIntoView({ block: 'end' })")
          try await page.screenshot(
            to: URL(fileURLWithPath: folder).appendingPathComponent("title-sheet-\(layout == .phone ? 375 : 1400).png"))
        }

        // Esc closes it; the title has the focus again.
        try await page.keyboard.press("Escape")
        try await expect(sheet).toHaveAttribute("data-state", "closed")
        try await expect(block).toBeFocused()

        // Again, and closed by its button.
        try await tapTail()
        try await expect(sheet).toHaveAttribute("data-state", "open")
        try await sheet.locator(".dialog-sheet-close").click()
        try await expect(sheet).toHaveAttribute("data-state", "closed")
        try await expect(block).toBeFocused()
        try await page.expectNoHorizontalOverflow()
      }
      try await clean()
    } catch {
      try? await clean()
      throw error
    }
  }
}
