import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An editor marks the caret's line as Xcode does (user, 2026-10-12): the
/// line's band in the code's gray, its number in the text's color, while the
/// editor has the focus; it follows the caret. Read-only code in the reader's
/// pane is on the page's ground. A throwaway contributor's scratch madrigal,
/// revised.
@Suite("Code editor current line", .serialized)
struct CodeEditorCurrentLineTests {
  static let markup = #"<div>\n  <p>One</p>\n  <p>Two</p>\n  <p>Three</p>\n</div>"#

  struct Mark: Decodable {
    let shown: Bool
    let current: [Int]
    let bandTop: Double
    let lineTop: Double
  }

  /// Whether the band shows, which numbers are current, and the band's and
  /// the current number's tops.
  static let mark = """
    (() => { const view = document.querySelector('.tei-page[data-active="true"] .tei-page-edit .code-view');
      const numbers = [...view.querySelectorAll('.code-gutter-lines > span')];
      const current = numbers.map((n, i) => n.dataset.current === 'true' ? i : -1).filter((i) => i >= 0);
      const band = view.querySelector('.code-current-line');
      return { shown: view.dataset.currentLine === 'true' && !!band && getComputedStyle(band).display !== 'none',
        current, bandTop: band ? band.getBoundingClientRect().top : -1,
        lineTop: current.length ? numbers[current[0]].getBoundingClientRect().top : -2 }; })()
    """

  @Test(arguments: [BrowserEngine.chrome])
  func theCaretsLineIsMarkedAndFollowsIt(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor)
    do {
      _ = try TestAdmin.query(
        """
        UPDATE bibliographic_madrigals SET
          proposed_content_json = '{"teiXml":"<TEI><text><body><pb n=\\"1\\" facs=\\"https://web-tests.invalid/iiif/p1/full/1300,/0/default.jpg\\"/>\(Self.markup)</body></text></TEI>"}'
        WHERE id = '\(commit.madrigalID)'
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(commit.madrigalPath)/revise")
        let code = page.locator(".tei-page[data-active='true'] .tei-page-edit .code-code").first
        if try await page.locator(".artifact-raw-toggle button").first.getAttribute("aria-pressed") != "true" {
          try await page.locator(".artifact-raw-toggle button").first.click()
        }
        try await expect(code).toBeVisible()
        // Not focused: no band.
        let resting = try await page.evaluate(Self.mark, as: Mark.self)
        #expect(!resting.shown, "a band shows with no focus")
        // A click on the second line marks it.
        let second = code.locator(".code-line").nth(1)
        try await second.click()
        try await Task.sleep(for: .milliseconds(200))
        let first = try await page.evaluate(Self.mark, as: Mark.self)
        #expect(first.shown, "the caret's line is not marked")
        #expect(first.current == [1], "the marked number is not the second: \(first.current)")
        #expect(abs(first.bandTop - first.lineTop) < 1, "the band is not on its line")
        if let dir = ProcessInfo.processInfo.environment["CARET_SHOTS"] {
          try await page.screenshot(to: URL(fileURLWithPath: dir + "/editor-line-2-light.png"))
          _ = try await page.evaluate("(() => { document.documentElement.setAttribute('data-color-scheme', 'dark'); return 1 })()")
          try await Task.sleep(for: .milliseconds(200))
          try await page.screenshot(to: URL(fileURLWithPath: dir + "/editor-line-2-dark.png"))
          _ = try await page.evaluate("(() => { document.documentElement.setAttribute('data-color-scheme', 'light'); return 1 })()")
        }
        // The arrow down: the next line.
        try await page.keyboard.press("ArrowDown")
        try await Task.sleep(for: .milliseconds(200))
        let next = try await page.evaluate(Self.mark, as: Mark.self)
        #expect(next.shown && next.current == [2], "the band did not follow the caret down: \(next.current)")
        #expect(abs(next.bandTop - next.lineTop) < 1, "the band is not on its line")
        try await page.expectNoErrors()
        if let dir = ProcessInfo.processInfo.environment["CARET_SHOTS"] {
          try await page.openHydrated(commit.madrigalPath)
          try await page.locator(".artifact-raw-toggle button").first.click()
          try await Task.sleep(for: .milliseconds(400))
          _ = try await page.evaluate("(() => { document.querySelector('.artifact-view').scrollIntoView({block: 'start'}); return 1 })()")
          try await page.screenshot(to: URL(fileURLWithPath: dir + "/raw-read-only.png"))
        }
      }
      commit.remove()
      try await contributor.remove()
    } catch {
      commit.remove()
      try await contributor.remove(after: error)
    }
  }
}
