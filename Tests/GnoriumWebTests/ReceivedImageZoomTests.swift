import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The images a session shows as the model received them zoom and pan in
/// place exactly as the artifact's viewer does (user, 2026-10-17): the plain
/// wheel zooms about the pointer and the page does not scroll over the image,
/// from the image's fit up to its actual size and no further, Safari's pinch
/// and a drag and the keys all the same, and a double-click is the browser's
/// own. Runs the real WASM client against local assets and a fixture page that
/// holds the server's markup for a received image, without a database. Build
/// with `make client` and `make styles` in gnorium-web first.
@Suite("Received image zoom", .serialized)
struct ReceivedImageZoomTests {
  /// What the fixture's page says of one stage.
  struct Stage: Decodable {
    let ratio: Double
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    let stageX: Double
    let stageY: Double
    let stageW: Double
    let stageH: Double
    let scrollY: Double
    let zoomed: String
    let hydrated: String
    let naturalW: Double
    let naturalH: Double
    let cursor: String
    let touchAction: String
  }

  struct Pointer: Decodable {
    let prevented: Bool
  }

  static let big = (width: 1200, height: 1600)
  static let small = (width: 300, height: 200)

  /// The server's markup for a received image (`MessageBlocksView.image`).
  static func stage(_ src: String, _ size: (width: Int, height: Int)) -> String {
    """
    <div class="expandable-attachment-view chat-template-raw-image" data-kind="image" data-fallback-src="" data-presentation="received">\
    <div class="expandable-attachment-image-frame" role="img" tabindex="0" aria-label="Image sent to the model">\
    <img src="\(src)" alt="" loading="lazy" class="expandable-attachment-image-received" width="\(size.width)" height="\(size.height)"/>\
    <span class="expandable-attachment-image-loading"></span></div></div>
    """
  }

  /// The page: a message's box (600 wide) among a long page, the stylesheet
  /// the server emits, the tokens it names. `holdFrames` keeps every
  /// `requestAnimationFrame` callback until `__releaseFrames()`, as a
  /// background tab does.
  static func html(css: String, holdFrames: Bool = false, stages: String) -> String {
    """
    <!doctype html><html><head><meta charset="utf-8"><link rel="icon" href="data:,">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    \(holdFrames ? """
      <script>
      (() => { const real = window.requestAnimationFrame.bind(window); const held = []; let hold = true;
        window.requestAnimationFrame = (cb) => { if (hold) { held.push(cb); return held.length } return real(cb) };
        window.__heldFrames = () => held.length;
        window.__releaseFrames = () => { hold = false; held.splice(0).forEach((cb) => real(cb)) } })()
      </script>
      """ : "")
    <style>
    :root { --line-height-medium-26: 26px; --border-radius-minimal: 2px; --border-width-base: 1px;
      --color-blue: #36c; --size-icon-small: 26px; --color-base: #202122 }
    \(css)
    html, body { margin: 0 }
    .above { height: 1500px }
    .below { height: 3000px }
    #box { width: 600px }
    </style></head><body>
    <div class="above"></div>
    <div id="box">\(stages)</div>
    <div class="below"></div>
    <script>
    window.zt = {
      stage: (i = 0) => document.querySelectorAll('.expandable-attachment-image-frame')[i],
      state(i = 0) {
        const st = this.stage(i), img = st.querySelector('img'), s = st.getBoundingClientRect(), r = img.getBoundingClientRect();
        const cs = getComputedStyle(st);
        return { ratio: r.width / img.naturalWidth, x: r.x, y: r.y, w: r.width, h: r.height,
          stageX: s.x, stageY: s.y, stageW: s.width, stageH: s.height, scrollY: window.scrollY,
          zoomed: st.dataset.zoomed || '', hydrated: st.closest('.expandable-attachment-view').dataset.attachmentHydrated || '',
          naturalW: img.naturalWidth, naturalH: img.naturalHeight, cursor: cs.cursor, touchAction: cs.touchAction }
      },
      // A wheel event at a fraction of the stage: whether the page's scrolling was prevented.
      wheel(i, deltaY, opts = {}) {
        const st = this.stage(i), b = st.getBoundingClientRect();
        const e = new WheelEvent('wheel', { deltaY, ctrlKey: !!opts.ctrl, clientX: b.x + b.width * (opts.fx ?? 0.5),
          clientY: b.y + b.height * (opts.fy ?? 0.5), bubbles: true, cancelable: true });
        st.dispatchEvent(e);
        return { prevented: e.defaultPrevented }
      },
      // Safari's pinch: WebKit's gesture events, which carry a scale and a pointer.
      gesture(i, scales, opts = {}) {
        const st = this.stage(i), b = st.getBoundingClientRect(), out = [];
        const fire = (type, scale) => {
          const e = new Event(type, { bubbles: true, cancelable: true });
          for (const [k, v] of Object.entries({ scale, rotation: 0, clientX: b.x + b.width * (opts.fx ?? 0.5), clientY: b.y + b.height * (opts.fy ?? 0.5) }))
            Object.defineProperty(e, k, { value: v });
          st.dispatchEvent(e); out.push(e.defaultPrevented);
        };
        fire('gesturestart', 1);
        for (const s of scales) fire('gesturechange', s);
        fire('gestureend', scales[scales.length - 1]);
        return { prevented: out.every(Boolean) }
      },
      dblclicks: [],
    };
    window.addEventListener('dblclick', (e) => window.zt.dblclicks.push(e.defaultPrevented));
    </script>
    <script src="/loader.js"></script></body></html>
    """
  }

  /// The local server's assets, nil (a cancelled test) where the client is
  /// not built.
  static func assets() throws -> (css: String, wasm: URL, loader: Data) {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let assets = root.appendingPathComponent("gnorium-web/Public")
    let wasm = ProcessInfo.processInfo.environment["ARTIFACT_TEST_WASM"]
      .map { URL(fileURLWithPath: $0) } ?? assets.appendingPathComponent("client.wasm")
    guard FileManager.default.fileExists(atPath: wasm.path),
      FileManager.default.fileExists(atPath: assets.appendingPathComponent("loader.js").path),
      FileManager.default.fileExists(
        atPath: assets.appendingPathComponent("style-sheets/expandable-attachment-view.css").path)
    else { try Test.cancel("Build gnorium-web's local client assets with make client and make styles first") }
    return (
      try String(contentsOf: assets.appendingPathComponent("style-sheets/expandable-attachment-view.css"), encoding: .utf8),
      wasm,
      try Data(contentsOf: assets.appendingPathComponent("loader.js"))
    )
  }

  static func svg(_ size: (width: Int, height: Int)) -> FixtureServer.File {
    .init(
      contentType: "image/svg+xml",
      body: Data(
        #"<svg xmlns="http://www.w3.org/2000/svg" width="\#(size.width)" height="\#(size.height)"><rect width="\#(size.width)" height="\#(size.height)" fill="gainsboro"/><circle cx="\#(size.width / 2)" cy="\#(size.height / 2)" r="\#(size.height / 4)" fill="royalblue"/></svg>"#
          .utf8))
  }

  /// A page with `stages` served beside the real client, opened and
  /// hydrated, scrolled so the first stage is in the middle of the window.
  static func withStages(
    _ stages: String? = nil, holdFrames: Bool = false,
    _ body: @Sendable (Page, FixtureServer) async throws -> Void
  ) async throws {
    let assets = try assets()
    let markup = stages ?? Self.stage("/big.svg", Self.big)
    let server = try await FixtureServer(files: [
      "/": .init(
        contentType: "text/html",
        body: Data(Self.html(css: assets.css, holdFrames: holdFrames, stages: markup).utf8)),
      "/loader.js": .init(contentType: "text/javascript", body: assets.loader),
      "/client.wasm": .init(contentType: "application/wasm", body: try Data(contentsOf: assets.wasm)),
      "/big.svg": Self.svg(Self.big),
      "/small.svg": Self.svg(Self.small),
    ])
    defer { server.stop() }
    let config = BrowserTestConfiguration(
      baseURL: URL(string: server.baseURL)!, engines: [.chrome], defaultTimeout: .seconds(30))
    try await withPage(.chrome, config, viewport: .init(width: 1000, height: 800)) { page in
      try await page.goto("/")
      try await expect(page.locator("html")).toHaveAttribute("data-wasm-status", "started")
      try await body(page, server)
    }
  }

  /// A stage hydrated and its image read, in the middle of the window (a lazy
  /// image is read once it is near it).
  static func ready(_ page: Page, _ index: Int = 0) async throws {
    let view = page.locator(".expandable-attachment-view").nth(index)
    try await expect(view).toHaveAttribute("data-attachment-hydrated", "true")
    _ = try await page.evaluate(
      "(() => { window.zt.stage(\(index)).scrollIntoView({ block: 'center' }); return 1 })()")
    try await expect(view).toHaveAttribute("data-image-loaded", "true")
    // Laid out: the image shown at its fit.
    try await expect(page.locator(".expandable-attachment-image-received").nth(index)).toBeVisible()
    try await settle()
  }

  static func state(_ page: Page, _ index: Int = 0) async throws -> Stage {
    try await page.evaluate("window.zt.state(\(index))", as: Stage.self)
  }

  /// Images are fitted a frame later by the layout, a zoom lands at once.
  static func settle() async throws { try await Task.sleep(for: .milliseconds(80)) }

  static func wheel(
    _ page: Page, _ deltaY: Double, steps: Int = 1, ctrl: Bool = false, at: (Double, Double) = (0.5, 0.5),
    stage index: Int = 0
  ) async throws -> Bool {
    var prevented = true
    for _ in 0..<steps {
      let result = try await page.evaluate(
        "window.zt.wheel(\(index), \(deltaY), { ctrl: \(ctrl), fx: \(at.0), fy: \(at.1) })", as: Pointer.self)
      prevented = prevented && result.prevented
    }
    try await settle()
    return prevented
  }

  // MARK: - The wheel

  @Test func theWheelZoomsInPlaceAboutThePointerWithNoKeyHeld() async throws {
    try await Self.withStages { page, _ in
      try await Self.ready(page)
      let start = try await Self.state(page)
      #expect(start.hydrated == "true")
      #expect(start.ratio > 0.3 && start.ratio < 0.99, "the image is shown below its actual size: \(start.ratio)")
      #expect(abs(start.stageW - 600) < 1.5, "the stage spans the box: \(start.stageW)")

      // Two steps of the wheel: 20% each, from the fit, about the middle.
      #expect(try await Self.wheel(page, -40, steps: 2), "the wheel was not taken")
      let two = try await Self.state(page)
      #expect(abs(two.ratio - start.ratio * 1.44) < 0.005, "two steps made \(start.ratio) → \(two.ratio)")
      #expect(two.zoomed == "true")
      #expect(two.cursor == "grab")
      #expect(two.touchAction == "none", "a finger pans the image once zoomed: \(two.touchAction)")

      // The same wheel with ctrl held (Chrome's trackpad pinch) is the same path.
      _ = try await Self.wheel(page, 40, steps: 2)
      let back = try await Self.state(page)
      #expect(abs(back.ratio - start.ratio) < 0.005, "two steps out: \(back.ratio) vs the fit \(start.ratio)")
      #expect(back.zoomed == "false")
      #expect(try await Self.wheel(page, -40, ctrl: true))
      let pinched = try await Self.state(page)
      #expect(pinched.ratio > start.ratio * 1.15, "ctrl and the wheel did not zoom: \(pinched.ratio)")
    }
  }

  @Test func theWheelZoomsAboutThePointerKeepingItsPointStill() async throws {
    try await Self.withStages { page, _ in
      try await Self.ready(page)
      let before = try await Self.state(page)
      // A point a quarter across the image and a third down it.
      let (fx, fy) = (0.25, 0.3)
      let px = before.stageX + before.stageW * fx
      let py = before.stageY + before.stageH * fy
      let ux = (px - before.x) / before.w
      let uy = (py - before.y) / before.h
      _ = try await Self.wheel(page, -40, steps: 3, at: (fx, fy))
      let after = try await Self.state(page)
      #expect(after.ratio > before.ratio * 1.5)
      #expect(abs((px - after.x) / after.w - ux) < 0.003, "the point slid sideways")
      #expect(abs((py - after.y) / after.h - uy) < 0.003, "the point slid down")
    }
  }

  @Test func theZoomRunsFromTheFitToTheActualSizeAndNoFurther() async throws {
    try await Self.withStages { page, _ in
      try await Self.ready(page)
      let fit = try await Self.state(page).ratio
      _ = try await Self.wheel(page, -40, steps: 60)
      let top = try await Self.state(page)
      #expect(abs(top.ratio - 1) < 0.002, "one image pixel to one CSS pixel at most: \(top.ratio)")
      #expect(abs(top.w - top.naturalW) < 1 && abs(top.h - top.naturalH) < 1)
      // Past the actual size nothing more happens, and the wheel is still taken.
      #expect(try await Self.wheel(page, -40, steps: 5))
      #expect(abs(try await Self.state(page).ratio - 1) < 0.002)
      _ = try await Self.wheel(page, 40, steps: 80)
      let bottom = try await Self.state(page)
      #expect(abs(bottom.ratio - fit) < 0.002, "no smaller than the fit: \(bottom.ratio) vs \(fit)")
      #expect(bottom.zoomed == "false")
    }
  }

  @Test func theWheelOverTheImageDoesNotScrollThePageAndElsewhereItDoes() async throws {
    try await Self.withStages { page, _ in
      try await Self.ready(page)
      let start = try await Self.state(page)
      let x = start.stageX + start.stageW / 2
      let y = start.stageY + min(start.stageH, 700) / 2
      // A real wheel, three notches down over the image: zoom out at the fit does nothing, and the page stays.
      for _ in 0..<3 { try await page.mouse.wheel(x: x, y: y, deltaY: 120) }
      try await Self.settle()
      let over = try await Self.state(page)
      #expect(over.scrollY == start.scrollY, "the page scrolled under the pointer: \(start.scrollY) → \(over.scrollY)")
      // Up over the image zooms it, the page still.
      for _ in 0..<3 { try await page.mouse.wheel(x: x, y: y, deltaY: -120) }
      try await Self.settle()
      let zoomed = try await Self.state(page)
      #expect(zoomed.ratio > start.ratio * 1.4, "a real wheel did not zoom: \(zoomed.ratio)")
      #expect(zoomed.scrollY == start.scrollY)
      // Beside the box the wheel is the page's.
      for _ in 0..<3 { try await page.mouse.wheel(x: 900, y: y, deltaY: 120) }
      try await Self.settle()
      let beside = try await Self.state(page)
      #expect(beside.scrollY > start.scrollY + 50, "the page did not scroll beside the image")
    }
  }

  // MARK: - Safari, drag, double-click, keys

  @Test func safarisPinchZoomsAboutItsPoint() async throws {
    try await Self.withStages { page, _ in
      try await Self.ready(page)
      let start = try await Self.state(page)
      let pinch = try await page.evaluate("window.zt.gesture(0, [1.2, 1.6, 2.2, 3.0])", as: Pointer.self)
      try await Self.settle()
      let zoomed = try await Self.state(page)
      #expect(pinch.prevented, "the page itself would have zoomed")
      #expect(abs(zoomed.ratio - min(1, start.ratio * 3)) < 0.005, "a pinch of 3 made \(start.ratio) → \(zoomed.ratio)")
      let out = try await page.evaluate("window.zt.gesture(0, [0.8, 0.5, 0.2])", as: Pointer.self)
      try await Self.settle()
      #expect(out.prevented)
      #expect(abs(try await Self.state(page).ratio - start.ratio) < 0.005, "a pinch in did not return to the fit")
    }
  }

  @Test func aDragPansOnceZoomedAndTheImageNeverLeavesTheStage() async throws {
    try await Self.withStages { page, _ in
      try await Self.ready(page)
      let start = try await Self.state(page)
      let x = start.stageX + start.stageW / 2
      let y = start.stageY + min(start.stageH, 700) / 2

      // At the fit a drag is the browser's own: nothing moves.
      try await page.mouse.move(x: x, y: y)
      try await page.mouse.down(x: x, y: y)
      try await page.mouse.move(x: x - 80, y: y - 60)
      try await page.mouse.up(x: x - 80, y: y - 60)
      let still = try await Self.state(page)
      #expect(abs(still.x - start.x) < 0.5 && abs(still.y - start.y) < 0.5, "the image moved at its fit")

      _ = try await Self.wheel(page, -40, steps: 8)
      let zoomed = try await Self.state(page)
      #expect(zoomed.ratio > start.ratio * 1.5)
      try await page.mouse.move(x: x, y: y)
      try await page.mouse.down(x: x, y: y)
      try await page.mouse.move(x: x - 80, y: y - 60)
      try await page.mouse.up(x: x - 80, y: y - 60)
      let moved = try await Self.state(page)
      // It follows the pointer, within the room it has (here, plenty).
      #expect(abs((moved.x - zoomed.x) - -80) < 1, "the drag moved the image \(moved.x - zoomed.x) across")
      #expect(abs((moved.y - zoomed.y) - -60) < 1, "the drag moved the image \(moved.y - zoomed.y) down")

      // Dragged far past a corner, the image's edge is flush with the
      // stage's there: it covers the stage, never fully out of it.
      for (dx, dy) in [(3000.0, 3000.0), (-3000.0, -3000.0)] {
        for _ in 0..<4 {
          try await page.mouse.move(x: x, y: y)
          try await page.mouse.down(x: x, y: y)
          try await page.mouse.move(x: x + dx / 2, y: y + dy / 2)
          try await page.mouse.move(x: x + dx, y: y + dy)
          try await page.mouse.up(x: x + dx, y: y + dy)
        }
        let edge = try await Self.state(page)
        if dx > 0 {
          #expect(abs(edge.x - edge.stageX) < 1, "the left edge is \(edge.x - edge.stageX) from the stage's")
          #expect(abs(edge.y - edge.stageY) < 1, "the top edge is \(edge.y - edge.stageY) from the stage's")
        } else {
          #expect(abs(edge.x + edge.w - edge.stageX - edge.stageW) < 1, "the right edge is off the stage's")
          #expect(abs(edge.y + edge.h - edge.stageY - edge.stageH) < 1, "the bottom edge is off the stage's")
        }
      }
    }
  }

  @Test func aDoubleClickIsTheBrowsersOwn() async throws {
    try await Self.withStages { page, _ in
      try await Self.ready(page)
      let start = try await Self.state(page)
      let x = start.stageX + start.stageW / 2
      let y = start.stageY + min(start.stageH, 700) / 2
      try await page.mouse.click(x: x, y: y, clickCount: 2)
      try await Self.settle()
      let after = try await Self.state(page)
      #expect(abs(after.ratio - start.ratio) < 0.001, "a double-click zoomed: \(start.ratio) → \(after.ratio)")
      let events = try await page.evaluate("window.zt.dblclicks", as: [Bool].self)
      #expect(!events.isEmpty, "no double-click reached the page")
      #expect(events.allSatisfy { !$0 }, "the stage took the double-click from the browser")
      // Zoomed, too.
      _ = try await Self.wheel(page, -40, steps: 3)
      let zoomed = try await Self.state(page)
      try await page.mouse.click(x: x, y: y, clickCount: 2)
      try await Self.settle()
      #expect(abs(try await Self.state(page).ratio - zoomed.ratio) < 0.001)
    }
  }

  @Test func theKeysZoomPanAndFitAgainWithTheDesignSystemsFocusRing() async throws {
    try await Self.withStages { page, _ in
      try await Self.ready(page)
      let fit = try await Self.state(page).ratio
      _ = try await page.evaluate("(() => { window.zt.stage(0).focus({ preventScroll: true }); return 1 })()")
      try await page.keyboard.press("+")
      let plus = try await Self.state(page)
      #expect(abs(plus.ratio - fit * 1.2) < 0.003, "+ made \(fit) → \(plus.ratio)")
      try await page.keyboard.press("-")
      #expect(abs(try await Self.state(page).ratio - fit) < 0.003)
      for _ in 0..<3 { try await page.keyboard.press("=") }
      let before = try await Self.state(page)
      try await page.keyboard.press("ArrowLeft")
      let left = try await Self.state(page)
      try await page.keyboard.press("ArrowDown")
      let down = try await Self.state(page)
      #expect(abs((left.x - before.x) - 40) < 1 || before.x >= before.stageX - 0.5, "ArrowLeft: \(before.x) → \(left.x)")
      #expect(abs((down.y - left.y) - -40) < 1, "ArrowDown: \(left.y) → \(down.y)")
      #expect(down.scrollY == before.scrollY, "the arrows scrolled the page")
      try await page.keyboard.press("0")
      #expect(abs(try await Self.state(page).ratio - fit) < 0.003, "0 did not fit it")
      for _ in 0..<3 { try await page.keyboard.press("+") }
      try await page.keyboard.press("Escape")
      let escaped = try await Self.state(page)
      #expect(abs(escaped.ratio - fit) < 0.003 && escaped.zoomed == "false", "Escape did not fit it")

      // The stage is a focusable image: Tab reaches it and the design system's
      // ring (1px, solid) shows on keyboard focus.
      // From the top of the page, where a click starts the keyboard's way.
      _ = try await page.evaluate("(() => { document.activeElement.blur(); window.scrollTo(0, 0); return 1 })()")
      try await page.mouse.click(x: 5, y: 5)
      try await page.keyboard.press("Tab")
      let ring = try await page.evaluate(
        """
        (() => { const el = document.activeElement, cs = getComputedStyle(el);
          return { stage: el.classList.contains('expandable-attachment-image-frame'), role: el.getAttribute('role'),
            label: el.getAttribute('aria-label'), outline: cs.outlineStyle, width: cs.outlineWidth, visible: el.matches(':focus-visible') } })()
        """)
      #expect(ring["stage"].bool == true, "Tab did not reach the stage")
      #expect(ring["role"].string == "img" && ring["label"].string == "Image sent to the model")
      #expect(ring["outline"].string == "solid" && ring["width"].string == "1px" && ring["visible"].bool == true)
    }
  }

  // MARK: - The range at the actual size, the stage following its box

  @Test func anImageShownAtItsActualSizeHasNoZoomInAndTheWheelStaysThePages() async throws {
    try await Self.withStages(Self.stage("/small.svg", Self.small)) { page, _ in
      try await Self.ready(page)
      let start = try await Self.state(page)
      #expect(abs(start.ratio - 1) < 0.002, "a 300 pixel image in a 600 pixel box is shown at 1:1: \(start.ratio)")
      let taken = try await page.evaluate("window.zt.wheel(0, -40)", as: Pointer.self)
      try await Self.settle()
      #expect(!taken.prevented, "a wheel over an image with no zoom to give was taken from the page")
      let after = try await Self.state(page)
      #expect(abs(after.ratio - 1) < 0.002, "an image at its actual size zoomed in: \(after.ratio)")
      let pinch = try await page.evaluate("window.zt.gesture(0, [2, 3])", as: Pointer.self)
      #expect(!pinch.prevented)
      try await page.keyboard.press("+")
      #expect(abs(try await Self.state(page).ratio - 1) < 0.002)
      // The page scrolls under a real wheel over it.
      let x = start.stageX + start.stageW / 2
      let y = start.stageY + start.stageH / 2
      for _ in 0..<3 { try await page.mouse.wheel(x: x, y: y, deltaY: 120) }
      try await Self.settle()
      #expect(try await Self.state(page).scrollY > start.scrollY + 50)
    }
  }

  @Test func aZoomAtTheFitFollowsTheStageAndAnyOtherIsKept() async throws {
    try await Self.withStages { page, _ in
      try await Self.ready(page)
      let fit = try await Self.state(page).ratio
      // At the fit it follows the box narrowing: 600 → 400 wide is a third smaller.
      _ = try await page.evaluate("(() => { document.getElementById('box').style.width = '400px'; return 1 })()")
      try await Self.settle()
      let narrower = try await Self.state(page)
      #expect(abs(narrower.stageW - 400) < 1.5)
      #expect(abs(narrower.ratio - fit * 400 / 600) < 0.005, "the fit did not follow the box: \(narrower.ratio)")
      #expect(narrower.zoomed == "false")

      // Zoomed it is kept: the same point at the middle and the same zoom over the fit.
      _ = try await Self.wheel(page, -40, steps: 3)
      let zoomed = try await Self.state(page)
      let centerX = (zoomed.stageX + zoomed.stageW / 2 - zoomed.x) / zoomed.w
      _ = try await page.evaluate("(() => { document.getElementById('box').style.width = '500px'; return 1 })()")
      try await Self.settle()
      let wider = try await Self.state(page)
      #expect(wider.zoomed == "true", "a zoomed image was reset to the fit when its box changed")
      let widerFit = fit * 500 / 600
      #expect(abs(wider.ratio / widerFit - zoomed.ratio / (fit * 400 / 600)) < 0.01, "the zoom over the fit changed")
      #expect(abs((wider.stageX + wider.stageW / 2 - wider.x) / wider.w - centerX) < 0.01, "the middle moved")
    }
  }

  // MARK: - Hydration

  @Test func theStageIsBoundWithoutAFrameAndTheOnesDrawnLaterToo() async throws {
    // Every frame held, as a background tab holds them: the first pass binds
    // the stage, a stage drawn after it is bound as it enters the page.
    try await Self.withStages(holdFrames: true) { page, _ in
      try await Self.ready(page)
      let held = try await page.evaluate("window.__heldFrames()", as: Int.self)
      #expect(held > 0, "the frames were not held, so this proves nothing")
      let start = try await Self.state(page)
      #expect(start.hydrated == "true", "the stage waited on a frame")
      #expect(try await Self.wheel(page, -40, steps: 2), "the wheel was not taken before any frame")
      #expect(try await Self.state(page).ratio > start.ratio * 1.3)

      // A live session draws its images after the page: appended, no hydration called.
      _ = try await page.evaluate(
        """
        (() => { const holder = document.createElement('div'); holder.innerHTML = `\(Self.stage("/small.svg", Self.small))\(Self.stage("/big.svg", Self.big))`;
          while (holder.firstElementChild) document.getElementById('box').appendChild(holder.firstElementChild); return 1 })()
        """)
      try await Self.ready(page, 2)
      let late = try await Self.state(page, 2)
      #expect(late.hydrated == "true", "an image drawn later was left inert")
      #expect(try await Self.wheel(page, -40, steps: 2, stage: 2), "the wheel was not taken on a late image")
      let zoomed = try await Self.state(page, 2)
      #expect(zoomed.ratio > late.ratio * 1.3)
      // And the earlier stage is as it was: drawing more did not redraw it.
      #expect(try await Self.state(page, 0).zoomed == "true")

      // A stage that leaves the page lets go, and the rest still answer.
      _ = try await page.evaluate("(() => { window.zt.stage(0).closest('.expandable-attachment-view').remove(); return 1 })()")
      try await Self.settle()
      try await Self.ready(page, 1)
      #expect(try await Self.wheel(page, -40, stage: 1), "the stage left standing was not bound")
      try await page.expectNoErrors()
    }
  }
}
