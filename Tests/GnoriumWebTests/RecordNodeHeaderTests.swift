import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A header's controls stand on its FIRST line (user, 2026-11-01): a
/// record node's number (centered on the tree's spine beside it, user
/// 2026-11-03), info icon and grip are level at the header's top, never
/// centered on a wrapped block; a tree node's header has no chevron, its
/// number folds it. A compact (minimal) header keeps its one line
/// centered in the pointer's target, its chevron on that line; a control
/// taller than a line (an outline's grip) stands centered on the first
/// line.
@Suite("Record node header", .serialized)
struct RecordNodeHeaderTests {
  /// Each top and center, from the summary's top.
  struct Marks: Decodable {
    let lines: Double
    let number: Double
    let info: Double?
    let chevron: Double?
    let handleCenter: Double?
    let numberCenter: Double
  }

  /// The first summary under `scope` holding a number: its value made long
  /// enough to wrap at every width, then its marks measured.
  static func measure(_ scope: String) -> String {
    """
    (() => {
      // Its number stands beside its header, centered on the tree's spine
      // (user, 2026-11-03), on the header's first line.
      const own = s => s.parentElement.closest('.record-node-view')
      const summary = [...document.querySelectorAll('\(scope) .accordion-summary')]
        .find(s => s.querySelector('.record-node-heading') && own(s) && own(s).querySelector(':scope > .record-node-anchor .record-node-number'))
      // Its value's box (user, 2026-11-02): the text inside its inset, a
      // field's where it is edited, the read box's words where it is read.
      const title = summary.querySelector('.record-node-heading .node-value-view :is(textarea, .node-value-box)')
      const long = 'The London bookseller and publisher John Trundell, who printed the first quarto '
        + 'of Hamlet with Nicholas Ling in 1603, and whose shop stood at the sign of the Barbican.'
      if (title.matches('textarea')) title.value = long
      else title.querySelector('.node-value-text').textContent = long
      const origin = summary.getBoundingClientRect().top
      const box = el => el ? el.getBoundingClientRect() : null
      const top = el => el ? box(el).top - origin : null
      const center = el => el ? box(el).top + box(el).height / 2 - origin : null
      const number = own(summary).querySelector(':scope > .record-node-anchor .record-node-number')
      return {
        lines: Math.round(title.clientHeight / parseFloat(getComputedStyle(title).lineHeight)) - 1,
        number: top(number),
        info: top(summary.querySelector('.record-node-uuid svg')),
        // A tree node's header has none: its number folds it (user,
        // 2026-11-03).
        chevron: (svg => svg && svg.getBoundingClientRect().height > 0 ? top(svg) : null)(
          summary.querySelector('.accordion-expand-icon svg')),
        handleCenter: center(summary.querySelector('.outliner-handle')),
        numberCenter: center(number)
      }
    })()
    """
  }

  static func expectFirstLine(_ marks: Marks) {
    #expect(marks.lines >= 2, "the value does not wrap: \(marks.lines) line")
    if let info = marks.info {
      #expect(abs(info - marks.number) < 1, "info icon \(info) vs number \(marks.number)")
    }
    #expect(marks.chevron == nil, "a tree node's header has a chevron")
    if let handle = marks.handleCenter {
      #expect(abs(handle - marks.numberCenter) < 1, "grip center \(handle) vs number center \(marks.numberCenter)")
    }
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWrappedHeadersControlsStandOnItsFirstLine(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(word.path)
        try await expect(page.locator(".record-node-view .record-node-uuid").first).toBeVisible()
        let marks = try await page.evaluate(Self.measure(".record-node-view"), as: Marks.self)
        #expect(marks.info != nil, "the row has no info icon")
        Self.expectFirstLine(marks)
      }
    } catch {
      word.remove()
      try await admin.remove(after: error)
    }
    word.remove()
    try await admin.remove()
  }

  /// A compact (minimal) header—none on a page yet, so a row's Metadata
  /// header is set compact: on one line its title centered in the pointer's
  /// target, as before; wrapped, its 4px padding above and below; the
  /// chevron on the title's first line either way.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aCompactHeadersOneLineStaysCentered(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    struct Compact: Decodable {
      let height: Double
      let target: Double
      let lineHeight: Double
      let above: Double
      let below: Double
      let chevron: Double
    }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(word.path)
        try await expect(page.locator("[id^='record-metadata-'] .accordion-summary").first).toBeVisible()
        for wrapped in [false, true] {
          let compact = try await page.evaluate(
            """
            (() => {
              const summary = [...document.querySelectorAll("[id^='record-metadata-'] .accordion-summary")]
                .find(s => s.getBoundingClientRect().height > 0)
              summary.dataset.separation = 'minimal'
              const title = summary.querySelector('.accordion-title')
              if (\(wrapped)) title.textContent = 'The London bookseller and publisher John Trundell, who printed '
                + 'the first quarto of Hamlet with Nicholas Ling in 1603, and whose shop stood at the sign of the Barbican.'
              const s = summary.getBoundingClientRect(), t = title.getBoundingClientRect()
              const probe = document.createElement('div')
              probe.style.height = 'var(--min-size-interactive-pointer)'
              document.body.append(probe)
              const target = probe.getBoundingClientRect().height
              probe.remove()
              return {
                height: s.height, target, lineHeight: parseFloat(getComputedStyle(title).lineHeight),
                above: t.top - s.top, below: s.bottom - t.bottom,
                chevron: summary.querySelector('.accordion-expand-icon svg').getBoundingClientRect().top - t.top
              }
            })()
            """, as: Compact.self)
          if !wrapped {
            #expect(abs(compact.height - compact.target) < 0.5, "a compact header is \(compact.height) high")
            #expect(
              abs(compact.above - (compact.target - compact.lineHeight) / 2) < 0.5,
              "its title stands \(compact.above) down")
          } else {
            #expect(compact.height > compact.target, "the compact title does not wrap")
            // Its padding alone above and below: 4px, never more.
            #expect(abs(compact.above - 4) < 0.5, "a wrapped compact title stands \(compact.above) down")
          }
          #expect(abs(compact.above - compact.below) < 0.5, "wrapped \(wrapped): above \(compact.above) vs below \(compact.below)")
          #expect(abs(compact.chevron) < 0.5, "wrapped \(wrapped): its chevron stands \(compact.chevron) off its title")
        }
      }
    } catch {
      word.remove()
      try await admin.remove(after: error)
    }
    word.remove()
    try await admin.remove()
  }

  /// An outline row (the amendment form): its grip is taller than a line,
  /// and still its number, grip and info icon share the first line.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aGripTallerThanALineStaysOnTheFirstLine(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("\(word.path)/amendments/new")
        let outline = page.locator(".sentiment-outliner-view")
        try await expect(outline.locator(".record-node-view .outliner-handle").first).toBeVisible()
        let marks = try await page.evaluate(Self.measure(".sentiment-outliner-view .record-node-view"), as: Marks.self)
        #expect(marks.handleCenter != nil, "the row has no grip")
        Self.expectFirstLine(marks)
      }
    } catch {
      word.remove()
      try await admin.remove(after: error)
    }
    word.remove()
    try await admin.remove()
  }
}
