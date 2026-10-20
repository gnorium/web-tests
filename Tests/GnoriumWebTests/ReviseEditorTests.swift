import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The Revise page's page editor (user, 2026-10-14): its XML mode colored by
/// role as every code view is, and a page's edit diffed against the page as
/// it stands whether a fragment or a headed page document was pasted. A
/// throwaway contributor's scratch madrigal; Chrome, desktop.
@Suite("Revise editor", .serialized)
struct ReviseEditorTests {
  static let markup = #"<div>\n  <p rend=\"x\">Old line</p>\n</div>"#

  /// The scratch madrigal's document: one page.
  static func setUp(_ commit: ScratchCommit) throws {
    _ = try TestAdmin.query(
      """
      UPDATE bibliographic_madrigals SET
        proposed_content_json = '{"teiXml":"<TEI><text><body><pb n=\\"1\\" facs=\\"https://web-tests.invalid/iiif/p1/full/1300,/0/default.jpg\\"/>\(Self.markup)</body></text></TEI>"}'
      WHERE id = '\(commit.madrigalID)'
      """)
  }

  /// The editor's stretches of each role, read from the page's highlights.
  static let editorStretches = """
    (() => { const code = document.querySelector('.tei-page[data-active="true"] .tei-page-edit .code-code');
      const out = {};
      for (const name of ['code-tag', 'code-name', 'code-attr', 'code-value']) {
        out[name] = [...(CSS.highlights?.get(name) ?? [])].filter(r => code.contains(r.startContainer)).map((r => { const x = document.createRange(); x.setStart(r.startContainer, r.startOffset); x.setEnd(r.endContainer, r.endOffset); return x.toString() }));
      }
      return JSON.stringify(out); })()
    """

  static func xmlOn(_ page: Page) async throws {
    if try await page.locator(".artifact-xml-toggle button").first.getAttribute("aria-pressed") != "true" {
      try await page.locator(".artifact-xml-toggle button").first.click()
    }
  }

  /// Polls the editor's highlights until its element names are colored.
  static func expectColored(_ page: Page, _ context: String) async throws {
    var last = ""
    for _ in 0..<40 {
      last = try await page.evaluate(Self.editorStretches, as: String.self)
      if last.contains(#""div""#) && last.contains(#""rend""#) { return }
      try await Task.sleep(for: .milliseconds(100))
    }
    Issue.record("\(context): the editor's XML is not colored: \(last)")
  }

  /// XML mode colors the editor's text by role, at once when pressed and
  /// when the page opens in it (the mode kept for the session).
  @Test(arguments: [BrowserEngine.chrome, .safari])
  func theEditorsXMLIsColoredByRole(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor)
    do {
      try Self.setUp(commit)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(commit.madrigalPath)/revise")
        try await Self.xmlOn(page)
        try await expect(page.locator(".tei-page[data-active='true'] .tei-page-edit .code-code").first).toBeVisible()
        try await Self.expectColored(page, "pressed")
        // Opened again, in XML mode as the session left it.
        try await page.openHydrated("\(commit.madrigalPath)/revise")
        try await Self.xmlOn(page)
        try await Self.expectColored(page, "reopened")
        try await page.expectNoErrors()
      }
      commit.remove()
      try await contributor.remove()
    } catch {
      commit.remove()
      try await contributor.remove(after: error)
    }
  }

  /// An edit pasted as a fragment or as a headed page document (an
  /// explication's page, its header declaring renditions) is read back
  /// and diffed byte for byte: the slot under the reader holds the code
  /// diff, the markup pane wears the change ring.
  @Test(arguments: [BrowserEngine.chrome])
  func aPastedEditIsDiffedFragmentOrHeaded(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor)
    let fragment = "<div>\n  <p rend=\"x\">New line</p>\n</div>"
    let headed =
      #"<TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><encodingDesc><tagsDecl><rendition xml:id="x" scheme="css">font-size: 1em;</rendition></tagsDecl></encodingDesc></teiHeader><text><body><pb n="1"/>"#
      + "\n" + fragment + "\n</body></text></TEI>"
    do {
      try Self.setUp(commit)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        for (name, pasted) in [("fragment", fragment), ("headed", headed)] {
          try await page.openHydrated("\(commit.madrigalPath)/revise")
          try await Self.xmlOn(page)
          let code = page.locator(".tei-page[data-active='true'] .tei-page-edit .code-code").first
          try await expect(code).toBeVisible()
          try await RevisePagesTests.replaceCode(code, with: pasted, page: page)
          try await expect(page.locator(".testament-diff[data-edited='true']")).toHaveCount(1)
          let diff = page.locator(".testament-diff[data-edited='true'] .diff-view[data-diff-mode='code']")
          try await expect(diff, timeout: .seconds(5)).toHaveCount(1)
          if name == "fragment" {
            try await expect(diff.locator(".diff-row[data-diff-line='removed']")).toHaveCount(1)
            try await expect(diff.locator(".diff-row[data-diff-line='inserted']")).toHaveCount(1)
          } else {
            // Byte for byte (user, 2026-10-15): its own header and side
            // break are changes too, each line shown; the word among them.
            try await expect(diff.locator(".diff-row[data-diff-line='inserted']").filter(hasText: "New line")).toHaveCount(1)
          }
          try await expect(page.locator(".artifact-markup").first).toHaveAttribute("data-diff-state", "changed")
        }
        try await page.expectNoErrors()
      }
      commit.remove()
      try await contributor.remove()
    } catch {
      commit.remove()
      try await contributor.remove(after: error)
    }
  }

  /// A real page (Skeat's page 5, paste-ready: headed, its side's break
  /// opening its body) pasted over the page as the document holds it, one
  /// word changed: the diff shows that line alone, byte for byte.
  @Test(arguments: [BrowserEngine.chrome])
  func aHeadedExplicationPageIsDiffedAgainstTheStoredPage(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let headed = try String(
      contentsOfFile: "/Users/Madhavik/Downloads/Gnorium/skeat-pages-2026-10-14/canvas-5.xml", encoding: .utf8)
    // The page's bytes as the document stores them: the body between the
    // headed view's frame (`TEIRendition.headedPage`), its side's break too.
    let body = try #require(headed.range(of: "<text><body>\n"))
    let end = try #require(headed.range(of: "\n</body></text>", options: .backwards))
    let stored = headed[body.upperBound..<end.lowerBound]
    // The document declaring the witness's renditions in its one header,
    // as an explication assembles it: the paste's header is no change.
    let header = try #require(headed.range(of: #"<teiHeader>[\s\S]*?</teiHeader>"#, options: .regularExpression))
    let document =
      "<TEI>\(headed[header])<text><body><pb n=\"1\" facs=\"https://web-tests.invalid/iiif/p1/full/1300,/0/default.jpg\"/>\n\(stored)\n</body></text></TEI>"
    let json = String(decoding: try JSONSerialization.data(withJSONObject: ["teiXml": document]), as: UTF8.self)
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor)
    do {
      _ = try TestAdmin.query(
        "UPDATE bibliographic_madrigals SET proposed_content_json = '\(json.replacingOccurrences(of: "'", with: "''"))' WHERE id = '\(commit.madrigalID)'")
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(commit.madrigalPath)/revise")
        try await Self.xmlOn(page)
        let code = page.locator(".tei-page[data-active='true'] .tei-page-edit .code-code").first
        try await expect(code).toBeVisible()
        try await RevisePagesTests.replaceCode(
          code, with: headed.replacingOccurrences(of: ">ETYMOLOGICAL<", with: ">ETYMOLOGIC<"), page: page)
        let diff = page.locator(".testament-diff[data-edited='true'] .diff-view[data-diff-mode='code']")
        try await expect(diff, timeout: .seconds(5)).toHaveCount(1)
        try await expect(diff.locator(".diff-row[data-diff-line='removed']")).toHaveCount(1)
        try await expect(diff.locator(".diff-row[data-diff-line='inserted']")).toHaveCount(1)
        try await expect(diff.locator(".diff-row[data-diff-line='inserted']")).toContainText("ETYMOLOGIC<")
        try await expect(page.locator(".artifact-markup").first).toHaveAttribute("data-diff-state", "changed")
        try await page.expectNoErrors()
      }
      commit.remove()
      try await contributor.remove()
    } catch {
      commit.remove()
      try await contributor.remove(after: error)
    }
  }

  /// Skeat as production holds it (user, 2026-10-15): 830 pages, the first
  /// ten read, each page's fragment as a laid-out document stores it (its
  /// side's `<pb n="N"/>`, its body indented), one header for the witness.
  /// The paste-ready pages (`skeat-pages-2026-10-14`) are made by the
  /// view's own serializer, so each is the headed page the editor shows.
  static func skeatAsStored() throws -> String {
    let folder = "/Users/Madhavik/Downloads/Gnorium/skeat-pages-2026-10-14"
    let first = try String(contentsOfFile: "\(folder)/canvas-1.xml", encoding: .utf8)
    let header = try #require(first.range(of: #"<teiHeader>[\s\S]*?</teiHeader>"#, options: .regularExpression))
    var body = ""
    for n in 1...830 {
      body += "      <pb n=\"\(n)\" facs=\"https://web-tests.invalid/iiif/p\(n)/full/1300,/0/default.jpg\"/>\n"
      guard n <= 10 else { continue }
      let page = try String(contentsOfFile: "\(folder)/canvas-\(n).xml", encoding: .utf8)
      let open = try #require(page.range(of: "<text><body>\n"))
      let close = try #require(page.range(of: "\n</body></text>", options: .backwards))
      body += "      " + page[open.upperBound..<close.lowerBound] + "\n"
    }
    return "<TEI xmlns=\"http://www.tei-c.org/ns/1.0\">\n  \(first[header])\n  <text>\n    <body>\n\(body)    </body>\n  </text>\n</TEI>"
  }

  /// The page on screen: its index, its editor's colored element names,
  /// the frame's ring, and whether its slot under the reader holds a diff.
  struct Shown: Decodable {
    let index: String
    let names: Int
    let ring: String
    let diff: Bool
    let text: String
  }

  static let shown = """
    (() => { const page = document.querySelector(".artifact-markup .tei-page[data-active='true']");
      const code = page?.querySelector('.tei-page-edit .code-code');
      if (!code) return { index: '', names: 0, ring: '', diff: false, text: '' };
      const slot = [...document.querySelectorAll('.testament-diff')].find(s => s.dataset.serviceId === page.dataset.serviceId);
      return { index: page.dataset.pageIndex,
        names: [...(CSS.highlights?.get('code-name') ?? [])].filter(r => code.contains(r.startContainer)).length,
        ring: document.querySelector('.artifact-markup').dataset.diffState ?? '',
        diff: !!slot?.querySelector(".diff-view[data-diff-mode='code']"), text: code.textContent }; })()
    """

  /// Waits for the page on screen to read `index` with its XML colored.
  static func expectColoredPage(_ page: Page, _ index: Int) async throws -> Shown {
    var last: Shown?
    for _ in 0..<40 {
      let now = try await page.evaluate(Self.shown, as: Shown.self)
      last = now
      if now.index == "\(index)" && now.names > 0 { return now }
      try await Task.sleep(for: .milliseconds(100))
    }
    Issue.record("page \(index + 1): not shown colored: \(String(describing: last).prefix(300))")
    return try #require(last)
  }

  /// A paste, and the reading it is sent to settled.
  static func paste(_ page: Page, _ markup: String) async throws -> Shown {
    let code = page.locator(".artifact-markup .tei-page[data-active='true'] .tei-page-edit .code-code").first
    try await RevisePagesTests.replaceCode(code, with: markup, page: page)
    try await Task.sleep(for: .milliseconds(1500))
    return try await page.evaluate(Self.shown, as: Shown.self)
  }

  /// The real Revise page of a production-sized witness: its editor's XML
  /// colored on the page it opens on and on each of the ten read pages it
  /// turns to; each paste-ready page byte for byte what its editor shows;
  /// a page pasted as it stands neither ringed nor diffed; laid out
  /// otherwise (its header on one line, its body unindented) ringed at once
  /// and diffed, its changed blanks shown; a real change ringed, diffed
  /// under the reader, and colored. In Safari too (user, 2026-10-15).
  @Test(arguments: [BrowserEngine.chrome, .safari])
  func aProductionSizedWitnessIsColoredAndRingedAsItsDiffReads(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let json = String(decoding: try JSONSerialization.data(withJSONObject: ["teiXml": try Self.skeatAsStored()]), as: UTF8.self)
    let folder = "/Users/Madhavik/Downloads/Gnorium/skeat-pages-2026-10-14"
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor)
    do {
      _ = try TestAdmin.query(
        "UPDATE bibliographic_madrigals SET proposed_content_json = '\(json.replacingOccurrences(of: "'", with: "''"))' WHERE id = '\(commit.madrigalID)'")
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(commit.madrigalPath)/revise")
        try await expect(page.locator("#artifact-page-total, .artifact-page-total").first).toHaveText("830")
        try await Self.xmlOn(page)
        // Each page turned to: colored, and the paste-ready page is what
        // the editor shows.
        for index in 0..<10 {
          if index > 0 { try await page.locator(".artifact-page-nav button[aria-label='Next page']").first.click() }
          let now = try await Self.expectColoredPage(page, index)
          // The paste-ready page less its header: the document's header is
          // drawn over the editor, read-only, never in it (user, 2026-10-20).
          let ready = try String(contentsOfFile: "\(folder)/canvas-\(index + 1).xml", encoding: .utf8)
            .replacingOccurrences(of: #"<teiHeader>[\s\S]*?</teiHeader>\n"#, with: "", options: .regularExpression)
          #expect(now.text == ready, "page \(index + 1): the paste-ready page is not what the editor shows")
          // A page of ten lines and more (its header is not in the editor):
          // the third.
          guard index == 2 else { continue }
          // Its line numbers (user, 2026-10-15): right-aligned, the widest
          // inset from the pane's edge as far as from the code, never touching.
          let insets = try await page.evaluate(
            """
            (() => { const code = document.querySelector(".artifact-markup .tei-page[data-active='true'] .tei-page-edit .code-code");
              const view = code.closest('.code-view').getBoundingClientRect();
              const line = code.querySelector('.code-line');
              const text = line.getBoundingClientRect().left + parseFloat(getComputedStyle(line).paddingInlineStart);
              const of = n => { const s = [...code.parentElement.querySelectorAll('.code-gutter-lines > span')].find(s => s.textContent === n);
                const r = document.createRange(); r.selectNodeContents(s); const b = r.getBoundingClientRect();
                return [Math.round(b.left - view.left), Math.round(text - b.right)]; };
              return JSON.stringify({ one: of('1'), ten: of('10') }); })()
            """, as: String.self)
          #expect(insets == #"{"one":[18,8],"ten":[8,8]}"#, "the gutter's insets: \(insets)")
        }
        for _ in 0..<9 { try await page.locator(".artifact-page-nav button[aria-label='Previous page']").first.click() }
        let first = try await Self.expectColoredPage(page, 0)

        // Pasted as it stands, byte for byte: no ring, no diff.
        var now = try await Self.paste(page, first.text)
        #expect(now.ring == "" && !now.diff, "the page pasted unchanged: \(now.ring) \(now.diff)")
        // Laid out otherwise, the same elements: its bytes changed, so
        // ringed at once and diffed, the changed blanks and line breaks
        // filled—never an empty diff (user, 2026-10-15).
        let compact = first.text
          .replacingOccurrences(of: ">\n<", with: "><")
          .replacingOccurrences(of: "\n      ", with: "\n")
        #expect(compact != first.text)
        let code = page.locator(".artifact-markup .tei-page[data-active='true'] .tei-page-edit .code-code").first
        try await RevisePagesTests.replaceCode(code, with: compact, page: page)
        try await expect(page.locator(".artifact-markup").first).toHaveAttribute("data-diff-state", "changed")
        try await Task.sleep(for: .milliseconds(1500))
        now = try await page.evaluate(Self.shown, as: Shown.self)
        #expect(now.ring == "changed" && now.diff, "the page pasted laid out otherwise: ring '\(now.ring)', diff \(now.diff)")
        let blanks = page.locator(".testament-diff[data-active='true'] .diff-view[data-diff-mode='code'] .diff-changed[data-blank='true']")
        #expect(try await blanks.count() > 0, "the layout's changed blanks are not shown")
        try await expect(page.locator(".testament-diff[data-active='true'] .diff-note")).toHaveCount(0)
        // A real change: ringed, diffed under the reader, colored.
        now = try await Self.paste(page, first.text.replacingOccurrences(of: #"reason="blank""#, with: #"reason="illegible""#))
        #expect(now.ring == "changed" && now.diff && now.names > 0, "the changed page: ring '\(now.ring)', diff \(now.diff), names \(now.names)")
        let diff = page.locator(".testament-diff[data-active='true'] .diff-view[data-diff-mode='code']")
        try await expect(diff.locator(".diff-row[data-diff-line='inserted']")).toHaveCount(1)
        try await expect(diff.locator(".diff-row[data-diff-line='inserted']")).toContainText("illegible")
        // The diff under the markup pane, in the reader; its zone the one
        // scrollport between it and the reader (scrolled with the pane, user,
        // 2026-10-16), and nothing wider than the page (user, 2026-10-15).
        let layout = try await page.evaluate(
          """
          (() => { const box = document.querySelector(".testament-diff[data-active='true'] .diff-box");
            const reader = box.closest('.artifact-view');
            const pane = reader.querySelector('.artifact-markup'), zone = box.closest('.artifact-under-markup');
            const scrolls = e => /(auto|scroll)/.test(getComputedStyle(e).overflowY + getComputedStyle(e).overflowX);
            // The scrollports from each zone's content up to the reader.
            const chain = start => { const out = []; for (let e = start; e && e !== reader; e = e.parentElement) if (scrolls(e)) out.push(e.className.split(' ')[0]); return out; };
            const inside = [...box.querySelectorAll('*'), box].filter(scrolls).length + [...pane.querySelectorAll('*')].filter(e => scrolls(e) && e.closest('.artifact-markup') === pane && e !== pane && getComputedStyle(e).display !== 'none' && e.offsetParent).length;
            return JSON.stringify({ under: zone.getBoundingClientRect().top >= pane.getBoundingClientRect().bottom - 1,
              diff: chain(box), markup: chain(pane), nested: inside,
              overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth }); })()
          """, as: String.self)
        #expect(
          layout == #"{"under":true,"diff":["artifact-under-markup"],"markup":["artifact-markup"],"nested":0,"overflow":0}"#,
          "one scrollport a zone, none nested, nothing wider than the page: \(layout)")
        // The markup pane and its diff, the column split evenly.
        let split = try await page.evaluate(
          """
          (() => { const pane = document.querySelector('.artifact-markup-box').getBoundingClientRect();
            const zone = document.querySelector('.artifact-under-markup').getBoundingClientRect();
            return Math.abs(pane.height - zone.height) <= 2 ? 'even' : `${Math.round(pane.height)} over ${Math.round(zone.height)}`; })()
          """, as: String.self)
        #expect(split == "even", "the markup pane over its diff: \(split)")
        if let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"] {
          _ = try await page.evaluate("(() => { document.querySelector('.artifact-view').scrollIntoView({block: 'start'}); return 1 })()")
          try await page.screenshot(to: URL(fileURLWithPath: directory).appendingPathComponent("revise-830-changed.png"))
        }
        // Not well-formed (gibberish after </TEI>): ringed and diffed, no
        // alert while it is edited (user, 2026-10-15).
        now = try await Self.paste(page, first.text + "gibberish")
        #expect(now.ring == "changed" && now.diff, "the malformed page: ring '\(now.ring)', diff \(now.diff)")
        try await expect(page.locator(".testament-diff[data-active='true'] .diff-row[data-diff-line='inserted']").filter(hasText: "gibberish")).toHaveCount(1)
        try await expect(page.locator(".testament-page-fault")).toBeHidden()
        try await expect(page.locator(".revision-form-page-fault")).toBeHidden()
        // Suggest finds it: not sent, the page named above the button; the
        // reader on it, XML on, where it is wrong one line under it.
        try await page.locator(".artifact-page-nav button[aria-label='Next page']").first.click()
        try await page.locator(".artifact-xml-toggle button").first.click()
        try await page.locator(".revision-form button[type='submit']").click()
        try await expect(page.locator(".revision-form-page-fault")).toBeVisible()
        try await expect(page.locator(".revision-form-page-fault")).toContainText("page 1 is not well-formed XML")
        try await expect(page.locator(".artifact-view").first).toHaveAttribute("data-raw", "true")
        try await expect(page.locator(".artifact-markup .tei-page[data-active='true']")).toHaveAttribute("data-page-index", "0")
        let line = page.locator(".testament-page-fault")
        try await expect(line).toBeVisible()
        try await expect(line).toContainText("Line ")
        try await expect(line).toContainText(", column ")
        #expect(try await page.evaluate("(() => location.pathname)()", as: String.self).hasSuffix("/revise"), "the suggestion was sent")
        // Mended: the line and the alert go.
        now = try await Self.paste(page, first.text)
        try await expect(line).toBeHidden()
        try await expect(page.locator(".revision-form-page-fault")).toBeHidden()
        #expect(now.ring == "" && !now.diff, "the change undone: ring '\(now.ring)', diff \(now.diff)")
        // A line added is numbered in the same frame (user, 2026-10-15).
        let numbered = """
          (() => { const code = document.querySelector(".artifact-markup .tei-page[data-active='true'] .tei-page-edit .code-code");
            return code.parentElement.querySelector('.code-gutter-lines').childElementCount; })()
          """
        let lines = try await page.evaluate(numbered, as: Int.self)
        let enter = try await page.evaluate(
          """
          (() => { const code = document.querySelector(".artifact-markup .tei-page[data-active='true'] .tei-page-edit .code-code");
            code.focus(); const r = document.createRange(); r.setStart(code.querySelector('.code-line').firstChild, 1); r.collapse(true);
            getSelection().removeAllRanges(); getSelection().addRange(r);
            document.execCommand('insertText', false, '\\n');
            return code.parentElement.querySelector('.code-gutter-lines').childElementCount; })()
          """, as: Int.self)
        #expect(enter == lines + 1, "the gutter after a new line, in the same frame: \(lines) → \(enter)")
        try await page.expectNoErrors()
      }
      commit.remove()
      try await contributor.remove()
    } catch {
      commit.remove()
      try await contributor.remove(after: error)
    }
  }

  /// A changed page's XML and its diff under it, in the reader's one card
  /// (user, 2026-10-18): each part its own scrollport under the wheel. The
  /// code's pane, ringed orange, scrolls as the diff's zone does: its ring
  /// is the house ring on the pane's box (1px border and 1px outline of one
  /// color, no pseudo-element layer, no box-shadow), so nothing takes the
  /// wheel from the pane. Chrome and Safari.
  @Test(arguments: [BrowserEngine.chrome, .safari])
  func aChangedPagesCodeScrollsAsItsDiffDoes(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let json = String(decoding: try JSONSerialization.data(withJSONObject: ["teiXml": try Self.skeatAsStored()]), as: UTF8.self)
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor)
    do {
      _ = try TestAdmin.query(
        "UPDATE bibliographic_madrigals SET proposed_content_json = '\(json.replacingOccurrences(of: "'", with: "''"))' WHERE id = '\(commit.madrigalID)'")
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(commit.madrigalPath)/revise")
        try await Self.xmlOn(page)
        // The third page, its diff long enough to scroll (the first's is
        // short since the header is no page's code, user 2026-10-20).
        for _ in 0..<2 { try await page.locator(".artifact-page-nav button[aria-label='Next page']").first.click() }
        let third = try await Self.expectColoredPage(page, 2)
        let now = try await Self.paste(page, third.text.replacingOccurrences(of: ">ETYMOLOGICAL<", with: ">ETYMOLOGIC<"))
        #expect(now.ring == "changed" && now.diff, "the changed page: ring '\(now.ring)', diff \(now.diff)")
        struct Parts: Decodable {
          let pane: [Double]
          let zone: [Double]
          let overlay: String
          let ring: [String]
          let hit: Bool
          let scrolls: Bool
        }
        let parts = try await page.evaluate(
          """
          (() => { const reader = document.querySelector('.artifact-view'); reader.scrollIntoView({ block: 'center' });
            const pane = reader.querySelector('.artifact-markup'), zone = reader.querySelector('.artifact-under-markup');
            const box = pane.parentElement; pane.scrollTop = 0; zone.scrollTop = 0;
            const rect = e => { const b = e.getBoundingClientRect(); return [b.x + b.width / 2, b.y + b.height / 2]; };
            const [x, y] = rect(pane);
            const style = getComputedStyle(box);
            return { pane: rect(pane), zone: rect(zone), overlay: getComputedStyle(box, '::after').content,
              ring: [style.borderTopWidth, style.borderTopColor, style.outlineWidth, style.outlineColor, style.boxShadow, getComputedStyle(pane).borderTopWidth],
              hit: document.elementFromPoint(x, y)?.closest('.artifact-markup') === pane,
              scrolls: /(auto|scroll)/.test(getComputedStyle(pane).overflowY) && pane.scrollHeight > pane.clientHeight + 1 }; })()
          """, as: Parts.self)
        #expect(parts.overlay == "none" || parts.overlay == "normal", "a layer stands over the code's pane: \(parts.overlay)")
        let ring = parts.ring
        #expect(ring[0] == "1px" && ring[2] == "1px" && ring[1] == ring[3] && ring[4] == "none" && ring[5] == "0px",
          "the ring is not one border and one outline of one color on the box alone: \(ring)")
        #expect(parts.hit, "the code's pane is not what the pointer is over")
        #expect(parts.scrolls, "the code's pane is not a scrollport with more to show")
        try await page.mouse.wheel(x: parts.pane[0], y: parts.pane[1], deltaY: 400)
        try await Task.sleep(for: .milliseconds(600))
        let pane = try await page.evaluate("(() => document.querySelector('.artifact-markup').scrollTop)()", as: Double.self)
        #expect(pane > 0, "the wheel over the code did not scroll it")
        let zoneBefore = try await page.evaluate("(() => document.querySelector('.artifact-under-markup').scrollTop)()", as: Double.self)
        try await page.mouse.wheel(x: parts.zone[0], y: parts.zone[1], deltaY: 400)
        try await Task.sleep(for: .milliseconds(600))
        let zone = try await page.evaluate("(() => document.querySelector('.artifact-under-markup').scrollTop)()", as: Double.self)
        #expect(zone > zoneBefore, "the wheel over the diff did not scroll it: \(zoneBefore) → \(zone)")
        try await page.expectNoErrors()
      }
      commit.remove()
      try await contributor.remove()
    } catch {
      commit.remove()
      try await contributor.remove(after: error)
    }
  }

  /// The editor's line numbers through an emptied editor (user,
  /// 2026-10-15): emptied, it numbers its one line; typed into, the number
  /// stays in the gutter, never inline; a page pasted in is numbered in
  /// the same frame, the column widening for a third digit, and no number
  /// ever over the code.
  static let gutterState = """
    (() => { const code = document.querySelector(".artifact-markup .tei-page[data-active='true'] .tei-page-edit .code-code");
      const numbers = [...code.parentElement.querySelectorAll('.code-gutter-lines > span')];
      const walker = document.createTreeWalker(code, NodeFilter.SHOW_TEXT); let first = null;
      while (walker.nextNode()) { if (walker.currentNode.data.length) { first = walker.currentNode; break } }
      let textLeft = null;
      if (first) { const r = document.createRange(); r.setStart(first, 0); r.setEnd(first, 1); textLeft = r.getBoundingClientRect().left; }
      const box = numbers[0] ? (() => { const r = document.createRange(); r.selectNodeContents(numbers[0]); return r.getBoundingClientRect(); })() : null;
      return ({ count: numbers.length, first: numbers[0]?.textContent ?? '', last: numbers.at(-1)?.textContent ?? '',
        numberRight: box ? Math.round(box.right) : null, textLeft: textLeft == null ? null : Math.round(textLeft) }); })()
    """

  struct Gutter: Decodable {
    let count: Int
    let first: String
    let last: String
    let numberRight: Int?
    let textLeft: Int?
  }

  static func edit(_ page: Page, _ script: String) async throws -> Gutter {
    _ = try await page.evaluate(
      """
      (() => { const code = document.querySelector(".artifact-markup .tei-page[data-active='true'] .tei-page-edit .code-code");
        code.focus(); \(script); return 1 })()
      """)
    return try await page.evaluate(Self.gutterState, as: Gutter.self)
  }

  @Test(arguments: [BrowserEngine.chrome, .safari])
  func theGutterFollowsAnEmptiedEditor(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let json = String(decoding: try JSONSerialization.data(withJSONObject: ["teiXml": try Self.skeatAsStored()]), as: UTF8.self)
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor)
    let selectAll = "const r = document.createRange(); r.selectNodeContents(code); getSelection().removeAllRanges(); getSelection().addRange(r)"
    func insert(_ text: String) -> String {
      let quoted = String(decoding: try! JSONSerialization.data(withJSONObject: [text]), as: UTF8.self).dropFirst().dropLast()
      return "document.execCommand('insertText', false, \(quoted))"
    }
    do {
      _ = try TestAdmin.query(
        "UPDATE bibliographic_madrigals SET proposed_content_json = '\(json.replacingOccurrences(of: "'", with: "''"))' WHERE id = '\(commit.madrigalID)'")
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(commit.madrigalPath)/revise?resemblance=9")
        try await Self.xmlOn(page)
        _ = try await Self.expectColoredPage(page, 9)
        func clear(_ g: Gutter, _ context: String) {
          if let right = g.numberRight, let left = g.textLeft {
            #expect(right <= left, "\(context): a number over the code: \(g)")
          }
        }
        // Emptied: its one line numbered.
        var g = try await Self.edit(page, "\(selectAll); document.execCommand('delete')")
        #expect(g.count == 1 && g.first == "1", "emptied: \(g)")
        // Typed into: the number in the gutter, the text clear of it.
        g = try await Self.edit(page, insert("a"))
        #expect(g.count == 1 && g.first == "1", "typed: \(g)")
        clear(g, "typed")
        // 37 lines pasted into it.
        let page37 = (1...37).map { "<l n=\"\($0)\">line \($0)</l>" }.joined(separator: "\n")
        g = try await Self.edit(page, "\(selectAll); \(insert(page37))")
        #expect(g.count == 37 && g.last == "37", "37 pasted: \(g)")
        clear(g, "37 pasted")
        // Emptied again, then 820 lines: a third digit.
        _ = try await Self.edit(page, "\(selectAll); document.execCommand('delete')")
        let page820 = (1...820).map { "<l n=\"\($0)\">line \($0)</l>" }.joined(separator: "\n")
        g = try await Self.edit(page, insert(page820))
        #expect(g.count == 820 && g.last == "820", "820 pasted: \(g)")
        clear(g, "820 pasted")
        try await page.expectNoErrors()
      }
      commit.remove()
      try await contributor.remove()
    } catch {
      commit.remove()
      try await contributor.remove(after: error)
    }
  }

  /// The windowed reader's pager counts the document (user, 2026-10-15):
  /// "10 of 830" on page 10, and it turns across the window's edges—next
  /// and previous past the pages drawn, a typed number far off, the last
  /// page, the first.
  @Test(arguments: [BrowserEngine.chrome, .safari])
  func thePagerCountsTheWholeDocument(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let json = String(decoding: try JSONSerialization.data(withJSONObject: ["teiXml": try Self.skeatAsStored()]), as: UTF8.self)
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor)
    do {
      _ = try TestAdmin.query(
        "UPDATE bibliographic_madrigals SET proposed_content_json = '\(json.replacingOccurrences(of: "'", with: "''"))' WHERE id = '\(commit.madrigalID)'")
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(commit.madrigalPath)/revise?resemblance=9")
        let input = page.locator("#artifact-page-input").first
        let active = page.locator(".artifact-markup .tei-page[data-active='true']")
        try await expect(input).toHaveValue("10")
        try await expect(page.locator("#artifact-page-total").first).toHaveText("830")
        try await expect(active).toHaveAttribute("data-page-index", "9")
        // Next, past the four pages drawn after it.
        for step in 1...6 {
          try await page.locator(".artifact-page-nav button[aria-label='Next page']").first.click()
          try await expect(input).toHaveValue("\(10 + step)")
          try await expect(active).toHaveAttribute("data-page-index", "\(9 + step)")
        }
        // Previous, back past them.
        for step in 1...6 {
          try await page.locator(".artifact-page-nav button[aria-label='Previous page']").first.click()
          try await expect(input).toHaveValue("\(16 - step)")
          try await expect(active).toHaveAttribute("data-page-index", "\(15 - step)")
        }
        // A page asked for never waits behind the neighbors fetched ahead:
        // typed far off right after rapid paging, it lands about as fast as
        // a lone jump does.
        let jump = """
          (async (rapid, target) => { const input = document.querySelector('#artifact-page-input');
            const next = document.querySelector(".artifact-page-nav button[aria-label='Next page']");
            for (let i = 0; i < rapid; i++) next.click();
            const t = performance.now(); input.value = String(target); input.dispatchEvent(new Event('change', { bubbles: true }));
            while (document.querySelector(".artifact-markup .tei-page[data-active='true']")?.dataset.pageIndex !== String(target - 1)) {
              if (performance.now() - t > 20000) return -1; await new Promise(r => setTimeout(r, 20)); }
            return Math.round(performance.now() - t); })
          """
        let lone = try await page.evaluate("(\(jump))(0, 300)", as: Int.self)
        let rapid = try await page.evaluate("(\(jump))(8, 600)", as: Int.self)
        print("JUMP lone \(lone) ms, after rapid paging \(rapid) ms")
        #expect(lone >= 0 && rapid >= 0 && rapid <= lone * 2 + 400, "a lone jump \(lone) ms, after rapid paging \(rapid) ms")
        // A number typed far off, the last page, the first.
        for (typed, index) in [("500", "499"), ("830", "829"), ("1", "0")] {
          try await input.fill(typed)
          try await input.press("Enter")
          try await expect(active).toHaveAttribute("data-page-index", index)
          try await expect(input).toHaveValue(typed)
          try await expect(page.locator("#artifact-page-total").first).toHaveText("830")
        }
        try await page.expectNoErrors()
      }
      commit.remove()
      try await contributor.remove()
    } catch {
      commit.remove()
      try await contributor.remove(after: error)
    }
  }

  /// A prompt's diff marks the words that changed inside a changed line
  /// (user, 2026-10-14), as GitHub's and Xcode's do: the line tinted, its
  /// changed words in the solid color, the rest of the long line not.
  @Test(arguments: [BrowserEngine.chrome])
  func aPromptsChangedWordIsMarkedInsideItsLine(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor)
    let slot = "bibliographic_arbitration"
    defer { _ = try? TestAdmin.query("DELETE FROM revisions WHERE requested_by_user_id = (SELECT id FROM users WHERE username = '\(contributor.username)')") }
    do {
      try Self.setUp(commit)
      _ = try TestAdmin.query(
        #"""
        UPDATE bibliographic_madrigals SET
          metadata_json = (metadata_json::jsonb || '{"title":"Web tests original title","provider":"folger_shakespeare_library"}'::jsonb)::text
        WHERE id = '\#(commit.madrigalID)'
        """#)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(commit.madrigalPath)/revise")
        let prompts = page.locator(".prompt-revision-fields-view .prompt-revision-fields-process[data-process='\(slot)']")
        try await prompts.locator("#prompt-revision-process-\(slot) .accordion-summary").first.click()
        try await prompts.locator("#prompt-revision-system-accordion-\(slot) .accordion-summary").first.click()
        let system = prompts.locator("#prompt-revision-system-accordion-\(slot) .prompt-text-view")
        try await system.locator(".prompt-text-markdown-toggle button").click()
        // One word of the longest line changed, mid-line.
        let word = try await page.evaluate(
          """
          (() => {
            const area = document.querySelector("textarea[name='prompt-system-\(slot)']")
            const lines = area.value.split('\\n')
            let at = 0
            lines.forEach((l, i) => { if (l.length > lines[at].length) at = i })
            const words = lines[at].split(' ')
            const middle = Math.floor(words.length / 2)
            const was = words[middle]
            words[middle] = 'Webtestword'
            lines[at] = words.join(' ')
            area.value = lines.join('\\n')
            area.dispatchEvent(new Event('input', { bubbles: true }))
            return was
          })()
          """, as: String.self)
        let box = prompts.locator(".field-diff-diff")
        try await expect(box.locator(".diff-row[data-diff-line='inserted']")).toHaveCount(1)
        let marks = try await page.evaluate(
          """
          (() => {
            const box = document.querySelector("[data-process='\(slot)'] .field-diff-diff")
            const of = kind => [...box.querySelectorAll(`.diff-row[data-diff-line='${kind}'] .diff-changed`)].map(e => e.textContent)
            const row = box.querySelector(".diff-row[data-diff-line='inserted']")
            const mark = row.querySelector('.diff-changed')
            return JSON.stringify({ removed: of('removed'), inserted: of('inserted'),
              tint: getComputedStyle(row).backgroundColor, mark: mark ? getComputedStyle(mark).backgroundColor : '' })
          })()
          """, as: String.self)
        #expect(marks.contains(#""removed":["\#(word)"]"#) && marks.contains(#""inserted":["Webtestword"]"#), "intraline marks: \(marks)")
        #expect(!marks.contains(#""mark":"""#), "the changed word's solid fill: \(marks)")
        if let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"] {
          _ = try await box.first.evaluate("e => { e.querySelector(\".diff-row[data-diff-line='inserted']\").scrollIntoView({block: 'center'}); return 1 }")
          try await page.screenshot(to: URL(fileURLWithPath: directory).appendingPathComponent("prompt-intraline.png"))
        }
        // Filed, its revision's page draws the same marks. Scrolled to, the
        // sections above the button draw what comes into view and the page
        // grows under it: the click waits until it stands still for a few
        // frames.
        let submit = page.locator(".revision-form button[type='submit']")
        _ = try await submit.evaluate(
          """
          async e => { e.scrollIntoView({block: 'center'}); let last = '', still = 0;
            for (let i = 0; i < 120 && still < 5; i++) {
              await new Promise(r => requestAnimationFrame(r));
              const b = e.getBoundingClientRect(); const now = b.top + ',' + b.left;
              still = now === last ? still + 1 : 0; last = now }
            return still }
          """)
        try await submit.click()
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("the madrigal at its locution", where: RevisePagesTests.atLocution(commit.madrigalPath))
        let user = try contributor.column("id")
        let id = try TestAdmin.query("SELECT id FROM revisions WHERE requested_by_user_id = '\(user)'").uppercased()
        try await page.openHydrated("\(commit.madrigalPath)/revisions/\(id)")
        let filed = try await page.evaluate(
          """
          (() => {
            const box = document.querySelector('.prompt-change-view .prompt-text-diff')
            if (!box) return 'no diff'
            const of = kind => [...box.querySelectorAll(`.diff-row[data-diff-line='${kind}'] .diff-changed`)].map(e => e.textContent)
            const mark = box.querySelector(".diff-row[data-diff-line='inserted'] .diff-changed")
            const row = box.querySelector(".diff-row[data-diff-line='inserted']")
            return JSON.stringify({ removed: of('removed'), inserted: of('inserted'),
              distinct: !!mark && getComputedStyle(mark).backgroundColor !== getComputedStyle(row).backgroundColor })
          })()
          """, as: String.self)
        #expect(filed == #"{"removed":["\#(word)"],"inserted":["Webtestword"],"distinct":true}"#, "the revision page's marks: \(filed)")
        if let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"] {
          _ = try await page.evaluate("(() => { document.querySelector(\".prompt-change-view .prompt-text-diff .diff-row[data-diff-line='inserted']\")?.scrollIntoView({block: 'center'}); return 1 })()")
          try await page.screenshot(to: URL(fileURLWithPath: directory).appendingPathComponent("prompt-intraline-revision.png"))
        }
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
