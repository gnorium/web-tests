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
          const state = status === 'running' ? 'running' : ['succeeded', 'committed'].includes(status) ? 'done'
            : status === 'stale' ? 'stale' : 'pending';
          // Stale has marks of its own: explication an orange ring,
          // translation a blue disc in an orange ring.
          const shape = state === 'running'
            ? (translation ? '.rotating-ring-sector-with-disc-view' : '.rotating-sector-view')
            : state === 'done' || state === 'stale' ? (translation ? '.ringed-disc-icon-view' : (state === 'done' ? '.disc-icon-view' : '.ring-icon-view'))
            : (translation ? '.disc-icon-view' : '.ring-icon-view');
          if (!visible('.roster-status-' + state + ' ' + shape)) failures.push(status + ': wrong shape');
          const tone = state === 'stale' && !translation ? 'orange' : 'blue';
          const probe = document.createElement('span');
          probe.style.color = 'var(--color-' + tone + ')'; document.body.append(probe);
          if (getComputedStyle(mark).color !== getComputedStyle(probe).color) failures.push(status + ': not ' + tone);
          if (state === 'stale' && translation) {
            const ring = mark.querySelector('.roster-status-stale circle:last-child');
            const orange = document.createElement('span');
            orange.style.color = 'var(--color-orange)'; document.body.append(orange);
            if (!ring || getComputedStyle(ring).stroke !== getComputedStyle(orange).color) failures.push('stale: ring not orange');
            orange.remove();
          }
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

  /// The in-progress mark of each process, one rule for every mark a running
  /// process draws (`ProcessInFlight.mark`, user, 2026-10-17): explication
  /// the turning disc sector, translation the turning ring sector round a
  /// still disc, arbitration by the highest level its object has fully
  /// reached (user, 2026-10-21): postulated the dotted ring sector,
  /// calibrated the ring sector, explicated the disc sector, translated the
  /// ring sector round a still disc.
  static func inProgressShape(_ process: String, arbitrated: String = "postulated") -> String {
    switch process {
    case "translation": return ".rotating-ring-sector-with-disc-view"
    case "arbitration":
      switch arbitrated {
      case "calibrated": return ".rotating-ring-sector-view"
      case "explicated": return ".rotating-sector-view"
      case "translated": return ".rotating-ring-sector-with-disc-view"
      default: return ".rotating-dotted-ring-sector-view"
      }
    default: return ".rotating-sector-view"
    }
  }

  /// Every Thinking card's running mark in `scope` is `process`'s
  /// in-progress mark, never another process's.
  static func checkThinking(
    _ page: Page, process: String, arbitrated: String = "postulated", scope: String = ".computorium-session-view"
  ) async throws {
    let shapes = [
      ".rotating-sector-view", ".rotating-ring-sector-with-disc-view", ".rotating-dotted-ring-sector-view",
      ".rotating-ring-sector-view",
    ]
    let shape = inProgressShape(process, arbitrated: arbitrated)
    let wrong = shapes.filter { $0 != shape }.joined(separator: ", ")
    let failures = try await page.evaluate(
      """
      (() => {
        const marks = [...document.querySelectorAll('\(scope) .computorium-session-output-thinking-mark-running')];
        if (!marks.length) return 'no thinking card';
        return marks.every(m => m.querySelector('\(shape)') && !m.querySelector('\(wrong)'))
          ? '' : 'wrong running mark';
      })()
      """, as: String.self)
    #expect(failures.isEmpty, "Computorium \(process) thinking marks: \(failures)")
  }
}
