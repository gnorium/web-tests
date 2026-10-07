import Testing
import WebTests
import WebTestsTesting

@Suite("Existing prompt snapshot comparison", .serialized)
struct ActualPromptSnapshotComparisonTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func actualSnapshotsShowColoredChangesInFullWhiteContext(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/mission-control/prompts/snapshots/compare?from=832FEFF0-9FD1-4711-86F9-AA1213C72996&to=CE0E6E42-ECF9-4BE8-A365-598219F30063")
      try await expect(page.locator(".page-heading")).toContainText("Compare Prompt Snapshots")
      try await expect(page.locator(".diff-view-box")).toHaveCSS("background-color", "rgb(255, 255, 255)")
      #expect(try await page.evaluate("""
        (()=>{const removed=[...document.querySelectorAll('[data-diff-line=removed] .diff-view-changed')];
          const inserted=[...document.querySelectorAll('[data-diff-line=inserted] .diff-view-changed')];
          const rgb = node => { const canvas=document.createElement('canvas');canvas.width=canvas.height=1;const ctx=canvas.getContext('2d');ctx.fillStyle=getComputedStyle(node).color;ctx.fillRect(0,0,1,1);return ctx.getImageData(0,0,1,1).data; };
          const boxes=[...document.querySelectorAll('.diff-view-box,.prompt-compare-unchanged')];const rows=[...document.querySelectorAll('.diff-view-row')];
          return removed.length===8 && inserted.length===0 && removed.every(e=>{const c=rgb(e);return c[0]>c[1]&&c[0]>c[2];})
            && document.querySelectorAll('[data-diff-line=inserted]').length===2 && rows.length>4
            && boxes.length===2 && boxes.every(e=>{const s=getComputedStyle(e);return s.maxHeight==='none' && s.overflowY==='visible' && s.backgroundColor==='rgb(255, 255, 255)';});})()
        """, as: Bool.self), "Actual snapshots remove eight spaces in red and retain full white unbounded context")
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }
}
