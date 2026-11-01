import Foundation
import WebTests

extension Page {
  /// Fails where a reader is clipped (user, 2026-11-02: past the screen the
  /// page widens, so a phone pinches out to see it whole): its footer one
  /// row, never scrolling on its own; no ancestor of an
  /// artifact that hides or scrolls overflow is narrower than it, the
  /// document is as wide as every artifact, and the page's fixed and sticky
  /// chrome stays on screen scrolled fully sideways.
  func expectArtifactsUnclipped(file: String = #fileID, filePath: String = #filePath, line: Int = #line) async throws {
    let problems = try await evaluate(
      """
      (() => {
        const out = [];
        const docRight = document.documentElement.scrollWidth;
        for (const v of document.querySelectorAll('.artifact-view')) {
          if (!v.getClientRects().length) continue;
          const r = v.getBoundingClientRect();
          if (r.right + scrollX > docRight + 1) out.push('document narrower than a reader');
          const footer = v.querySelector('.artifact-footer');
          const items = footer ? [...footer.children].filter((c) => c.getClientRects().length > 0) : [];
          if (items.length && !items.every((c) => Math.abs(c.getBoundingClientRect().top - items[0].getBoundingClientRect().top) < 2))
            out.push('a footer on two rows');
          if (footer && footer.scrollWidth > footer.clientWidth + 1) out.push('a footer scrolling on its own');
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
