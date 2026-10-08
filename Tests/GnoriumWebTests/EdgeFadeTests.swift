import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A single line too long for its box is clipped and fades out at its edge
/// (`fadeOverflow`, EdgeFade.swift), never cut with an ellipsis—in tables,
/// datums, breadcrumbs, menus, chips, sidebars, everywhere. The fade is drawn
/// exactly on the boxes whose line runs past them. The line scrolls sideways
/// with no scrollbar, and the fades follow it: the end's while more remains,
/// the start's once scrolled.
///
/// On every device a click or a tap shows the whole value and another folds
/// it back (user, 2026-10-08). A link in the box stays a link: a click on its
/// words follows it, and only a click in the fade opens the box. A click off
/// an open box folds it; Enter on a focused box opens and folds it. A closed
/// dropdown's value scrolls too. An editable input fades at rest, and not
/// while it is focused.
///
/// With `EDGE_FADE_SCREENSHOTS` set to a folder, each page is also saved
/// there, light and dark, for a look.
@Suite("Edge fade", .serialized)
struct EdgeFadeTests {
  /// The main pages, as a reader first meets them.
  static let pages = [
    "/", "/biblio-records", "/lexico-records", "/mission-control/lifecycles/bibliographic", "/mission-control/contributors",
    "/mission-control/antiphons/bibliographic", "/mission-control/madrigals/bibliographic", "/mission-control/folksongs/bibliographic",
    "/mission-control/locutions",
  ]
  static let tables = ["/biblio-records", "/lexico-records", "/mission-control/lifecycles/bibliographic"]

  struct Report: Decodable {
    /// Boxes that may fade, shown.
    let boxes: Int
    let overflowing: Int
    /// Anything on the page ending its text in "…" by CSS.
    let ellipses: [String]
    /// Boxes whose fade disagrees with their overflow.
    let wrong: [String]
    /// Boxes that are buttons or tab stops: none should be, on any device.
    let buttons: Int
  }

  /// Reads the fade of every shown box under `scope`.
  static func report(_ page: Page, _ scope: String) async throws -> Report {
    try await page.evaluate(
      """
      (() => {
        const shown = (e) => e.getClientRects().length > 0
        // An input draws its fade over itself, not as a mask: checked apart.
        const boxes = [...document.querySelectorAll('\(scope) [data-edge-fade]:not(input)')].filter(shown)
        const faded = (e) => {
          const s = getComputedStyle(e)
          return (s.maskImage || '').includes('gradient') || (s.webkitMaskImage || '').includes('gradient')
        }
        const over = (e) => e.scrollWidth > e.clientWidth
        return {
          boxes: boxes.length,
          overflowing: boxes.filter(over).length,
          ellipses: [...document.querySelectorAll('*')]
            .filter((e) => getComputedStyle(e).textOverflow === 'ellipsis')
            .map((e) => e.tagName + '.' + e.className.toString()),
          wrong: boxes.filter((e) => e.getAttribute('data-edge-fade-expanded') !== 'true')
            .filter((e) => over(e) !== faded(e))
            .map((e) => (over(e) ? 'unfaded: ' : 'faded: ') + e.className.toString() + ' ' + e.textContent.trim().slice(0, 60)),
          buttons: boxes.filter((e) => e.getAttribute('role') === 'button' || e.tabIndex >= 0).length,
        }
      })()
      """, as: Report.self)
  }

  /// The report once the boxes are measured: the client marks them a frame
  /// after the page settles.
  static func settledReport(_ page: Page, _ scope: String) async throws -> Report {
    var report = try await Self.report(page, scope)
    for _ in 0..<25 where !report.wrong.isEmpty {
      try await Task.sleep(for: .milliseconds(200))
      report = try await Self.report(page, scope)
    }
    return report
  }

  struct Target: Decodable {
    /// A point on the link's words, or the box's middle when it has none.
    let wordsX: Double
    let wordsY: Double
    /// A point in the fade, at the box's reading end.
    let fadeX: Double
    let fadeY: Double
    let href: String?
  }

  /// Marks the first overflowing expandable box under `scope` (holding a
  /// link, or not) `data-test-edge-fade`, and says where to tap it.
  static func markFirstOverflowing(_ page: Page, _ scope: String, withLink: Bool) async throws -> Target? {
    let value = try await page.evaluate(
      """
      (() => {
        const link = (e) => e.querySelector('a') || e.closest('a')
        const box = [...document.querySelectorAll('\(scope) [data-edge-fade="expand"]')]
          .find((e) => e.getClientRects().length > 0 && e.getAttribute('data-overflowing') === 'true'
            && !!link(e) === \(withLink))
        if (!box) return null
        box.scrollIntoView({ block: 'center' })
        box.setAttribute('data-test-edge-fade', 'true')
        const r = box.getBoundingClientRect()
        const rtl = getComputedStyle(box).direction === 'rtl'
        const a = link(box)
        return {
          wordsX: a ? (rtl ? r.right - 8 : r.left + 8) : r.left + r.width / 2,
          wordsY: r.top + r.height / 2,
          fadeX: rtl ? r.left + 4 : r.right - 4,
          fadeY: r.top + r.height / 2,
          href: a ? a.href : null,
        }
      })()
      """)
    if case .null = value { return nil }
    return try value.decode(as: Target.self)
  }

  /// A point off every control and box, to tap away from an open box.
  static func quietPoint(_ page: Page) async throws -> (Double, Double) {
    struct Point: Decodable { let x: Double; let y: Double }
    let point = try await page.evaluate(
      """
      (() => {
        const busy = 'a, button, label, input, select, textarea, [role], [tabindex], [data-edge-fade], table, nav, header, dialog'
        for (let y = 12; y < innerHeight; y += 24) {
          for (let x = 12; x < innerWidth; x += 24) {
            const e = document.elementFromPoint(x, y)
            if (e && !e.closest(busy)) return { x, y }
          }
        }
        return null
      })()
      """, as: Point.self)
    return (point.x, point.y)
  }

  static func press(_ page: Page, _ x: Double, _ y: Double, _ viewport: Viewport) async throws {
    if viewport.touch {
      try await page.driver.tap(x: x, y: y)
    } else {
      try await page.mouse.click(x: x, y: y)
    }
  }

  static func screenshots(_ page: Page, _ name: String, _ layout: Layout) async throws {
    guard let folder = ProcessInfo.processInfo.environment["EDGE_FADE_SCREENSHOTS"] else { return }
    let directory = URL(fileURLWithPath: folder)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for scheme in ["light", "dark"] {
      _ = try await page.evaluate("document.documentElement.setAttribute('data-color-scheme', '\(scheme)')")
      try await page.screenshot(to: directory.appendingPathComponent("\(name)-\(layout)-\(scheme).png"))
    }
    _ = try await page.evaluate("document.documentElement.setAttribute('data-color-scheme', 'light')")
  }

  static func slug(_ path: String) -> String {
    path == "/" ? "home" : path.dropFirst().replacingOccurrences(of: "/", with: "-")
  }

  /// No ellipsis anywhere, every box faded exactly where it overflows, and
  /// none a button or a tab stop of its own, at any width (user, 2026-10-08).
  @Test(arguments: gnorium.engines, Layout.allCases)
  func everyPageFadesWhereItOverflows(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      for path in Self.pages {
        try await page.openHydrated(path)
        try await page.expectNoErrors()
        let report = try await Self.settledReport(page, "body")
        #expect(report.ellipses.isEmpty, "\(path): text-overflow: ellipsis on \(report.ellipses)")
        #expect(report.wrong.isEmpty, "\(path): the fade disagrees with the overflow on \(report.wrong)")
        #expect(report.buttons == 0, "\(path): \(report.buttons) faded values are buttons or tab stops")
        try await Self.screenshots(page, Self.slug(path), layout)
      }
    }
  }

  /// A table cell: its link's words follow the link at any width; a click
  /// or a tap in the fade opens the cell and stays on the page, one off it
  /// folds it, and Enter opens and folds it—at 375 and at 1400 alike.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aFadedCellsLinkIsALinkAndItsFadeExpandsIt(engine: BrowserEngine, layout: Layout) async throws {
    let viewport = layout.viewport(for: engine)
    try await withPage(engine, gnorium, viewport: viewport) { page in
      var checked = 0
      for path in Self.tables {
        try await page.openHydrated(path)
        _ = try await Self.settledReport(page, ".table-view")
        guard let target = try await Self.markFirstOverflowing(page, ".table-view", withLink: true) else { continue }
        let href = try #require(target.href)
        let box = page.locator("[data-test-edge-fade]")

        do {
          // The fade opens it, and the page stays where it is.
          try await expect(box).toHaveAttribute("data-edge-fade-expanded", "false")
          try await Self.press(page, target.fadeX, target.fadeY, viewport)
          try await expect(box).toHaveAttribute("data-edge-fade-expanded", "true")
          let whole = try await box.evaluate("(e) => e.scrollWidth <= e.clientWidth")
          #expect(whole.bool == true, "\(path): an expanded cell still overflows")
          #expect(try await page.url().hasSuffix(path), "\(path): the click in the fade followed a link")
          // A click off it folds it.
          let (x, y) = try await Self.quietPoint(page)
          try await Self.press(page, x, y, viewport)
          try await expect(box).toHaveAttribute("data-edge-fade-expanded", "false")
          // Enter, focused.
          try await box.press("Enter")
          try await expect(box).toHaveAttribute("data-edge-fade-expanded", "true")
          try await box.press("Enter")
          try await expect(box).toHaveAttribute("data-edge-fade-expanded", "false")
          #expect(try await page.url().hasSuffix(path), "\(path): Enter on the cell followed a link")
        }

        // The link's words follow the link.
        try await Self.press(page, target.wordsX, target.wordsY, viewport)
        try await expect(page, timeout: .seconds(15)).toHaveURL(href)
        checked += 1
      }
      #expect(checked > 0, "no table cell with a link overflows")
    }
  }

  /// A faded cell's link reached by Tab shows the cell whole, unfaded, as an
  /// input shows its value while focused; Tab on folds it again. No state is
  /// kept: it is the link's `:focus-visible` alone.
  @Test(arguments: gnorium.engines)
  func tabbingOntoAFadedCellsLinkShowsItWhole(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine)) { page in
      var checked = 0
      for path in Self.tables {
        try await page.openHydrated(path)
        _ = try await Self.settledReport(page, ".table-view")
        guard try await Self.markFirstOverflowing(page, ".table-view", withLink: true) != nil else { continue }
        let box = page.locator("[data-test-edge-fade]")
        let shown = "(e) => { const s = getComputedStyle(e); return { whole: e.scrollWidth <= e.clientWidth, masked: (s.webkitMaskImage || s.maskImage || '').includes('gradient') } }"
        // Reached by the keyboard: focus the link, Tab past it, and back.
        _ = try await box.evaluate("(e) => (e.querySelector('a') || e.closest('a')).focus()")
        try await page.keyboard.press("Tab")
        try await page.keyboard.press("Shift+Tab")
        let onLink = try await box.evaluate("(e) => { const a = e.querySelector('a') || e.closest('a'); return document.activeElement === a && a.matches(':focus-visible') }")
        #expect(onLink.bool == true, "\(path): Shift+Tab did not come back to the cell's link")
        var state = try await box.evaluate(shown)
        #expect(state.object?["whole"]?.bool == true, "\(path): a focused link's cell is not shown whole")
        #expect(state.object?["masked"]?.bool == false, "\(path): a focused link's cell is still faded")
        try await expect(box).not.toHaveAttribute("data-edge-fade-expanded", "true")
        // Tab on: folded and faded again (measured afresh a frame after
        // the focus leaves).
        try await page.keyboard.press("Tab")
        try await Task.sleep(for: .milliseconds(300))
        state = try await box.evaluate(shown)
        #expect(state.object?["whole"]?.bool == false, "\(path): the cell stays whole after Tab moved on")
        #expect(state.object?["masked"]?.bool == true, "\(path): the cell is not faded after Tab moved on")
        #expect(try await page.url().hasSuffix(path), "\(path): tabbing followed a link")
        checked += 1
      }
      #expect(checked > 0, "no table cell with a link overflows at 1400")
    }
  }

  /// A cell with no link opens on a click or a tap anywhere in it, and folds
  /// on another, at 375 and at 1400.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aFadedPlainCellExpandsOnATap(engine: BrowserEngine, layout: Layout) async throws {
    let viewport = layout.viewport(for: engine)
    try await withPage(engine, gnorium, viewport: viewport) { page in
      var checked = 0
      for path in Self.tables {
        try await page.openHydrated(path)
        _ = try await Self.settledReport(page, ".table-view")
        guard let target = try await Self.markFirstOverflowing(page, ".table-view", withLink: false) else { continue }
        let box = page.locator("[data-test-edge-fade]")
        try await Self.press(page, target.wordsX, target.wordsY, viewport)
        try await expect(box).toHaveAttribute("data-edge-fade-expanded", "true")
        try await Self.press(page, target.wordsX, target.wordsY, viewport)
        try await expect(box).toHaveAttribute("data-edge-fade-expanded", "false")
        #expect(try await page.url().hasSuffix(path), "\(path): a tap on a plain cell followed the row's link")
        checked += 1
      }
      if checked == 0 { try Test.cancel("no plain table cell overflows at \(layout) in the dev data") }
    }
  }

  struct Scrolling: Decodable {
    let scrolls: Bool
    let scrollbar: Double
    let tabindex: String?
    let startFade: String
    let endFade: String
  }

  /// How the marked box scrolls: sideways, with no scrollbar drawn, no tab
  /// stop of its own, and the two fade lengths as the scroll has them.
  static func scrolling(_ page: Page) async throws -> Scrolling {
    try await page.evaluate(
      """
      (() => {
        const e = document.querySelector('[data-test-edge-fade]')
        const s = getComputedStyle(e)
        return {
          scrolls: s.overflowX === 'auto',
          scrollbar: e.offsetHeight - e.clientHeight,
          tabindex: e.getAttribute('tabindex'),
          startFade: s.getPropertyValue('--edge-fade-start').trim(),
          endFade: s.getPropertyValue('--edge-fade-end').trim(),
        }
      })()
      """, as: Scrolling.self)
  }

  /// A faded value scrolls sideways, with no scrollbar, and its fades follow
  /// the scroll: the end's while more remains, the start's once scrolled.
  /// It is no tab stop and no button, and a click or a tap on it wraps it
  /// whole at any width.
  /// One datum (its value made long on the page) and one table cell.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aFadedValueScrollsAndItsFadesFollow(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let record = try ScratchRecord()
    defer { record.remove() }
    let viewport = layout.viewport(for: engine)
    try await withPage(engine, gnorium, viewport: viewport) { page in
      let long = String(repeating: "web-tests-edge-fade-scroll-", count: 12)
      let cases: [(path: String, prepare: String)] = [
        (
          record.path,
          """
          (() => {
            const e = [...document.querySelectorAll('.datum-text')].find((e) => e.getClientRects().length > 0 && !e.querySelector('a'))
            if (!e) return false
            // The record's metadata is folded at first: open it, as a reader would.
            const folded = e.closest('details:not([open])')
            if (folded) folded.querySelector('summary').click()
            e.textContent = '\(long)'
            e.setAttribute('data-test-edge-fade', 'true')
            return true
          })()
          """
        ),
        (
          "/biblio-records",
          """
          (() => {
            // A plain cell (no link) that already overflows its column; else
            // one made long, where the column is held to its width.
            const plain = [...document.querySelectorAll('.table-view td [data-edge-fade="expand"]')]
              .filter((e) => e.getClientRects().length > 0 && !e.querySelector('a') && !e.closest('a'))
            const e = plain.find((e) => e.getAttribute('data-overflowing') === 'true') || plain[0]
            if (!e) return false
            if (e.getAttribute('data-overflowing') !== 'true') e.textContent = '\(long)'
            e.setAttribute('data-test-edge-fade', 'true')
            return true
          })()
          """
        ),
      ]
      for (path, prepare) in cases {
        try await page.openHydrated(path)
        try await page.expectNoErrors()
        let found = try await page.evaluate(prepare)
        #expect(found.bool == true, "\(path): no value to make long")
        guard found.bool == true else { continue }
        let box = page.locator("[data-test-edge-fade]")
        try await expect(box).toHaveAttribute("data-overflowing", "true")
        try await expect(box).toHaveAttribute("data-overflowing-start", "false")
        try await expect(box).toHaveAttribute("data-overflowing-end", "true")
        var state = try await Self.scrolling(page)
        #expect(state.scrolls, "\(path): the value does not scroll sideways")
        #expect(state.scrollbar == 0, "\(path): a scrollbar \(state.scrollbar) tall is drawn")
        #expect(state.startFade == "0px" && state.endFade != "0px", "\(path): fades \(state.startFade) / \(state.endFade) at rest")
        #expect(state.tabindex == "-1", "\(path): the value's tabindex is \(state.tabindex ?? "none")")
        try await expect(box).not.toHaveAttribute("role")

        // Partway: both edges hide some of it.
        _ = try await box.evaluate("(e) => { e.scrollLeft = (e.scrollWidth - e.clientWidth) / 2 * (getComputedStyle(e).direction === 'rtl' ? -1 : 1) }")
        try await expect(box).toHaveAttribute("data-overflowing-start", "true")
        try await expect(box).toHaveAttribute("data-overflowing-end", "true")
        // At the end: only the start does.
        _ = try await box.evaluate("(e) => { e.scrollLeft = (e.scrollWidth) * (getComputedStyle(e).direction === 'rtl' ? -1 : 1) }")
        try await expect(box).toHaveAttribute("data-overflowing-start", "true")
        try await expect(box).toHaveAttribute("data-overflowing-end", "false")
        state = try await Self.scrolling(page)
        #expect(state.startFade != "0px" && state.endFade == "0px", "\(path): fades \(state.startFade) / \(state.endFade) at the end")
        let masked = try await box.evaluate("(e) => (getComputedStyle(e).webkitMaskImage || getComputedStyle(e).maskImage || '').includes('gradient')")
        #expect(masked.bool == true, "\(path): a scrolled value is not faded")

        do {
          // The page above it settles first (the opened metadata grows into
          // place): the point is read once the box holds still.
          let measure = "(e) => { e.scrollIntoView({ block: 'center', behavior: 'instant' }); const r = e.getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2] }"
          var middle = try await box.evaluate(measure)
          for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(250))
            let again = try await box.evaluate(measure)
            if again == middle { break }
            middle = again
          }
          let x = try #require(middle.array?[0].double)
          let y = try #require(middle.array?[1].double)
          try await Self.press(page, x, y, viewport)
          try await expect(box).toHaveAttribute("data-edge-fade-expanded", "true")
          let whole = try await box.evaluate("(e) => e.scrollWidth <= e.clientWidth")
          #expect(whole.bool == true, "\(path): an expanded value still overflows")
          try await Self.press(page, x, y, viewport)
          try await expect(box).toHaveAttribute("data-edge-fade-expanded", "false")
          #expect(try await page.url().hasSuffix(path), "\(path): a tap on the value followed a link")
        }
      }
    }
  }

  /// A closed dropdown's value scrolls, as every faded value does, and its
  /// fades follow the scroll.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aClosedDropdownsValueScrolls(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/biblio-records")
      try await page.expectNoErrors()
      let long = String(repeating: "web-tests-dropdown-scroll-", count: 8)
      let found = try await page.evaluate(
        """
        (() => {
          const e = [...document.querySelectorAll('.dropdown-selected-text')].find((e) => e.getClientRects().length > 0)
          if (!e) return false
          e.textContent = '\(long)'
          e.setAttribute('data-test-edge-fade', 'true')
          return true
        })()
        """)
      try #require(found.bool == true, "no closed dropdown on the page")
      let box = page.locator("[data-test-edge-fade]")
      try await expect(box).toHaveAttribute("data-overflowing", "true")
      try await expect(box).toHaveAttribute("data-overflowing-end", "true")
      let state = try await Self.scrolling(page)
      #expect(state.scrolls, "a closed dropdown's value does not scroll sideways")
      #expect(state.scrollbar == 0, "a scrollbar \(state.scrollbar) tall is drawn in a dropdown's value")
      _ = try await box.evaluate("(e) => { e.scrollLeft = e.scrollWidth * (getComputedStyle(e).direction === 'rtl' ? -1 : 1) }")
      try await expect(box).toHaveAttribute("data-overflowing-start", "true")
      try await expect(box).toHaveAttribute("data-overflowing-end", "false")
    }
  }

  struct InputFade: Decodable {
    let start: Double
    let end: Double
  }

  /// The opacity of the marked input's two fades (its control's `::before`
  /// and `::after`).
  static func inputFade(_ page: Page) async throws -> InputFade {
    try await page.evaluate(
      """
      (() => {
        const control = document.querySelector('[data-test-edge-fade]').parentElement
        return {
          start: parseFloat(getComputedStyle(control, '::before').opacity),
          end: parseFloat(getComputedStyle(control, '::after').opacity),
        }
      })()
      """, as: InputFade.self)
  }

  /// An editable one-line input keeps its native scroll and caret: its long
  /// value fades at its end at rest, and not at all while it is focused.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aLongInputFadesAtRestAndNotWhileTyped(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/auth/register")
      try await page.expectNoErrors()
      let found = try await page.evaluate(
        """
        (() => {
          const e = [...document.querySelectorAll('input.text-input-input[data-edge-fade]')]
            .find((e) => e.getClientRects().length > 0 && (e.type === 'text' || e.type === 'email'))
          if (!e) return false
          e.setAttribute('data-test-edge-fade', 'true')
          return true
        })()
        """)
      try #require(found.bool == true, "no text input on the page")
      let input = page.locator("[data-test-edge-fade]")
      // Typed, then left.
      try await input.click()
      try await page.keyboard.insertText(String(repeating: "webtestsinputfade", count: 8))
      try await expect(input).toHaveAttribute("data-overflowing", "true")
      var fade = try await Self.inputFade(page)
      #expect(fade.start == 0 && fade.end == 0, "a focused input fades: \(fade)")
      _ = try await input.evaluate("(e) => e.blur()")
      try await expect(input).toHaveAttribute("data-overflowing-end", "true")
      fade = try await Self.inputFade(page)
      #expect(fade.end == 1 && fade.start == 0, "an input at rest fades \(fade)")
      // Focused again, the caret is in sight: no fade.
      try await input.focus()
      fade = try await Self.inputFade(page)
      #expect(fade.start == 0 && fade.end == 0, "a focused input fades: \(fade)")
    }
  }

  /// Whether a trail sits inside its footer and the page.
  struct TrailLayout: Decodable {
    let fits: Bool
  }

  static func trailLayout(_ page: Page, _ trail: String) async throws -> TrailLayout {
    try await page.evaluate(
      """
      (() => {
        const trail = document.querySelector('\(trail)')
        const footer = trail.closest('footer') || trail.parentElement
        return {
          fits: trail.getBoundingClientRect().right <= footer.getBoundingClientRect().right + 0.5
            && [...trail.querySelectorAll('*')].every((e) => e.getBoundingClientRect().right <= footer.getBoundingClientRect().right + 0.5 || e.closest('[data-overflowing]'))
            && document.documentElement.scrollWidth <= innerWidth,
        }
      })()
      """, as: TrailLayout.self)
  }

  /// The page's own crumb is never faded, long title or short, shallow
  /// trail or deep: it wraps whole (2026-10-04), its title its full text.
  /// Crumbs wrap between each other like words; a chevron may end a line
  /// (user, 2026-10-07).
  @Test(arguments: gnorium.engines, Layout.allCases)
  func theCurrentCrumbIsShownWhole(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let suffix = String(UUID().uuidString.lowercased().prefix(8))
    let title =
      "Web tests edge fade \(suffix): a title long enough to run past its breadcrumb at every width, "
      + "as the long titles of early printed books do"
    let long = try ScratchRecord(title: (title: title, slug: "web-tests-edge-fade-\(suffix)"))
    let short = try ScratchRecord()
    let viewport = layout.viewport(for: engine)
    defer {
      long.remove()
      short.remove()
    }
    try await withPage(engine, gnorium, viewport: viewport) { page in
      let trail = ".footer-breadcrumbs"
      let titlePage = "/" + long.path.split(separator: "/").prefix(3).joined(separator: "/")
      let shortTitlePage = "/" + short.path.split(separator: "/").prefix(3).joined(separator: "/")
      // (page, screenshot, its crumb's text, whether it overflows)
      let cases: [(String, String, String, Bool)] = [
        (titlePage, "breadcrumb", title, true),
        (shortTitlePage, "breadcrumb-short", short.title, false),
        ("\(long.path)/vignettes", "breadcrumb-deep", "Vignettes", false),
      ]
      for (path, name, text, overflows) in cases {
        try await page.openHydrated(path)
        try await page.expectNoErrors()
        let current = page.locator("\(trail) .breadcrumb-current")
        try await expect(current).toHaveText(text)
        let report = try await Self.settledReport(page, trail)
        #expect(report.ellipses.isEmpty, "\(path): text-overflow: ellipsis on \(report.ellipses)")
        #expect(report.wrong.isEmpty, "\(path): the fade disagrees with the overflow on \(report.wrong)")
        // The page's own crumb is never faded: shown whole, it wraps in its
        // room (2026-10-04); only an ancestor's label fades.
        try await expect(current).not.toHaveAttribute("data-edge-fade")
        if overflows {
          try await expect(current).toHaveAttribute("title", title)
        }
        let placed = try await Self.trailLayout(page, trail)
        #expect(placed.fits, "\(path): the breadcrumb trail runs past its footer or the page")
        _ = try await current.evaluate("(e) => e.scrollIntoView({ block: 'center' })")
        try await Self.screenshots(page, name, layout)
        // Shown whole, it has nothing to open.
        try await expect(current).not.toHaveAttribute("data-edge-fade-expanded")
      }
    }
  }

  struct ColumnReport: Decodable {
    let titleWidth: Double
    let widest: Double
    let languageShown: String
    let languageTitle: String
  }

  /// A phone gives the records tables' title the room: its column at least
  /// as wide as any other. The language is its full name at every width,
  /// never a code (user, 2026-09-30).
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aPhoneGivesTheTitleTheRoom(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      for path in ["/biblio-records", "/lexico-records"] {
        try await page.openHydrated(path)
        let columns = try await page.evaluate(
          """
          (() => {
            const heads = [...document.querySelectorAll('.table-table thead th[data-table-column-id]')]
            const width = (e) => e.getBoundingClientRect().width
            const title = heads.find((h) => h.getAttribute('data-table-column-id') === 'title')
            const cell = document.querySelector('main .table-view tbody tr > td:nth-child(2)')
            return {
              titleWidth: width(title),
              widest: Math.max(...heads.filter((h) => h !== title).map(width)),
              languageShown: cell.innerText.trim(),
              languageTitle: cell.title,
            }
          })()
          """, as: ColumnReport.self)
        switch layout {
        case .phone:
          #expect(columns.titleWidth >= columns.widest, "\(path): the title column is \(columns.titleWidth) wide, another \(columns.widest)")
          #expect(columns.titleWidth >= 150, "\(path): the title column is \(columns.titleWidth) wide at 375")
        case .desktop:
          break
        }
        #expect(columns.languageShown == columns.languageTitle, "\(path): the language reads \(columns.languageShown)")
        #expect(columns.languageTitle.count > 3, "\(path): the language cell's title is \(columns.languageTitle)")
        try await Self.screenshots(page, "columns\(path.replacingOccurrences(of: "/", with: "-"))", layout)
      }
    }
  }
}
