import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The madrigal page's column holds its margin through everything its reader
/// does (user, 2026-11-05: "again this bug of margin clipped … in zoomed out
/// mode? your agents always test in their own zoomed out resolution"): at
/// the user's browser pane (770×923 CSS px at 2x), at the CSS widths that
/// pane's zoom levels give (90, 80, 75 and 67%: the window's size over the
/// zoom, its pixel ratio times it), and at a phone's and a wide screen's.
/// After each interaction—a figure clicked (its gloss closed by its × and by
/// Escape), the page turned on and back, Raw, Reflow, Detach and Overlay on
/// and off, full screen in and out, the Prompts' and the Arbitration's
/// sections opened and closed—the page has not scrolled sideways, no box
/// around the column has (nor any box that only clips), and every section
/// of the column starts where it started. A failure names the interaction
/// and the box.
///
/// The same pass checks the figure and the page's diff: a figure draws no
/// description of its own (its `<figDesc>` is the encoder's, never printed:
/// user, 2026-11-05), shows none on press, and goes straight to its gloss,
/// which carries the description, as the page's XML does; under Raw the
/// page's diff is the lines Raw shows, line for line, and its box stays in
/// the text pane.
///
/// On the user's own page (Hamlet Q1, its title page: a woodcut device, its
/// markup added since the overture), read only; `READER_MARGIN_PAGE` names
/// another. Cancelled where the server has no such page.
@Suite("Reader margins", .serialized)
struct ReaderMarginTests {
  static let path =
    ProcessInfo.processInfo.environment["READER_MARGIN_PAGE"]
    ?? "/mission-control/madrigals/bibliographic/01A1946C-E748-8060-B4D7-1B8B13227FB0?frame=6"

  struct Size: Sendable, CustomStringConvertible {
    let name: String
    let viewport: Viewport
    var description: String { name }
  }

  /// The pane at 100% and zoomed out: its 770×923 over the zoom.
  static let sizes: [Size] = [
    .init(name: "pane 770x923@2", viewport: Viewport(width: 770, height: 923, deviceScaleFactor: 2)),
    .init(name: "pane at 90% 856x1026", viewport: Viewport(width: 856, height: 1026, deviceScaleFactor: 1.8)),
    .init(name: "pane at 80% 963x1154", viewport: Viewport(width: 963, height: 1154, deviceScaleFactor: 1.6)),
    .init(name: "pane at 75% 1027x1231", viewport: Viewport(width: 1027, height: 1231, deviceScaleFactor: 1.5)),
    .init(name: "pane at 67% 1149x1378", viewport: Viewport(width: 1149, height: 1378, deviceScaleFactor: 1.34)),
    .init(name: "phone 375", viewport: .phone),
    .init(name: "wide 1280x923@2", viewport: Viewport(width: 1280, height: 923, deviceScaleFactor: 2)),
  ]

  /// The madrigal's own reader; the record tree above it holds other
  /// witnesses' readers.
  static let reader = ".madrigal-object .artifact-view"

  /// The page on screen in the reader's text pane: never the page's diff
  /// under it (`.artifact-under-markup`), whose fragment draws the page
  /// again, its page active too (TestamentView `.testament-diff`).
  static let page = ".artifact-markup .tei-page[data-active='true']"

  /// Whether the reader's pages either side of the one on screen are all in
  /// (TestamentView's windowed reader, `reach` 4). As the page starts it
  /// asks for them at once, with its thread: nine requests on Chrome's six
  /// connections a host, each seconds long on a busy server. A gloss pressed
  /// meanwhile waits its turn behind them, which is no matter of the margin,
  /// so nothing is pressed before they are in.
  static let neighborsIn = """
    (() => { const r = document.querySelector(`\(ReaderMarginTests.reader)`);
      const at = parseInt(r?.querySelector(`\(ReaderMarginTests.page)`)?.dataset.pageIndex ?? '');
      const total = parseInt(r?.querySelector('#artifact-page-total, .artifact-page-total')?.textContent ?? '');
      if (isNaN(at) || isNaN(total)) return true;
      const want = Math.min(at + 4, total - 1) - Math.max(at - 4, 0) + 1;
      return r.querySelectorAll('.artifact-markup .tei-page').length >= want; })()
    """

  /// What the checks read, kept on the page: a box's name, where each of
  /// the column's sections starts, and what moved since `before`.
  static let helpers = """
    (() => {
      const name = (e) => e === document.documentElement ? 'html' : e === document.body ? 'body'
        : ((e.className && e.className.baseVal === undefined ? e.className : '') || e.tagName).toString().split(' ')[0];
      const edges = () => {
        const out = {};
        const column = document.querySelector('.disputorium-core-view');
        [...column.children].forEach((c, i) => {
          if (c.getClientRects().length) out[name(c) + ' #' + i] = Math.round(c.getBoundingClientRect().left * 10) / 10;
        });
        for (const h of column.querySelectorAll('.prompt-previews-heading, .thread-heading')) {
          if (h.getClientRects().length) out[name(h)] = Math.round(h.getBoundingClientRect().left * 10) / 10;
        }
        return out;
      };
      const check = (before) => {
        const out = [];
        if (scrollX !== 0) out.push('the page scrolled sideways (scrollX ' + scrollX + ')');
        for (let e = document.querySelector('.disputorium-core-view'); e; e = e.parentElement)
          if (e.scrollLeft !== 0) out.push('the column\\'s box ' + name(e) + ' scrolled sideways (' + e.scrollLeft + ')');
        // A box people cannot scroll, scrolled by a focus or a scrollIntoView.
        for (const e of document.querySelectorAll('body *')) {
          if (e.scrollLeft === 0) continue;
          const ox = getComputedStyle(e).overflowX;
          if (ox === 'hidden' || ox === 'clip') out.push('the clipping box ' + name(e) + ' scrolled sideways (' + e.scrollLeft + ')');
        }
        const now = edges();
        for (const k of Object.keys(before))
          if (k in now && Math.abs(now[k] - before[k]) > 0.5) out.push(k + ' moved from ' + before[k] + ' to ' + now[k]);
        return [...new Set(out)].join('; ');
      };
      window.__margins = { name, edges, check };
      return true;
    })()
    """

  /// Where to press `selector` (the first shown and enabled in the reader),
  /// the page scrolled up or down to it, never sideways; nil where there is
  /// none. Sideways, only what a hand swipes moves: a box that scrolls
  /// (`auto` or `scroll`) and holds it past its edge brings it in, as the
  /// reader's footer does at a phone's width, where its pager's next stands
  /// past the footer's end (ArtifactView: one row that scrolls sideways
  /// under its own scrollbar, user 2026-11-03). Pressed where it stood, the
  /// press reached nothing and the page never turned.
  static func center(_ page: Page, _ selector: String) async throws -> (Double, Double)? {
    let point = try await page.evaluate(
      """
      (() => {
        const e = [...document.querySelectorAll(`\(selector)`)].find((x) => x.getClientRects().length && !x.disabled);
        if (!e) return null;
        for (let s = e.parentElement; s && s !== document.body && s !== document.documentElement; s = s.parentElement) {
          const ox = getComputedStyle(s).overflowX;
          if ((ox !== 'auto' && ox !== 'scroll') || s.scrollWidth <= s.clientWidth) continue;
          const a = e.getBoundingClientRect(), b = s.getBoundingClientRect();
          const start = b.left + s.clientLeft, end = start + s.clientWidth;
          if (a.left < start) s.scrollLeft += a.left - start - 8;
          else if (a.right > end) s.scrollLeft += a.right - end + 8;
        }
        let r = e.getBoundingClientRect();
        // Off screen, or under a bar that stays (the navbar): the page
        // scrolled up or down to it.
        const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
        if (r.top < 0 || r.bottom > innerHeight || !hit || !e.contains(hit)) {
          scrollTo(0, scrollY + r.top - innerHeight / 3); r = e.getBoundingClientRect();
        }
        return [r.left + r.width / 2, r.top + r.height / 2];
      })()
      """)
    guard let values = point.array, values.count == 2, let x = values[0].double, let y = values[1].double else {
      return nil
    }
    return (x, y)
  }

  static func press(_ page: Page, at point: (Double, Double)) async throws {
    try await page.mouse.move(x: point.0, y: point.1)
    try await page.mouse.down(x: point.0, y: point.1)
    try await page.mouse.up(x: point.0, y: point.1)
  }

  @Test(arguments: ReaderMarginTests.sizes)
  func theColumnHoldsItsMarginThroughEveryInteraction(size: Size) async throws {
    guard gnorium.engines.contains(.chrome) else { return }
    try await withPage(.chrome, gnorium, viewport: size.viewport) { page in
      let opened = try await page.goto(Self.path, waitUntil: .load)
      if let status = opened.status, status >= 400 {
        try Test.cancel(Comment(rawValue: "\(Self.path) answered HTTP \(status) on this server"))
      }
      try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
      let reader = page.locator(Self.reader).first
      // The page in the reader's text pane (`Self.page`): the diff under it
      // holds the page drawn again.
      try await expect(reader.locator("\(Self.page) .tei-figure")).toHaveCount(1)
      // The reader's own loads in before anything is pressed (`neighborsIn`).
      var settled = try await page.evaluate(Self.neighborsIn, as: Bool.self)
      for _ in 0..<150 where !settled {
        try await Task.sleep(for: .milliseconds(200))
        settled = try await page.evaluate(Self.neighborsIn, as: Bool.self)
      }
      #expect(settled, "\(size): the reader's pages beside the one on screen never all came")
      _ = try await page.evaluate(Self.helpers)
      // The pane the user reads at, as the page reports it.
      let reported = try await page.evaluate("[innerWidth, innerHeight, devicePixelRatio].join('x')", as: String.self)
      let place = "\(size) (\(reported))"

      var ran: [String] = []
      var skipped: [String] = []
      /// `action` done, then the margin checked against before it.
      func step(_ name: String, settle: Int = 450, _ action: () async throws -> Bool) async throws {
        _ = try await page.evaluate("(() => { window.__before = __margins.edges(); return true })()")
        guard try await action() else {
          skipped.append(name)
          return
        }
        ran.append(name)
        try await Task.sleep(for: .milliseconds(settle))
        let problems = try await page.evaluate("__margins.check(window.__before)", as: String.self)
        #expect(problems.isEmpty, "\(place), after \(name): \(problems)")
      }
      /// A control of the reader pressed as a hand presses it, and the
      /// press reaching it: a control out of its box's view or under
      /// another took none, and its step proved nothing.
      func control(_ selector: String) async throws -> Bool {
        guard let point = try await Self.center(page, "\(Self.reader) \(selector)") else { return false }
        let reached = try await page.evaluate(
          """
          (() => { const e = [...document.querySelectorAll(`\(Self.reader) \(selector)`)].find((x) => x.getClientRects().length && !x.disabled);
            const hit = document.elementFromPoint(\(point.0), \(point.1));
            return e && hit && e.contains(hit) ? '' : (hit ? __margins.name(hit) : 'nothing'); })()
          """, as: String.self)
        #expect(reached.isEmpty, "\(place): a press on \(selector) reaches \(reached)")
        try await Self.press(page, at: point)
        return true
      }

      // The figure: its description, on its drawing's label (or its crop's).
      let figure = "\(Self.reader) \(Self.page) .tei-figure"
      let description = try await page.evaluate(
        """
        (() => { const f = document.querySelector(`\(figure)`);
          const l = f.querySelector('svg[aria-label], img[alt]');
          return l ? (l.getAttribute('aria-label') || l.getAttribute('alt')) : ''; })()
        """, as: String.self)
      #expect(!description.isEmpty, "\(place): the figure has no description on its drawing")
      let probe = String(description.prefix(30)).replacingOccurrences(of: "'", with: "\\'")
      // Nothing of it drawn on the page: no caption, no text in the figure.
      let drawn = try await page.evaluate(
        "(() => { const f = document.querySelector(`\(figure)`); return f.querySelectorAll('figcaption').length + '|' + f.innerText.trim() })()",
        as: String.self)
      #expect(drawn == "0|", "\(place): the figure draws its description: \(drawn)")
      /// What shows the description outside its XML: a caption, a tooltip,
      /// a title, any text on screen with it.
      let shown = """
        (() => {
          const out = [];
          if (document.querySelector('.tei-figure figcaption, .tei-figure .tei-figure-caption')) out.push('a caption');
          if (document.querySelector('.tei-figure[title], .tei-figure [title]')) out.push('a title');
          for (const t of document.querySelectorAll('.tooltip-content')) {
            const s = getComputedStyle(t);
            if (t.getClientRects().length && s.visibility !== 'hidden' && s.opacity !== '0') out.push('a tooltip: ' + t.textContent.slice(0, 40));
          }
          const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
          for (let n; (n = w.nextNode()); ) {
            if (!n.data.includes('\(probe)')) continue;
            const e = n.parentElement;
            if (e.closest('.tei-page-raw, .code-view, .diff-view, .gloss-view, script')) continue;
            if (e.getClientRects().length && getComputedStyle(e).visibility !== 'hidden') out.push('the description drawn in ' + __margins.name(e));
          }
          return out.join('; ');
        })()
        """

      /// The figure pressed: brought into its pane by the pane's own scroll,
      /// then held down (nothing shows its description), then let go: its
      /// gloss opens, titled by no description, carrying it in its body.
      func pressFigure() async throws -> Bool {
        _ = try await page.evaluate(
          """
          (() => { const f = document.querySelector(`\(figure)`), pane = f.closest('.artifact-markup');
            const r = f.getBoundingClientRect(), p = pane.getBoundingClientRect();
            pane.scrollTop += r.top - p.top - 8; return true })()
          """)
        guard let point = try await Self.center(page, figure) else { return false }
        try await page.mouse.move(x: point.0, y: point.1)
        try await page.mouse.down(x: point.0, y: point.1)
        let pressed = try await page.evaluate(shown, as: String.self)
        #expect(pressed.isEmpty, "\(place): pressed, the figure shows its description: \(pressed)")
        try await page.mouse.up(x: point.0, y: point.1)
        let opening = try await page.evaluate(
          "(() => (document.querySelector('.gloss-sheet .gloss-sheet-title')?.textContent || '').includes('\(probe)'))()",
          as: Bool.self)
        #expect(!opening, "\(place): the gloss opens titled by the figure's description")
        let sheet = page.locator(".gloss-sheet")
        try await expect(sheet).toHaveAttribute("data-state", "open")
        try await expect(sheet.locator(".gloss-view")).toContainText(String(description.prefix(30)))
        let after = try await page.evaluate(shown, as: String.self)
        #expect(after.isEmpty, "\(place): with its gloss open, the figure shows its description: \(after)")
        return true
      }

      try await step("figure clicked") { try await pressFigure() }
      try await step("gloss closed by its ×") {
        guard let point = try await Self.center(page, ".gloss-sheet[data-state='open'] .dialog-sheet-close") else {
          return false
        }
        try await Self.press(page, at: point)
        try await expect(page.locator(".gloss-sheet")).toHaveAttribute("data-state", "closed")
        return true
      }
      try await step("figure clicked again") { try await pressFigure() }
      try await step("gloss closed by Escape") {
        try await page.keyboard.press("Escape")
        try await expect(page.locator(".gloss-sheet")).toHaveAttribute("data-state", "closed")
        return true
      }
      // The roster's own scroller, where the sidebar shows (not the phone
      // menu's copy): a page turn brings its selected row into view there
      // alone (`ScrollPort.reveal`), never by `scrollIntoView`, which moved
      // every box around the row, the clipping ones among them.
      let sidebar =
        "[...document.querySelectorAll('.sidebar-content')].find((e) => !e.closest('.navbar-slide-menu') && e.getClientRects().length)"
      /// Where the roster's selected row is against its scroller; "" when it
      /// is in view, or where no sidebar shows.
      func rosterRow() async throws -> String {
        try await page.evaluate(
          """
          (() => { const s = \(sidebar); if (!s) return '';
            const r = s.querySelector('.roster-row.roster-row-selected');
            if (!r) return 'no selected row in the roster';
            const a = r.getBoundingClientRect(), b = s.getBoundingClientRect();
            return a.top >= b.top - 0.5 && a.bottom <= b.bottom + 0.5 ? ''
              : 'the selected row at ' + Math.round(a.top) + '–' + Math.round(a.bottom)
                + ', the sidebar ' + Math.round(b.top) + '–' + Math.round(b.bottom); })()
          """, as: String.self)
      }
      try await step("page next", settle: 900) {
        // The sidebar scrolled to its end first, so the turn has to bring
        // the row back.
        _ = try await page.evaluate("(() => { const s = \(sidebar); if (s) s.scrollTop = s.scrollHeight; return true })()")
        return try await control(".artifact-page-nav .pagination-next-container button")
      }
      let revealed = try await rosterRow()
      #expect(revealed.isEmpty, "\(place), after page next: the roster did not show its selected row: \(revealed)")
      try await step("page previous", settle: 900) {
        try await control(".artifact-page-nav .pagination-previous-container button")
      }
      try await expect(reader.locator("\(Self.page) .tei-figure")).toHaveCount(1)

      // Raw: the page's diff, the lines Raw shows, its box in the text pane.
      try await step("Raw on") { try await control(".artifact-xml-toggle button") }
      let diff = try await page.evaluate(
        """
        (() => {
          const view = document.querySelector(`\(Self.reader)`);
          const raw = view.querySelector(`\(Self.page) .tei-page-raw`);
          const lines = [...raw.querySelectorAll('.code-line')].map((l) => l.textContent.replace(/\\n$/, ''));
          const start = lines.findIndex((l) => l.trim() === '<text><body>'), end = lines.findIndex((l) => l.trim() === '</body></text>');
          const body = lines.slice(start + 1, end).filter((l) => l.trim());
          const slot = view.querySelector('.testament-diff[data-active="true"]');
          const box = slot && slot.querySelector('.diff-view[data-diff-mode="code"] .diff-box');
          if (!box) return { found: false };
          const inserted = [...box.querySelectorAll('.diff-row[data-diff-line="inserted"] .diff-content')]
            .map((c) => c.textContent.replace(/\\n$/, '')).filter((l) => l.trim());
          const pane = view.querySelector('.artifact-markup-viewport').getBoundingClientRect();
          return { found: true, rawHasDescription: raw.textContent.includes('\(probe)'), body, inserted,
            boxRight: box.getBoundingClientRect().right, paneRight: pane.right };
        })()
        """)
      if diff.object?["found"]?.bool == true {
        #expect(diff.object?["rawHasDescription"]?.bool == true, "\(place): the page's XML lacks the figure's description")
        let body = diff.object?["body"]?.array?.compactMap(\.string) ?? []
        let inserted = diff.object?["inserted"]?.array?.compactMap(\.string) ?? []
        #expect(body.count > 3, "\(place): Raw shows the page on \(body.count) lines")
        // A page added since the overture: every line Raw shows added, as Raw shows it.
        #expect(inserted == body, "\(place): the diff's lines are not Raw's: \(inserted.prefix(3)) vs \(body.prefix(3))")
        let boxRight = diff.object?["boxRight"]?.double ?? .infinity
        let paneRight = diff.object?["paneRight"]?.double ?? 0
        #expect(boxRight <= paneRight + 0.5, "\(place): the diff's box runs to \(boxRight), past the text pane's \(paneRight)")
      } else {
        Issue.record("\(place): no diff under Raw on the page")
      }
      // The code scrolled sideways, its diff's box follows, and the box
      // scrolled, the code follows (user, 2026-11-05: the title page's code
      // scrolled right, its diff left at 0), where the code runs past its
      // pane at this size.
      let across = try await page.evaluate(
        """
        (async () => {
          const frames = async () => { for (let i = 0; i < 10; i++) await new Promise(requestAnimationFrame); };
          const view = document.querySelector(`\(Self.reader)`), pane = view.querySelector('.artifact-markup');
          const box = view.querySelector(".testament-diff[data-active='true'] .diff-view[data-diff-mode='code'] .diff-box");
          if (!box || pane.scrollWidth <= pane.clientWidth + 40 || box.scrollWidth <= box.clientWidth + 40) return '';
          const out = [];
          for (const [side, other, left] of [[pane, box, 30], [box, pane, 15], [pane, box, 40]]) {
            side.scrollLeft = left; await frames();
            if (Math.abs(other.scrollLeft - side.scrollLeft) > 1)
              out.push((side === pane ? 'the code' : 'the diff') + ' scrolled to ' + side.scrollLeft + ', the other stood at ' + other.scrollLeft);
          }
          pane.scrollLeft = 0; await frames();
          return out.join('; ');
        })()
        """, as: String.self)
      #expect(across.isEmpty, "\(place), under Raw: \(across)")
      try await step("Raw off") { try await control(".artifact-xml-toggle button") }
      try await step("Reflow on") { try await control(".artifact-reflow-toggle button") }
      try await step("Reflow off") { try await control(".artifact-reflow-toggle button") }
      try await step("Detach on") { try await control(".artifact-detach-toggle button") }
      try await step("Detach off") { try await control(".artifact-detach-toggle button") }
      try await step("Overlay on", settle: 900) { try await control(".artifact-overlay-toggle button") }
      try await step("Overlay off", settle: 900) { try await control(".artifact-overlay-toggle button") }
      try await step("full screen in", settle: 900) { try await control("#artifact-fullscreen-btn") }
      try await step("full screen out", settle: 900) { try await control("#artifact-fullscreen-btn") }

      // The sections under the reader, opened and closed.
      try await expect(page.locator(".prompt-previews-view .accordion-summary").first, timeout: .seconds(20)).toBeVisible()
      func section(_ selector: String) async throws -> Bool {
        guard let point = try await Self.center(page, selector) else { return false }
        try await Self.press(page, at: point)
        return true
      }
      try await step("a prompt opened", settle: 700) { try await section(".prompt-previews-view .accordion-summary") }
      try await step("a prompt closed", settle: 700) { try await section(".prompt-previews-view .accordion-summary") }
      try await step("Arbitration folded", settle: 700) { try await section(".thread-view .thread-collapse") }
      try await step("Arbitration opened", settle: 700) { try await section(".thread-view .thread-collapse") }

      // Every interaction ran where its control is offered; Detach and
      // Overlay are offered only on a traced page.
      let required = ["figure clicked", "page next", "page previous", "Raw on", "Reflow on", "full screen in"]
      for name in required { #expect(ran.contains(name), "\(place): \(name) did not run (skipped: \(skipped))") }
      try await page.expectNoErrors(ignoring: ["Failed to fetch"])
    }
  }

  /// The title page's reader keeps its foot and its page (user, 2026-11-05:
  /// at narrow widths a tall page pushed the reader's footer off, under the
  /// sections below it, which took its presses): at 455, 600 and the
  /// user's 770, with the images off and on, the footer stands inside the
  /// reader and its Reflow is what a press there reaches; the page, at its
  /// fit, runs past neither its scale box (`[data-page-scale]`) nor the
  /// pane, which scrolls neither way.
  @Test(arguments: [455, 600, 770])
  func theTitlePageKeepsItsFooterAndItsFit(width: Int) async throws {
    guard gnorium.engines.contains(.chrome) else { return }
    try await withPage(.chrome, gnorium, viewport: Viewport(width: width, height: 923, deviceScaleFactor: 2)) { page in
      let opened = try await page.goto(Self.path, waitUntil: .load)
      if let status = opened.status, status >= 400 {
        try Test.cancel(Comment(rawValue: "\(Self.path) answered HTTP \(status) on this server"))
      }
      try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
      let reader = page.locator(Self.reader).first
      try await expect(reader.locator("\(Self.page) > [data-page-scale='true']"), timeout: .seconds(20)).toHaveCount(1)
      try await expect(reader, timeout: .seconds(20)).toHaveAttribute("data-canvas-confirmed", "true")
      let check = """
        (() => {
          const view = document.querySelector(`\(Self.reader)`), out = [];
          const name = (e) => !e ? 'nothing' : ((e.className && e.className.baseVal === undefined ? e.className : '') || e.tagName).toString().split(' ')[0];
          const r = (b) => [b.left, b.top, b.right, b.bottom].map((n) => Math.round(n)).join(',');
          const footer = view.querySelector('.artifact-footer');
          let f = footer.getBoundingClientRect();
          if (f.bottom > innerHeight || f.top < 0) { scrollTo(0, scrollY + f.bottom - innerHeight + 16); f = footer.getBoundingClientRect(); }
          const v = view.getBoundingClientRect();
          if (f.left < v.left - 0.5 || f.top < v.top - 0.5 || f.right > v.right + 0.5 || f.bottom > v.bottom + 0.5)
            out.push('the footer at ' + r(f) + ' stands outside the reader at ' + r(v));
          const button = view.querySelector('.artifact-reflow-toggle button');
          if (!button) out.push('no Reflow in the footer'); else {
            const b = button.getBoundingClientRect(), hit = document.elementFromPoint(b.left + b.width / 2, b.top + b.height / 2);
            if (!hit || !button.contains(hit)) out.push('a press on Reflow reaches ' + name(hit));
          }
          const pane = view.querySelector('.artifact-markup');
          const box = pane.querySelector(`\(Self.page) > [data-page-scale='true']`);
          if (!box) out.push('the page has no scale box'); else {
            if (box.scrollWidth > box.clientWidth + 1 || box.scrollHeight > box.clientHeight + 1)
              out.push('the page runs past its scale box: ' + box.scrollWidth + 'x' + box.scrollHeight + ' in ' + box.clientWidth + 'x' + box.clientHeight);
            const p = pane.getBoundingClientRect(), q = box.getBoundingClientRect();
            const left = p.left + pane.clientLeft, top = p.top + pane.clientTop;
            if (q.left < left - 1 || q.top < top - 1 || q.right > left + pane.clientWidth + 1 || q.bottom > top + pane.clientHeight + 1)
              out.push('the scale box at ' + r(q) + ' runs past the pane at ' + [left, top, left + pane.clientWidth, top + pane.clientHeight].map(Math.round).join(','));
          }
          if (pane.scrollWidth > pane.clientWidth + 1 || pane.scrollHeight > pane.clientHeight + 1)
            out.push('the pane scrolls: ' + pane.scrollWidth + 'x' + pane.scrollHeight + ' in ' + pane.clientWidth + 'x' + pane.clientHeight);
          return out.join('; ');
        })()
        """
      for shown in [false, true] {
        let now = try await reader.getAttribute("data-canvas-shown") == "true"
        if now != shown { try await reader.locator(".artifact-canvas-toggle button").first.click() }
        try await expect(reader).toHaveAttribute("data-canvas-shown", shown ? "true" : "false")
        try await Task.sleep(for: .milliseconds(900))
        let problems = try await page.evaluate(check, as: String.self)
        #expect(problems.isEmpty, "at \(width), the images \(shown ? "on" : "off"): \(problems)")
      }
      try await page.expectNoErrors(ignoring: ["Failed to fetch"])
    }
  }

  /// Hamlet Q1's front cover, the user's own (page 1 of the same madrigal;
  /// `READER_COVER_PAGE` names another).
  static let coverPath =
    ProcessInfo.processInfo.environment["READER_COVER_PAGE"]
    ?? "/mission-control/madrigals/bibliographic/01A1946C-E748-8060-B4D7-1B8B13227FB0?frame=0"

  /// Reflow changes only how text runs on and wraps, never the page's
  /// vertical rhythm (user, 2026-11-05: "why reflow changes vertical
  /// gaps?"; reflowed, "HAMLET", "SHAKESPEARE", the device and "LONDON
  /// 1603" each stood 25–40 px lower, the gaps between them grown): on the
  /// front cover, where nothing wraps, each line of its text and each
  /// figure stands as far below the page's top with Reflow on as off,
  /// within a pixel at the same zoom (each read in the page's own pixels,
  /// its scale taken out, then at Reflow off's scale).
  @Test(arguments: [770, 1280])
  func reflowKeepsTheCoversVerticalPlaces(width: Int) async throws {
    guard gnorium.engines.contains(.chrome) else { return }
    try await withPage(.chrome, gnorium, viewport: Viewport(width: width, height: 923, deviceScaleFactor: 2)) { page in
      let opened = try await page.goto(Self.coverPath, waitUntil: .load)
      if let status = opened.status, status >= 400 {
        try Test.cancel(Comment(rawValue: "\(Self.coverPath) answered HTTP \(status) on this server"))
      }
      try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
      let reader = page.locator(Self.reader).first
      try await expect(reader.locator("\(Self.page) > [data-page-scale='true']"), timeout: .seconds(20)).toHaveCount(1)
      try await expect(reader).toHaveAttribute("data-reflow", "false")
      try await Task.sleep(for: .milliseconds(700))
      struct Place: Decodable {
        let name: String
        let top: Double
      }
      struct Reading: Decodable {
        let scale: Double
        let places: [Place]
      }
      /// Each text line's glyphs' top and each figure's top, below the
      /// page's top, in the page's own pixels; and the page's scale.
      let read = """
        (() => {
          const layer = document.querySelector(`\(Self.reader) \(Self.page) [data-layer='rendering']`);
          const t = getComputedStyle(layer).transform;
          const scale = (t === 'none' ? 1 : new DOMMatrix(t).a) * (layer.currentCSSZoom || 1);
          const top = layer.getBoundingClientRect().top, places = [];
          layer.querySelectorAll('.tei-block').forEach((block, i) => {
            const range = document.createRange(); range.selectNodeContents(block);
            const rects = [...range.getClientRects()].filter((r) => r.width > 0 && r.height > 0);
            if (rects.length) places.push({ name: block.textContent.trim() || 'block ' + i, top: (Math.min(...rects.map((r) => r.top)) - top) / scale });
          });
          layer.querySelectorAll('.tei-figure').forEach((figure, i) => {
            places.push({ name: 'figure ' + (i + 1), top: (figure.getBoundingClientRect().top - top) / scale });
          });
          return { scale, places };
        })()
        """
      let off = try await page.evaluate(read, as: Reading.self)
      #expect(off.places.contains { $0.name.contains("HAMLET") }, "\(width): no HAMLET on the cover: \(off.places.map(\.name))")
      try await reader.locator(".artifact-reflow-toggle button").first.click()
      try await expect(reader).toHaveAttribute("data-reflow", "true")
      try await Task.sleep(for: .milliseconds(900))
      let on = try await page.evaluate(read, as: Reading.self)
      #expect(on.places.map(\.name) == off.places.map(\.name), "\(width): the cover holds other lines reflowed: \(on.places.map(\.name))")
      for (a, b) in zip(off.places, on.places) {
        let moved = (b.top - a.top) * off.scale
        #expect(abs(moved) <= 1, "\(width): reflowed, \(a.name) moved \(moved) px down, at Reflow off's zoom")
      }
      try await page.expectNoErrors(ignoring: ["Failed to fetch"])
    }
  }
}
