import Foundation

/// The window of a Safari session.
final class SafariPage: PageDriver, @unchecked Sendable {
  private let context: SafariContext
  private let pending = Locked<[Diagnostic]>([])
  private let viewportSize = Locked<Viewport?>(nil)

  init(context: SafariContext) {
    self.context = context
  }

  // MARK: - Navigation

  func navigate(to url: URL, waitUntil: LoadState, timeout: Duration) async throws -> NavigationResult {
    try? await collect()
    // A page loaded in a window that is not in front gets no animation
    // frames, and whatever it defers to one (hydration, say) never runs.
    try? await ensureFrontmost()
    // Navigate To returns once the document has loaded (page load strategy
    // "normal").
    _ = try await context.command("POST", "url", ["url": .string(url.absoluteString)], timeout: timeout.milliseconds / 1000 + 5)
    return try await afterLoad(waitUntil, timeout: timeout)
  }

  func reload(waitUntil: LoadState, timeout: Duration) async throws -> NavigationResult {
    try? await collect()
    try? await ensureFrontmost()
    _ = try await context.command("POST", "refresh", timeout: timeout.milliseconds / 1000 + 5)
    return try await afterLoad(waitUntil, timeout: timeout)
  }

  func waitForLoadState(_ state: LoadState, timeout: Duration) async throws {
    let deadline = Deadline(timeout)
    while try await evaluate("document.readyState").string != "complete" {
      if deadline.hasPassed { throw WebTestError("Timed out after \(timeout.secondsText) waiting for load.") }
      try await Task.sleep(for: .milliseconds(50))
    }
    _ = try await afterLoad(state, timeout: deadline.remaining)
  }

  private func afterLoad(_ state: LoadState, timeout: Duration) async throws -> NavigationResult {
    _ = try await evaluate(Self.captureScript)
    if state == .networkIdle {
      // No network events in WebDriver: idle is the resource timeline
      // standing still for half a second.
      let deadline = Deadline(timeout)
      var count = -1
      var stableSince = ContinuousClock.now
      while true {
        let now = try await evaluate("performance.getEntriesByType('resource').length").int ?? 0
        if now != count {
          count = now
          stableSince = .now
        } else if ContinuousClock.now - stableSince >= .milliseconds(500) {
          break
        }
        if deadline.hasPassed { throw WebTestError("Timed out after \(timeout.secondsText) waiting for the network to go idle.") }
        try await Task.sleep(for: .milliseconds(100))
      }
    }
    let status = try? await evaluate(
      "(performance.getEntriesByType('navigation')[0] || {}).responseStatus ?? null"
    ).int
    return NavigationResult(status: status)
  }

  /// Hooks console.error, uncaught errors, unhandled rejections, failed
  /// subresources and fetch responses into a buffer the driver drains.
  static let captureScript = """
    (() => {
      if (window.__webTestsCapture) return true;
      const store = window.__webTestsCapture = [];
      const push = (kind, message, extra) => store.push(Object.assign({ kind, message: String(message), documentURL: location.href }, extra || {}));
      const text = (value) => {
        if (typeof value === 'string') return value;
        // Safari's stack leaves out the message: give both.
        if (value instanceof Error) return value.name + ': ' + value.message + (value.stack ? '\\n' + value.stack : '');
        try { return JSON.stringify(value); } catch (e) { return String(value); }
      };
      const consoleError = console.error;
      console.error = function (...args) { push('consoleError', args.map(text).join(' ')); return consoleError.apply(this, args); };
      addEventListener('error', (event) => {
        const target = event.target;
        if (target && target !== window && (target.src || target.href)) {
          const url = target.src || target.href;
          push('requestFailed', 'failed to load ' + url, { url });
        } else {
          push('pageError', event.error ? text(event.error) : event.message, { url: event.filename || null });
        }
      }, true);
      addEventListener('unhandledrejection', (event) => push('pageError', 'Unhandled rejection: ' + text(event.reason)));
      const fetch = window.fetch;
      if (fetch) {
        window.fetch = function (...args) {
          return fetch.apply(this, args).then((response) => {
            if (response.status >= 400) push('httpError', 'HTTP ' + response.status + ' for ' + response.url, { url: response.url, status: response.status });
            return response;
          }, (error) => {
            const url = String(args[0] && args[0].url || args[0]);
            if (!(error && error.name === 'AbortError')) push('requestFailed', text(error) + ' for ' + url, { url: new URL(url, location.href).href });
            throw error;
          });
        };
      }
      const status = (performance.getEntriesByType('navigation')[0] || {}).responseStatus;
      if (status >= 400) push('httpError', 'HTTP ' + status + ' for ' + location.href, { url: location.href, status });
      return true;
    })()
    """

  // MARK: - Scripts

  func evaluate(_ expression: String) async throws -> JSONValue {
    let script = """
      const done = arguments[arguments.length - 1];
      Promise.resolve().then(() => (\(expression)))
        .then((value) => done({ __webTestsValue: value === undefined ? null : value }),
              (error) => done({ __webTestsError: String(error && error.stack || error) }));
      """
    let result: JSONValue
    do {
      result = try await context.command("POST", "execute/async", ["script": .string(script), "args": []])
    } catch let error as WebDriverError {
      let transient = ["javascript error", "no such window", "script timeout", "unknown error"].contains(error.error)
      throw JavaScriptError(error.message, isTransient: transient)
    }
    if let message = result["__webTestsError"].string {
      throw JavaScriptError(message)
    }
    return result["__webTestsValue"]
  }

  // MARK: - Emulation

  func setViewport(_ viewport: Viewport) async throws {
    if viewport.touch {
      throw EngineLimitation(
        engine: .safari,
        reason: "no touch emulation over WebDriver; use Viewport.narrow for the 375-wide layout, or the iOS Simulator for a real phone.")
    }
    // The window's outer size includes the toolbar: size it, measure the
    // difference, and size it again.
    var width = viewport.width
    var height = viewport.height
    for _ in 0..<3 {
      _ = try await context.command("POST", "window/rect", ["width": JSONValue(width), "height": JSONValue(height)])
      let inner = try await evaluate("[innerWidth, innerHeight]")
      let innerWidth = inner[0].int ?? 0
      let innerHeight = inner[1].int ?? 0
      if innerWidth == viewport.width && innerHeight == viewport.height { break }
      width += viewport.width - innerWidth
      height += viewport.height - innerHeight
    }
    let inner = try await evaluate("[innerWidth, innerHeight]")
    if inner[0].int != viewport.width {
      throw EngineLimitation(
        engine: .safari,
        reason: "Safari's window could not be made \(viewport.width) CSS pixels wide (it is \(inner[0].int ?? 0)).")
    }
    viewportSize.withLock { $0 = viewport }
  }

  // MARK: - Input

  /// Safari delivers simulated pointer events only to its key window: with
  /// another app in front, a click is silently dropped (keys still arrive).
  /// So bring Safari forward first when its page has lost focus.
  private func ensureFrontmost() async throws {
    if try await hasFocus() { return }
    // macOS may turn an activation down while the user is busy in another
    // app, so ask again each second.
    let deadline = Deadline(.seconds(6))
    while !deadline.hasPassed {
      let open = Process()
      open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      open.arguments = ["-b", "com.apple.Safari"]
      open.standardOutput = FileHandle.nullDevice
      open.standardError = FileHandle.nullDevice
      try open.run()
      open.waitUntilExit()
      for _ in 0..<20 {
        if try await hasFocus() { return }
        try await Task.sleep(for: .milliseconds(50))
      }
    }
    throw WebTestError(
      "Safari's automation window is not in front and could not be brought there; Safari drops pointer input to a window that is not the key window. Leave the Mac to the test while Safari runs.")
  }

  private func hasFocus() async throws -> Bool {
    try await evaluate("document.hasFocus()").bool == true
  }

  func dispatchMouse(_ actions: [MouseAction]) async throws {
    try await ensureFrontmost()
    try await performMouse(actions)
    // Focus lost while the actions ran means they were most likely dropped:
    // bring Safari back and send them once more.
    if try await !hasFocus() {
      try await ensureFrontmost()
      try await performMouse(actions)
    }
  }

  private func performMouse(_ actions: [MouseAction]) async throws {
    var steps: [JSONValue] = []
    for action in actions {
      switch action {
      case .move(let x, let y):
        steps.append(Self.pointerMove(x, y))
      case .down(let x, let y, let button, _):
        steps.append(Self.pointerMove(x, y))
        steps.append(["type": "pointerDown", "button": JSONValue(Self.buttonIndex(button))])
      case .up(let x, let y, let button, _):
        steps.append(Self.pointerMove(x, y))
        steps.append(["type": "pointerUp", "button": JSONValue(Self.buttonIndex(button))])
      }
    }
    _ = try await context.command(
      "POST", "actions",
      ["actions": [["type": "pointer", "id": "mouse", "parameters": ["pointerType": "mouse"], "actions": .array(steps)]]])
  }

  private static func pointerMove(_ x: Double, _ y: Double) -> JSONValue {
    ["type": "pointerMove", "x": JSONValue(Int(x.rounded())), "y": JSONValue(Int(y.rounded())), "origin": "viewport", "duration": 0]
  }

  private static func buttonIndex(_ button: MouseButton) -> Int {
    switch button {
    case .left: return 0
    case .middle: return 1
    case .right: return 2
    }
  }

  func tap(x: Double, y: Double) async throws {
    throw EngineLimitation(engine: .safari, reason: "no touch input over WebDriver on macOS.")
  }

  func dispatchKeys(_ actions: [KeyAction]) async throws {
    let steps: [JSONValue] = actions.map { action in
      switch action {
      case .down(let key): return ["type": "keyDown", "value": .string(key.webDriverValue)]
      case .up(let key): return ["type": "keyUp", "value": .string(key.webDriverValue)]
      }
    }
    _ = try await context.command("POST", "actions", ["actions": [["type": "key", "id": "keyboard", "actions": .array(steps)]]])
  }

  func insertText(_ text: String) async throws {
    // WebDriver has no input-method commit; type the characters.
    var actions: [KeyAction] = []
    for character in text {
      let key = KeyDefinition(key: String(character), code: "", keyCode: 0, text: String(character), webDriverValue: String(character))
      actions.append(.down(key))
      actions.append(.up(key))
    }
    try await dispatchKeys(actions)
  }

  // MARK: - Output

  func screenshot() async throws -> Data {
    guard let base64 = try await context.command("GET", "screenshot").string, let data = Data(base64Encoded: base64) else {
      throw WebTestError("Safari returned no screenshot.")
    }
    return data
  }

  /// Moves what the page's capture script has buffered into `pending`, and
  /// installs the script if this document has none yet (after a click
  /// navigated, say).
  private func collect() async throws {
    let entries = try await evaluate(
      """
      (() => {
        const store = window.__webTestsCapture;
        if (!store) { \(Self.captureScript); return []; }
        return store.splice(0);
      })()
      """)
    let diagnostics: [Diagnostic] = (entries.array ?? []).compactMap { entry in
      guard let kind = entry["kind"].string.flatMap(Diagnostic.Kind.init(rawValue:)) else { return nil }
      return Diagnostic(
        kind: kind, message: entry["message"].string ?? "", url: entry["url"].string, status: entry["status"].int,
        documentURL: entry["documentURL"].string)
    }
    pending.withLock { $0.append(contentsOf: diagnostics) }
  }

  func drainDiagnostics() async throws -> [Diagnostic] {
    try? await collect()
    return pending.withLock { pending in
      defer { pending.removeAll() }
      return pending
    }
  }

  func close() async {}
}
