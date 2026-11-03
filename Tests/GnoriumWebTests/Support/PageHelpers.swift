import Foundation
import WebTests

extension Page {
  /// Fails where a reader is clipped or widens the page (user, 2026-11-03:
  /// the page never widens for it; its footer is one row that scrolls
  /// sideways inside itself where its controls do not fit): its footer one
  /// row, scrolling on its own; the reader no wider than the screen; no
  /// ancestor of it that hides or scrolls overflow narrower than it; and the
  /// page's fixed and sticky chrome on screen scrolled fully sideways.
  func expectArtifactsUnclipped(file: String = #fileID, filePath: String = #filePath, line: Int = #line) async throws {
    let problems = try await evaluate(
      """
      (() => {
        const out = [];
        for (const v of document.querySelectorAll('.artifact-view')) {
          if (!v.getClientRects().length) continue;
          const r = v.getBoundingClientRect();
          if (r.right + scrollX > innerWidth + 1) out.push('a reader wider than the screen');
          const footer = v.querySelector('.artifact-footer');
          const items = footer ? [...footer.children].filter((c) => c.getClientRects().length > 0) : [];
          if (items.length && !items.every((c) => Math.abs(c.getBoundingClientRect().top - items[0].getBoundingClientRect().top) < 2))
            out.push('a footer on two rows');
          if (footer && getComputedStyle(footer).overflowX !== 'auto') out.push('a footer that cannot scroll on its own');
          for (let e = v.parentElement; e && e !== document.body; e = e.parentElement) {
            const ox = getComputedStyle(e).overflowX;
            if (ox === 'visible') continue;
            const b = e.getBoundingClientRect();
            if (b.left > r.left + 1 || b.right < r.right - 1)
              out.push(ox + ' ' + (e.className || e.tagName).toString().split(' ')[0] + ' ' + Math.round(b.width) + ' < ' + Math.round(r.width));
          }
        }
        // Fixed and sticky chrome on screen at the start stays on screen
        // scrolled fully sideways.
        const x = scrollX;
        scrollTo(0, scrollY);
        const onScreen = (e) => { const b = e.getBoundingClientRect();
          return b.width > 0 && b.height > 0 && b.right > 0 && b.left < innerWidth && b.bottom > 0 && b.top < innerHeight; };
        const chrome = [...document.querySelectorAll('body *')].filter((e) => {
          const p = getComputedStyle(e).position; return (p === 'fixed' || p === 'sticky') && onScreen(e); });
        scrollTo(document.documentElement.scrollWidth, scrollY);
        for (const e of chrome) {
          if (!onScreen(e)) out.push(getComputedStyle(e).position + ' ' + (e.className || e.tagName).toString().split(' ')[0] + ' off screen');
        }
        scrollTo(x, scrollY);
        return [...new Set(out)].join('; ');
      })()
      """
    ).string ?? ""
    if !problems.isEmpty {
      throw WebTestError(
        "Clipped on \((try? await url()) ?? "the page"): \(problems)",
        location: CodeLocation(fileID: file, filePath: filePath, line: line, column: 1))
    }
  }

  /// A form committed in a Source (user, 2026-11-03): the words from the
  /// element `first` names to the one `last` names (each a selector inside
  /// `box`; `last` nil for one word) selected as a hand's drag selects
  /// them, the native selection, then "+ Form" on the bar floating over it.
  func addForm(in box: Locator, from first: String, to last: String? = nil) async throws {
    let selected = try await box.first.evaluate(
      """
      (b) => {
        const a = b.querySelector(`\(first)`), z = b.querySelector(`\(last ?? first)`);
        if (!a || !z) return false;
        a.scrollIntoView({ block: 'center' });
        getSelection().setBaseAndExtent(a, 0, z, z.childNodes.length);
        return !getSelection().isCollapsed;
      }
      """
    ).bool ?? false
    guard selected else { throw WebTestError("No words to select for a form: \(first) … \(last ?? first)") }
    // The bar of the Source the selection is in: the one offering it.
    let add = locator(".quote-passage-bar .quote-passage-form-add[data-visible='true']")
    try await expect(add).toHaveCount(1)
    try await expect(add).toBeVisible()
    try await add.click()
  }

  /// Loads a Gnorium page and waits for the client to hydrate it: the load
  /// event, then the WebAssembly client started
  /// (`<html data-wasm-status="started">`, set by loader.js). Not
  /// `.networkIdle`: the home page keeps a request open and never goes idle.
  func openHydrated(_ path: String, file: String = #fileID, filePath: String = #filePath, line: Int = #line) async throws {
    let result = try await goto(path, waitUntil: .load)
    if let status = result.status, status >= 400 {
      throw WebTestError(
        "\(path) answered HTTP \(status).",
        location: CodeLocation(fileID: file, filePath: filePath, line: line, column: 1))
    }
    try await expect(locator("html"), timeout: .seconds(20), fileID: file, filePath: filePath, line: line)
      .toHaveAttribute("data-wasm-status", "started")
  }

  /// The size a control of `size` ("small", "medium" or "large") is drawn
  /// at here: itself, or one step down (large to medium, medium to small,
  /// small to mini) under the phone step below the phone breakpoint
  /// (`ButtonView.phoneStep`).
  func controlSize(_ size: String) async throws -> String {
    try await evaluate(
      """
      (() => {
        const root = document.documentElement;
        const breakpoint = getComputedStyle(root).getPropertyValue('--max-width-breakpoint-phone-narrow').trim();
        const stepped = root.dataset.phoneStep === 'down' && matchMedia(`(max-width: ${breakpoint})`).matches;
        const sizes = ['mini', 'small', 'medium', 'large'];
        return sizes[sizes.indexOf('\(size)') - (stepped ? 1 : 0)];
      })()
      """, as: String.self)
  }

  /// A CSS length here, in px ("40px"): a probe's height set to it, so
  /// tokens (`var(--spacing-8)`) and `calc()` resolve as the page has them.
  func length(_ css: String) async throws -> String {
    try await evaluate(
      """
      (() => {
        const probe = document.createElement('div');
        probe.style.cssText = 'position: absolute; visibility: hidden; height: \(css)';
        document.body.appendChild(probe);
        const height = getComputedStyle(probe).height;
        probe.remove();
        return height;
      })()
      """, as: String.self)
  }

  /// A ButtonView's height here for its `size` ("medium" or "large"): its
  /// inset on every side of the 22px line inside its 1px border, read off
  /// the size tokens, at the size it is drawn (`controlSize`).
  func controlHeight(_ size: String) async throws -> String {
    let inset = ["mini": "--spacing-0", "small": "--spacing-4", "medium": "--spacing-8", "large": "--spacing-12"][
      try await controlSize(size)] ?? ""
    return try await length("calc(2 * var(\(inset)) + var(--line-height-small-22) + 2 * var(--border-width-base))")
  }

  /// A control's icon size: its 22px line at every size (user, 2026-10-21),
  /// so the icon fills the line and never grows the control.
  func controlIconSize() async throws -> String {
    try await length("var(--line-height-small-22)")
  }

  /// A control's type size here for its `size`, at the size it is drawn
  /// (`controlSize`).
  func controlFontSize(_ size: String) async throws -> String {
    let token = [
      "mini": "--font-size-x-small-12", "small": "--font-size-small-14", "medium": "--font-size-medium-16",
      "large": "--font-size-large-18",
    ][
      try await controlSize(size)] ?? ""
    return try await length("var(\(token))")
  }
}

extension Locator {
  /// An avatar's or a tree node marker's ring (user, 2026-11-03), for this
  /// locator, the control that folds (a locution's `.locution-collapse`,
  /// whose avatar is ringed, or a node's `.outliner-marker`): "rest" when
  /// it is one subtle 1px border outside the disc, which keeps its full
  /// size, no outline; "focus" when, focused from the keyboard, it is the
  /// focus ring every control wears, the border in the focus color and a
  /// 1px outline of it, the control drawing no ring of its own; else what
  /// is off. Never a box-shadow.
  func discRing() async throws -> String {
    try await evaluate(
      """
      (control) => {
        const disc = control.matches('.outliner-marker') ? control : control.querySelector('.avatar-view');
        const probe = (name) => {
          const el = document.createElement('span');
          el.style.color = `var(${name})`;
          document.body.appendChild(el);
          const color = getComputedStyle(el).color;
          el.remove();
          return color;
        };
        const d = getComputedStyle(disc), r = getComputedStyle(disc, '::after'), c = getComputedStyle(control);
        const off = [];
        if (d.borderTopStyle !== 'none' && d.borderTopWidth !== '0px') off.push('a border inside the disc ' + d.borderTopWidth);
        if (r.position !== 'absolute' || [r.top, r.right, r.bottom, r.left].some((v) => v !== '-1px'))
          off.push('not outside the disc ' + [r.position, r.top, r.right, r.bottom, r.left].join(' '));
        if (r.borderTopWidth !== '1px' || r.borderTopStyle !== 'solid') off.push('border ' + r.borderTopWidth + ' ' + r.borderTopStyle);
        if ([d.boxShadow, r.boxShadow, c.boxShadow].some((s) => s !== 'none')) off.push('a box-shadow');
        const focused = control.matches(':focus-visible');
        const color = probe(focused ? '--border-color-blue-focus' : '--border-color-subtle');
        if (r.borderTopColor !== color) off.push('border color ' + r.borderTopColor + ' not ' + color);
        if (focused) {
          if (r.outlineStyle !== 'solid' || r.outlineWidth !== '1px' || r.outlineColor !== color || r.outlineOffset !== '0px')
            off.push('outline ' + [r.outlineStyle, r.outlineWidth, r.outlineColor, r.outlineOffset].join(' '));
          if (c.outlineStyle !== 'none' && c.outlineColor !== 'rgba(0, 0, 0, 0)') off.push('a ring of its own ' + c.outlineColor);
        } else if (r.outlineStyle !== 'none' && r.outlineWidth !== '0px') {
          off.push('an outline at rest ' + r.outlineWidth);
        }
        return off.length ? off.join('; ') : focused ? 'focus' : 'rest';
      }
      """
    ).string ?? "nothing"
  }
}
