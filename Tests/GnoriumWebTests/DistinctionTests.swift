import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A sentiment's distinction (user, 2026-09-27): its explication's
/// `<note type="usage" subtype="distinction">` is plain prose in its
/// definition's box, under its label and above its Metadata (user,
/// 2026-10-10, `SentimentDefinitionView`), its quotations below, rendered
/// once (the box's Raw holds its XML), with no heading; a pointer to another
/// sentiment reads as its number. A throwaway admin owns
/// a scratch word made by SQL and removed after.
@Suite("Distinction", .serialized)
struct DistinctionTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aSentimentsDistinctionStandsAboveItsQuotations(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    // Its quotation is in a scratch testament (`QuotationTests`).
    let testament = try ScratchTestament(owner: admin, tei: QuotationTests.tei)
    let word = try ScratchWord(
      owner: admin, distinction: "Unlike sense {branch}, a leaf sense grows no further senses.",
      anchor: .init(
        recordID: testament.reading.work.recordID, versionID: testament.versionID,
        resemblanceID: "https://example.org/iiif/webtests-p3", page: 3, line: 3, word: 3, surface: "scratchword"))
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(word.path)
        // The leaf's row opens into its Metadata, its notes and quotations.
        let row = page.locator("#record-row-\(word.leaf)")
        try await page.locator("#record-row-\(word.leaf) > .accordion-summary").click()
        try await expect(row).toHaveAttribute("data-open-finished", "true")
        let note = row.locator(".lexicographic-explication-note-text")
        try await expect(note).toHaveCount(1)
        try await expect(note).toHaveText("Unlike sense 1, a leaf sense grows no further senses.")
        // Rendered once on the page: not in the Metadata or elsewhere; the
        // definition box's Raw holds it only as XML.
        let rendered = try await page.evaluate(
          """
          (() => { const main = document.querySelector('main').cloneNode(true);
            main.querySelectorAll("[data-definition-layer='raw']").forEach(e => e.remove());
            return main.textContent.split('grows no further senses').length - 1; })()
          """, as: Int.self)
        #expect(rendered == 1)
        try await expect(page.locator("main")).not.toContainText("Distinction")

        let metadata = try #require(try await page.locator("#record-metadata-s-1-1").boundingBox())
        let prose = try #require(try await note.boundingBox())
        let quotation = try #require(try await row.locator(".attestation-view").boundingBox())
        #expect(prose.y + prose.height <= metadata.y)
        #expect(metadata.y + metadata.height <= quotation.y)

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
