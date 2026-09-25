import Foundation

/// A way to find elements, resolved afresh each time it is used, so it never
/// holds a stale element.
///
/// Actions wait until the element can take them. Before a click, the
/// locator must match exactly one element, and that element must be:
/// - **attached**: in the document;
/// - **visible**: a non-empty box, not `visibility: hidden`;
/// - **stable**: the same box over two animation frames (scrolled into view
///   first when off screen);
/// - **enabled**: not `disabled`, not `aria-disabled="true"`;
/// - **the one hit**: `elementFromPoint` at the click point is the element
///   or inside it, not an overlay on top.
///
/// Each check is retried until the timeout (the page's `defaultTimeout`),
/// and a timeout says which one never held.
public struct Locator: Sendable, CustomStringConvertible {
  enum Step: Sendable {
    case css(String)
    case role(String, name: String?, exact: Bool)
    case text(String, exact: Bool)
    case label(String, exact: Bool)
    case hasText(String, exact: Bool)
    case visible(Bool)
    case nth(Int)

    var json: JSONValue {
      switch self {
      case .css(let selector): return ["kind": "css", "selector": .string(selector)]
      case .role(let role, let name, let exact):
        return ["kind": "role", "role": .string(role), "name": name.map(JSONValue.string) ?? .null, "exact": .bool(exact)]
      case .text(let text, let exact): return ["kind": "text", "text": .string(text), "exact": .bool(exact)]
      case .label(let text, let exact): return ["kind": "label", "text": .string(text), "exact": .bool(exact)]
      case .hasText(let text, let exact): return ["kind": "hasText", "text": .string(text), "exact": .bool(exact)]
      case .visible(let visible): return ["kind": "visible", "visible": .bool(visible)]
      case .nth(let index): return ["kind": "nth", "index": JSONValue(index)]
      }
    }

    var description: String {
      switch self {
      case .css(let selector): return "locator(\(JSONValue.quoted(selector)))"
      case .role(let role, let name, let exact):
        var text = "getByRole(.\(role)"
        if let name { text += ", name: \(JSONValue.quoted(name))" }
        if exact { text += ", exact: true" }
        return text + ")"
      case .text(let text, let exact): return "getByText(\(JSONValue.quoted(text))\(exact ? ", exact: true" : ""))"
      case .label(let text, let exact): return "getByLabel(\(JSONValue.quoted(text))\(exact ? ", exact: true" : ""))"
      case .hasText(let text, let exact): return "filter(hasText: \(JSONValue.quoted(text))\(exact ? ", exact: true" : ""))"
      case .visible(let visible): return "filter(visible: \(visible))"
      case .nth(let index):
        switch index {
        case 0: return "first"
        case -1: return "last"
        default: return "nth(\(index))"
        }
      }
    }
  }

  public let page: Page
  let steps: [Step]

  init(page: Page, steps: [Step]) {
    self.page = page
    self.steps = steps
  }

  public var description: String {
    steps.map(\.description).joined(separator: ".")
  }

  var stepsJSON: JSONValue { .array(steps.map(\.json)) }

  private func appending(_ step: Step) -> Locator {
    Locator(page: page, steps: steps + [step])
  }

  // MARK: - Refining

  /// Elements inside this locator's matching a CSS selector.
  public func locator(_ css: String) -> Locator { appending(.css(css)) }

  public func getByRole(_ role: AriaRole, name: String? = nil, exact: Bool = false) -> Locator {
    appending(.role(role.rawValue, name: name, exact: exact))
  }

  public func getByText(_ text: String, exact: Bool = false) -> Locator { appending(.text(text, exact: exact)) }

  public func getByLabel(_ text: String, exact: Bool = false) -> Locator { appending(.label(text, exact: exact)) }

  /// The matches whose text contains `text` (or equals it, with `exact`).
  public func filter(hasText text: String, exact: Bool = false) -> Locator { appending(.hasText(text, exact: exact)) }

  /// The matches that are (or are not) visible.
  public func filter(visible: Bool) -> Locator { appending(.visible(visible)) }

  /// The match at `index`, counting from the end when negative.
  public func nth(_ index: Int) -> Locator { appending(.nth(index)) }

  public var first: Locator { nth(0) }
  public var last: Locator { nth(-1) }

  // MARK: - Actions

  struct ActionOptions {
    var enabled = true
    var editable = false
    var hitTest = true
    var json: JSONValue { ["enabled": .bool(enabled), "editable": .bool(editable), "hitTest": .bool(hitTest)] }
  }

  private func location(_ fileID: String, _ filePath: String, _ line: Int, _ column: Int) -> CodeLocation {
    CodeLocation(fileID: fileID, filePath: filePath, line: line, column: column)
  }

  /// Retries `operation` until it reports "ok" or the timeout passes.
  private func waitUntilOK(
    _ action: String, timeout: Duration?, location: CodeLocation?, operation: () async throws -> JSONValue
  ) async throws -> JSONValue {
    let timeout = timeout ?? page.defaultTimeout
    let deadline = Deadline(timeout)
    var backoff = Backoff()
    var last = "it was never checked"
    while true {
      do {
        let result = try await operation()
        if result["status"].string == "ok" { return result }
        last = Self.explain(result)
      } catch let error as JavaScriptError where error.isTransient {
        last = "the page was navigating (\(error.message))"
      }
      if deadline.hasPassed {
        throw WebTestError(
          "\(action) on \(self) timed out after \(timeout.secondsText): \(last).", location: location)
      }
      try await Task.sleep(for: backoff.next())
    }
  }

  static func explain(_ result: JSONValue) -> String {
    let detail = result["detail"].string ?? ""
    switch result["status"].string {
    case "notAttached": return "no element matches"
    case "notUnique": return "strict mode: \(detail)"
    default: return detail.isEmpty ? (result["status"].string ?? "not ready") : detail
    }
  }

  private func actionPoint(
    _ action: String, options: ActionOptions, timeout: Duration?, location: CodeLocation
  ) async throws -> (x: Double, y: Double) {
    let result = try await waitUntilOK(action, timeout: timeout, location: location) {
      try await page.evaluate(InjectedScript.call("actionPoint", stepsJSON, options.json))
    }
    return (result["x"].double ?? 0, result["y"].double ?? 0)
  }

  /// Clicks the element's centre with the mouse, once it is actionable.
  ///
  /// - Parameter force: Skip the checks that the element is enabled and not
  ///   covered (it must still be visible and stable).
  public func click(
    button: MouseButton = .left, clickCount: Int = 1, force: Bool = false, timeout: Duration? = nil,
    fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column
  ) async throws {
    let point = try await actionPoint(
      "click", options: ActionOptions(enabled: !force, hitTest: !force), timeout: timeout,
      location: location(fileID, filePath, line, column))
    try await page.mouse.click(x: point.x, y: point.y, button: button, clickCount: clickCount)
  }

  public func dblclick(
    timeout: Duration? = nil,
    fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column
  ) async throws {
    try await click(clickCount: 2, timeout: timeout, fileID: fileID, filePath: filePath, line: line, column: column)
  }

  /// Taps the element's centre with a touch, where the engine emulates touch.
  public func tap(
    timeout: Duration? = nil,
    fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column
  ) async throws {
    let point = try await actionPoint(
      "tap", options: ActionOptions(), timeout: timeout, location: location(fileID, filePath, line, column))
    try await page.driver.tap(x: point.x, y: point.y)
  }

  /// Moves the mouse over the element's centre.
  public func hover(
    timeout: Duration? = nil,
    fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column
  ) async throws {
    let point = try await actionPoint(
      "hover", options: ActionOptions(enabled: false), timeout: timeout,
      location: location(fileID, filePath, line, column))
    try await page.mouse.move(x: point.x, y: point.y)
  }

  /// Replaces the field's contents with `text`: focus, select all, then the
  /// text committed as one input, as a paste would. The field must be
  /// visible, enabled and editable.
  public func fill(
    _ text: String, timeout: Duration? = nil,
    fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column
  ) async throws {
    let here = location(fileID, filePath, line, column)
    _ = try await actionPoint("fill", options: ActionOptions(editable: true, hitTest: false), timeout: timeout, location: here)
    let selected = try await waitUntilOK("fill", timeout: timeout, location: here) {
      try await page.evaluate(InjectedScript.call("selectContents", stepsJSON))
    }
    if text.isEmpty {
      if selected["empty"].bool != true { try await page.keyboard.press("Delete") }
    } else {
      try await page.keyboard.insertText(text)
    }
  }

  /// Focuses the element and types `text` a key at a time.
  public func type(
    _ text: String, timeout: Duration? = nil,
    fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column
  ) async throws {
    try await focus(timeout: timeout, fileID: fileID, filePath: filePath, line: line, column: column)
    try await page.keyboard.type(text)
  }

  /// Focuses the element and presses a key or chord ("Enter",
  /// "Shift+PageDown").
  public func press(
    _ key: String, timeout: Duration? = nil,
    fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column
  ) async throws {
    try await focus(timeout: timeout, fileID: fileID, filePath: filePath, line: line, column: column)
    try await page.keyboard.press(key)
  }

  public func focus(
    timeout: Duration? = nil,
    fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column
  ) async throws {
    _ = try await waitUntilOK("focus", timeout: timeout, location: location(fileID, filePath, line, column)) {
      try await page.evaluate(InjectedScript.call("focus", stepsJSON))
    }
  }

  /// Clicks a checkbox or radio if it is not checked, then waits until it
  /// is.
  public func check(
    timeout: Duration? = nil,
    fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column
  ) async throws {
    try await setChecked(true, timeout: timeout, location: location(fileID, filePath, line, column))
  }

  public func uncheck(
    timeout: Duration? = nil,
    fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column
  ) async throws {
    try await setChecked(false, timeout: timeout, location: location(fileID, filePath, line, column))
  }

  private func setChecked(_ checked: Bool, timeout: Duration?, location: CodeLocation) async throws {
    if try await inspect()["checked"].bool == checked { return }
    let point = try await actionPoint(checked ? "check" : "uncheck", options: ActionOptions(), timeout: timeout, location: location)
    try await page.mouse.click(x: point.x, y: point.y)
    let deadline = Deadline(timeout ?? page.defaultTimeout)
    while try await inspect()["checked"].bool != checked {
      if deadline.hasPassed {
        throw WebTestError("\(checked ? "check" : "uncheck") on \(self): clicking did not change its state.", location: location)
      }
      try await Task.sleep(for: .milliseconds(50))
    }
  }

  // MARK: - Reading (no waiting)

  func inspect(_ options: JSONValue = [:]) async throws -> JSONValue {
    try await page.evaluate(InjectedScript.call("inspect", stepsJSON, options))
  }

  /// How many elements match now.
  public func count() async throws -> Int {
    try await inspect()["count"].int ?? 0
  }

  /// Whether exactly one element matches and it is visible, now.
  public func isVisible() async throws -> Bool {
    try await inspect()["visible"].bool ?? false
  }

  /// The text of every match, whitespace collapsed.
  public func allTextContents() async throws -> [String] {
    (try await inspect(["all": true])["texts"].array ?? []).compactMap(\.string)
  }

  /// The visible text of every match (`innerText`), whitespace collapsed.
  public func allInnerTexts() async throws -> [String] {
    (try await inspect(["all": true, "innerText": true])["texts"].array ?? []).compactMap(\.string)
  }

  /// A locator for each current match.
  public func all() async throws -> [Locator] {
    (0..<(try await count())).map { nth($0) }
  }

  /// The one match's text content, whitespace collapsed; waits for it to be
  /// attached.
  public func textContent(timeout: Duration? = nil) async throws -> String {
    try await attached(timeout: timeout)["text"].string ?? ""
  }

  public func innerText(timeout: Duration? = nil) async throws -> String {
    try await attached(timeout: timeout)["innerText"].string ?? ""
  }

  public func getAttribute(_ name: String, timeout: Duration? = nil) async throws -> String? {
    try await attached(options: ["attribute": .string(name)], timeout: timeout)["attribute"].string
  }

  public func inputValue(timeout: Duration? = nil) async throws -> String {
    try await attached(timeout: timeout)["value"].string ?? ""
  }

  /// The element's box in viewport CSS pixels, or nil when it is not
  /// visible.
  public func boundingBox(timeout: Duration? = nil) async throws -> BoundingBox? {
    let result = try await attached(timeout: timeout)
    guard result["visible"].bool == true else { return nil }
    return try result["box"].decode(as: BoundingBox.self)
  }

  /// Evaluates `function` (a JavaScript function source taking the element)
  /// on the one match: `"el => el.scrollHeight"`.
  public func evaluate(_ function: String, timeout: Duration? = nil) async throws -> JSONValue {
    _ = try await attached(timeout: timeout)
    let expression = """
      (async () => {
        const WT = (\(InjectedScript.source))();
        const [el] = WT.resolve(\(stepsJSON.jsonText));
        return await (\(function))(el);
      })()
      """
    return try await page.evaluate(expression)
  }

  /// Waits until exactly one element matches and returns what `inspect`
  /// read of it.
  private func attached(options: JSONValue = [:], timeout: Duration?) async throws -> JSONValue {
    try await waitUntilOK("read", timeout: timeout, location: nil) {
      let result = try await inspect(options)
      switch result["count"].int ?? 0 {
      case 0: return ["status": "notAttached"]
      case 1:
        var object = result.object ?? [:]
        object["status"] = "ok"
        return .object(object)
      default: return ["status": "notUnique", "detail": .string("it matches \(result["count"].int ?? 0) elements: \(result["detail"].string ?? "")")]
      }
    }
  }

  /// Waits for the element to reach `state`.
  public func waitFor(
    _ state: ElementState = .visible, timeout: Duration? = nil,
    fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column
  ) async throws {
    _ = try await waitUntilOK("waitFor(.\(state))", timeout: timeout, location: location(fileID, filePath, line, column)) {
      let result = try await inspect()
      let count = result["count"].int ?? 0
      let visible = result["visible"].bool ?? false
      let ok: Bool
      switch state {
      case .attached: ok = count >= 1
      case .detached: ok = count == 0
      case .visible: ok = count == 1 && visible
      case .hidden: ok = count == 0 || (count == 1 && !visible)
      }
      return ok ? ["status": "ok"] : ["status": "waiting", "detail": .string(Self.stateText(result))]
    }
  }

  /// What `inspect` found, in words.
  static func stateText(_ result: JSONValue) -> String {
    let count = result["count"].int ?? 0
    switch count {
    case 0: return "no element matches"
    case 1:
      let description = result["description"].string ?? "the element"
      if result["visible"].bool == true { return "\(description) is visible" }
      return "\(description) is not visible (\(result["hiddenReason"].string ?? "hidden"))"
    default: return "it matches \(count) elements: \(result["detail"].string ?? "")"
    }
  }
}

/// The states `Locator.waitFor` can wait for.
public enum ElementState: String, Sendable {
  case attached, detached, visible, hidden
}

/// A box in viewport CSS pixels.
public struct BoundingBox: Sendable, Hashable, Decodable, CustomStringConvertible {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public var minX: Double { x }
  public var maxX: Double { x + width }
  public var minY: Double { y }
  public var maxY: Double { y + height }

  public var description: String {
    "(x: \(Self.format(x)), y: \(Self.format(y)), width: \(Self.format(width)), height: \(Self.format(height)))"
  }

  private static func format(_ value: Double) -> String {
    value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
  }
}
