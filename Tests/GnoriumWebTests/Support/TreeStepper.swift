import Foundation
import WebTests
import WebTestsTesting

/// A tree's one row of steppers (`OutlinerStepperView`, user 2026-11-03),
/// after the tree: "‹ + Testament 1.2. ›" stepping through every place a
/// new node may go, its button putting one there, and "‹ − Testament 1.1. ›"
/// stepping through the nodes that may go, its button removing the one
/// chosen (a removed one's, "+ Testament 1.1.", restoring it). Where an
/// open object holds the node or place stepped to, the button is disabled,
/// the object linked in its tooltip (`holdTooltip`).
struct TreeStepper {
  /// The row: `.outliner-stepper-view` for the tree `tree` names.
  let row: Locator

  /// The row of the tree whose id is `tree` ("testament-outliner").
  init(_ page: Page, tree: String) {
    row = page.locator(".outliner-stepper-view[data-outliner-stepper-for='\(tree)']")
  }

  /// The row inside `scope` (an origin block, a form): the first, or that
  /// of the tree whose id is `tree`.
  init(in scope: Locator, tree: String? = nil) {
    row = scope.locator(
      tree.map { ".outliner-stepper-view[data-outliner-stepper-for='\($0)']" } ?? ".outliner-stepper-view"
    ).first
  }

  /// Submit Testament's tree of the new testament's nodes.
  static let submission = "submission-tree-outliner"

  /// The add stepper's button: "+ Testament 2.", aria-label "Add testament 2.".
  var addButton: Locator { row.locator(".outliner-stepper-add .outliner-stepper-button") }
  /// The remove stepper's button: "− Testament 1.", aria-label "Remove testament 1.".
  var removeButton: Locator { row.locator(".outliner-stepper-remove .outliner-stepper-button") }

  /// The tooltip round `stepper`'s ("add" or "remove") button, saying the
  /// hold that disables it; off while none does.
  func holdTooltip(_ stepper: String) -> Locator { row.locator(".outliner-stepper-\(stepper) .outliner-stepper-hold") }

  /// Steps `stepper` ("add" or "remove") to the choice its button names
  /// `label` ("Add testament 1.2."), from its first: false where none is.
  /// The page may still be settling what the tree offers (its rules read
  /// after it opens): tried again for a while before it is given up.
  @discardableResult
  func choose(_ stepper: String, _ label: String) async throws -> Bool {
    try await ready()
    for _ in 0..<30 {
      if try await attempt(stepper, label) { return true }
      try await Task.sleep(for: .milliseconds(100))
    }
    return false
  }

  private func attempt(_ stepper: String, _ label: String) async throws -> Bool {
    try await row.evaluate(
      """
      (r) => { const p = r.querySelector('.outliner-stepper-\(stepper)');
        const b = p.querySelector('.outliner-stepper-button');
        const prev = p.querySelector('.pagination-prev'), next = p.querySelector('.pagination-next');
        for (let i = 0; i < 400 && !prev.hasAttribute('disabled'); i++) prev.click();
        for (let i = 0; i < 400; i++) {
          if (b.getAttribute('aria-label') === \(Self.quoted(label))) return true;
          if (next.hasAttribute('disabled')) return false;
          next.click();
        }
        return false; }
      """
    ).bool ?? false
  }

  /// Every choice `stepper` steps through, its button's aria-label at each,
  /// first to last; the stepper left at its first.
  func choices(_ stepper: String) async throws -> [String] {
    try await ready()
    let joined = try await row.evaluate(
      """
      (r) => { const p = r.querySelector('.outliner-stepper-\(stepper)');
        const b = p.querySelector('.outliner-stepper-button');
        const prev = p.querySelector('.pagination-prev'), next = p.querySelector('.pagination-next');
        for (let i = 0; i < 400 && !prev.hasAttribute('disabled'); i++) prev.click();
        const out = [b.getAttribute('aria-label')];
        for (let i = 0; i < 400 && !next.hasAttribute('disabled'); i++) { next.click(); out.push(b.getAttribute('aria-label')); }
        for (let i = 0; i < 400 && !prev.hasAttribute('disabled'); i++) prev.click();
        return out.join('|'); }
      """
    ).string ?? ""
    return joined.isEmpty ? [] : joined.components(separatedBy: "|")
  }

  /// Waits for the page to have read the tree and bound the steppers.
  func ready() async throws {
    try await expect(row).toHaveAttribute("data-outliner-stepper-ready", "true")
  }

  /// Puts a new node where the add stepper's button reads `label` ("Add
  /// testament 1.2."), by a real press of it from the keyboard (a field
  /// left as it is focused can grow the page under a pointer's press).
  func add(_ label: String) async throws {
    guard try await choose("add", label) else {
      throw WebTestError("No place to add: \(label) (offered: \(try await choices("add")))")
    }
    try await addButton.focus()
    try await addButton.press("Enter")
  }

  /// Removes (or restores) the node the remove stepper's button names
  /// `label` ("Remove testament 1.1."), by a real press of it from the
  /// keyboard.
  func remove(_ label: String) async throws {
    guard try await choose("remove", label) else {
      throw WebTestError("No node to remove: \(label) (offered: \(try await choices("remove")))")
    }
    try await removeButton.focus()
    try await removeButton.press("Enter")
  }

  /// Removes the node `item` (an `.outliner-item`), named by its number
  /// as it now stands: "Remove testament 1.1.".
  func remove(node item: Locator, noun: String) async throws {
    let number =
      try await item.locator(":scope > .outliner-row .record-node-number").first.evaluate(
        "(e) => e.textContent.trim()"
      ).string ?? ""
    try await remove("Remove \(noun) \(number).")
  }

  private static func quoted(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") + "'"
  }
}
