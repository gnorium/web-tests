import Testing
import WebTests

/// Exercise the status changes used by the watch stream on real roster markup.
enum ComputoriumMarks {
  static func check(_ page: Page, process: String) async throws {
    let failures = try await page.evaluate(
      """
      (() => {
        const mark = document.querySelector('.computorium-core-sessions-slot .roster-status');
        if (!mark || mark.dataset.process !== '\(process)') return 'missing process mark';
        const row = mark.closest('.roster-row');
        const selected = row.classList.contains('roster-row-selected');
        const original = mark.dataset.status;
        row.classList.remove('roster-row-selected');
        const translation = '\(process)' === 'translation';
        const failures = [];
        // The header chip keeps its own vocabulary (never the roster's):
        // submitted green, failed red, in flight or pending blue.
        const header = document.querySelector('.computorium-core-header-status-chip');
        const label = header ? header.textContent.trim() : '';
        const tone = label === 'Submitted' ? 'green' : label === 'Failed' ? 'red' : 'blue';
        if (!header || !header.classList.contains('info-chip-' + tone)) failures.push('header not ' + tone);
        if (document.querySelector('.computorium-core-view :is(.alert-red, .alert-orange, .alert-green)'))
          failures.push('non-blue alert');
        const visible = selector => {
          const el = mark.querySelector(selector);
          return el && getComputedStyle(el.parentElement).display !== 'none';
        };
        for (const status of ['queued', 'awaiting', 'failed', 'stale', 'running', 'succeeded', 'committed']) {
          mark.dataset.status = status;
          const state = status === 'running' ? 'running' : ['succeeded', 'committed'].includes(status) ? 'done' : 'pending';
          const shape = state === 'running'
            ? (translation ? '.rotating-ring-sector-with-disc-view' : '.rotating-sector-view')
            : state === 'done' ? (translation ? '.ringed-disc-icon-view' : '.disc-icon-view')
            : (translation ? '.disc-icon-view' : '.ring-icon-view');
          if (!visible('.roster-status-' + state + ' ' + shape)) failures.push(status + ': wrong shape');
          const probe = document.createElement('span');
          probe.style.color = 'var(--color-blue)'; document.body.append(probe);
          if (getComputedStyle(mark).color !== getComputedStyle(probe).color) failures.push(status + ': not blue');
          probe.remove();
        }
        if (translation) {
          const core = mark.querySelector('.rotating-ring-sector-with-disc-core');
          const svg = core.parentElement;
          if (getComputedStyle(core).animationName !== 'none' || getComputedStyle(svg).animationName !== 'none')
            failures.push('translation disc rotates');
          const ring = mark.querySelector('.rotating-ring-sector-with-disc-ring');
          if (getComputedStyle(ring).animationName !== 'rotating-ring-sector-with-disc-spin') failures.push('ring does not rotate');
        }
        mark.dataset.status = original;
        if (selected) row.classList.add('roster-row-selected');
        return failures.join('; ');
      })()
      """, as: String.self)
    #expect(failures.isEmpty, "Computorium \(process) marks: \(failures)")
  }
}
