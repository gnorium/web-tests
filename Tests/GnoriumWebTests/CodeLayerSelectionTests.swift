import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The code layer's text is one layer, read or edited: a selection dragged
/// past the pane's edge scrolls the pane and extends over the line, and
/// what is typed is the text the form posts.
@Suite("Code layer selection", .serialized)
struct CodeLayerSelectionTests {
  /// One line far wider than the pane: sixty words joined by commas, no
  /// white space for the layout to break at.
  static let words = (1...60).map { #"<w lemma=\"word\#($0)\">Word\#($0)</w>"# }.joined(separator: "<pc>,</pc>")

  /// Where the drag landed: the pane's scroll, the selection's length, and
  /// whether it stands in the code text.
  static let state = """
    (() => {
      const pane = document.querySelector('.artifact-transcript');
      const selection = getSelection();
      const node = selection.focusNode;
      const inCode = !!(node && (node.nodeType === 3 ? node.parentElement : node).closest('.code-code'));
      return pane.scrollLeft + '|' + selection.toString().length + '|' + inCode;
    })()
    """

  @Test(arguments: [BrowserEngine.chrome])
  func aDragPastThePanesEdgeScrollsItAndExtendsTheSelection(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor)
    defer { commit.remove() }
    _ = try TestAdmin.query(
      ##"""
      UPDATE bibliographic_madrigals SET
        metadata_json = (metadata_json::jsonb || '{"provider":"folger_shakespeare_library"}'::jsonb)::text,
        proposed_content_json = '{"teiXml":"<TEI><text><body><pb n=\"1\" facs=\"https://web-tests.invalid/iiif/p1/full/1300,/0/default.jpg\"/><div><p><s>\##(Self.words)</s></p></div></body></text></TEI>"}'
      WHERE id = '\##(commit.madrigalID)'
      """##)
    try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
      // The madrigal's code layer, read; the Revise page's, edited.
      for (url, code) in [
        (commit.madrigalPath, ".tei-page-raw .code-code"),
        ("\(commit.madrigalPath)/revise", ".tei-page-edit .code-code"),
      ] {
        try await page.openHydrated(url)
        try await page.locator(".artifact-code-toggle").first.click()
        let text = page.locator(code).first
        try await expect(text).toBeVisible()
        _ = try await text.evaluate("e => { e.scrollIntoView({block: 'center'}); return true }")
        let box = try #require(try await text.boundingBox())
        let pane = try #require(try await page.locator(".artifact-transcript").first.boundingBox())
        // The fourth line, the long one (div, p, s, then the words).
        let y = box.y + 22 * 3 + 11
        try await page.mouse.down(x: box.x + 2, y: y)
        for step in 1...8 { try await page.mouse.move(x: box.x + Double(step) * 80, y: y) }
        // Held past the pane's edge, as a person holds it.
        for _ in 0..<20 {
          try await page.mouse.move(x: pane.x + pane.width + 20, y: y)
          try await Task.sleep(for: .milliseconds(50))
        }
        let state = try await page.evaluate(Self.state, as: String.self).split(separator: "|")
        try await page.mouse.up(x: pane.x + pane.width + 20, y: y)
        #expect((Double(state[0]) ?? 0) > 0, "The pane scrolled with the selection: \(state)")
        #expect((Int(state[1]) ?? 0) > 200, "The selection ran on along the line: \(state)")
        #expect(state[2] == "true", "The selection is in the code's own text: \(state)")
      }

      // Colored by highlights over its text, not markup written into it.
      #expect(
        try await page.evaluate(
          "(() => (CSS.highlights.get('code-name')?.size ?? 0) > 0 && !document.querySelector('.tei-page-edit .code-code span'))()",
          as: Bool.self))

      // Typed into, the text is what the form posts, and the diff follows.
      let text = page.locator(".tei-page-edit .code-code").first
      _ = try await text.evaluate(
        "e => { e.focus(); const r = document.createRange(); r.selectNodeContents(e); r.collapse(true); getSelection().removeAllRanges(); getSelection().addRange(r); return true }")
      try await page.keyboard.insertText("<!-- typed -->")
      let value = try await page.evaluate(
        "(() => document.querySelector('.tei-page-edit textarea').value)()", as: String.self)
      #expect(value.hasPrefix("<!-- typed --><div>"), "The form posts what was typed: \(value.prefix(40))")
      try await expect(page.locator(".testament-diff[data-edited='true']")).toHaveCount(1)
      try await page.expectNoErrors()
    }
  }
}
