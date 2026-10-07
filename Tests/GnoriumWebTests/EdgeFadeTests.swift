import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A single line too long for its box is clipped and fades out at its end
/// (`fadeOverflow`, EdgeFade.swift), never cut with an ellipsis—in tables,
/// breadcrumbs, menus, chips, sidebars, everywhere. The fade is drawn exactly
/// on the boxes whose line runs past them.
///
/// On a phone a tap shows the whole value and another folds it back. A link
/// in the box stays a link: a tap on its words follows it, and only a tap in
/// the fade opens the box. A tap off an open box folds it; Enter on a focused
/// box opens and folds it. At 1400 wide a click on a link always follows it.
///
/// With `EDGE_FADE_SCREENSHOTS` set to a folder, each page is also saved
/// there, light and dark, for a look.
@Suite("Edge fade", .serialized)
struct EdgeFadeTests {
  /// The main pages, as a reader first meets them.
  static let pages = [
    "/", "/biblio-records", "/lexico-records", "/mission-control/lifecycles", "/mission-control/contributors",
    "/mission-control/antiphons", "/mission-control/notations", "/mission-control/instances",
    "/mission-control/interventions",
  ]
  static let tables = ["/biblio-records", "/lexico-records", "/mission-control/lifecycles"]

  struct Report: Decodable {
    /// Boxes that may fade, shown.
    let boxes: Int
    let overflowing: Int
    /// Anything on the page ending its text in "…" by CSS.
    let ellipses: [String]
    /// Boxes whose fade disagrees with their overflow.
    let wrong: [String]
    /// Boxes that are buttons (expand on a tap).
    let buttons: Int
  }

  /// Reads the fade of every shown box under `scope`.
  static func report(_ page: Page, _ scope: String) async throws -> Report {
    try await page.evaluate(
      """
      (() => {
        const shown = (e) => e.getClientRects().length > 0
        const boxes = [...document.querySelectorAll('\(scope) [data-edge-fade]')].filter(shown)
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
          wrong: boxes.filter((e) => e.getAttribute('aria-expanded') !== 'true')
            .filter((e) => over(e) !== faded(e))
            .map((e) => (over(e) ? 'unfaded: ' : 'faded: ') + e.className.toString() + ' ' + e.textContent.trim().slice(0, 60)),
          buttons: boxes.filter((e) => e.getAttribute('role') === 'button').length,
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

  /// No ellipsis anywhere, and every box faded exactly where it overflows—and
  /// never a button at 1400 wide.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func everyPageFadesWhereItOverflows(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      for path in Self.pages {
        try await page.openHydrated(path)
        try await page.expectNoErrors()
        let report = try await Self.settledReport(page, "body")
        #expect(report.ellipses.isEmpty, "\(path): text-overflow: ellipsis on \(report.ellipses)")
        #expect(report.wrong.isEmpty, "\(path): the fade disagrees with the overflow on \(report.wrong)")
        if layout == .desktop {
          #expect(report.buttons == 0, "\(path): \(report.buttons) boxes expand at 1400 wide")
        }
        try await Self.screenshots(page, Self.slug(path), layout)
      }
    }
  }

  /// A table cell: its link's words follow the link at any width; on a phone
  /// a tap in the fade opens the cell and stays on the page, a tap off it
  /// folds it, and Enter opens and folds it.
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

        if layout == .phone {
          // The fade opens it, and the page stays where it is.
          try await expect(box).toHaveAttribute("aria-expanded", "false")
          try await Self.press(page, target.fadeX, target.fadeY, viewport)
          try await expect(box).toHaveAttribute("aria-expanded", "true")
          let whole = try await box.evaluate("(e) => e.scrollWidth <= e.clientWidth")
          #expect(whole.bool == true, "\(path): an expanded cell still overflows")
          #expect(try await page.url().hasSuffix(path), "\(path): the tap in the fade followed a link")
          // A tap off it folds it.
          let (x, y) = try await Self.quietPoint(page)
          try await Self.press(page, x, y, viewport)
          try await expect(box).toHaveAttribute("aria-expanded", "false")
          // Enter, focused.
          try await box.press("Enter")
          try await expect(box).toHaveAttribute("aria-expanded", "true")
          try await box.press("Enter")
          try await expect(box).toHaveAttribute("aria-expanded", "false")
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

  /// A cell with no link opens on a tap anywhere in it, and folds on another.
  @Test(arguments: gnorium.engines)
  func aFadedPlainCellExpandsOnATap(engine: BrowserEngine) async throws {
    let viewport = Layout.phone.viewport(for: engine)
    try await withPage(engine, gnorium, viewport: viewport) { page in
      var checked = 0
      for path in Self.tables {
        try await page.openHydrated(path)
        _ = try await Self.settledReport(page, ".table-view")
        guard let target = try await Self.markFirstOverflowing(page, ".table-view", withLink: false) else { continue }
        let box = page.locator("[data-test-edge-fade]")
        try await Self.press(page, target.wordsX, target.wordsY, viewport)
        try await expect(box).toHaveAttribute("aria-expanded", "true")
        try await Self.press(page, target.wordsX, target.wordsY, viewport)
        try await expect(box).toHaveAttribute("aria-expanded", "false")
        #expect(try await page.url().hasSuffix(path), "\(path): a tap on a plain cell followed the row's link")
        checked += 1
      }
      if checked == 0 { try Test.cancel("no plain table cell overflows at 375 in the dev data") }
    }
  }

  /// Where a trail's crumbs sit: the page's own crumb on the line of the
  /// chevron before it, and the trail inside its footer and the page.
  struct TrailLayout: Decodable {
    let currentTop: Double
    let chevronTop: Double
    let fits: Bool
  }

  static func trailLayout(_ page: Page, _ trail: String) async throws -> TrailLayout {
    try await page.evaluate(
      """
      (() => {
        const trail = document.querySelector('\(trail)')
        const current = trail.querySelector('.breadcrumb-current')
        const chevrons = [...trail.querySelectorAll('.breadcrumb-separator')]
        const chevron = chevrons[chevrons.length - 1]
        const footer = trail.closest('footer') || trail.parentElement
        return {
          currentTop: current.getBoundingClientRect().top + current.getBoundingClientRect().height / 2,
          chevronTop: chevron.getBoundingClientRect().top + chevron.getBoundingClientRect().height / 2,
          fits: trail.getBoundingClientRect().right <= footer.getBoundingClientRect().right + 0.5
            && [...trail.querySelectorAll('*')].every((e) => e.getBoundingClientRect().right <= footer.getBoundingClientRect().right + 0.5 || e.closest('[data-overflowing]'))
            && document.documentElement.scrollWidth <= innerWidth,
        }
      })()
      """, as: TrailLayout.self)
  }

  /// The page's own crumb stays after its chevron, on the same line, long
  /// title or short, shallow trail or deep; a long one is never faded but
  /// wraps whole (2026-10-04), its title its full text.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func theCurrentCrumbStaysOnItsChevronsLine(engine: BrowserEngine, layout: Layout) async throws {
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
        ("\(long.path)/snapshots", "breadcrumb-deep", "Snapshots", false),
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
        #expect(abs(placed.currentTop - placed.chevronTop) < 2,
          "\(path): the page's crumb is not on its chevron's line (\(placed.currentTop) vs \(placed.chevronTop))")
        #expect(placed.fits, "\(path): the breadcrumb trail runs past its footer or the page")
        _ = try await current.evaluate("(e) => e.scrollIntoView({ block: 'center' })")
        try await Self.screenshots(page, name, layout)
        if layout == .desktop {
          #expect(report.buttons == 0, "\(path): \(report.buttons) crumbs expand at 1400 wide")
        }
        // Shown whole, it has nothing to open.
        try await expect(current).not.toHaveAttribute("aria-expanded")
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
