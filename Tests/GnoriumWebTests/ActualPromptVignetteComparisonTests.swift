import Testing
import WebTests
import WebTestsTesting

@Suite("Existing prompt vignette comparison", .serialized)
struct ActualPromptVignetteComparisonTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func actualVignettesShowColoredChangesInFullWhiteContext(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/mission-control/prompts/vignettes/compare?from=832FEFF0-9FD1-4711-86F9-AA1213C72996&to=CE0E6E42-ECF9-4BE8-A365-598219F30063")
      try await expect(page.locator(".page-heading")).toContainText("Compare Prompt Vignettes")
      // The diff beside the changed prompt's box, under it, the box in Raw.
      let changed = page.locator(".prompt-compare-content .prompt-text-comparison:has(> .prompt-text-diff .diff-box)").first
      try await expect(changed.locator(".prompt-text-view")).toHaveAttribute("data-prompt-text-hydrated", "true")
      try await expect(changed.locator(".prompt-text-view")).toHaveAttribute("data-raw", "true")
      try await expect(page.locator(".diff-box")).toBeVisible()
      try await expect(page.locator(".diff-box")).toHaveCSS("background-color", "rgb(255, 255, 255)")
      #expect(try await page.evaluate("""
        (()=>{const removed=[...document.querySelectorAll('[data-diff-line=removed] .diff-changed')];
          const inserted=[...document.querySelectorAll('[data-diff-line=inserted] .diff-changed')];
          const rgb = (node, property = 'color') => { const canvas=document.createElement('canvas');canvas.width=canvas.height=1;const ctx=canvas.getContext('2d');ctx.fillStyle=getComputedStyle(node)[property];ctx.fillRect(0,0,1,1);return ctx.getImageData(0,0,1,1).data; };
          const fill = node => rgb(node, 'backgroundColor');
          const boxes=[...document.querySelectorAll('.diff-box')];const rows=[...document.querySelectorAll('.diff-row')];
          return removed.length===4 && inserted.length===4 && removed.every(e=>{const c=fill(e);return c[0]>c[1]&&c[0]>c[2];})
            && inserted.every(e=>{const c=fill(e);return c[1]>c[0]&&c[1]>c[2];})
            && removed.every(e=>e.textContent===' \u{2014} ') && inserted.every(e=>e.textContent==='\u{2014}')
            && !document.body.textContent.includes(String.fromCharCode(183))
            && document.querySelectorAll('[data-diff-line=inserted]').length===2 && rows.length>4
            && boxes.length===1 && boxes.every(e=>{const s=getComputedStyle(e);return s.maxHeight==='none' && s.overflowY==='visible' && s.backgroundColor==='rgb(255, 255, 255)';});})()
        """, as: Bool.self), "Actual vignettes mark each spaced dash whole, red, and its closed-up dash whole, green (whole-token marks), no stand-in dots, in full white context the page leaves uncapped on purpose")
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }

  /// From, arrow, to stand on one row wherever they fit, whatever the width
  /// of the viewport, and stack (arrow turned down) only where they don't.
  @Test(arguments: [1440, 840, 600, 420, 320])
  func headerStacksOnlyWhenTheRowDoesNotFit(width: Int) async throws {
    try await withPage(.chrome, gnorium, viewport: Viewport(width: width, height: 900)) { page in
      try await page.openHydrated("/mission-control/prompts/vignettes/compare?from=832FEFF0-9FD1-4711-86F9-AA1213C72996&to=CE0E6E42-ECF9-4BE8-A365-598219F30063")
      let header = page.locator(".vignette-header")
      try await expect(header).toHaveAttribute("data-crowded")
      let fits = try await page.evaluate("""
        (() => {
          const row = document.querySelector('.vignette-header');
          const children = [...row.children];
          return children.reduce((sum, child) => sum + child.getBoundingClientRect().width, 0)
            + parseFloat(getComputedStyle(row).columnGap) * (children.length - 1) <= row.clientWidth + 0.5;
        })()
        """, as: Bool.self)
      // Side by side when every child's top is above every child's bottom;
      // one above the other when each starts below the one before ends.
      let boxes = try await page.evaluate(
        "[...document.querySelector('.vignette-header').children].map(child => { const box = child.getBoundingClientRect(); return [box.top, box.bottom]; })",
        as: [[Double]].self)
      let oneRow = boxes.map { $0[0] }.max()! < boxes.map { $0[1] }.min()!
      let oneAboveTheOther = zip(boxes, boxes.dropFirst()).allSatisfy { $1[0] >= $0[1] - 1 }
      let crowded = try await header.getAttribute("data-crowded")
      if fits {
        #expect(crowded == "false", "the row fits, so it stays one row at \(width)")
        #expect(oneRow, "from, arrow, to on one row at \(width): \(boxes)")
      } else {
        #expect(crowded == "true", "the row doesn't fit, so it stacks at \(width)")
        #expect(oneAboveTheOther, "one above the other at \(width): \(boxes)")
      }
      if width >= 600 { #expect(fits, "a \(width)-wide window has room for one row") }
      try await page.expectNoHorizontalOverflow()
    }
  }
}
