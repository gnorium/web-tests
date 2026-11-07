import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The trace stands in its leaf with the margins its scan shows (user,
/// 2026-11-06, Hamlet Q1's title page beside its frame: "the leaf margins
/// are still not there in the trace pane"). At its fit the whole leaf is in
/// the text pane (artifact-core `ArtifactView.applyPageScale`, user
/// 2026-10-31), filling it one way; and the white between the leaf's edges
/// and what the page prints is, on each side, the scan's share of its leaf
/// within `tolerance`: on the scan, between its leaf's zone (`type="leaf"`)
/// and the zones its markup names (`data-zones`: its lines and figures); in
/// the trace, between the page's box (`[data-page-scale] > .tei-page-text`,
/// the type area and its margins, TEIView) and its glyphs' ink and its
/// figures' drawings, after the page's scale.
///
/// The user's own pages, read only: the title page (frame 7) and three body
/// pages (frames 9, 11 and 41), at the user's Safari (856×983) and browser
/// pane (770×923), images on. `READER_LEAF_PAGE` names another madrigal's
/// path (without its `?frame=`). Cancelled where the server has no such page.
@Suite("Reader leaf margins", .serialized)
struct ReaderLeafMarginsTests {
  static let path =
    ProcessInfo.processInfo.environment["READER_LEAF_PAGE"]
    ?? "/mission-control/madrigals/bibliographic/01A1946C-E748-8060-B4D7-1B8B13227FB0"

  /// How far a trace's margin may stand from its scan's, as a share of the
  /// leaf's width (left, right) or height (top, bottom). The edition sets
  /// every leaf of a size in one type area, its margins the work's
  /// (xml-utilities `TEIPage.typeArea`), and this copy's leaves are inlaid in
  /// mount sheets that differ from the work's leaf by up to 3.6% (p. 5's:
  /// 50.8 em across, the work's 49.06): its regularized margins stand up to
  /// 3.2% off the scan's there (dev, 2026-11-06). The title page's right
  /// margin stood 12.6% short, p. 3's head 11.8%.
  static let tolerance = 0.04

  struct Frame: Sendable, CustomStringConvertible {
    /// The reader's frame, from 0 (`?frame=`).
    let index: Int
    let name: String
    var description: String { "frame \(index + 1) (\(name))" }
  }

  static let frames: [Frame] = [
    .init(index: 6, name: "the title page"),
    .init(index: 8, name: "p. 3"),
    .init(index: 10, name: "p. 5"),
    .init(index: 40, name: "p. 35"),
  ]

  /// The user's Safari and the user's browser pane.
  static let sizes: [Viewport] = [
    Viewport(width: 856, height: 983, deviceScaleFactor: 2),
    Viewport(width: 770, height: 923, deviceScaleFactor: 2),
  ]

  /// The madrigal's own reader; the record tree above it holds other
  /// witnesses' readers.
  static let reader = ".madrigal-object .artifact-view"
  /// The page on screen in its text pane, never the page's diff under it.
  static let page = ".artifact-markup .tei-page[data-active='true']"

  struct Margins: Decodable, CustomStringConvertible {
    let left: Double
    let right: Double
    let top: Double
    let bottom: Double
    var description: String {
      [left, right, top, bottom].map { String(format: "%.3f", $0) }.joined(separator: " ")
    }
  }

  struct Reading: Decodable {
    let error: String
    let label: String
    let scan: Margins?
    let trace: Margins?
    /// The leaf's width over its height, on the scan and in the trace.
    let scanShape: Double
    let traceShape: Double
    /// The page's box inside the pane's room, and filling it one way.
    let inside: Bool
    let fills: Bool
    let box: String
    let room: String
  }

  /// The margins, each a share of its leaf's width or height, on the scan and
  /// in the trace, and the page's box against its pane.
  static let read = #"""
    (async () => {
      const none = { label: '', scan: null, trace: null, scanShape: 0, traceShape: 0, inside: false, fills: false, box: '', room: '' };
      const view = document.querySelector(`\#(ReaderLeafMarginsTests.reader)`);
      const page = view && view.querySelector(`\#(ReaderLeafMarginsTests.page)`);
      const layer = page && page.querySelector("[data-page-scale='true'] > .tei-page-text");
      if (!layer) return { ...none, error: 'no page at its scale in the text pane' };
      await document.fonts.ready;
      const attrs = (tag) => Object.fromEntries([...tag.matchAll(/\s([\w:-]+)="([^"]*)"/g)].map((m) => [m[1], m[2]]));
      const raw = page.querySelector('.tei-page-raw')?.textContent || '';
      const surface = attrs((raw.match(/<surface\b[^>]*>/) || [''])[0]);
      const graphic = attrs((raw.match(/<graphic\b[^>]*>/) || [''])[0]);
      const leafTag = (raw.match(/<zone\b[^>]*\stype="leaf"[^>]*>/) || [''])[0];
      if (!leafTag) return { ...none, label: page.dataset.label || '', error: 'its scan keeps no leaf' };
      const ulx = +(surface.ulx || 0), uly = +(surface.uly || 0), lrx = +(surface.lrx || 1000), lry = +(surface.lry || 1000);
      const corners = attrs(leafTag).points.trim().split(/\s+/).map((p) => p.split(',').map(Number));
      const xs = corners.map((c) => (c[0] - ulx) / (lrx - ulx)), ys = corners.map((c) => (c[1] - uly) / (lry - uly));
      const leaf = { left: Math.min(...xs), top: Math.min(...ys), right: Math.max(...xs), bottom: Math.max(...ys) };
      // The zones its markup names: "id x y w h", the 0–1000 space over the image.
      const zones = (page.dataset.zones || '').split(';').filter((z) => z.trim())
        .map((z) => z.trim().split(/\s+/).slice(1).map((n) => +n / 1000));
      if (!zones.length) return { ...none, label: page.dataset.label || '', error: 'its markup names no zone' };
      const lw = leaf.right - leaf.left, lh = leaf.bottom - leaf.top;
      const scan = {
        left: (Math.min(...zones.map((z) => z[0])) - leaf.left) / lw,
        right: (leaf.right - Math.max(...zones.map((z) => z[0] + z[2]))) / lw,
        top: (Math.min(...zones.map((z) => z[1])) - leaf.top) / lh,
        bottom: (leaf.bottom - Math.max(...zones.map((z) => z[1] + z[3]))) / lh,
      };
      // The trace's ink: each run of text's glyphs (its box across; down, its
      // glyphs' own top and bottom, never its font's ascent and descent),
      // and each figure's drawing.
      const box = layer.getBoundingClientRect();
      const context = document.createElement('canvas').getContext('2d');
      const ink = [];
      const walker = document.createTreeWalker(layer, NodeFilter.SHOW_TEXT);
      for (let node; (node = walker.nextNode()); ) {
        if (!node.data.trim()) continue;
        const style = getComputedStyle(node.parentElement);
        context.font = `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
        const m = context.measureText(node.data.trim());
        const content = m.fontBoundingBoxAscent + m.fontBoundingBoxDescent;
        const range = document.createRange();
        range.selectNodeContents(node);
        for (const r of range.getClientRects()) {
          if (r.width <= 0 || r.height <= 0) continue;
          const k = r.height / content;
          ink.push({ left: r.left, right: r.right, top: r.top + (m.fontBoundingBoxAscent - m.actualBoundingBoxAscent) * k,
            bottom: r.top + (m.fontBoundingBoxAscent + m.actualBoundingBoxDescent) * k });
        }
      }
      layer.querySelectorAll('.tei-figure svg, .tei-figure img').forEach((e) => {
        const r = e.getBoundingClientRect();
        if (r.width > 0 && r.height > 0) ink.push(r);
      });
      if (!ink.length) return { ...none, label: page.dataset.label || '', error: 'the trace prints nothing' };
      const trace = {
        left: (Math.min(...ink.map((r) => r.left)) - box.left) / box.width,
        right: (box.right - Math.max(...ink.map((r) => r.right))) / box.width,
        top: (Math.min(...ink.map((r) => r.top)) - box.top) / box.height,
        bottom: (box.bottom - Math.max(...ink.map((r) => r.bottom))) / box.height,
      };
      const pane = view.querySelector('.artifact-markup'), p = pane.getBoundingClientRect();
      const left = p.left + pane.clientLeft, top = p.top + pane.clientTop, right = left + pane.clientWidth, bottom = top + pane.clientHeight;
      const r = (values) => values.map((n) => Math.round(n * 10) / 10).join(',');
      return {
        error: '', label: page.dataset.label || '', scan, trace,
        scanShape: (lw * parseFloat(graphic.width || '1')) / (lh * parseFloat(graphic.height || '1')),
        traceShape: box.width / box.height,
        inside: box.left >= left - 1 && box.top >= top - 1 && box.right <= right + 1 && box.bottom <= bottom + 1,
        fills: Math.abs(box.width - pane.clientWidth) <= 2 || Math.abs(box.height - pane.clientHeight) <= 2,
        box: r([box.left, box.top, box.right, box.bottom]), room: r([left, top, right, bottom]),
      };
    })()
    """#

  @Test(arguments: ReaderLeafMarginsTests.sizes, ReaderLeafMarginsTests.frames)
  func theTraceStandsInItsLeafWithItsScansMargins(size: Viewport, frame: Frame) async throws {
    guard gnorium.engines.contains(.chrome) else { return }
    try await withPage(.chrome, gnorium, viewport: size) { page in
      let path = "\(Self.path)?frame=\(frame.index)"
      let opened = try await page.goto(path, waitUntil: .load)
      if let status = opened.status, status >= 400 {
        try Test.cancel(Comment(rawValue: "\(path) answered HTTP \(status) on this server"))
      }
      try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
      let reader = page.locator(Self.reader).first
      try await expect(reader.locator("\(Self.page) [data-page-scale='true']"), timeout: .seconds(20)).toHaveCount(1)
      try await expect(reader, timeout: .seconds(20)).toHaveAttribute("data-canvas-confirmed", "true")
      // Images on, as the user reads it: the text pane is the reader's half.
      if try await reader.getAttribute("data-canvas-shown") != "true" {
        try await reader.locator(".artifact-canvas-toggle button").first.click()
      }
      try await expect(reader).toHaveAttribute("data-canvas-shown", "true")
      // The page fitted again to its narrower pane (`watchLeaf`).
      try await Task.sleep(for: .milliseconds(1200))
      let place = "\(size), \(frame)"
      let reading = try await page.evaluate(Self.read, as: Reading.self)
      guard reading.error.isEmpty, let scan = reading.scan, let trace = reading.trace else {
        Issue.record("\(place): \(reading.error)")
        return
      }
      // At its fit, the whole leaf in its pane, filling it one way.
      #expect(reading.inside, "\(place): the leaf at \(reading.box) runs past its pane's room at \(reading.room)")
      #expect(reading.fills, "\(place): the leaf at \(reading.box) fills its pane's room at \(reading.room) neither way")
      let sides: [(String, KeyPath<Margins, Double>)] = [
        ("left", \.left), ("right", \.right), ("top", \.top), ("bottom", \.bottom),
      ]
      for (side, key) in sides {
        let off = trace[keyPath: key] - scan[keyPath: key]
        #expect(
          abs(off) <= Self.tolerance,
          """
          \(place), \(reading.label): its \(side) margin is \(String(format: "%.3f", trace[keyPath: key])) of its leaf, \
          the scan's \(String(format: "%.3f", scan[keyPath: key])) (trace \(trace), scan \(scan), left right top bottom; \
          the leaf's width over its height \(String(format: "%.3f", reading.traceShape)), the scan's \
          \(String(format: "%.3f", reading.scanShape)))
          """)
      }
      try await page.expectNoErrors(ignoring: ["Failed to fetch"])
    }
  }
}
