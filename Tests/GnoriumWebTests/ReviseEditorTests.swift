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
        out[name] = [...(CSS.highlights?.get(name) ?? [])].filter(r => code.contains(r.startContainer)).map(r => r.toString());
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
  @Test(arguments: [BrowserEngine.chrome])
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
  /// and diffed: the slot under the reader holds the code diff, the
  /// markup pane wears the change ring.
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
          try await expect(diff.locator(".diff-row[data-diff-line='removed']")).toHaveCount(1)
          try await expect(diff.locator(".diff-row[data-diff-line='inserted']")).toHaveCount(1)
          try await expect(page.locator(".artifact-markup").first).toHaveAttribute("data-diff-state", "changed")
          _ = name
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

  /// A real page (Skeat's page 5, as an explication keeps it: headed, its
  /// side's break opening its body) pasted over the page as the document
  /// holds it, one word changed: the diff shows that line.
  @Test(arguments: [BrowserEngine.chrome])
  func aHeadedExplicationPageIsDiffedAgainstTheStoredPage(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let headed = try String(
      contentsOfFile: "/Users/Madhavik/Downloads/Gnorium/skeat-pages-2026-10-14/canvas-5.xml", encoding: .utf8)
    let body = try #require(headed.range(of: "<pb n=\"5\"/>"))
    let end = try #require(headed.range(of: "</body>", options: .backwards))
    let stored = headed[body.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
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
      const code = page.querySelector('.tei-page-edit .code-code');
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
  /// turns to; each paste-ready page byte for byte what its editor
  /// shows; a page pasted
  /// as it stands—byte for byte, or laid out otherwise (its header on one
  /// line, its body unindented)—neither ringed nor diffed; a real change
  /// ringed, diffed under the reader, and colored.
  @Test(arguments: [BrowserEngine.chrome])
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
          let ready = try String(contentsOfFile: "\(folder)/canvas-\(index + 1).xml", encoding: .utf8)
          #expect(now.text == ready, "page \(index + 1): the paste-ready page is not what the editor shows")
        }
        for _ in 0..<9 { try await page.locator(".artifact-page-nav button[aria-label='Previous page']").first.click() }
        let first = try await Self.expectColoredPage(page, 0)

        // Pasted as it stands, byte for byte: no ring, no diff.
        var now = try await Self.paste(page, first.text)
        #expect(now.ring == "" && !now.diff, "the page pasted unchanged: \(now.ring) \(now.diff)")
        // Laid out otherwise, the same document: no ring, no diff.
        let compact = first.text
          .replacingOccurrences(of: ">\n<", with: "><")
          .replacingOccurrences(of: "\n      ", with: "\n")
        #expect(compact != first.text)
        now = try await Self.paste(page, compact)
        #expect(now.ring == "" && !now.diff, "the page pasted laid out otherwise: ring '\(now.ring)', diff \(now.diff)")
        // A real change: ringed, diffed under the reader, colored.
        now = try await Self.paste(page, first.text.replacingOccurrences(of: #"reason="blank""#, with: #"reason="illegible""#))
        #expect(now.ring == "changed" && now.diff && now.names > 0, "the changed page: ring '\(now.ring)', diff \(now.diff), names \(now.names)")
        let diff = page.locator(".testament-diff[data-active='true'] .diff-view[data-diff-mode='code']")
        try await expect(diff.locator(".diff-row[data-diff-line='inserted']")).toHaveCount(1)
        try await expect(diff.locator(".diff-row[data-diff-line='inserted']")).toContainText("illegible")
        if let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"] {
          _ = try await page.evaluate("(() => { document.querySelector('.artifact-view').scrollIntoView({block: 'start'}); return 1 })()")
          try await page.screenshot(to: URL(fileURLWithPath: directory).appendingPathComponent("revise-830-changed.png"))
        }
        // Undone: the ring goes.
        now = try await Self.paste(page, first.text)
        #expect(now.ring == "" && !now.diff, "the change undone: ring '\(now.ring)', diff \(now.diff)")
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
        // Filed, its revision's page draws the same marks.
        try await page.locator(".revision-form button[type='submit']").click()
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
