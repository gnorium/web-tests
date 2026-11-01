import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The lexico-record page (SENSES-DESIGN 8.4, W4): a leaf's selected quote is
/// read in its testament—the testament reader (an artifact), fetched as it
/// comes into view, opened at the quote's page with its image off, its Header
/// switch present and off (its document declares a header), its XML switch
/// its own—and the leaf ends with "View
/// all (n)", n its live assigned quotes, leading to the biblio-records'
/// quotes filtered by its UUID, the filter shown in the filter bar. The
/// sidebar counts the sentiments per level, with their marks, as visible
/// text. Phone and desktop: past the screen the page widens, nothing clipped. A throwaway admin
/// owns a scratch work with a permitted testament, a scratch word attested
/// in it and the word's assignment, made by SQL and removed after. Chrome
/// headless.
@Suite("Lexico-record artifacts", .serialized)
struct LexicoRecordArtifactsTests {
  static let service = "https://example.org/iiif/webtests-artifact-p3"

  /// Five pages and a header; the quote on the third, its word the third of
  /// its third line (page 3, line 3, word 3), with an `xml:id` its
  /// assignment names it by.
  static let tei: String = {
    func page(_ number: Int, _ body: String) -> String {
      #"<pb n="\#(number)" facs="https://example.org/iiif/webtests-artifact-p\#(number)/full/1300,/0/default.jpg"/>"#
        + body
    }
    func lines(_ number: Int) -> String {
      (1...10).map { "<s>Page \(number), line \($0).</s><lb/>" }.joined()
    }
    // A header the document declares (`TEIRenderer.declaredHeader`: one
    // that declares its renditions), which the reader's Header switch shows.
    return "<TEI><teiHeader><fileDesc><titleStmt><title>Web tests artifact</title></titleStmt></fileDesc>"
      + #"<encodingDesc><tagsDecl><rendition xml:id="size-1" scheme="css">font-size:1rem</rendition></tagsDecl></encodingDesc>"#
      + "</teiHeader>"
      + "<text><body>"
      + page(1, "<p>\(lines(1))</p>")
      + page(2, "<p>\(lines(2))</p>")
      + page(
        3,
        #"<p><s>Third page, first line.</s><lb/><s>Third page, second line.</s><lb/><s>Here the <w xml:id="webtests-artifact-word">scratchword</w> stands.</s></p>"#)
      + page(4, "<p>\(lines(4))</p>")
      + page(5, "<p>\(lines(5))</p>")
      + "</body></text></TEI>"
  }()

  /// Where it is read: a 320 and a 375 phone, and a desktop; on the
  /// smallest, a leaf five levels deep too.
  enum Width: String, CaseIterable, Sendable, CustomStringConvertible {
    case phone320, phone375, desktop, deepTree320
    var viewport: Viewport {
      switch self {
      case .phone320, .deepTree320: return Viewport(width: 320, height: 700, deviceScaleFactor: 3, touch: true)
      case .phone375: return .phone
      case .desktop: return .desktop
      }
    }
    var isPhone: Bool { self != .desktop }
    var depth: Int { self == .deepTree320 ? 5 : 2 }
    var description: String { rawValue }
  }

  @Test(arguments: [BrowserEngine.chrome], Width.allCases)
  func aLeafReadsItsQuoteAsATestamentArtifact(engine: BrowserEngine, width: Width) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    var testament: ScratchTestament?
    var word: ScratchWord?
    var assignment: ScratchAssignment?
    func clean() async throws {
      assignment?.remove()
      word?.remove()
      testament?.remove()
      try await admin.remove()
    }
    do {
      let scratch = try ScratchTestament(owner: admin, tei: Self.tei)
      testament = scratch
      let scratchWord = try ScratchWord(
        owner: admin,
        anchor: .init(
          recordID: scratch.reading.work.recordID, versionID: scratch.versionID, imageID: Self.service, page: 3,
          line: 3, word: 3, surface: "scratchword"), depth: width.depth)
      word = scratchWord
      assignment = try ScratchAssignment(
        owner: admin, testament: scratch, word: scratchWord, image: Self.service, wordID: "webtests-artifact-word",
        surface: "scratchword", lemma: "scratchword", wordClass: "noun")
      let leaf = scratchWord.leaf.lowercased()
      try await withPage(engine, gnorium, viewport: width.viewport) { page in
        try await page.openHydrated(scratchWord.path)

        let row = page.locator("#record-row-\(scratchWord.leaf)")
        try await page.locator("#record-row-\(scratchWord.leaf) > .accordion-summary").click()
        try await expect(row).toHaveAttribute("data-open-finished", "true")
        let attestation = row.locator(".attestation-view")
        let viewer = attestation.locator(".artifact-view")
        try await expect(viewer).toHaveCount(1)
        // Headed by its Source box, no citation line (user, 2026-11-01).
        try await expect(attestation.locator(".attestation-quote > .quote-source-view")).toHaveCount(1)
        try await expect(attestation.locator(".attestation-quote > .chicago-citation-view")).toHaveCount(0)
        // Opened at the quote's page, the quote highlighted.
        try await expect(
          attestation.locator(".tei-page[data-service-id='\(Self.service)'] mark[data-highlight='title']")
        ).toHaveText("scratchword")
        // Its image off at first.
        try await expect(viewer.locator(".artifact-canvas-toggle button")).toHaveAttribute("aria-pressed", "false")
        // Its Header switch present, off at first.
        try await expect(viewer.locator(".artifact-header-toggle")).toHaveCount(1)
        try await expect(viewer).toHaveAttribute("data-header", "false")
        // Its footer one row, never scrolling on its own, the viewer as wide
        // as it; past the screen the page widens, nothing clipped.
        let footer = try await viewer.evaluate(
          """
          (v) => { const f = v.querySelector('.artifact-footer');
            const items = [...f.children].filter((c) => c.getClientRects().length > 0);
            const top = items[0].getBoundingClientRect().top;
            return [items.every((c) => Math.abs(c.getBoundingClientRect().top - top) < 2),
              f.scrollWidth <= f.clientWidth + 1, v.getBoundingClientRect().width + 1 >= f.scrollWidth,
              !!v.closest('.outliner-scroll'), Math.round(v.getBoundingClientRect().width)].join(' '); }
          """
        ).string ?? ""
        #expect(footer.hasPrefix("true true true"), "the footer one row, the viewer as wide: \(footer)")

        // Its XML switch is its own (a sentiment's value is its header, no
        // box of its own to switch: 2026-10-28).
        try await viewer.locator(".artifact-xml-toggle button").click()
        try await expect(viewer).toHaveAttribute("data-raw", "true")
        try await viewer.locator(".artifact-xml-toggle button").click()
        try await expect(viewer).toHaveAttribute("data-raw", "false")
        // The Header and XML switches are exclusive: the header on, the
        // XML off.
        try await viewer.locator(".artifact-header-toggle button").click()
        try await expect(viewer).toHaveAttribute("data-header", "true")
        try await expect(viewer).toHaveAttribute("data-raw", "false")

        // After the leaf's quotes, "View all (1)" to its quotes.
        let all = row.locator(".sentiment-quotes-link")
        try await expect(all).toHaveText("View all (1)")
        try await expect(all).toHaveAttribute("href", "/biblio-records/quotes?sentiment=\(leaf)")
        try await page.expectArtifactsUnclipped()
        try await page.expectNoErrors()

        // The quotes page, filtered by the sentiment: the filter in its bar,
        // its one quote read in its testament.
        try await all.click()
        try await expect(page).toHaveURL("/biblio-records/quotes?sentiment=\(leaf)")
        try await expect(page.locator(".quotes-content input[name='sentiment']")).toHaveValue(leaf)
        try await expect(page.locator(".quotes-count")).toHaveText("1 quote")
        let quote = page.locator(".quotes-content .attestation-view")
        try await expect(quote).toHaveCount(1)
        _ = try await quote.evaluate("(el) => { el.scrollIntoView({ block: 'center' }); return true }")
        try await expect(quote.locator(".artifact-view")).toHaveCount(1)
        try await expect(quote.locator("mark[data-highlight='title']").first).toHaveText("scratchword")
        try await page.expectArtifactsUnclipped()
        try await page.expectNoErrors()

        // Its sentiments counted per level in the record's sidebar, as text:
        // both explicated, a disc beside the count; no single level.
        try await page.openHydrated(scratchWord.path)
        if width.isPhone {
          try await page.locator("[aria-label='Open menu']").filter(visible: true).first.click()
        }
        let counts = page.locator(".record-sidebar-view .record-level-counts-view").filter(visible: true).first
        try await expect(counts).toBeVisible()
        try await expect(counts.locator(".record-level-counts-level")).toHaveTexts(["\(width.depth) explicated"])
        try await expect(counts.locator(".record-level-counts-level .icon-view")).toHaveCount(1)
        try await expect(page.locator(".record-sidebar-view .record-level-view")).toHaveCount(0)
        try await page.expectArtifactsUnclipped()
      }
    } catch {
      do { try await clean() } catch let removal {
        throw WebTestError("\(error)\n…and cleaning up failed too: \(removal)")
      }
      throw error
    }
    try await clean()
  }
}
