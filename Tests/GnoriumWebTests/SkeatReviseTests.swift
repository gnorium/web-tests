import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Skeat's witness revised through the real Revise page (user, 2026-10-14):
/// its document as an explication assembles it (the witness's renditions in
/// its header, each scan's measured text block), its scans served on this
/// machine. Each page's source reads as one headed TEI document wherever it
/// is shown; canvas 3's bookplate, an owner's mark, stays in its code and
/// is never set in the reading pane (user, 2026-10-26), before and after an
/// explication's headed page is pasted over it;
/// a page fetched in as the reader turns is colored in XML at once. A
/// throwaway contributor's scratch madrigal; Chrome, desktop.
@Suite("Skeat revise", .serialized)
struct SkeatReviseTests {
  static let canvases = [2, 3, 4, 5]

  /// What the reading pane sets on the page on screen: its marginal boxes
  /// (-1 where it has no rendering layer), the bookplate's words it draws,
  /// and whether its title is set.
  struct Reading: Decodable {
    let margins: Int
    let drawn: [String]
    let title: Bool
  }

  static let reading = """
    (() => { const page = document.querySelector(".artifact-markup .tei-page[data-active='true'] [data-layer='rendering']");
      const text = page ? page.textContent : '';
      return { margins: page ? page.querySelectorAll('.tei-margin').length : -1,
        drawn: ['This book is a gift', 'Southern Evangelical', 'William E. Nix'].filter((s) => text.includes(s)),
        title: text.includes('ETYMOLOGICAL') && text.includes('LANGUAGE') }; })()
    """

  /// Canvas 3's bookplate is an owner's mark (`<note type="provenance">`):
  /// kept in the page's code, the scan's alone, never set in the reading
  /// pane (user, 2026-10-26: a copy's makers' work is rendered, its owners'
  /// marks are the image pane's; xml-utilities `TEIRenderer.isOwnersMark`,
  /// as `ArtifactOverlayTests` holds the structure to). Before 2026-10-26 it
  /// stood in the frame's head margin, which this test measured. The page's
  /// own text is set as ever.
  static func expectBookplateInItsCodeAlone(_ page: Page, _ context: String) async throws {
    let at = try await page.evaluate(Self.reading, as: Reading.self)
    #expect(at.margins == 0, "\(context): the reading pane sets \(at.margins) margin boxes, the bookplate's among them")
    #expect(at.drawn.isEmpty, "\(context): the reading pane sets the bookplate's words: \(at.drawn)")
    #expect(at.title, "\(context): the page's title is not set")
  }

  static func shot(_ page: Page, _ name: String) async throws {
    guard let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"] else { return }
    _ = try await page.evaluate("(() => { document.querySelector('.artifact-view').scrollIntoView({block: 'start'}); return 1 })()")
    try await page.screenshot(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
  }

  @Test(arguments: [BrowserEngine.chrome])
  func canvasThreeRevisedHeadedKeepsItsBookplateAndOneSource(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let witness = try await FixtureServer.skeatWitness(canvases: Self.canvases)
    defer { witness.server.stop() }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor, sourceURL: witness.server.baseURL + "/manifest.json")
    let json = String(decoding: try JSONSerialization.data(withJSONObject: ["teiXml": witness.document]), as: UTF8.self)
    let pasted = try String(contentsOfFile: "\(ReviseEditorTests.skeatPages)/canvas-3.xml", encoding: .utf8)
    do {
      _ = try TestAdmin.query(
        "UPDATE bibliographic_madrigals SET proposed_content_json = '\(json.replacingOccurrences(of: "'", with: "''"))' WHERE id = '\(commit.madrigalID)'")
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        // The madrigal's own Raw: the page headed.
        try await page.openHydrated("\(commit.madrigalPath)?frame=1")
        try await page.locator(".artifact-xml-toggle button").first.click()
        // The page's code, never the document's header: that is the
        // reader's Header pane's, as code, under its own switch, the two
        // exclusive in the one column (user, 2026-10-21).
        let raw = page.locator(".artifact-markup .tei-page[data-active='true'] .tei-page-raw > .code-view .code-code").first
        try await expect(raw).toBeVisible()
        let shown = try await raw.evaluate("e => e.textContent").string ?? ""
        #expect(shown.hasPrefix(#"<TEI xmlns="http://www.tei-c.org/ns/1.0">"#), "Raw is not headed: \(shown.prefix(120))")
        try await page.locator(".artifact-header-toggle button").first.click()
        let header = page.locator(".artifact-markup-viewport > .artifact-document-header .code-code").first
        try await expect(header).toBeVisible()
        let headerShown = try await header.evaluate("e => e.textContent").string ?? ""
        #expect(headerShown.contains("<tagsDecl>") && headerShown.contains(#"xml:id="text-block""#), "The header has no renditions")
        // The header on turned the XML off: the page's code put away.
        try await expect(page.locator(".artifact-view").first).toHaveAttribute("data-raw", "false")
        try await expect(raw).toBeHidden()
        try await page.locator(".artifact-header-toggle button").first.click()
        // Its words as read, each <w> naming its scan zones (@facs); its
        // surface as its <facsimile>, between the header and the text, never
        // in the body (web-components ff0cb26, user, 2026-10-16).
        let text = shown.range(of: "<text>")
        let body = text.map { String(shown[$0.lowerBound...]) } ?? ""
        let words = body.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
          .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(words.contains("Southern Evangelical Seminary") && !body.contains("<facsimile"), "Raw's body")
        let facsimile = shown.range(of: "<facsimile>")
        #expect(
          text.map { at in facsimile.map { $0.lowerBound < at.lowerBound } ?? false } ?? false
            && shown.components(separatedBy: "<surface ").count == 2,
          "Raw's facsimile is not the page's own surface ahead of its text")

        // The Revise page's editor: the same text.
        try await page.openHydrated("\(commit.madrigalPath)/revise?frame=1")
        if try await page.locator(".artifact-xml-toggle button").first.getAttribute("aria-pressed") != "true" {
          try await page.locator(".artifact-xml-toggle button").first.click()
        }
        let area = ".artifact-markup .tei-page[data-active='true'] .tei-page-edit textarea"
        let editor = try await page.evaluate("(() => document.querySelector(\"\(area)\").value)()", as: String.self)
        if editor != shown {
          let common = zip(editor, shown).prefix { $0 == $1 }.count
          Issue.record("The editor and Raw show different sources from \(common): \(editor.dropFirst(common).prefix(80).debugDescription) | \(shown.dropFirst(common).prefix(80).debugDescription)")
        }
        try await Self.shot(page, "skeat-3-revise-xml")
        try await page.locator(".artifact-xml-toggle button").first.click()

        // The scans shown, then the overlay at rest: the bookplate the
        // scan's alone, none of it in the reading pane.
        if try await page.locator(".artifact-view").first.getAttribute("data-canvas-shown") != "true" {
          try await page.locator(".artifact-canvas-toggle button").first.click()
        }
        try await expect(page.locator(".artifact-view").first).toHaveAttribute("data-canvas-shown", "true")
        try await page.locator(".artifact-overlay-toggle button").first.click()
        try await Task.sleep(for: .milliseconds(1500))
        try await Self.expectBookplateInItsCodeAlone(page, "stored")
        try await Self.shot(page, "skeat-3-stored")
        try await page.locator(".artifact-overlay-toggle button").first.click()
        try await Task.sleep(for: .milliseconds(800))

        // An explication's headed page pasted over it, one word changed.
        try await page.locator(".artifact-xml-toggle button").first.click()
        let code = page.locator(".artifact-markup .tei-page[data-active='true'] .tei-page-edit .code-code").first
        try await expect(code).toBeVisible()
        try await RevisePagesTests.replaceCode(code, with: pasted.replacingOccurrences(of: "Evangelical Seminary<", with: "Evangelical Seminary College<"), page: page)
        let diff = page.locator(".testament-diff[data-edited='true'] .diff-view[data-diff-mode='code']")
        try await expect(diff, timeout: .seconds(8)).toHaveCount(1)
        // Byte for byte (user, 2026-10-15): the explication's page differs
        // from the stored one in more than the word, each line shown; the
        // word among them.
        try await expect(diff.locator(".diff-row[data-diff-line='inserted']").filter(hasText: "Seminary College")).toHaveCount(1)
        try await Self.shot(page, "skeat-3-diff")
        try await page.locator(".artifact-xml-toggle button").first.click()
        try await page.locator(".artifact-overlay-toggle button").first.click()
        try await Task.sleep(for: .milliseconds(1500))
        try await Self.expectBookplateInItsCodeAlone(page, "pasted")
        try await Self.shot(page, "skeat-3-pasted")
        try await page.locator(".artifact-overlay-toggle button").first.click()
        try await Task.sleep(for: .milliseconds(800))

        // The next page, fetched in as the reader turns, colored in XML
        // with no click after it arrives.
        try await page.locator(".artifact-xml-toggle button").first.click()
        try await page.locator(".artifact-page-nav button[aria-label='Next page']").first.click()
        var colored = ""
        for _ in 0..<40 {
          colored = try await page.evaluate(
            """
            (() => { const code = document.querySelector(".artifact-markup .tei-page[data-active='true'] .tei-page-edit .code-code");
              if (!code) return 'no editor';
              const label = code.closest('.tei-page').dataset.pageIndex;
              const names = [...(CSS.highlights?.get('code-name') ?? [])].filter(r => code.contains(r.startContainer));
              return label + ':' + names.length; })()
            """, as: String.self)
          if colored.hasPrefix("2:"), !colored.hasSuffix(":0") { break }
          try await Task.sleep(for: .milliseconds(100))
        }
        #expect(colored.hasPrefix("2:") && !colored.hasSuffix(":0"), "the fetched page's XML is not colored: \(colored)")
        try await page.expectNoErrors()
      }
      commit.remove()
      try await contributor.remove()
    } catch {
      commit.remove()
      try await contributor.remove(after: error)
    }
  }
}
