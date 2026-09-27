import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A sentiment's distinction (user, 2026-09-27): its explication's
/// `<note type="usage" subtype="distinction">` is plain prose under the
/// sentiment's Metadata and above its utterances, once, with no heading; a
/// pointer to another sentiment reads as its number. A throwaway admin owns
/// a scratch word made by SQL and removed after.
@Suite("Distinction", .serialized)
struct DistinctionTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aSentimentsDistinctionStandsAboveItsUtterances(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    // Its utterance is in a scratch testament (`UtteranceTests`).
    let testament = try ScratchTestament(owner: admin, tei: UtteranceTests.tei)
    let word = try ScratchWord(
      owner: admin, distinction: "Unlike sense {branch}, a leaf sense grows no further senses.",
      anchor: .init(
        recordID: testament.reading.work.recordID, versionID: testament.versionID,
        canvasID: "https://example.org/iiif/webtests-p3", passage: 49..<76, headword: 58..<69))
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(word.path)
        // The leaf's row opens into its Metadata, its notes and utterances.
        let row = page.locator("#record-row-s-1-1")
        try await page.locator("#record-row-s-1-1 > .accordion-summary").click()
        try await expect(row).toHaveAttribute("data-open-finished", "true")
        let note = row.locator(".lexicographic-explication-note-text")
        try await expect(note).toHaveCount(1)
        try await expect(note).toHaveText("Unlike sense 1, a leaf sense grows no further senses.")
        // Once on the page: not in the definition, the Metadata or elsewhere.
        #expect(try await page.locator("main").textContent().components(separatedBy: "grows no further senses").count == 2)
        try await expect(page.locator("main")).not.toContainText("Distinction")

        let metadata = try #require(try await page.locator("#record-metadata-s-1-1").boundingBox())
        let prose = try #require(try await note.boundingBox())
        let utterance = try #require(try await row.locator(".attestation-view").boundingBox())
        #expect(metadata.y + metadata.height <= prose.y)
        #expect(prose.y + prose.height <= utterance.y)

        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      word.remove()
      testament.remove()
      await admin.remove()
      throw error
    }
    word.remove()
    testament.remove()
    await admin.remove()
  }
}
