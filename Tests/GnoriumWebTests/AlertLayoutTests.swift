import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The two kinds of alert are laid out differently (user, 2026-10-17). A
/// boxed alert (`AlertView`'s default, framed) keeps the mark in a column of
/// its own, level with the first line, the content wrapping in its own
/// column. An inline alert (`inline: true`, the source-change notice) is a
/// line of text: the mark is an inline icon at the start of the first line,
/// and the lines the content wraps to start at the alert's start edge, under
/// the mark; a thumbnail it names is a line high in the same flow, with no
/// caption. A line with something beside its words (a fault's detail) is one
/// wrapping row (`AlertLineView`). Checked at 1000px and 375px, left to right
/// and right to left, on the stylesheets the server emits against the markup
/// the views draw, in a fixture page with no client and no database. Build
/// with `make styles` in gnorium-web first.
@Suite("Alert layout", .serialized)
struct AlertLayoutTests {
  /// A line of text: its top and bottom, and where it starts along the
  /// inline axis (the left edge left to right, the right edge right to left,
  /// as a distance from the start).
  struct Line: Decodable {
    let top: Double
    let bottom: Double
    let start: Double
    var center: Double { (top + bottom) / 2 }
  }

  /// An alert as laid out, along the inline axis in start coordinates.
  struct Alert: Decodable {
    let alertStart: Double
    let iconStart: Double
    let iconEnd: Double
    let iconTop: Double
    let iconBottom: Double
    let contentStart: Double
    let lines: [Line]
    let lineHeight: Double
    let thumb: Thumb?
    let scrollWidth: Double
    let clientWidth: Double
    var iconCenter: Double { (iconTop + iconBottom) / 2 }
  }

  struct Thumb: Decodable {
    let top: Double
    let bottom: Double
    let width: Double
    let height: Double
    let caption: String
    var center: Double { (top + bottom) / 2 }
  }

  /// An alert line's pieces (`AlertLineView`), in start coordinates.
  struct Pieces: Decodable {
    let iconTop: Double
    let headingTop: Double
    let headingWeight: String
    let wordsTop: Double
    let wordsBottom: Double
    let wordsStart: Double
    let wordsEnd: Double
    let asideTop: Double
    let asideStart: Double
    let detailEnd: Double
    let contentEnd: Double
    let rowGap: String
    let columnGap: String
  }

  struct Single: Decodable {
    let alertTop: Double
    let alertBottom: Double
    let iconCenter: Double
    let textCenter: Double
    let textEnd: Double
    let dismissCenter: Double?
    let dismissStart: Double?
    let dismissHeight: Double?
  }

  static let icon =
    #"<span class="alert-icon" aria-hidden="true" data-color="orange"><svg width="16" height="16" viewBox="0 0 16 16"><circle cx="8" cy="8" r="7" fill="currentColor"/></svg></span>"#

  /// `SourceChangeNoticeView`'s markup for an image changed: an inline
  /// alert, its thumbnail in the sentence (its size inline, as the
  /// component renders a presentation's own style on the element).
  static let notice = """
    <div class="source-change-notice"><div class="alert-view alert-orange alert-inline" id="notice" aria-live="polite">\
    <div class="alert-motion-content">\(icon)<div class="alert-content">\
    <span>This page’s image changed at its source since it was sent (seen <time>Oct 17, 2026</time>)</span>\
    <span>; the source’s image now: </span>\
    <div class="expandable-attachment-view" data-kind="image" data-fallback-src="" data-presentation="line">\
    <button type="button" class="expandable-attachment-trigger expandable-attachment-image-trigger" \
    aria-label="The page’s image as its source serves it now">\
    <img src="/page.svg" alt="The page’s image as its source serves it now" loading="lazy" class="expandable-attachment-image-thumb" \
    style="display: block; flex-shrink: 0; width: var(--line-height-small-22); height: var(--line-height-small-22); \
    object-fit: contain"/>\
    </button></div><span>.</span><span> The image shown is the one that was sent, as archived.</span>\
    </div></div></div></div>
    """

  /// A boxed alert whose words wrap at either width.
  static let boxed = """
    <div class="alert-view alert-orange" id="boxed"><div class="alert-motion-content">\(icon)<div class="alert-content">\
    <span>A later markup of this testament changed this word, and the quote is read where it was anchored \
    until its word is explicated again; every quote of the word waits with it, and none is shown changed \
    until a person permits the new markup.</span></div></div></div>
    """

  /// A page's faults: a heading line, then a line a fault—its words, then
  /// its detail in the mono style, edge-faded.
  static func faults(detail: String) -> String {
    """
    <div class="alert-view alert-orange" id="faults"><div class="alert-motion-content">\(icon)<div class="alert-content">\
    <div class="alert-line-view" data-heading="true" id="heading"><div class="alert-line-words">Page 5: 1 fault</div></div>\
    <div class="alert-line-view" id="line"><div class="alert-line-words" id="words">Box without its zone:</div>\
    <div class="alert-line-aside" id="aside"><span class="image-fault-detail" id="detail" data-edge-fade-view="expand" \
    style="min-width:0;font-family:ui-monospace,monospace;white-space:nowrap;overflow:hidden">\(detail)</span></div></div>\
    </div></div></div>
    """
  }

  static let single = """
    <div class="alert-view alert-orange" id="single"><div class="alert-motion-content">\(icon)\
    <div class="alert-content"><span id="text">Nothing was changed.</span></div></div></div>
    """

  static let dismissible = """
    <div class="alert-view alert-red" id="dismissible"><div class="alert-motion-content">\(icon)\
    <div class="alert-content"><span id="text">Sign in failed.</span></div>\
    <button type="button" class="alert-dismiss" id="dismiss" aria-label="Close">×</button></div></div>
    """

  static func html(_ body: String, dir: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let sheets = root.appendingPathComponent("gnorium-web/Public/style-sheets")
    var css = ""
    for name in ["layout-view", "alert-view", "alert-line-view", "expandable-attachment-view"] {
      let file = sheets.appendingPathComponent("\(name).css")
      guard let text = try? String(contentsOf: file, encoding: .utf8) else {
        try Test.cancel("Build gnorium-web's stylesheets with make styles first (\(name).css)")
      }
      css += text + "\n"
    }
    return """
      <!doctype html><html lang="en" dir="\(dir)"><head><meta charset="utf-8"><link rel="icon" href="data:,">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>\(css)</style>
      <style>body { margin: 0; padding: 16px } .page { display: flex; flex-direction: column; gap: 16px }</style>
      </head><body><div class="page">\(body)</div>
      <script>
      const rtl = document.documentElement.dir === 'rtl';
      // Along the inline axis, from the start: the left edge left to right,
      // the right edge (negated) right to left.
      const start = (r) => rtl ? -(r.x + r.width) : r.x;
      const end = (r) => rtl ? -r.x : r.x + r.width;
      const rect = (e) => e.getBoundingClientRect();
      // The text's line fragments, grouped into lines by their top.
      function lines(root) {
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT), found = [];
        while (walker.nextNode()) {
          const node = walker.currentNode;
          if (!node.textContent.trim()) continue;
          const range = document.createRange(); range.selectNodeContents(node);
          for (const r of range.getClientRects()) if (r.width > 0) found.push(r);
        }
        found.sort((a, b) => a.y - b.y);
        const out = [];
        for (const r of found) {
          const line = out.find((l) => Math.abs(l.top - r.y) < 8);
          if (line) { line.start = Math.min(line.start, start(r)); line.bottom = Math.max(line.bottom, r.y + r.height) }
          else out.push({ top: r.y, bottom: r.y + r.height, start: start(r) });
        }
        return out;
      }
      window.measure = {
        alert(id) {
          const a = document.getElementById(id), icon = a.querySelector('.alert-icon svg'),
            iconBox = rect(a.querySelector('.alert-icon')), content = a.querySelector('.alert-content'),
            s = getComputedStyle(a), img = a.querySelector('.expandable-attachment-view img');
          const ab = rect(a), ib = rect(icon);
          const inset = parseFloat(s.paddingInlineStart) + parseFloat(s.borderInlineStartWidth);
          return { alertStart: start(ab) + inset, iconStart: start(ib), iconEnd: end(iconBox),
            iconTop: ib.y, iconBottom: ib.y + ib.height, contentStart: start(rect(content)), lines: lines(content),
            lineHeight: parseFloat(getComputedStyle(content).lineHeight),
            thumb: img ? { top: rect(img).y, bottom: rect(img).y + rect(img).height, width: rect(img).width,
              height: rect(img).height, caption: img.closest('.expandable-attachment-trigger').textContent.trim() } : null,
            scrollWidth: document.documentElement.scrollWidth, clientWidth: document.documentElement.clientWidth }
        },
        pieces() {
          const a = document.getElementById('faults'), words = rect(document.getElementById('words')),
            aside = rect(document.getElementById('aside')), line = document.getElementById('line'),
            heading = document.querySelector('#heading .alert-line-words');
          return { iconTop: rect(a.querySelector('.alert-icon')).y, headingTop: rect(heading).y,
            headingWeight: getComputedStyle(heading).fontWeight, wordsTop: words.y, wordsBottom: words.y + words.height,
            wordsStart: start(words), wordsEnd: end(words), asideTop: aside.y, asideStart: start(aside),
            detailEnd: end(rect(document.getElementById('detail'))), contentEnd: end(rect(a.querySelector('.alert-content'))),
            rowGap: getComputedStyle(line).rowGap, columnGap: getComputedStyle(line).columnGap }
        },
        single(id) {
          const a = document.getElementById(id), text = rect(a.querySelector('#text')), icon = rect(a.querySelector('.alert-icon')),
            dismiss = a.querySelector('#dismiss'), d = dismiss ? rect(dismiss) : null, ab = rect(a);
          return { alertTop: ab.y, alertBottom: ab.y + ab.height, iconCenter: icon.y + icon.height / 2,
            textCenter: text.y + text.height / 2, textEnd: end(text),
            dismissCenter: d ? d.y + d.height / 2 : null, dismissStart: d ? start(d) : null, dismissHeight: d ? d.height : null }
        },
      };
      </script></body></html>
      """
  }

  static func render(
    width: Int, dir: String = "ltr", _ body: String, _ test: @Sendable (Page) async throws -> Void
  ) async throws {
    let server = try await FixtureServer(files: [
      "/": .init(contentType: "text/html", body: Data(try Self.html(body, dir: dir).utf8)),
      "/page.svg": .init(
        contentType: "image/svg+xml",
        body: Data(
          #"<svg xmlns="http://www.w3.org/2000/svg" width="300" height="400"><rect width="300" height="400" fill="gainsboro"/><circle cx="150" cy="200" r="90" fill="royalblue"/></svg>"#
            .utf8)),
    ])
    defer { server.stop() }
    let config = BrowserTestConfiguration(
      baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(30))
    try await withPage(.chrome, config, viewport: .init(width: width, height: 800)) { page in
      try await page.goto("/")
      try await test(page)
    }
  }

  // MARK: - An inline alert

  /// The mark is an inline icon at the start of the first line, the words
  /// right after it; the lines they wrap to start at the alert's start
  /// edge, under the mark; the thumbnail is a line high in the flow, with
  /// no caption, and opens no line of its own.
  @Test(arguments: [1000, 375], ["ltr", "rtl"])
  func anInlineAlertWrapsUnderItsMark(width: Int, dir: String) async throws {
    try await Self.render(width: width, dir: dir, Self.notice) { page in
      try await expect(page.locator("#notice img")).toBeVisible()
      let a = try await page.evaluate("window.measure.alert('notice')", as: Alert.self)
      let first = try #require(a.lines.first)
      #expect(a.lines.count >= 2, "the sentence wraps at \(width) \(dir): \(a.lines.count) lines")
      #expect(abs(a.iconCenter - first.center) <= 3, "the mark is on the first line: \(a.iconCenter) vs \(first.center)")
      #expect(abs(a.iconStart - a.alertStart) <= 1, "the mark starts the line: \(a.iconStart) vs \(a.alertStart)")
      #expect(abs(first.start - a.iconEnd) <= 1.5, "the words follow the mark: \(first.start) vs \(a.iconEnd)")
      for line in a.lines.dropFirst() {
        #expect(abs(line.start - a.iconStart) <= 1, "a wrapped line starts under the mark: \(line.start) vs \(a.iconStart)")
      }
      // One line high each: the mark and the thumbnail open no line.
      for (above, below) in zip(a.lines, a.lines.dropFirst()) {
        #expect(abs(below.top - above.top - a.lineHeight) <= 1.5, "lines \(a.lineHeight) apart: \(below.top - above.top)")
      }
      let thumb = try #require(a.thumb)
      #expect(abs(thumb.height - a.lineHeight) <= 0.5, "the thumbnail is a line high: \(thumb.height)")
      #expect(abs(thumb.width - a.lineHeight) <= 0.5, "and as wide: \(thumb.width)")
      #expect(thumb.caption == "", "no caption: \(thumb.caption)")
      #expect(a.lines.contains { abs($0.center - thumb.center) <= 3 }, "the thumbnail stands in a line of the words")
      #expect(a.scrollWidth <= a.clientWidth, "no sideways scroll: \(a.scrollWidth) vs \(a.clientWidth)")
    }
  }

  // MARK: - A boxed alert

  /// The mark is in a column of its own, level with the first line; every
  /// line of the content starts at the content's column, past the mark.
  @Test(arguments: [1000, 375], ["ltr", "rtl"])
  func aBoxedAlertWrapsInItsOwnColumn(width: Int, dir: String) async throws {
    try await Self.render(width: width, dir: dir, Self.boxed) { page in
      let a = try await page.evaluate("window.measure.alert('boxed')", as: Alert.self)
      let first = try #require(a.lines.first)
      #expect(a.lines.count >= 2, "the words wrap at \(width) \(dir): \(a.lines.count) lines")
      #expect(abs(a.iconCenter - first.center) <= 2, "the mark is level with the first line: \(a.iconCenter) vs \(first.center)")
      #expect(abs(a.contentStart - a.iconEnd - 8) <= 1, "a gap of 8 after the mark: \(a.contentStart - a.iconEnd)")
      for line in a.lines {
        #expect(abs(line.start - a.contentStart) <= 1, "every line starts at the content's column: \(line.start) vs \(a.contentStart)")
        #expect(line.start > a.iconEnd, "never under the mark")
      }
      #expect(a.scrollWidth <= a.clientWidth, "no sideways scroll")
    }
  }

  /// A line of text sits in the alert's minimum height as it always did:
  /// the mark and the text on one center.
  @Test func aSingleLineIsCenteredInTheMinimumHeightWithItsMark() async throws {
    try await Self.render(width: 1000, Self.single) { page in
      let s = try await page.evaluate("window.measure.single('single')", as: Single.self)
      #expect(s.alertBottom - s.alertTop >= 63.5, "the minimum height: \(s.alertBottom - s.alertTop)")
      #expect(abs(s.iconCenter - s.textCenter) <= 1, "one center: \(s.iconCenter) vs \(s.textCenter)")
      #expect(abs(s.iconCenter - (s.alertTop + s.alertBottom) / 2) <= 1, "centered in the box")
    }
  }

  /// With a close button its 40px target is the first row: the mark and
  /// the line stand level with its center.
  @Test(arguments: ["ltr", "rtl"])
  func aCloseButtonIsOnTheSameCenterAsTheMarkAndTheLine(dir: String) async throws {
    try await Self.render(width: 1000, dir: dir, Self.dismissible) { page in
      let s = try await page.evaluate("window.measure.single('dismissible')", as: Single.self)
      let center = try #require(s.dismissCenter)
      #expect(abs((s.dismissHeight ?? 0) - 40) <= 0.5, "a 40px target")
      #expect(abs(s.iconCenter - center) <= 1, "the mark: \(s.iconCenter) vs \(center)")
      #expect(abs(s.textCenter - center) <= 1, "the line: \(s.textCenter) vs \(center)")
      #expect((s.dismissStart ?? 0) > s.textEnd, "the button is last")
    }
  }

  // MARK: - A line with something beside its words

  /// A short detail follows its words on the same row, with a gap between.
  @Test(arguments: ["ltr", "rtl"])
  func aDetailFollowsItsWordsOnTheRowWhereItFits(dir: String) async throws {
    try await Self.render(width: 1000, dir: dir, Self.faults(detail: "#p5-wz17")) { page in
      let p = try await page.evaluate("window.measure.pieces()", as: Pieces.self)
      #expect(abs(p.asideTop - p.wordsTop) <= 1, "the same row: \(p.asideTop) vs \(p.wordsTop)")
      #expect(abs(p.asideStart - p.wordsEnd - 8) <= 1, "after the words, a gap of 8: \(p.asideStart - p.wordsEnd)")
      #expect(p.columnGap == "8px" && p.rowGap == "4px", "gaps, never margins: \(p.columnGap) \(p.rowGap)")
      #expect(abs(p.iconTop - p.headingTop) <= 1, "the mark is level with the heading line, the first row")
      #expect(p.headingWeight == "600", "the heading is semibold: \(p.headingWeight)")
    }
  }

  /// A detail too long for the row drops under the words, shrinking to the
  /// column rather than widening the alert; the mark stays on the first row.
  @Test(arguments: ["ltr", "rtl"])
  func aLongDetailDropsToTheNextRowAndKeepsToTheColumn(dir: String) async throws {
    let long = "#" + String(repeating: "p5-wz17-", count: 40)
    try await Self.render(width: 375, dir: dir, Self.faults(detail: long)) { page in
      let p = try await page.evaluate("window.measure.pieces()", as: Pieces.self)
      #expect(abs(p.asideTop - p.wordsBottom - 4) <= 1, "under the words, a row gap of 4: \(p.asideTop - p.wordsBottom)")
      #expect(abs(p.asideStart - p.wordsStart) <= 1, "at the words' start")
      #expect(p.detailEnd <= p.contentEnd + 1, "kept to the column: \(p.detailEnd) vs \(p.contentEnd)")
      #expect(abs(p.iconTop - p.headingTop) <= 1, "the mark stays on the first row")
    }
  }
}
