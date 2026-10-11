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
    // The slide (250ms) and its settle, with room to spare.
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
}
