import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A fenced code block's body sits at 16 on every side (user, 2026-10-14):
/// from the header's rule to the code's first line, and from its last line
/// to the frame's bottom border, wherever `CodeBlockView` is shown—a capped,
/// scrolling Markdown column (a prompt's rendering) never squeezes the frame.
/// Chrome, desktop.
@Suite("Code block padding", .serialized)
struct CodeBlockPaddingTests {
  /// Every block's body: its computed padding, and the space the frame
  /// shows above the code's first line and below its last.
  static let measure = """
    (() => JSON.stringify([...document.querySelectorAll('.code-block-view')]
      .filter(view => view.getClientRects().length > 0)
      .map(view => {
        const pre = view.querySelector('pre')
        const s = getComputedStyle(pre)
        const frame = view.getBoundingClientRect()
        const header = view.querySelector('.code-block-header').getBoundingClientRect()
        const range = document.createRange()
        range.selectNodeContents(pre)
        const text = range.getBoundingClientRect()
        const border = parseFloat(getComputedStyle(view).borderBottomWidth)
        const round = n => Math.round(n * 2) / 2
        return {
          padding: [s.paddingTop, s.paddingRight, s.paddingBottom, s.paddingLeft].join(' '),
          above: round(text.top - header.bottom), below: round(frame.bottom - border - text.bottom),
        }
      })))()
    """

  struct Body: Decodable, Equatable {
    let padding: String
    let above: Double
    let below: Double
  }

  static func expectEqualPadding(_ page: Page, _ context: String) async throws {
    let json = try await page.evaluate(measure, as: String.self)
    let bodies = try JSONDecoder().decode([Body].self, from: Data(json.utf8))
    #expect(!bodies.isEmpty, "A code block in \(context)")
    for body in bodies {
      #expect(body == Body(padding: "16px 16px 16px 16px", above: 16, below: 16), "\(context): \(body)")
    }
  }

  /// A process's prompt page, rendered: its fences.
  @Test(arguments: [BrowserEngine.chrome])
  func promptPage(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: .desktop) { page in
      try await page.openHydrated("/mission-control/prompts/bibliographic/explication")
      try await Self.expectEqualPadding(page, "the prompt page")
    }
  }

  /// A prompt palinode's Revise page, Explication's Task Prompt rendered
  /// in its capped column.
  @Test(arguments: [BrowserEngine.chrome])
  func revisePage(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let slot = "bibliographic_explication"
    let palinode = try ScratchPalinode(slot: slot, owner: contributor)
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(palinode.path)/revise")
        let prompts = page.locator(".prompt-revision-fields-view .prompt-revision-fields-process[data-process='\(slot)']")
        try await prompts.locator("#prompt-revision-process-\(slot) .accordion-summary").first.click()
        try await prompts.locator("#prompt-revision-task-accordion-\(slot) .accordion-summary").first.click()
        let task = prompts.locator("#prompt-revision-task-accordion-\(slot)")
        try await expect(task).toHaveAttribute("data-open-finished", "true")
        try await expect(task.locator(".prompt-text-rendered .code-block-view").first).toBeVisible()
        if let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"] {
          _ = try await page.evaluate(
            "(() => { document.querySelector('#prompt-revision-task-accordion-\(slot) .code-block-view').scrollIntoView({block: 'center'}); return 1 })()",
            as: Int.self)
          try await page.screenshot(to: URL(fileURLWithPath: directory).appendingPathComponent("code-block-padding.png"))
        }
        try await Self.expectEqualPadding(page, "the Revise page")
      }
    } catch {
      palinode.remove()
      try await contributor.remove(after: error)
    }
    palinode.remove()
    try await contributor.remove()
  }
}
