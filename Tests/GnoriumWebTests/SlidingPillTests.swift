import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The solid tabs' sliding pill ends exactly under the selected tab however
/// its slide is interrupted (user, 2026-10-12): a burst of clicks, a click
/// in the middle of a slide, a run of arrow keys. A half-finished slide had
/// left it short of its tab, the label clipped ("Lexicograph"). The system
/// account's profile carries a two-tab set any reader can open.
@Suite("Sliding pill", .serialized)
struct SlidingPillTests {
  struct Placement: Decodable {
    let selected: String
    let thumb: [Double]
    let tab: [Double]
  }

  /// The thumb's drawn box and the selected tab's, as [left, top, width, height].
  static let measure = """
    (() => {
      const tabs = document.querySelector('.user-profile-work');
      const tab = tabs.querySelector("[role='tab'][aria-selected='true']");
      const box = (e) => { const r = e.getBoundingClientRect(); return [r.left, r.top, r.width, r.height]; };
      return { selected: tab.textContent.trim(), thumb: box(tabs.querySelector('.sliding-pill-thumb')), tab: box(tab) };
    })()
    """

  func expectSettled(on page: Page, at name: String) async throws {
    // The slide and its settle, with room to spare.
    try await Task.sleep(for: .milliseconds(700))
    let placement = try await page.evaluate(Self.measure, as: Placement.self)
    #expect(placement.selected == name)
    for (thumb, tab) in zip(placement.thumb, placement.tab) {
      #expect(abs(thumb - tab) < 0.5, "pill \(placement.thumb) under tab \(placement.tab)")
    }
  }

  @Test(arguments: [BrowserEngine.chrome])
  func anInterruptedSlideEndsUnderTheSelectedTab(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: .desktop) { page in
      try await page.openHydrated("/users/gnorium")
      let list = page.locator(".user-profile-work .tabs-list")
      try await expect(list).toHaveAttribute("data-sliding-pill", "ready")
      let bibliographic = try #require(try await page.locator(".user-profile-work #tab-bibliographic").boundingBox())
      let lexicographic = try #require(try await page.locator(".user-profile-work #tab-lexicographic").boundingBox())
      let points = [bibliographic, lexicographic].map { ($0.x + $0.width / 2, $0.y + $0.height / 2) }

      // A burst of clicks, none waiting for the slide.
      for index in 0..<7 {
        let point = points[(index + 1) % 2]
        try await page.mouse.click(x: point.0, y: point.1)
      }
      try await expectSettled(on: page, at: "Lexicographic")

      // A click in the middle of each slide.
      for index in 0..<4 {
        let point = points[index % 2]
        try await page.mouse.click(x: point.0, y: point.1)
        try await Task.sleep(for: .milliseconds(100))
      }
      try await expectSettled(on: page, at: "Lexicographic")

      // A run of arrow keys.
      try await page.locator(".user-profile-work #tab-lexicographic").focus()
      for _ in 0..<5 { try await page.keyboard.press("ArrowRight") }
      try await expectSettled(on: page, at: "Bibliographic")
      try await page.expectNoErrors()
    }
  }

  struct Layers: Decodable {
    /// The hovered tab's own background, its fill layer's, and the layer's z-index.
    let hoveredBackground: String
    let hoveredFill: String
    let hoveredFillZ: String
    /// Every tab's own z-index and background: none may stack over the pill.
    let tabZ: [String]
    let tabBackgrounds: [String]
    let listIsolation: String
  }

  static let layers = """
    (() => {
      const tabs = document.querySelector('.user-profile-work');
      const all = [...tabs.querySelectorAll("[role='tab']")];
      const hovered = tabs.querySelector('#tab-bibliographic');
      const fill = getComputedStyle(hovered, '::before');
      return {
        hoveredBackground: getComputedStyle(hovered).backgroundColor,
        hoveredFill: fill.backgroundColor, hoveredFillZ: fill.zIndex,
        tabZ: all.map(t => getComputedStyle(t).zIndex),
        tabBackgrounds: all.map(t => getComputedStyle(t).backgroundColor),
        listIsolation: getComputedStyle(tabs.querySelector('.tabs-list')).isolation,
      };
    })()
    """

  /// The race the user found (2026-10-12): select the next tab, then hover
  /// the one just left while the pill slides away from it. The hover fill
  /// is painted, but under the pill: no tab paints a background of its own
  /// or stacks over the pill, mid-slide or after; the pill ends under the
  /// selected tab, its label whole on it.
  @Test(arguments: [BrowserEngine.chrome])
  func aTabHoveredMidSlideStaysUnderThePill(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: .desktop) { page in
      try await page.openHydrated("/users/gnorium")
      try await expect(page.locator(".user-profile-work .tabs-list")).toHaveAttribute("data-sliding-pill", "ready")
      let bibliographic = try #require(try await page.locator(".user-profile-work #tab-bibliographic").boundingBox())
      let lexicographic = try #require(try await page.locator(".user-profile-work #tab-lexicographic").boundingBox())
      try await page.mouse.click(x: lexicographic.x + lexicographic.width / 2, y: lexicographic.y + lexicographic.height / 2)
      try await page.mouse.move(x: bibliographic.x + bibliographic.width / 2, y: bibliographic.y + bibliographic.height / 2)
      for wait in [80, 700] {
        try await Task.sleep(for: .milliseconds(wait))
        let layers = try await page.evaluate(Self.layers, as: Layers.self)
        #expect(layers.listIsolation == "isolate")
        #expect(layers.hoveredFill != "rgba(0, 0, 0, 0)", "the hover is painted: \(layers.hoveredFill)")
        #expect(layers.hoveredFillZ == "-1")
        #expect(layers.tabZ.allSatisfy { $0 == "auto" }, "\(layers.tabZ)")
        #expect(layers.tabBackgrounds.allSatisfy { $0 == "rgba(0, 0, 0, 0)" }, "\(layers.tabBackgrounds)")
      }
      // The pill under the selected tab, so its label is whole on blue.
      let placement = try await page.evaluate(Self.measure, as: Placement.self)
      #expect(placement.selected == "Lexicographic")
      for (thumb, tab) in zip(placement.thumb, placement.tab) {
        #expect(abs(thumb - tab) < 0.5, "pill \(placement.thumb) under tab \(placement.tab)")
      }
      try await page.expectNoErrors()
    }
  }
}
