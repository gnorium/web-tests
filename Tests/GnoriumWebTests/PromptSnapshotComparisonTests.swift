import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Prompt snapshot comparison", .serialized)
struct PromptSnapshotComparisonTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func checkboxSelectionEnablesBlueCompareAndNavigatesToStyledDiff(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine), ["localhost", "127.0.0.1"].contains(gnorium.baseURL.host ?? "") else { return }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let old = UUID().uuidString
    let new = UUID().uuidString
    _ = try TestAdmin.query("""
      INSERT INTO prompt_templates(id,hash,stage,system_prompt,task_prompt,template_version,is_proprietary_content,created_at) VALUES
      ('\(old)','\(old)','bibliographic_explication','Recognize cat carefully.\nRemove old sentence.\nUnchanged context line 1\nUnchanged context line 2\nUnchanged context line 3\nUnchanged context line 4\nUnchanged context line 5\nUnchanged context line 6\nUnchanged context line 7\nUnchanged context line 8\nUnchanged context line 9\nUnchanged context line 10\nUnchanged context line 11\nUnchanged context line 12\nUnchanged context line 13\nUnchanged context line 14\nUnchanged context line 15\nUnchanged context line 16\nUnchanged context line 17\nUnchanged context line 18\nUnchanged context line 19\nUnchanged context line 20\nUnchanged context line 21\nUnchanged context line 22\nUnchanged context line 23\nUnchanged context line 24\nUnchanged context line 25\nUnchanged context line 26\nUnchanged context line 27\nUnchanged context line 28\nUnchanged context line 29\nUnchanged context line 30\nUnchanged context line 31\nUnchanged context line 32\nUnchanged context line 33\nUnchanged context line 34\nUnchanged context line 35\nUnchanged context line 36\nUnchanged context line 37\nUnchanged context line 38\nUnchanged context line 39\nUnchanged context line 40','Unchanged task {page}','compare-fixture-old',false,'2026-01-01T00:00:00Z'),
      ('\(new)','\(new)','bibliographic_explication','Recognize cats carefully.\nAdd new sentence.\nUnchanged context line 1\nUnchanged context line 2\nUnchanged context line 3\nUnchanged context line 4\nUnchanged context line 5\nUnchanged context line 6\nUnchanged context line 7\nUnchanged context line 8\nUnchanged context line 9\nUnchanged context line 10\nUnchanged context line 11\nUnchanged context line 12\nUnchanged context line 13\nUnchanged context line 14\nUnchanged context line 15\nUnchanged context line 16\nUnchanged context line 17\nUnchanged context line 18\nUnchanged context line 19\nUnchanged context line 20\nUnchanged context line 21\nUnchanged context line 22\nUnchanged context line 23\nUnchanged context line 24\nUnchanged context line 25\nUnchanged context line 26\nUnchanged context line 27\nUnchanged context line 28\nUnchanged context line 29\nUnchanged context line 30\nUnchanged context line 31\nUnchanged context line 32\nUnchanged context line 33\nUnchanged context line 34\nUnchanged context line 35\nUnchanged context line 36\nUnchanged context line 37\nUnchanged context line 38\nUnchanged context line 39\nUnchanged context line 40','Unchanged task {page}','compare-fixture-new',false,'2026-01-02T00:00:00Z');
      """)
    defer { _ = try? TestAdmin.query("DELETE FROM prompt_templates WHERE id IN ('\(old)','\(new)')") }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/mission-control/prompts/bibliographic/explication/snapshots")
      let button = page.locator(".compare-button")
      #expect(try await page.evaluate("document.querySelector('.compare-button').disabled", as: Bool.self))
      try await page.locator("input[name='row-selection'][value='\(old)']").click()
      #expect(try await page.evaluate("document.querySelector('.compare-button').disabled", as: Bool.self))
      try await page.locator("input[name='row-selection'][value='\(new)']").click()
      try await expect(button).toHaveCSS("color", "rgb(255, 255, 255)")
      #expect(try await page.evaluate("!document.querySelector('.compare-button').disabled && document.querySelector('.compare-button').dataset.color === 'blue' && document.querySelector('.compare-button').dataset.weight === 'solid' && (() => { const canvas=document.createElement('canvas');canvas.width=canvas.height=1;const ctx=canvas.getContext('2d');ctx.fillStyle=getComputedStyle(document.querySelector('.compare-button')).backgroundColor;ctx.fillRect(0,0,1,1);const c=ctx.getImageData(0,0,1,1).data; return c[2] > c[0] && c[2] > c[1]; })()", as: Bool.self))
      #expect(try await page.evaluate("!document.querySelector('.compare-button').hasAttribute('aria-disabled')", as: Bool.self))
      let enabledAppearance = """
        (() => {
          const style = getComputedStyle(document.querySelector('.compare-button'));
          const text = style.color.match(/\\d+/g).map(Number);
          return style.cursor === 'pointer' && text.slice(0, 3).every(channel => channel === 255);
        })()
        """
      #expect(try await page.evaluate(enabledAppearance, as: Bool.self))
      try await button.hover()
      try await expect(button).toHaveCSS("color", "rgb(255, 255, 255)")
      #expect(try await page.evaluate(enabledAppearance, as: Bool.self))
      try await page.locator("input[name='row-selection'][value='\(new)']").click()
      let disabledColor = try await page.evaluate("(() => { const n=document.createElement('span');n.style.color='var(--color-disabled)';document.body.append(n);const color=getComputedStyle(n).color;n.remove();return color; })()", as: String.self)
      try await expect(button).toHaveCSS("color", disabledColor)
      #expect(try await page.evaluate("""
        (() => {
          const button = document.querySelector('.compare-button');
          const style = getComputedStyle(button);
          const canvas=document.createElement('canvas');canvas.width=canvas.height=1;const ctx=canvas.getContext('2d');ctx.fillStyle=style.backgroundColor;ctx.fillRect(0,0,1,1);const background=ctx.getImageData(0,0,1,1).data;
          return button.disabled && style.cursor === 'not-allowed'
            && Math.max(...background.slice(0, 3)) - Math.min(...background.slice(0, 3)) < 20;
        })()
        """, as: Bool.self))
      try await page.locator("input[name='row-selection'][value='\(new)']").click()
      try await button.hover()
      try await expect(button).toHaveCSS("color", "rgb(255, 255, 255)")
      #expect(try await page.evaluate(enabledAppearance, as: Bool.self))
      try await button.click()
      try await expect(page.locator(".prompt-compare-content")).toBeVisible()
      try await expect(page.locator(".diff-view-changed").first).toBeAttached()
      try await expect(page.locator(".prompt-compare-unchanged")).toHaveText("Unchanged task {page}")
      let styled = try await page.evaluate("""
        (() => {
          const content = document.querySelector('.prompt-compare-content');
          const header = content.querySelector('.snapshot-header');
          return getComputedStyle(content).display === 'flex'
            && getComputedStyle(header).flexWrap === 'wrap'
            && getComputedStyle(header).justifyContent === 'center'
            && getComputedStyle(header).textAlign === 'center'
            && [...header.querySelectorAll('a')].every(a => a.classList.contains('link-view'))
            && [...header.querySelectorAll('.snapshot-identity')].length === 2
            && [...header.querySelectorAll('.snapshot-identity')].every(side => side.querySelector('.local-time-view')
              && getComputedStyle(side).alignItems === 'center');
        })()
        """, as: Bool.self)
      #expect(styled)
      try await expect(page.locator(".page-heading")).toHaveText("Compare Prompt Snapshots")
      #expect(try await page.evaluate("""
        (() => {
          const box = document.querySelector('.diff-view-box');
          const unchanged = document.querySelector('.prompt-compare-unchanged');
          const removed = document.querySelector('.diff-view-row[data-diff-line="removed"] .diff-view-changed');
          const inserted = document.querySelector('.diff-view-row[data-diff-line="inserted"] .diff-view-changed');
          const rgb = node => { const canvas=document.createElement('canvas');canvas.width=canvas.height=1;const ctx=canvas.getContext('2d');ctx.fillStyle=getComputedStyle(node).color;ctx.fillRect(0,0,1,1);return ctx.getImageData(0,0,1,1).data; };
          const red = rgb(removed), green = rgb(inserted);
          return box.textContent.includes('Unchanged context line 40')
            && getComputedStyle(box).maxHeight === 'none'
            && box.clientHeight >= box.scrollHeight - 1
            && getComputedStyle(box).backgroundColor === 'rgb(255, 255, 255)'
            && getComputedStyle(unchanged).backgroundColor === 'rgb(255, 255, 255)'
            && red[0] > red[1] && red[0] > red[2]
            && green[1] > green[0] && green[1] > green[2];
        })()
        """, as: Bool.self))
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }
}
