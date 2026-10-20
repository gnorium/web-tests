import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The lexico-record page (SENSES-DESIGN 8.4, W4): a leaf's selected quote is
/// read in its testament—the testament reader (an artifact), fetched as it
/// comes into view, opened at the quote's page with its image off, its Header
/// switch present and off, its XML switch its own (the record's definition
/// boxes keep theirs: neither follows the other)—and the leaf ends with "View
/// all (n)", n its live assigned quotes, leading to the biblio-records'
/// quotes filtered by its UUID, the filter shown in the filter bar. The
/// sidebar counts the sentiments per level, with their marks, as visible
/// text. Phone and desktop, nothing scrolling sideways. A throwaway admin
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
    return "<TEI><teiHeader><fileDesc><titleStmt><title>Web tests artifact</title></titleStmt></fileDesc></teiHeader>"
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

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aLeafReadsItsQuoteAsATestamentArtifact(engine: BrowserEngine, layout: Layout) async throws {
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
          line: 3, word: 3, surface: "scratchword"))
      word = scratchWord
      assignment = try ScratchAssignment(
        owner: admin, testament: scratch, word: scratchWord, image: Self.service, wordID: "webtests-artifact-word",
        surface: "scratchword", lemma: "scratchword", wordClass: "noun")
      let leaf = scratchWord.leaf.lowercased()
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(scratchWord.path)

        let row = page.locator("#record-row-\(scratchWord.leaf)")
        try await page.locator("#record-row-\(scratchWord.leaf) > .accordion-summary").click()
        try await expect(row).toHaveAttribute("data-open-finished", "true")
        let attestation = row.locator(".attestation-view")
        let viewer = attestation.locator(".artifact-view")
        try await expect(viewer).toHaveCount(1)
        // Headed by its testament's Chicago note.
        try await expect(attestation.locator(".attestation-quote > .chicago-citation-view")).toHaveCount(1)
        // Opened at the quote's page, the quote highlighted.
        try await expect(
          attestation.locator(".tei-page[data-service-id='\(Self.service)'] mark[data-highlight='title']")
        ).toHaveText("scratchword")
        // Its image off at first.
        try await expect(viewer.locator(".artifact-canvas-toggle button")).toHaveAttribute("aria-pressed", "false")
        // Its Header switch present, off at first.
        try await expect(viewer.locator(".artifact-header-toggle")).toHaveCount(1)
        try await expect(viewer).toHaveAttribute("data-header", "false")

        // Its XML switch is its own: the definition box keeps its rendering.
        let definition = row.locator(".sentiment-definition-view").first
        try await expect(definition).toHaveAttribute("data-raw", "false")
        try await viewer.locator(".artifact-xml-toggle button").click()
        try await expect(viewer).toHaveAttribute("data-raw", "true")
        try await expect(definition).toHaveAttribute("data-raw", "false")
        // And the definition's XML switch leaves the artifact as it is.
        try await viewer.locator(".artifact-xml-toggle button").click()
        try await expect(viewer).toHaveAttribute("data-raw", "false")
        try await definition.locator(".sentiment-definition-xml-toggle button").click()
        try await expect(definition).toHaveAttribute("data-raw", "true")
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
        try await page.expectNoHorizontalOverflow()
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
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()

        // Its sentiments counted per level in the record's sidebar, as text:
        // both explicated, a disc beside the count; no single level.
        try await page.openHydrated(scratchWord.path)
        if layout == .phone {
          try await page.locator("[aria-label='Open menu']").filter(visible: true).first.click()
        }
        let counts = page.locator(".record-sidebar-view .record-level-counts-view").filter(visible: true).first
        try await expect(counts).toBeVisible()
        try await expect(counts.locator(".record-level-counts-level")).toHaveTexts(["2 explicated"])
        try await expect(counts.locator(".record-level-counts-level .icon-view")).toHaveCount(1)
        try await expect(page.locator(".record-sidebar-view .record-level-view")).toHaveCount(0)
        try await page.expectNoHorizontalOverflow()
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
