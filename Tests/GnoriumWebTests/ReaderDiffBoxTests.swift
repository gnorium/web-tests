import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A page's diff under Raw behaves as the pane above it (user, 2026-11-05:
/// "it should scroll just like the quote pane… in reflow mode diff should
/// reflow like the quote pane"). Reflow off: its lines unwrapped, as Raw's
/// are; its box fills the zone under the pane and is the one scroller, both
/// ways, so its sideways bar is at its foot, where the pane's is, and a
/// sideways scroll of either moves the other, every time (user, 2026-11-05:
/// Hamlet Q1's title page, its code scrolled right, its diff left at 0). Reflow on: each of its lines
/// breaks where Raw's same line breaks, and nothing scrolls sideways. At the
/// user's pane (770×923 at 2x), a narrow one and a wide one.
///
/// A throwaway contributor's scratch madrigal, its one page new (every line
/// of its code added): forty paragraphs, each one long line of the laid-out
/// code; its scan never served (the reader reads its text alone). Chrome.
@Suite("Reader diff box", .serialized)
struct ReaderDiffBoxTests {
  /// Forty paragraphs, each a line of the page's code as Raw shows it
  /// (`XMLFormatter.formatted`: a paragraph one line) and far wider than
  /// any pane.
  static let page: String = {
    let words = "the quick brown fox jumps over the lazy dog while the printer sets each line of type by hand"
    let paragraphs = (1...40).map { "<p>Paragraph \($0): \(words), \(words).</p>" }.joined()
    return #"<TEI><text><body><pb n="1" facs="https://web-tests.invalid/page-1/full/max/0/default.jpg"/><div>"#
      + paragraphs + "</div></body></text></TEI>"
  }()

  struct Size: Sendable, CustomStringConvertible {
    let width: Int
    var description: String { "\(width)x923@2" }
  }

  static let sizes: [Size] = [.init(width: 455), .init(width: 770), .init(width: 1280)]

  /// Where each of `element`'s text wraps: the offset, in its text, of the
  /// first character of each row after its first.
  static let breaks = """
    const breaks = (element) => {
      const out = [], walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT), range = document.createRange();
      let offset = 0, top = null;
      for (let node; (node = walker.nextNode()); ) {
        for (let i = 0; i < node.data.length; i++, offset++) {
          if (node.data[i] === '\\n') continue;
          range.setStart(node, i); range.setEnd(node, i + 1);
          const r = [...range.getClientRects()].find((q) => q.width > 0);
          if (!r) continue;
          if (top !== null && r.top > top + 1) out.push(offset);
          top = r.top;
        }
      }
      return out;
    };
    """

  @Test(arguments: ReaderDiffBoxTests.sizes)
  func theDiffBoxScrollsAndWrapsAsItsPane(size: Size) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(.chrome) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor)
    let json = String(decoding: try JSONSerialization.data(withJSONObject: ["teiXml": Self.page]), as: UTF8.self)
    do {
      _ = try TestAdmin.query(
        "UPDATE bibliographic_madrigals SET proposed_content_json = '\(json.replacingOccurrences(of: "'", with: "''"))' WHERE id = '\(commit.madrigalID)'")
      let viewport = Viewport(width: size.width, height: 923, deviceScaleFactor: 2)
      try await withPage(.chrome, gnorium, viewport: viewport, cookies: [contributor.cookie]) { page in
        try await page.openHydrated(commit.madrigalPath)
        let view = page.locator(".madrigal-object .artifact-view").first
        try await view.locator(".artifact-xml-toggle button").first.click()
        try await expect(view).toHaveAttribute("data-raw", "true")
        try await expect(view.locator(".artifact-under-markup").first).toHaveAttribute("data-shown", "true")
        try await expect(view.locator(".testament-diff[data-active='true'] .diff-row[data-diff-line='inserted']").first).toBeVisible()
        try await Task.sleep(for: .milliseconds(500))

        // Reflow off.
        let off = try await page.evaluate(
          """
          (async () => {
            const frames = async () => { for (let i = 0; i < 10; i++) await new Promise(requestAnimationFrame); };
            const view = document.querySelector('.madrigal-object .artifact-view'), pane = view.querySelector('.artifact-markup');
            const zone = view.querySelector('.artifact-under-markup');
            const box = zone.querySelector(".testament-diff[data-active='true'] .diff-view[data-diff-mode='code'] .diff-box");
            const out = [];
            if (!box) return 'no diff box under the pane';
            const s = getComputedStyle(box), z = getComputedStyle(zone);
            if (s.overflowX !== 'auto' || s.overflowY !== 'auto') out.push('the box does not scroll both ways: ' + s.overflowX + ' ' + s.overflowY);
            if (/(auto|scroll)/.test(z.overflowX + z.overflowY)) out.push('the zone is a scroller: ' + z.overflowX + ' ' + z.overflowY);
            if (zone.scrollWidth > zone.clientWidth + 1 || zone.scrollHeight > zone.clientHeight + 1)
              out.push('the zone overflows: ' + zone.scrollWidth + 'x' + zone.scrollHeight + ' in ' + zone.clientWidth + 'x' + zone.clientHeight);
            if (box.scrollWidth <= box.clientWidth) out.push('the long lines do not run past the box');
            if (box.scrollHeight <= box.clientHeight) out.push('the lines do not run past the box down');
            // The box fills its zone, the reader's inset above and below it: its foot, where its sideways bar is,
            // at the zone's, in sight.
            const b = box.getBoundingClientRect(), q = zone.getBoundingClientRect(), p = pane.getBoundingClientRect();
            if (Math.abs(b.bottom - (q.bottom - 16)) > 1) out.push('the box ends at ' + Math.round(b.bottom) + ', the zone at ' + Math.round(q.bottom));
            if (Math.abs(b.left - q.left) > 1 || Math.abs(b.right - q.right) > 1)
              out.push('the box spans ' + Math.round(b.left) + '–' + Math.round(b.right) + ', the column ' + Math.round(q.left) + '–' + Math.round(q.right));
            if (b.right > view.getBoundingClientRect().right + 0.5) out.push('the box runs past the reader');
            // Its lines unwrapped: each row in sight one line high.
            const lineHeight = parseFloat(getComputedStyle(box.querySelector('.diff-lines')).lineHeight);
            const tall = [...box.querySelectorAll('.diff-row')].map((r) => r.getBoundingClientRect())
              .filter((r) => r.bottom > b.top && r.top < b.bottom && r.height > lineHeight + 1);
            if (tall.length) out.push(tall.length + ' rows wrap, ' + Math.round(tall[0].height) + ' px for ' + lineHeight);
            // Sideways, either moves the other, every time: a move down
            // first, then moves across alone, each after one the other side
            // made (its echo never swallows the next).
            pane.scrollTop = 200; await frames();
            if (box.scrollTop <= 0) out.push('the pane scrolled down, the box stayed');
            for (const [side, other, left] of [[pane, box, 160], [box, pane, 320], [pane, box, 80], [pane, box, 240], [box, pane, 40], [box, pane, 200]]) {
              side.scrollLeft = left; await frames();
              if (Math.abs(other.scrollLeft - left) > 1)
                out.push((side === pane ? 'the pane' : 'the box') + ' scrolled to ' + left + ' across, the other stood at ' + other.scrollLeft);
            }
            pane.scrollLeft = 0; pane.scrollTop = 0; await frames();
            return out.join('; ');
          })()
          """, as: String.self)
        #expect(off.isEmpty, "\(size), Reflow off: \(off)")

        // Reflow on.
        try await view.locator(".artifact-reflow-toggle button").first.click()
        try await expect(view).toHaveAttribute("data-reflow", "true")
        try await Task.sleep(for: .milliseconds(700))
        struct Wrapped: Decodable {
          let problems: String
          let compared: Int
          let wrapping: Int
        }
        let on = try await page.evaluate(
          """
          (() => {
            \(Self.breaks)
            const view = document.querySelector('.madrigal-object .artifact-view');
            const zone = view.querySelector('.artifact-under-markup');
            const box = zone.querySelector(".testament-diff[data-active='true'] .diff-view[data-diff-mode='code'] .diff-box");
            const out = [];
            if (box.scrollWidth > box.clientWidth + 1) out.push('the box scrolls sideways: ' + box.scrollWidth + ' in ' + box.clientWidth);
            const code = [...view.querySelectorAll(".artifact-markup .tei-page[data-active='true'] .tei-page-raw .code-line")];
            const text = (e) => e.textContent.replace(/\\n$/, '');
            let compared = 0, wrapping = 0;
            for (const row of box.querySelectorAll(".diff-row[data-diff-line='inserted']")) {
              const content = row.querySelector('.diff-content'), line = text(content);
              if (!line.includes('<p>')) continue;
              const raw = code.find((c) => text(c) === line);
              if (!raw) { out.push('no Raw line reads ' + line.slice(0, 40)); continue; }
              const a = breaks(raw), d = breaks(content);
              compared++;
              if (a.length) wrapping++;
              if (a.join() !== d.join()) out.push(line.slice(0, 24) + ' breaks at ' + d.join() + ' in the diff, at ' + a.join() + ' in Raw');
            }
            return { problems: [...new Set(out)].slice(0, 6).join('; '), compared, wrapping };
          })()
          """, as: Wrapped.self)
        #expect(on.problems.isEmpty, "\(size), Reflow on: \(on.problems)")
        #expect(on.compared == 40, "\(size), Reflow on: \(on.compared) of the 40 paragraphs compared")
        #expect(on.wrapping >= 20, "\(size), Reflow on: only \(on.wrapping) lines wrap in Raw")
        try await page.expectNoErrors(ignoring: ["Failed to fetch"])
      }
    } catch {
      commit.remove()
      try await contributor.remove(after: error)
    }
    commit.remove()
    try await contributor.remove()
  }
}
