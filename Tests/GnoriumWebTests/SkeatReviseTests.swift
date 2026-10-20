import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Skeat's witness revised through the real Revise page (user, 2026-10-14):
/// its document as an explication assembles it (the witness's renditions in
/// its header, each scan's measured text block), its scans served on this
/// machine. Each page's source reads as one headed TEI document wherever it
/// is shown; canvas 3's bookplate stands in the frame's head, over the
/// scan's, before and after an explication's headed page is pasted over it;
/// a page fetched in as the reader turns is colored in XML at once. A
/// throwaway contributor's scratch madrigal; Chrome, desktop.
@Suite("Skeat revise", .serialized)
struct SkeatReviseTests {
  static let canvases = [2, 3, 4, 5]

  /// The bookplate's box against the frame's and the page's, in the
  /// reader's pixels, on the page on screen.
  struct Placement: Decodable {
    let note: Bool
    let noteTop: Double
    let noteBottom: Double
    let blockTop: Double
    let pageTop: Double
    let pageBottom: Double
  }

  static let placement = """
    (() => { const page = document.querySelector(".artifact-markup .tei-page[data-active='true'] [data-layer='rendering']");
      const note = page.querySelector(".tei-margin[data-place='top']");
      const block = page.querySelector('.tei-text-block');
      const box = e => e ? e.getBoundingClientRect() : { top: -1, bottom: -1 };
      const p = box(page);
      return { note: !!note, noteTop: box(note).top, noteBottom: box(note).bottom, blockTop: box(block).top,
        pageTop: p.top, pageBottom: p.bottom }; })()
    """

  static func expectBookplateAtTheHead(_ page: Page, _ context: String) async throws {
    let at = try await page.evaluate(Self.placement, as: Placement.self)
    #expect(at.note, "\(context): the bookplate is not in the frame's head margin")
    // Over the frame's head: above the text block, in the page's top part.
    #expect(at.noteBottom <= at.blockTop + 1, "\(context): the bookplate runs into the text block: \(at)")
    #expect(at.noteTop >= at.pageTop - 1 && at.noteBottom < at.pageTop + (at.pageBottom - at.pageTop) / 2,
      "\(context): the bookplate is not at the page's head: \(at)")
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
    let pasted = try String(
      contentsOfFile: "/Users/Madhavik/Downloads/Gnorium/skeat-pages-2026-10-14/canvas-3.xml", encoding: .utf8)
    do {
      _ = try TestAdmin.query(
        "UPDATE bibliographic_madrigals SET proposed_content_json = '\(json.replacingOccurrences(of: "'", with: "''"))' WHERE id = '\(commit.madrigalID)'")
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        // The madrigal's own Raw: the page headed.
        try await page.openHydrated("\(commit.madrigalPath)?image=1")
        try await page.locator(".artifact-xml-toggle button").first.click()
        // The page's code, never the document's header: that is the
        // reader's Header pane's, as code, under its own switch (user,
        // 2026-10-21).
        let raw = page.locator(".artifact-markup .tei-page[data-active='true'] .tei-page-raw > .code-view .code-code").first
        try await expect(raw).toBeVisible()
        let shown = try await raw.evaluate("e => e.textContent").string ?? ""
        #expect(shown.hasPrefix(#"<TEI xmlns="http://www.tei-c.org/ns/1.0">"#), "Raw is not headed: \(shown.prefix(120))")
        try await page.locator(".artifact-header-toggle button").first.click()
        let header = page.locator(".artifact-markup-frame > .artifact-document-header .code-code").first
        try await expect(header).toBeVisible()
        let headerShown = try await header.evaluate("e => e.textContent").string ?? ""
        #expect(headerShown.contains("<tagsDecl>") && headerShown.contains(#"xml:id="text-block""#), "The header has no renditions")
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
        try await page.openHydrated("\(commit.madrigalPath)/revise?image=1")
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

        // The scans shown, then the overlay at rest: the bookplate over the
        // frame's head.
        if try await page.locator(".artifact-view").first.getAttribute("data-canvas-shown") != "true" {
          try await page.locator(".artifact-canvas-toggle button").first.click()
        }
        try await expect(page.locator(".artifact-view").first).toHaveAttribute("data-canvas-shown", "true")
        try await page.locator(".artifact-overlay-toggle button").first.click()
        try await Task.sleep(for: .milliseconds(1500))
        try await Self.expectBookplateAtTheHead(page, "stored")
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
        try await Self.expectBookplateAtTheHead(page, "pasted")
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
