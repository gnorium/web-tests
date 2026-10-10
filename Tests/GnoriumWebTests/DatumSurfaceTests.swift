import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A datum is a read-only field's box to the pixel: 8px inset on every side,
/// one line 22px high, a 1px border, so 40px tall (a list that wraps by
/// design grows by whole lines); its value on the disabled
/// field's gray at every depth (white only where `data-sent`), its label
/// and the view itself transparent. Read on the seeded lexicographic
/// overture, whose record metadata is all datums.
@Suite("Read-only datum boxes", .serialized)
struct DatumSurfaceTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func valuesKeepTheReadOnlyFieldBoxAndGround(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/mission-control/overtures/lexicographic/C0FFEE00-0000-4000-8000-000000000130")
      try await expect(page.locator("#record-language > .datum-value")).toBeVisible()
      let failures = try await page.evaluate(
        """
        (() => {
          const probe = document.createElement('span');
          document.body.append(probe);
          probe.style.backgroundColor = 'var(--background-color-disabled)';
          const gray = getComputedStyle(probe).backgroundColor;
          probe.style.backgroundColor = 'var(--background-color-base)';
          const white = getComputedStyle(probe).backgroundColor;
          probe.remove();
          const clear = c => c === 'rgba(0, 0, 0, 0)' || c === 'transparent';
          const views = [...document.querySelectorAll('.datum-view')].filter(v => v.getClientRects().length > 0);
          const out = [];
          if (views.length < 4) out.push('only ' + views.length + ' visible datums');
          if (gray === white) out.push('disabled ground is white');
          for (const view of views) {
            const name = view.querySelector(':scope > .datum-label')?.textContent.trim() || view.id || '?';
            const label = view.querySelector(':scope > .datum-label');
            const value = view.querySelector(':scope > .datum-value');
            const v = getComputedStyle(value);
            const ground = view.dataset.sent === 'true' ? white : gray;
            const box = value.getBoundingClientRect();
            const wraps = [...value.querySelectorAll('*')].some(e => getComputedStyle(e).whiteSpace === 'normal');
            const lines = (box.height - 18) / 22;
            const problems = [
              !clear(getComputedStyle(view).backgroundColor) && 'view ground',
              !clear(getComputedStyle(label).backgroundColor) && 'label ground',
              v.backgroundColor !== ground && 'value ground ' + v.backgroundColor,
              [v.paddingTop, v.paddingRight, v.paddingBottom, v.paddingLeft].some(p => p !== '8px')
                && 'padding ' + [v.paddingTop, v.paddingRight, v.paddingBottom, v.paddingLeft].join(' '),
              [v.borderTopWidth, v.borderRightWidth, v.borderBottomWidth, v.borderLeftWidth].some(b => b !== '1px')
                && 'border ' + v.borderTopWidth,
              v.lineHeight !== '22px' && 'line height ' + v.lineHeight,
              // One line, 40px; a list that wraps by design (a terms list)
              // grows by whole 22px lines.
              (wraps ? !(lines >= 1 && Math.abs(lines - Math.round(lines)) < 0.03) : Math.abs(box.height - 40) > 0.5)
                && 'height ' + box.height,
            ].filter(Boolean);
            if (problems.length) out.push(name + ': ' + problems.join(', '));
          }
          return out;
        })()
        """, as: [String].self)
      #expect(failures.isEmpty, "\(failures)")
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }
}
