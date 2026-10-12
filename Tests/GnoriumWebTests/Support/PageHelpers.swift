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

  /// A ButtonView's height here for its `size` ("medium" or "large"): its
  /// inset on every side of the 22px line inside its 1px border, read off
  /// the size tokens, one step down (large to medium, medium to small)
  /// under the phone step below the phone breakpoint (`ButtonView.phoneStep`).
  func controlHeight(_ size: String) async throws -> String {
    try await evaluate(
      """
      (() => {
        const root = document.documentElement;
        const breakpoint = getComputedStyle(root).getPropertyValue('--max-width-breakpoint-phone-narrow').trim();
        const stepped = root.dataset.phoneStep === 'down' && matchMedia(`(max-width: ${breakpoint})`).matches;
        const sizes = ['small', 'medium', 'large'];
        const stepIndex = sizes.indexOf('\(size)') - (stepped ? 1 : 0);
        const inset = { small: '--spacing-4', medium: '--spacing-8', large: '--spacing-12' }[sizes[stepIndex]];
        const probe = document.createElement('div');
        probe.style.cssText = `position: absolute; visibility: hidden; height: calc(2 * var(${inset}) + var(--line-height-small-22) + 2 * var(--border-width-base))`;
        document.body.appendChild(probe);
        const height = getComputedStyle(probe).height;
        probe.remove();
        return height;
      })()
      """, as: String.self)
  }
}
