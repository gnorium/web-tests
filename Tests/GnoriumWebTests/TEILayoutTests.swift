import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A page read as the image sets it (user, 2026-09-27): each block's
/// alignment and indent from its rend; a page number and a running head set
/// on one line a row, each in its place; a right-aligned catchword at the
/// right. Its lines open as the scan breaks them, Reflow off (user,
/// 2026-10-12); under Reflow a block's lines run on as one paragraph, a
/// break inside a word joining it with no space; a centered block centers
/// its flow. The
/// page, from the Wikisource example the user
/// gave ("On the Goodness of the Supreme Being", 1756, p. 10), encoded as the
/// explication now writes it.
@Suite("TEI layout", .serialized)
struct TEILayoutTests {
  static let tei = #"""
    <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt><title>t</title></titleStmt></fileDesc></teiHeader><text><body>
    <pb n="10" facs="https://example.org/iiif/web-tests/full/1300,/0/default.jpg"/>
    <fw type="pageNum" rend="align(left)">10</fw> <fw type="header" rend="align(center)">On the Goodness</fw>
    <lg><l rend="indent(1)"><s><w lemma="the" type="article">The</w> <w lemma="mighty" type="adjective">migh-<lb break="no"/>ty</w> <w lemma="power" type="noun">Power</w><lb/><w lemma="that" type="pronoun">that</w> <w lemma="form" type="verb">form'd</w> <w lemma="the" type="article">the</w> <w lemma="world" type="noun">world</w></s></l></lg>
    <note place="foot" rend="align(center)"><w lemma="buy" type="verb">Bought</w><lb/><w lemma="in" type="preposition">in</w><lb/><num value="1800">1800</num></note>
    <fw type="catch" rend="align(right)">Here,</fw>
    </body></text></TEI>
    """#

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aPageIsSetAsTheImageSetsIt(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reading = try ScratchReading(owner: admin, tei: Self.tei)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(reading.path)
        let text = page.locator(".tei-page-text").first
        // The page number and the running head: one row, number at the start,
        // head in the middle.
        let row = text.locator(".tei-forme-row")
        try await expect(row).toHaveCount(1)
        try await expect(row.locator(".tei-forme-row-start .tei-line-forme-pageNumber")).toHaveText("10")
        try await expect(row.locator(".tei-forme-row-center .tei-line-forme-header")).toHaveText("On the Goodness")
        let number = try #require(try await row.locator(".tei-line-forme-pageNumber").boundingBox())
        let head = try #require(try await row.locator(".tei-line-forme-header").boundingBox())
        #expect(abs(number.y - head.y) < 4)
        #expect(number.x < head.x)
        // The catchword at the right.
        let catchword = text.locator(".tei-line-forme-catchword")
        try await expect(catchword).toHaveAttribute("data-rend", "align(right)")
        try await expect(catchword).toHaveCSS("text-align", "end")
        // The verse line's block, indented.
        let block = text.locator(".tei-block[data-rend='indent(1)']")
        try await expect(block).toHaveCount(1)
        let lines = block.locator(".tei-line")
        try await expect(lines).toHaveCount(3)
        // Reflow off, as the reader opens: each line its own, as the scan
        // breaks it.
        try await expect(lines.nth(0)).toHaveCSS("display", "block")
        try await expect(lines.nth(1)).toHaveCSS("display", "block")
        // Reflowed: the lines run on, the word broken inside joined.
        try await page.locator(".artifact-reflow-toggle button").first.click()
        try await expect(page.locator("[data-reflow='true']")).toHaveCount(1)
        let first = try #require(try await lines.nth(0).boundingBox())
        try await expect(block).toHaveCSS("display", "block")
        try await expect(lines.nth(0)).toHaveCSS("display", "inline")
        try await expect(lines.nth(1)).toHaveAttribute("data-joins-previous", "true")
        let flowed = try await block.innerText()
        #expect(flowed.contains("The migh-ty Power that form'd the world"))
        let blockBox = try #require(try await block.boundingBox())
        let textBox = try #require(try await text.boundingBox())
        #expect(first.x >= blockBox.x)
        // The rendered layer's own 16 inset, then the block.
        #expect(abs(blockBox.x - (textBox.x + 16)) < 0.5)
        try await expect(block).toHaveCSS("padding-inline-start", "24px")
        // The note's lines run on too, the block centered as its rend says.
        let note = text.locator(".tei-block[data-rend='align(center)']")
        try await expect(note).toHaveCount(1)
        try await expect(note).toHaveCSS("text-align", "center")
        let noteLines = note.locator(".tei-line-note")
        try await expect(noteLines).toHaveCount(3)
        try await expect(noteLines.nth(0)).toHaveCSS("display", "inline")
        let noteBox = try #require(try await note.boundingBox())
        let noteFlow = try #require(try await noteLines.nth(0).boundingBox())
        let noteEnd = try #require(try await noteLines.nth(2).boundingBox())
        #expect(abs(noteFlow.y - noteEnd.y) < 2, "the note's lines do not run on")
        #expect(abs((noteFlow.x + noteEnd.x + noteEnd.width) / 2 - (noteBox.x + noteBox.width / 2)) < 4, "the note is not centered")
        // The page's code at CodeEditorView's size, 16 on 22 (user,
        // 2026-10-08), so it runs line for line with the editor.
        let code = page.locator(".tei-page-raw .code-view").first
        try await expect(code).toHaveCSS("font-size", "16px")
        try await expect(code).toHaveCSS("line-height", "22px")
        // The rendered layer at the body's 16 on 26 beside it (user,
        // 2026-10-08): switching layers never changes the size.
        try await expect(lines.nth(0)).toHaveCSS("font-size", "16px")
        try await expect(lines.nth(0)).toHaveCSS("line-height", "26px")
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      reading.remove()
      try await admin.remove(after: error)
    }
    reading.remove()
    try await admin.remove()
  }

  /// An abbreviation with its expansion (`<choice><abbr>M.A.</abbr><expan>
  /// Master of Arts</expan></choice>`) is a word of its line: the line's
  /// font, size and baseline, its expansion on hover. The view has no
  /// padding; the text's 16 inset is its page's (user, 2026-10-10).
  static let abbreviationTEI = #"""
    <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt><title>t</title></titleStmt></fileDesc></teiHeader><text><body>
    <pb n="4" facs="https://example.org/iiif/web-tests/full/1300,/0/default.jpg"/>
    <p><w lemma="take" type="verb">took</w> <w lemma="his" type="pronoun">his</w> <choice><abbr>M.A.</abbr><expan>Master of Arts</expan></choice> <w lemma="degree" type="noun">degree</w></p>
    </body></text></TEI>
    """#

  @Test(arguments: [BrowserEngine.chrome])
  func anAbbreviationSitsOnItsLine(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reading = try ScratchReading(owner: admin, tei: Self.abbreviationTEI)
    do {
      try await withPage(engine, gnorium, viewport: .desktop) { page in
        try await page.openHydrated(reading.path)
        let view = page.locator(".tei-view").first
        // 1px inside its pane, so the ring's inward outline stays clear;
        // the rendered text's inset is its layer's 16.
        try await expect(view).toHaveCSS("padding-top", "1px")
        try await expect(view).toHaveCSS("padding-left", "1px")
        try await expect(page.locator(".tei-page-text[data-layer='rendering']").first)
          .toHaveCSS("padding-left", "16px")
        let line = page.locator(".tei-page-text").first
        let abbreviation = line.locator(".tei-run-alternative").first
        try await expect(abbreviation).toContainText("M.A.")
        let word = line.locator(".tei-run").filter(hasText: "his").first
        let fontSize = try await word.evaluate("el => getComputedStyle(el).fontSize").string
        try await expect(abbreviation).toHaveCSS("font-size", try #require(fontSize))
        try await expect(abbreviation).toHaveCSS("vertical-align", "baseline")
        let abbreviated = try #require(try await abbreviation.locator(".tei-run").first.boundingBox())
        let neighbor = try #require(try await word.boundingBox())
        #expect(abs(abbreviated.y - neighbor.y) < 0.5, "on the line's baseline: \(abbreviated.y) vs \(neighbor.y)")
        #expect(abs(abbreviated.height - neighbor.height) < 0.5)

        // Raw: the code box fills the view edge to edge, square: its gray
        // starts at the pane's border plus 1 (the view's padding).
        try await page.locator(".artifact-raw-toggle").first.click()
        let code = page.locator(".tei-page-raw .code-view").first
        try await expect(code).toBeVisible()
        try await expect(code).toHaveCSS("border-top-left-radius", "0px")
        let inset = try await code.evaluate(
          """
          el => {
            const pane = el.closest('.artifact-markup');
            const view = el.closest('.tei-view');
            const box = el.getBoundingClientRect(), p = pane.getBoundingClientRect(), v = view.getBoundingClientRect();
            return [box.left - v.left, box.top - v.top, v.left - (p.left + pane.clientLeft)];
          }
          """).array?.compactMap(\.double) ?? []
        #expect(inset.count == 3 && abs(inset[0] - 1) < 0.5 && abs(inset[1] - 1) < 0.5, "code at the view's 1px: \(inset)")
        #expect(inset.count == 3 && abs(inset[2]) < 0.5, "the view at the pane's inner edge: \(inset)")
      }
    } catch {
      reading.remove()
      try await admin.remove(after: error)
    }
    reading.remove()
    try await admin.remove()
  }

  /// A decorated initial is the first letter of its word, never a figure
  /// (user, 2026-09-29): `<w><hi rend="initial" facs="#…">W</hi>hen</w>`,
  /// its box a zone of the document's facsimile (FIGURES.md §1.1). The
  /// decoration is cut from the facsimile as a figure's is, and the letter is
  /// drawn over it transparent: still the word's text.
  static let initialTEI = #"""
    <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt><title>t</title></titleStmt></fileDesc></teiHeader>
    <facsimile><surface n="1" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="https://example.org/iiif/web-tests/full/1300,/0/default.jpg"/><zone xml:id="p1-z1" ulx="40" uly="60" lrx="160" lry="210"/></surface></facsimile>
    <text><body>
    <pb n="1" facs="https://example.org/iiif/web-tests/full/1300,/0/default.jpg"/>
    <p><w lemma="when" type="adverb"><hi rend="initial" facs="#p1-z1">W</hi>hen</w> <w lemma="in" type="preposition">in</w> <w lemma="the" type="article">the</w> <w lemma="course" type="noun">course</w></p>
    </body></text></TEI>
    """#

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aDecoratedInitialIsTheFirstLetterOfItsWord(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reading = try ScratchReading(owner: admin, tei: Self.initialTEI)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(reading.path)
        let text = page.locator(".tei-page-text").first
        try await expect(text.locator(".tei-figure")).toHaveCount(0)
        let initial = text.locator(".tei-initial")
        try await expect(initial).toHaveCount(1)
        try await expect(initial).toHaveAttribute("data-rend", "initial")
        let image = initial.locator("img.tei-initial-image")
        try await expect(image).toHaveAttribute(
          "src", "https://example.org/iiif/web-tests/pct:4,6,12,15/!192,192/0/default.jpg")
        try await expect(image).toHaveAttribute("alt", "")
        try await expect(image).toHaveCSS("max-width", "96px")
        try await expect(image).toHaveCSS("max-height", "96px")
        // The letter is still the word's text, drawn transparent over the crop.
        let letter = initial.locator(".tei-initial-letter")
        try await expect(letter).toHaveText("W")
        try await expect(letter).toHaveCSS("position", "absolute")
        try await expect(letter).toHaveCSS("color", "rgba(0, 0, 0, 0)")
        try await expect(initial).toHaveCSS("position", "relative")
        // Read as the line's text, the letter joins its word.
        try await expect(text.locator(".tei-line").first).toHaveText("When in the course")
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      reading.remove()
      try await admin.remove(after: error)
    }
    reading.remove()
    try await admin.remove()
  }

  /// A figure keeps its box through submission (user, 2026-09-29; FIGURES.md
  /// phase 2): a zone of the document's facsimile, named by the figure's
  /// facs, cut from the page's IIIF image as a crop in the madrigal's
  /// transcript, its description as its alternative text and caption.
  static let figureTEI = #"""
    <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt><title>t</title></titleStmt></fileDesc></teiHeader>
    <facsimile><surface n="1" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="https://example.org/iiif/web-tests/full/1300,/0/default.jpg"/><zone xml:id="p1-z1" ulx="100" uly="200" lrx="400" lry="600"/></surface></facsimile>
    <text><body>
    <pb n="1" facs="https://example.org/iiif/web-tests/full/1300,/0/default.jpg"/>
    <p><w lemma="a" type="article">A</w> <w lemma="woodcut" type="noun">woodcut</w><lb/></p>
    <figure type="illustration" facs="#p1-z1"><head><w lemma="figure" type="noun">Fig.</w> <num value="1">1</num></head><figDesc>Woodcut of the bones of a hand.</figDesc></figure>
    </body></text></TEI>
    """#

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aFigureIsCutFromItsZone(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reading = try ScratchReading(owner: admin, tei: Self.figureTEI)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(reading.path)
        let text = page.locator(".tei-page-text").first
        let figure = text.locator("figure.tei-figure")
        try await expect(figure).toHaveCount(1)
        try await expect(figure).toHaveAttribute("data-figure-type", "illustration")
        let image = figure.locator("img.tei-figure-image")
        try await expect(image).toHaveAttribute(
          "src", "https://example.org/iiif/web-tests/pct:10,20,30,40/!600,600/0/default.jpg")
        try await expect(image).toHaveAttribute("alt", "Woodcut of the bones of a hand.")
        try await expect(figure.locator(".tei-figure-caption")).toHaveText("Woodcut of the bones of a hand.")
        // The printed caption stays text, after the crop.
        try await expect(text.locator(".tei-line-heading").last).toHaveText("Fig. 1")
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      reading.remove()
      try await admin.remove(after: error)
    }
    reading.remove()
    try await admin.remove()
  }

  /// Paragraphs a paragraph's space apart, as a TEI reader sets a `<p>`;
  /// verse lines close; a vertical `<space/>` that many of the text's
  /// lines high, with or without dim="vertical" (user, 2026-10-11).
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func paragraphsStandApartAndSpaceHasItsHeight(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let tei = #"""
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt><title>t</title></titleStmt></fileDesc></teiHeader><text><body>
      <pb n="10" facs="https://example.org/iiif/web-tests/full/1300,/0/default.jpg"/>
      <p>First paragraph.<lb/></p><p>Second paragraph.<lb/></p>
      <lg><l>Verse one<lb/></l><l>Verse two<lb/></l></lg>
      <space quantity="2" unit="lines"/>
      <p>After two lines.<lb/></p>
      <space dim="vertical" quantity="1" unit="lines"/>
      <p>After one line.<lb/></p>
      </body></text></TEI>
      """#
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let reading = try ScratchReading(owner: admin, tei: tei)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(reading.path)
        let measured = try await page.evaluate(
          """
          (() => {
            const text = document.querySelector('.tei-page-text');
            const line = (t) => [...text.querySelectorAll('.tei-line')].find(l => l.textContent.includes(t))
              .closest('.tei-block').getBoundingClientRect();
            const gap = (a, b) => Math.round(line(b).top - line(a).bottom);
            const spaces = [...text.querySelectorAll('.tei-space')];
            const lh = parseFloat(getComputedStyle(text.querySelector('.tei-line')).lineHeight);
            return [gap('First', 'Second'), gap('Verse one', 'Verse two'), gap('Second', 'Verse one'),
              spaces.length, ...spaces.map(s => Math.round(s.getBoundingClientRect().height / lh * 10) / 10)].join(' ');
          })()
          """, as: String.self)
        #expect(measured == "16 2 16 2 2 1", "paragraph gap, verse gap, stanza gap, spaces and their heights in lines: \(measured)")
      }
    } catch {
      reading.remove()
      try await admin.remove(after: error)
    }
    reading.remove()
    try await admin.remove()
  }

  /// The header's page label stands where the footer's Raw text stands
  /// (user, 2026-10-11), at every width.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func theCanvasLabelStandsOverRaw(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor, sourceURL: fixture.baseURL + "/manifest.json")
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [contributor.cookie]) { page in
        try await page.openHydrated(commit.madrigalPath)
        try await expect(page.locator(".artifact-canvas-label").first).not.toHaveText("")
        // The page label's text over the Raw button's text.
        let aligned = try await page.evaluate(
          """
          (() => {
            const start = (el) => { const r = document.createRange(); r.selectNodeContents(el); return r.getBoundingClientRect().left; };
            const label = document.querySelector('.artifact-canvas-label');
            const raw = [...document.querySelectorAll('.artifact-raw-toggle button')].find(b => b.getClientRects().length);
            const word = [...raw.querySelectorAll('*')].find(e => e.children.length === 0 && e.textContent.trim() === 'Raw');
            if (!label.textContent.trim()) return 'no label';
            return Math.abs(start(label) - start(word)) < 1 ? 'ok' : start(label) + ' vs ' + start(word);
          })()
          """, as: String.self)
        #expect(aligned == "ok", "label and Raw: \(aligned)")
      }
    } catch {
      commit.remove()
      try await contributor.remove(after: error)
    }
    commit.remove()
    try await contributor.remove()
  }
}
