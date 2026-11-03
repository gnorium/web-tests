import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A board's lettering reflowed (user, 2026-11-03: Hamlet Q1's front cover,
/// image 1, Reflow on: "HAMLE" over its "T", "SHAKESPEAR" over its "E",
/// "LONDON" over "1603", each wrapped line drawn over the one above). A page
/// with no type of its own sets each line at its zone (xml-utilities
/// `TEIPage.placedByZone`): its box its ink's width, which the edition face
/// fills, and its line its box's height, 0.714 of its type. Reflowed, a line
/// runs about its box's middle as far as its leaf lets it, and a line it
/// wraps sets solid (TEIView `reflowStyle`): no two lines' type overlaps and
/// no word breaks inside, at a desktop's width and a phone's. The cover as
/// dev holds it, and below its imprint a line of capitals longer than its
/// leaf, which wraps; its scan never served (the reader reads its text
/// alone); a throwaway contributor's scratch madrigal; Chrome.
@Suite("Artifact reflow cover", .serialized)
struct ArtifactReflowCoverTests {
  /// Each line the page's text runs on: its text, its type's em box (its
  /// font-size tall, centered on its glyphs' box), its row's ends.
  struct Row: Decodable {
    let text: String
    let top: Double
    let bottom: Double
    let left: Double
    let right: Double
  }

  struct Reading: Decodable {
    let reflow: String
    let rows: [Row]
    /// How many boxes each word draws: one, where it never breaks inside.
    let words: [Int]
  }

  /// The cover as integrated (dev, 2026-11-03, p15150coll3:1360): the work's
  /// frame in the header, the board's tooled frame a figure at its zone, its
  /// lettering three lines at their line breaks', each tracked as printed;
  /// and a fourth at HAMLET's size that its leaf is too narrow for.
  static func document(image: String) -> String {
    #"<TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><encodingDesc><tagsDecl>"#
      + #"<rendition xml:id="text-block" scheme="css" selector="text">font-size:85.44px;inline-size:26.47em;block-size:47.94em;margin:7.42em 13.26em 11.23em 9.33em;max-inline-size:80.61em</rendition>"#
      + "</tagsDecl></encodingDesc></teiHeader>"
      + #"<facsimile><surface n="Front cover" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="\#(image)" width="6120px" height="6630px"/>"#
      + #"<zone xml:id="p1-z-L2" ulx="417" uly="238" lrx="637" lry="259"/><zone xml:id="p1-z-L3" ulx="434" uly="304" lrx="620" lry="319"/>"#
      + #"<zone xml:id="p1-z-L6" ulx="464" uly="427" lrx="595" lry="438"/><zone xml:id="p1-z-fig-2" ulx="173" uly="61" lrx="882" lry="938"/>"#
      + #"<zone xml:id="p1-z-L9" ulx="280" uly="600" lrx="774" lry="621"/>"#
      + #"<zone xml:id="p1-textblock" type="textblock" points="172.3,64.24 879.57,59.61 884.82,936.85 175.7,941.07"/>"#
      + #"<zone type="leaf" points="144.85,53.4 890.9,53.4 890.9,945.42 144.85,945.42"/></surface></facsimile>"#
      + ##"<text><body><pb n="Front cover" facs="\##(image)" rend="color(yellow)"/><figure facs="#p1-z-fig-2"/>"##
      + ##"<lb facs="#p1-z-L2"/><note type="binding" subtype="copy" style="letter-spacing:0.527em">HAMLET</note>"##
      + ##"<lb facs="#p1-z-L3"/><note type="binding" subtype="copy" style="letter-spacing:0.1119em">SHAKESPEARE</note>"##
      + ##"<lb facs="#p1-z-L6"/><note type="binding" subtype="copy" style="letter-spacing:0.1004em">LONDON 1603</note>"##
      + ##"<lb facs="#p1-z-L9"/><note type="binding" subtype="copy">THE TRAGICALL HISTORIE OF HAMLET PRINCE OF DENMARKE</note>"##
      + "</body></text></TEI>"
  }

  static let reading = """
    (() => {
      const page = document.querySelector(".artifact-markup .tei-page[data-active='true']");
      const rows = [];
      for (const line of page.querySelectorAll(".tei-page-text[data-layer='rendering'] .tei-line:not(.tei-figure)")) {
        const range = document.createRange();
        range.selectNodeContents(line);
        const size = parseFloat(getComputedStyle(line).fontSize);
        const own = [];
        for (const r of range.getClientRects()) {
          if (r.width <= 0 || r.height <= 0) continue;
          const row = own.find(o => Math.abs((o.top + o.bottom) / 2 - (r.top + r.bottom) / 2) < 1);
          if (row) { row.left = Math.min(row.left, r.left); row.right = Math.max(row.right, r.right); }
          else own.push({top: r.top, bottom: r.bottom, left: r.left, right: r.right});
        }
        for (const o of own) {
          const middle = (o.top + o.bottom) / 2;
          rows.push({text: line.textContent.trim(), top: middle - size / 2, bottom: middle + size / 2, left: o.left, right: o.right});
        }
      }
      const words = [...page.querySelectorAll(".tei-page-text[data-layer='rendering'] .tei-word")]
        .map(word => [...word.getClientRects()].filter(r => r.width > 0).length);
      return {reflow: document.querySelector(".artifact-view").dataset.reflow, rows, words};
    })()
    """

  @Test(arguments: [BrowserEngine.chrome], [Viewport.desktop, Viewport.phone])
  func aCoversLetteringReflowsWithNoLineOverAnother(engine: BrowserEngine, viewport: Viewport) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor)
    let image = ScratchCommit.sourceURL.replacingOccurrences(of: "/manifest.json", with: "") + "/page-1/full/max/0/default.jpg"
    let json = String(
      decoding: try JSONSerialization.data(withJSONObject: ["teiXml": Self.document(image: image)]), as: UTF8.self)
    do {
      _ = try TestAdmin.query(
        "UPDATE bibliographic_madrigals SET proposed_content_json = '\(json.replacingOccurrences(of: "'", with: "''"))' WHERE id = '\(commit.madrigalID)'")
      try await withPage(engine, gnorium, viewport: viewport, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(commit.madrigalPath)?image=1")
        let view = page.locator(".artifact-view").first
        try await expect(page.locator(".artifact-markup .tei-page[data-active='true'] .tei-block")).toHaveCount(4)
        try await page.locator(".artifact-reflow-toggle button").first.click()
        try await expect(view).toHaveAttribute("data-reflow", "true")
        try await Task.sleep(for: .milliseconds(500))
        let reading = try await page.evaluate(Self.reading, as: Reading.self)
        #expect(reading.reflow == "true")
        // The lettering one row a line, whole, about its zone's middle within the leaf; the long line wrapped
        // between its words, its rows each a whole line of its type.
        let long = "THE TRAGICALL HISTORIE OF HAMLET PRINCE OF DENMARKE"
        #expect(reading.rows.filter { $0.text != long }.map(\.text) == ["HAMLET", "SHAKESPEARE", "LONDON 1603"])
        #expect(reading.rows.filter { $0.text == long }.count >= 2, "the long line never wrapped")
        #expect(reading.words.allSatisfy { $0 == 1 }, "a word broke inside: \(reading.words)")
        // No line's type over another's: wrapped onto a line 0.714 em down, "T" stood 7 px into "HAMLE".
        for (index, a) in reading.rows.enumerated() {
          for b in reading.rows[(index + 1)...] {
            let down = min(a.bottom, b.bottom) - max(a.top, b.top)
            let across = min(a.right, b.right) - max(a.left, b.left)
            #expect(down <= 0.5 || across <= 0.5, "\(a.text) and \(b.text) overlap \(down) px down, \(across) across")
          }
        }
      }
    } catch {
      commit.remove()
      try await contributor.remove(after: error)
    }
    commit.remove()
    try await contributor.remove()
  }
}
