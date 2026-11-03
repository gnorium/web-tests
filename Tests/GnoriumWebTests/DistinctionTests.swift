import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A sentiment's distinction (user, 2026-09-27): its explication's
/// `<note type="usage" subtype="distinction">` is plain prose in its
/// definition's box, under its label and above its Metadata (user,
/// 2026-10-10, `SentimentDefinitionView`), its quotes below, rendered
/// once (its <sense> under Verbose holds its XML), with no heading; a pointer to another
/// sentiment reads as its number. A throwaway admin owns
/// a scratch word made by SQL and removed after.
@Suite("Distinction", .serialized)
struct DistinctionTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aSentimentsDistinctionStandsAboveItsQuotes(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    // Its quote is in a scratch testament (`QuoteTests`).
    let testament = try ScratchTestament(owner: admin, tei: QuoteTests.tei)
    let word = try ScratchWord(
      owner: admin, distinction: "Unlike sense {branch}, a leaf sense grows no further senses.",
      anchor: .init(
        recordID: testament.reading.work.recordID, versionID: testament.versionID,
        imageID: "https://example.org/iiif/webtests-p3", page: 3, line: 3, word: 3, surface: "scratchword"))
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(word.path)
        // The leaf's row opens into its Metadata, its note and quotes.
        let row = page.locator("#record-row-\(word.leaf)")
        try await page.locator("#record-row-\(word.leaf)-fold").click()
        try await expect(row).toHaveAttribute("data-open-finished", "true")
        // Its one Note, frozen, under its Metadata (user, 2026-11-02).
        let note = row.locator(".note-field-view textarea")
        try await expect(note).toHaveCount(1)
        try await expect(note).toHaveValue("Unlike sense 1, a leaf sense grows no further senses.")
        try await expect(note).toBeDisabled()
        // Rendered once on the page: not in the Metadata or elsewhere; the
        // header's <sense>, shown only under Verbose, holds it only as XML.
        let rendered = try await page.evaluate(
          """
          (() => { const main = document.querySelector('main').cloneNode(true);
            main.querySelectorAll('.sentiment-sense-xml').forEach(e => e.remove());
            return main.textContent.split('grows no further senses').length - 1; })()
          """, as: Int.self)
        #expect(rendered == 1)
        try await expect(page.locator("main")).not.toContainText("Distinction")

        let metadata = try #require(try await page.locator("#record-metadata-s-1-1").boundingBox())
        let prose = try #require(try await note.boundingBox())
        let quote = try #require(try await row.locator(".attestation-view").boundingBox())
        // Metadata › Note, then the quote (user, 2026-11-02).
        #expect(metadata.y + metadata.height <= prose.y)
        #expect(prose.y + prose.height <= quote.y)

        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      word.remove()
      testament.remove()
      try await admin.remove(after: error)
    }
    word.remove()
    testament.remove()
    try await admin.remove()
  }
}
