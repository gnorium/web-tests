import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Prompt vignette comparison", .serialized)
struct PromptVignetteComparisonTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func checkboxSelectionEnablesBlueCompareAndNavigatesToStyledDiff(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine), ["localhost", "127.0.0.1"].contains(gnorium.baseURL.host ?? "") else { return }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let old = UUID().uuidString
    let new = UUID().uuidString
    _ = try TestAdmin.query("""
      INSERT INTO prompt_vignettes(id,hash,slot,system_prompt,task_prompt,autocompaction_system_prompt,autocompaction_task_prompt,continuation_system_prompt,continuation_task_prompt,is_proprietary_content,created_at,committed_object_type,committed_object_id,committed_by_user_id,committed_at) VALUES
      ('\(old)','\(old)','bibliographic_explication','Recognize cat carefully.\nRemove old sentence.\nUnchanged context line 1\nUnchanged context line 2\nUnchanged context line 3\nUnchanged context line 4\nUnchanged context line 5\nUnchanged context line 6\nUnchanged context line 7\nUnchanged context line 8\nUnchanged context line 9\nUnchanged context line 10\nUnchanged context line 11\nUnchanged context line 12\nUnchanged context line 13\nUnchanged context line 14\nUnchanged context line 15\nUnchanged context line 16\nUnchanged context line 17\nUnchanged context line 18\nUnchanged context line 19\nUnchanged context line 20\nUnchanged context line 21\nUnchanged context line 22\nUnchanged context line 23\nUnchanged context line 24\nUnchanged context line 25\nUnchanged context line 26\nUnchanged context line 27\nUnchanged context line 28\nUnchanged context line 29\nUnchanged context line 30\nUnchanged context line 31\nUnchanged context line 32\nUnchanged context line 33\nUnchanged context line 34\nUnchanged context line 35\nUnchanged context line 36\nUnchanged context line 37\nUnchanged context line 38\nUnchanged context line 39\nUnchanged context line 40','Unchanged task {page}','Web tests summary.','Web tests {transcript}','','Web tests carry on.',false,'2026-01-01T00:00:00Z','bibliographicOverture',gen_random_uuid(),(SELECT id FROM users WHERE username = 'gnorium'),NOW()),
      ('\(new)','\(new)','bibliographic_explication','Recognize cats carefully.\nAdd new sentence.\nUnchanged context line 1\nUnchanged context line 2\nUnchanged context line 3\nUnchanged context line 4\nUnchanged context line 5\nUnchanged context line 6\nUnchanged context line 7\nUnchanged context line 8\nUnchanged context line 9\nUnchanged context line 10\nUnchanged context line 11\nUnchanged context line 12\nUnchanged context line 13\nUnchanged context line 14\nUnchanged context line 15\nUnchanged context line 16\nUnchanged context line 17\nUnchanged context line 18\nUnchanged context line 19\nUnchanged context line 20\nUnchanged context line 21\nUnchanged context line 22\nUnchanged context line 23\nUnchanged context line 24\nUnchanged context line 25\nUnchanged context line 26\nUnchanged context line 27\nUnchanged context line 28\nUnchanged context line 29\nUnchanged context line 30\nUnchanged context line 31\nUnchanged context line 32\nUnchanged context line 33\nUnchanged context line 34\nUnchanged context line 35\nUnchanged context line 36\nUnchanged context line 37\nUnchanged context line 38\nUnchanged context line 39\nUnchanged context line 40','Unchanged task {page}','Web tests summary.','Web tests {transcript}','','Web tests carry on, newer.',false,'2026-01-02T00:00:00Z','bibliographicOverture',gen_random_uuid(),(SELECT id FROM users WHERE username = 'gnorium'),NOW());
      """)
    defer { _ = try? TestAdmin.query("DELETE FROM prompt_vignettes WHERE id IN ('\(old)','\(new)')") }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/mission-control/prompts/bibliographic/explication/vignettes")
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
      try await expect(page.locator(".diff-changed").first).toBeAttached()
      // Each prompt shown as a prompt is, its diff under its box as every
      // field's is: a changed one opens in Raw, the diff beside the box,
      // never inside it; the unchanged one rendered with no diff.
      let comparisons = page.locator(".prompt-compare-content .prompt-text-comparison")
      try await expect(comparisons.nth(1).locator(".prompt-text-view .prompt-text-rendered")).toContainText("Unchanged task {page}")
      try await expect(comparisons.nth(1).locator(".diff-box")).toHaveCount(0)
      let changed = comparisons.nth(0)
      try await expect(changed.locator(".prompt-text-view")).toHaveAttribute("data-prompt-text-hydrated", "true")
      try await expect(changed.locator(".prompt-text-view")).toHaveAttribute("data-raw", "true")
      try await expect(changed.locator(".prompt-text-view .diff-box")).toHaveCount(0)
      try await expect(changed.locator(":scope > .prompt-text-diff .diff-box")).toBeVisible()
      // Every prompt of the process, in the vignette's order (user,
      // 2026-10-17), as the Revise page and the prompt previews list them
      // (gnorium-web e140e4996): the continuation changed, then the
      // autocompaction's two unchanged.
      try await expect(comparisons).toHaveCount(5)
      try await expect(comparisons.nth(2).locator(".prompt-text-view")).toHaveAttribute("data-raw", "true")
      try await expect(comparisons.nth(2).locator(":scope > .prompt-text-diff .diff-box")).toBeVisible()
      try await expect(comparisons.nth(3).locator(".prompt-text-view")).toHaveAttribute("data-raw", "false")
      try await expect(comparisons.nth(4).locator(".prompt-text-view")).toHaveAttribute("data-raw", "false")
      let styled = try await page.evaluate("""
        (() => {
          const content = document.querySelector('.prompt-compare-content');
          const header = content.querySelector('.vignette-header');
          return getComputedStyle(content).display === 'flex'
            && getComputedStyle(header).flexDirection === (innerWidth <= 768 ? 'column' : 'row')
            && (() => { const [a, b] = header.querySelectorAll('.vignette-identity'); const arrow = header.querySelector('.vignette-arrow').getBoundingClientRect(); const x = r => r.left + r.width / 2; const ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect();
              return innerWidth <= 768 ? (arrow.top >= ra.bottom && arrow.bottom <= rb.top && Math.abs(x(arrow) - x(ra)) < 2 && getComputedStyle(header.querySelector('.vignette-arrow')).transform !== 'none')
                : (arrow.left >= ra.right && arrow.right <= rb.left); })()
            && getComputedStyle(header).justifyContent === 'center'
            && getComputedStyle(header).textAlign === 'center'
            && [...header.querySelectorAll('a')].every(a => a.classList.contains('link-view'))
            && [...header.querySelectorAll('.vignette-identity')].length === 2
            // Each side its creation time, then its UUID, linked, in an (i)
            // tooltip after it.
            && [...header.querySelectorAll('.vignette-identity')].every((side, i) => side.firstElementChild.classList.contains('local-time-view')
              && side.lastElementChild.classList.contains('vignette-identifier')
              && side.lastElementChild.classList.contains('tooltip-view')
              // Its bubble portaled to <body> once hydrated.
              && [...document.querySelectorAll('.tooltip-content a.link-view')].some(a => a.textContent.trim().toUpperCase() === [\(old.debugDescription), \(new.debugDescription)][i].toUpperCase())
              && getComputedStyle(side).alignItems === 'center');
        })()
        """, as: Bool.self)
      #expect(styled)
      try await expect(page.locator(".page-heading")).toHaveText("Compare Prompt Vignettes")
      #expect(try await page.evaluate("""
        (() => {
          const box = document.querySelector('.diff-box');
          const removed = document.querySelector('.diff-row[data-diff-line="removed"] .diff-changed');
          const inserted = document.querySelector('.diff-row[data-diff-line="inserted"] .diff-changed');
          const rgb = (node, property = 'color') => { const canvas=document.createElement('canvas');canvas.width=canvas.height=1;const ctx=canvas.getContext('2d');ctx.fillStyle=getComputedStyle(node)[property];ctx.fillRect(0,0,1,1);return ctx.getImageData(0,0,1,1).data; };
          const fill = node => rgb(node, 'backgroundColor');
          const red = fill(removed), green = fill(inserted);
          const redLine = fill(removed.closest('.diff-row')), greenLine = fill(inserted.closest('.diff-row'));
          return box.textContent.includes('Unchanged context line 40')
            && getComputedStyle(box).maxHeight === 'none'
            && box.clientHeight >= box.scrollHeight - 1
            && getComputedStyle(box).backgroundColor === 'rgb(255, 255, 255)'
            // Changed characters filled solid, red where they were and
            // green where they are, their text inverted; their lines tinted
            // lighter in the same hue.
            && red[0] > red[1] && red[0] > red[2]
            && green[1] > green[0] && green[1] > green[2]
            && rgb(removed)[0] > 200 && rgb(inserted)[1] > 200
            && [redLine, greenLine].every((line, i) => { const solid = [red, green][i]; return line[0] + line[1] + line[2] > solid[0] + solid[1] + solid[2]; });
        })()
        """, as: Bool.self))
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }
}
