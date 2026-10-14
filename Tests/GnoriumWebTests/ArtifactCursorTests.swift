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

  /// Reflowed, the rendered pane is a plain text pane (user, 2026-10-14):
  /// the browser's own cursor (no hand), the wheel scrolls it natively, the
  /// arrows too, and a press off the text pans nothing; on the reader's
  /// page and on the Revise page.
  @Test(arguments: [BrowserEngine.chrome])
  func reflowedThePaneScrollsAsText(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor)
    defer { commit.remove() }
    let lines = (1...120).map { "<p>Line \($0) of a page long enough to scroll when it is read at its actual size.</p>" }.joined()
    _ = try TestAdmin.query(
      ##"""
      UPDATE bibliographic_madrigals SET
        proposed_content_json = '{"teiXml":"<TEI><text><body><pb n=\"1\" facs=\"https://web-tests.invalid/iiif/p1/full/1300,/0/default.jpg\"/><div>\##(lines)</div></body></text></TEI>"}'
      WHERE id = '\##(commit.madrigalID)'
      """##)
    try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
      for url in [commit.madrigalPath, "\(commit.madrigalPath)/revise"] {
        try await page.openHydrated(url)
        try await expect(page.locator(".artifact-markup [data-layer='rendering']").first).toBeVisible()
        if try await page.locator(".artifact-reflow-toggle button").first.getAttribute("aria-pressed") != "true" {
          try await page.locator(".artifact-reflow-toggle button").first.click()
        }
        try await expect(page.locator(".artifact-view").first).toHaveAttribute("data-reflow", "true")
        _ = try await page.locator(".artifact-markup").first.evaluate(
          "e => { e.scrollIntoView({block: 'start'}); e.focus({preventScroll: true}); return true }")
        // Read at its actual size: taller than the pane.
        try await page.keyboard.press("0")
        for _ in 0..<6 { try await page.keyboard.press("+") }
        try await Task.sleep(for: .milliseconds(300))
        let pane = try #require(try await page.locator(".artifact-markup").first.boundingBox())
        let scroll = "(() => document.querySelector('.artifact-markup').scrollTop)()"
        let overflow = try await page.evaluate(
          "(() => { const p = document.querySelector('.artifact-markup'); return p.scrollHeight - p.clientHeight })()", as: Double.self)
        #expect(overflow > 100, "\(url): reflowed text taller than the pane: \(overflow)")
        _ = try await page.locator(".artifact-markup").first.evaluate("e => { e.scrollTop = 0; return true }")
        // The browser's cursor: no hand anywhere in the pane.
        try await page.mouse.move(x: pane.x + pane.width - 6, y: pane.y + 6)
        let cursor = """
          (() => [getComputedStyle(document.querySelector('.artifact-markup')).cursor,
            getComputedStyle(document.querySelector(".artifact-markup [data-layer='rendering']")).cursor].join('|'))()
          """
        #expect(try await page.evaluate(cursor, as: String.self) == "auto|auto", "\(url): the text pane's own cursor")
        // The wheel scrolls it.
        try await page.mouse.wheel(x: pane.x + pane.width / 2, y: pane.y + pane.height / 2, deltaY: 300)
        var scrolled = 0.0
        for _ in 0..<20 {
          scrolled = try await page.evaluate(scroll, as: Double.self)
          if scrolled > 0 { break }
          try await Task.sleep(for: .milliseconds(50))
        }
        #expect(scrolled > 0, "\(url): the wheel scrolled nothing")
        // A press dragged off the text pans nothing.
        let before = try await page.evaluate(scroll, as: Double.self)
        let middle = pane.y + pane.height / 2
        // Clear of the scrollbar, which is the browser's own to drag.
        try await page.mouse.down(x: pane.x + pane.width - 40, y: middle)
        try await page.mouse.move(x: pane.x + pane.width - 80, y: middle + 40)
        #expect(try await page.locator(".artifact-markup[data-dragging='true']").count() == 0, "\(url): a drag pans")
        try await page.mouse.up(x: pane.x + pane.width - 80, y: middle + 40)
        #expect(try await page.evaluate(scroll, as: Double.self) == before, "\(url): a drag moved the text")
        // Reflow off again for the next page.
        try await page.locator(".artifact-reflow-toggle button").first.click()
      }
      try await page.expectNoErrors()
    }
  }
}

