import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The rendered page's cursor says what a drag does (user, 2026-10-14):
/// the hand where the pane pans, the closed hand while it pans, a gloss
/// word's own pointer; on the reader's page and on the Revise page, whose
/// editable reader set the arrow over the whole page before.
@Suite("Artifact cursor", .serialized)
struct ArtifactCursorTests {
  @Test(arguments: [BrowserEngine.chrome])
  func theRenderedPaneShowsTheHandWhereItPans(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor)
    defer { commit.remove() }
    _ = try TestAdmin.query(
      ##"""
      UPDATE bibliographic_madrigals SET
        proposed_content_json = '{"teiXml":"<TEI><text><body><pb n=\"1\" facs=\"https://web-tests.invalid/iiif/p1/full/1300,/0/default.jpg\"/><div><p><s><w lemma=\"word\">Word</w> and more words on a line<lb/></s></p></div></body></text></TEI>"}'
      WHERE id = '\##(commit.madrigalID)'
      """##)
    try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
      for url in [commit.madrigalPath, "\(commit.madrigalPath)/revise"] {
        try await page.openHydrated(url)
        let layer = page.locator(".artifact-markup [data-layer='rendering']").first
        try await expect(layer).toBeVisible()
        // Off the text, in the pane's ground: the hand, the layer's own
        // cursor the pane's.
        _ = try await page.locator(".artifact-markup").first.evaluate("e => { e.scrollIntoView({block: 'start'}); return true }")
        let pane = try #require(try await page.locator(".artifact-markup").first.boundingBox())
        try await page.mouse.move(x: pane.x + pane.width - 6, y: pane.y + 6)
        let cursor = """
          (() => [getComputedStyle(document.querySelector('.artifact-markup')).cursor,
            getComputedStyle(document.querySelector(".artifact-markup [data-layer='rendering']")).cursor].join('|'))()
          """
        #expect(try await page.evaluate(cursor, as: String.self) == "grab|grab", "\(url): the hand where the pane pans")
        // Pressed and dragged: the closed hand.
        try await page.mouse.move(x: pane.x + pane.width - 30, y: pane.y + 30)
        try await page.mouse.down(x: pane.x + pane.width - 30, y: pane.y + 30)
        try await page.mouse.move(x: pane.x + pane.width - 60, y: pane.y + 50)
        let dragging = try await page.evaluate(cursor, as: String.self)
        #expect(dragging == "grabbing|grabbing", "\(url): the closed hand while it pans: \(dragging)")
        try await page.mouse.up(x: pane.x + pane.width - 60, y: pane.y + 50)
        // A gloss word keeps its own pointer.
        let word = try await page.evaluate(
          "(() => { const w = document.querySelector('.artifact-markup .tei-word'); return w ? getComputedStyle(w).cursor : 'pointer' })()",
          as: String.self)
        #expect(word == "pointer", "\(url): a word's own cursor")
      }
      try await page.expectNoErrors()
    }
  }
}
