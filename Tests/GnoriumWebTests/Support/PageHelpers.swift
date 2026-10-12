import Foundation
import WebTests

extension Page {
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

  /// A control's type size here for its `size`, at the size it is drawn
  /// (`controlSize`): its own icon's size too.
  func controlFontSize(_ size: String) async throws -> String {
    let token = [
      "mini": "--font-size-x-small-12", "small": "--font-size-small-14", "medium": "--font-size-medium-16",
      "large": "--font-size-large-18",
    ][
      try await controlSize(size)] ?? ""
    return try await length("var(\(token))")
  }
}
