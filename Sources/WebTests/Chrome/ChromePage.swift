import Foundation

/// One tab in a Chrome context, attached in flat mode.
final class ChromePage: PageDriver, @unchecked Sendable {
  private struct State {
    var mainFrameID = ""
    var documentURL = ""
    /// The lifecycle events seen for each document load, by loader id.
    var lifecycle: [String: Set<String>] = [:]
    var currentLoaderID = ""
    var documentStatus: [String: Int] = [:]
    var requests: [String: (url: String, documentURL: String)] = [:]
    var diagnostics: [Diagnostic] = []
    var modifiers: KeyModifiers = []
    var closed = false
  }

  private let browser: ChromeBrowser
  private let targetID: String
  private let sessionID: String
  private let state = Locked(State())

  init(browser: ChromeBrowser, targetID: String, sessionID: String) {
    self.browser = browser
    self.targetID = targetID
    self.sessionID = sessionID
  }

  private func send(_ method: String, _ params: JSONValue = [:], timeout: Duration = .seconds(30)) async throws -> JSONValue {
    do {
      return try await browser.connection.send(method, params, sessionID: sessionID, timeout: timeout)
    } catch let error as CDPError {
      throw CDPError(method: method, code: error.code, message: error.message)
    }
  }

  func initialize() async throws {
    browser.connection.addListener(sessionID: sessionID) { [weak self] event in
      self?.handle(event)
    }
    _ = try await send("Page.enable")
    _ = try await send("Page.setLifecycleEventsEnabled", ["enabled": true])
    _ = try await send("Runtime.enable")
    _ = try await send("Network.enable")
    // Focus follows the page even when the window is not the key window,
    // so focus rings, :focus-visible and focus events behave as for a user.
    _ = try await send("Emulation.setFocusEmulationEnabled", ["enabled": true])
    _ = try await send("Page.bringToFront")
    let tree = try await send("Page.getFrameTree")
    let frame = tree["frameTree"]["frame"]
    state.withLock { state in
      state.mainFrameID = frame["id"].string ?? ""
      state.currentLoaderID = frame["loaderId"].string ?? ""
      state.documentURL = frame["url"].string ?? ""
    }
  }

  // MARK: - Events

  private func handle(_ event: CDPEvent) {
    let params = event.params
    switch event.method {
    case "Page.lifecycleEvent":
      guard let loaderID = params["loaderId"].string, let name = params["name"].string else { return }
      state.withLock { state in
        guard params["frameId"].string == state.mainFrameID else { return }
        if name == "init" { state.currentLoaderID = loaderID }
        state.lifecycle[loaderID, default: []].insert(name)
      }

    case "Page.frameNavigated":
      let frame = params["frame"]
      state.withLock { state in
        guard frame["parentId"].isNull, let url = frame["url"].string else { return }
        state.mainFrameID = frame["id"].string ?? state.mainFrameID
        state.documentURL = url
      }

    case "Runtime.consoleAPICalled":
      guard params["type"].string == "error" || params["type"].string == "assert" else { return }
      let text = (params["args"].array ?? []).map(Self.describe).joined(separator: " ")
      let url = params["stackTrace"]["callFrames"][0]["url"].string
      append(Diagnostic(kind: .consoleError, message: text, url: url?.isEmpty == false ? url : nil))

    case "Runtime.exceptionThrown":
      let details = params["exceptionDetails"]
      let message = details["exception"]["description"].string ?? details["text"].string ?? "Uncaught exception"
      append(Diagnostic(kind: .pageError, message: message, url: details["url"].string))

    case "Network.requestWillBeSent":
      guard let id = params["requestId"].string, let url = params["request"]["url"].string else { return }
      let documentURL = params["documentURL"].string ?? ""
      state.withLock { $0.requests[id] = (url, documentURL) }

    case "Network.responseReceived":
      guard let id = params["requestId"].string else { return }
      let response = params["response"]
      let status = response["status"].int ?? 0
      if params["type"].string == "Document", let loaderID = params["loaderId"].string {
        state.withLock { $0.documentStatus[loaderID] = status }
      }
      guard status >= 400 else { return }
      let url = response["url"].string ?? ""
      let documentURL = state.withLock { $0.requests[id]?.documentURL } ?? ""
      append(
        Diagnostic(
          kind: .httpError, message: "HTTP \(status) \(response["statusText"].string ?? "") for \(url)",
          url: url, status: status, documentURL: documentURL))

    case "Network.loadingFailed":
      // A request the page itself dropped (a navigation away, an aborted
      // fetch) is not a failure of the server's.
      if params["canceled"].bool == true { return }
      guard let id = params["requestId"].string else { return }
      let request = state.withLock { $0.requests[id] }
      let error = params["errorText"].string ?? "failed"
      let reason = params["blockedReason"].string.map { " (blocked: \($0))" } ?? ""
      append(
        Diagnostic(
          kind: .requestFailed, message: "\(error)\(reason) for \(request?.url ?? "a request")",
          url: request?.url, documentURL: request?.documentURL))

    case "Network.loadingFinished":
      guard let id = params["requestId"].string else { return }
      _ = state.withLock { $0.requests.removeValue(forKey: id) }

    default:
      break
    }
  }

  private func append(_ diagnostic: Diagnostic) {
    state.withLock { state in
      var diagnostic = diagnostic
      if diagnostic.documentURL?.isEmpty != false { diagnostic.documentURL = state.documentURL }
      state.diagnostics.append(diagnostic)
    }
  }

  private static func describe(_ remote: JSONValue) -> String {
    if let text = remote["value"].string { return text }
    if !remote["value"].isNull { return remote["value"].jsonText }
    return remote["description"].string ?? remote["type"].string ?? ""
  }

  // MARK: - Navigation

  func navigate(to url: URL, waitUntil: LoadState, timeout: Duration) async throws -> NavigationResult {
    let result = try await send("Page.navigate", ["url": .string(url.absoluteString)], timeout: timeout)
    if let error = result["errorText"].string, !error.isEmpty {
      throw WebTestError("Navigating to \(url.absoluteString) failed: \(error)")
    }
    // A same-document navigation (a #fragment) has no loader and no load.
    guard let loaderID = result["loaderId"].string else { return NavigationResult(status: nil) }
    try await waitFor(waitUntil, loaderID: loaderID, timeout: timeout, what: "navigating to \(url.absoluteString)")
    return NavigationResult(status: state.withLock { $0.documentStatus[loaderID] })
  }

  func reload(waitUntil: LoadState, timeout: Duration) async throws -> NavigationResult {
    let previous = state.withLock { $0.currentLoaderID }
    _ = try await send("Page.reload", timeout: timeout)
    let deadline = Deadline(timeout)
    var loaderID = previous
    while loaderID == previous {
      if deadline.hasPassed { throw WebTestError("Reload did not start a new document within \(timeout.secondsText).") }
      try await Task.sleep(for: .milliseconds(20))
      loaderID = state.withLock { $0.currentLoaderID }
    }
    try await waitFor(waitUntil, loaderID: loaderID, timeout: deadline.remaining, what: "reloading")
    return NavigationResult(status: state.withLock { $0.documentStatus[loaderID] })
  }

  func waitForLoadState(_ loadState: LoadState, timeout: Duration) async throws {
    let loaderID = state.withLock { $0.currentLoaderID }
    try await waitFor(loadState, loaderID: loaderID, timeout: timeout, what: "waiting for \(loadState.rawValue)")
  }

  private func waitFor(_ loadState: LoadState, loaderID: String, timeout: Duration, what: String) async throws {
    let deadline = Deadline(timeout)
    let event = loadState == .load ? "load" : "networkIdle"
    while true {
      let (seen, superseded) = state.withLock { state in
        // Superseded only once this load has begun and another began after
        // it; before its init event the current loader is still the old one.
        (state.lifecycle[loaderID]?.contains(event) ?? false, state.lifecycle[loaderID] != nil && state.currentLoaderID != loaderID)
      }
      if seen { return }
      // A redirect or a script-driven navigation replaced the document:
      // wait for the one that is loading now.
      if superseded {
        let current = state.withLock { $0.currentLoaderID }
        return try await waitFor(loadState, loaderID: current, timeout: deadline.remaining, what: what)
      }
      if deadline.hasPassed {
        throw WebTestError("Timed out after \(timeout.secondsText) \(what): no \(event) event.")
      }
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  // MARK: - Scripts

  func evaluate(_ expression: String) async throws -> JSONValue {
    let result: JSONValue
    do {
      result = try await send(
        "Runtime.evaluate",
        ["expression": .string(expression), "returnByValue": true, "awaitPromise": true, "userGesture": true])
    } catch let error as CDPError {
      let transient = ["Execution context was destroyed", "Cannot find context", "Inspected target navigated", "Promise was collected"]
      throw JavaScriptError(error.message, isTransient: transient.contains { error.message.contains($0) })
    }
    let exception = result["exceptionDetails"]
    if !exception.isNull {
      let message = exception["exception"]["description"].string ?? exception["text"].string ?? "exception"
      throw JavaScriptError(message)
    }
    return result["result"]["value"]
  }

  // MARK: - Emulation

  func setViewport(_ viewport: Viewport) async throws {
    _ = try await send(
      "Emulation.setDeviceMetricsOverride",
      [
        "width": JSONValue(viewport.width), "height": JSONValue(viewport.height),
        "deviceScaleFactor": JSONValue(viewport.deviceScaleFactor), "mobile": JSONValue(viewport.touch),
        "screenWidth": JSONValue(viewport.width), "screenHeight": JSONValue(viewport.height),
      ])
    _ = try await send("Emulation.setTouchEmulationEnabled", ["enabled": JSONValue(viewport.touch), "maxTouchPoints": 5])
    let agent = viewport.touch ? Self.phoneUserAgent : browser.userAgent
    _ = try await send(
      "Emulation.setUserAgentOverride",
      ["userAgent": .string(agent), "platform": .string(viewport.touch ? "iPhone" : "MacIntel")])
  }

  /// Safari on an iPhone, as a phone-sized page would be served to one.
  static let phoneUserAgent =
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

  // MARK: - Input

  func dispatchMouse(_ actions: [MouseAction]) async throws {
    let modifiers = state.withLock { $0.modifiers.rawValue }
    for action in actions {
      let params: JSONValue
      switch action {
      case .move(let x, let y):
        params = ["type": "mouseMoved", "x": JSONValue(x), "y": JSONValue(y), "button": "none", "modifiers": JSONValue(modifiers)]
      case .down(let x, let y, let button, let clickCount):
        params = [
          "type": "mousePressed", "x": JSONValue(x), "y": JSONValue(y), "button": .string(button.rawValue),
          "buttons": JSONValue(Self.buttons(button)), "clickCount": JSONValue(clickCount), "modifiers": JSONValue(modifiers),
        ]
      case .up(let x, let y, let button, let clickCount):
        params = [
          "type": "mouseReleased", "x": JSONValue(x), "y": JSONValue(y), "button": .string(button.rawValue),
          "buttons": 0, "clickCount": JSONValue(clickCount), "modifiers": JSONValue(modifiers),
        ]
      }
      _ = try await send("Input.dispatchMouseEvent", params)
    }
  }

  private static func buttons(_ button: MouseButton) -> Int {
    switch button {
    case .left: return 1
    case .right: return 2
    case .middle: return 4
    }
  }

  func tap(x: Double, y: Double) async throws {
    let modifiers = state.withLock { $0.modifiers.rawValue }
    _ = try await send(
      "Input.dispatchTouchEvent",
      ["type": "touchStart", "touchPoints": [["x": JSONValue(x), "y": JSONValue(y)]], "modifiers": JSONValue(modifiers)])
    _ = try await send("Input.dispatchTouchEvent", ["type": "touchEnd", "touchPoints": [], "modifiers": JSONValue(modifiers)])
  }

  func dispatchKeys(_ actions: [KeyAction]) async throws {
    for action in actions {
      switch action {
      case .down(let key):
        let modifiers = state.withLock { state -> KeyModifiers in
          if let modifier = key.modifier { state.modifiers.insert(modifier) }
          return state.modifiers
        }
        // With a modifier other than Shift held, a key types nothing
        // (Control+a selects, it does not type "a").
        let typing = modifiers.subtracting(.shift).isEmpty ? key.text : nil
        var params: [String: JSONValue] = [
          "type": .string(typing == nil ? "rawKeyDown" : "keyDown"),
          "key": .string(key.key), "code": .string(key.code),
          // No nativeVirtualKeyCode: on a Mac it is read as a macOS key code
          // (27 is Minus there, not Escape), and the mismatch leaves Chrome
          // repeating a phantom key.
          "windowsVirtualKeyCode": JSONValue(key.keyCode),
          "modifiers": JSONValue(modifiers.rawValue), "location": JSONValue(key.location),
        ]
        if let typing {
          params["text"] = .string(typing)
          params["unmodifiedText"] = .string(typing)
        }
        _ = try await send("Input.dispatchKeyEvent", .object(params))
      case .up(let key):
        let modifiers = state.withLock { state -> KeyModifiers in
          if let modifier = key.modifier { state.modifiers.remove(modifier) }
          return state.modifiers
        }
        _ = try await send(
          "Input.dispatchKeyEvent",
          [
            "type": "keyUp", "key": .string(key.key), "code": .string(key.code),
            "windowsVirtualKeyCode": JSONValue(key.keyCode),
            "modifiers": JSONValue(modifiers.rawValue), "location": JSONValue(key.location),
          ])
      }
    }
  }

  func insertText(_ text: String) async throws {
    _ = try await send("Input.insertText", ["text": .string(text)])
  }

  // MARK: - Output

  func screenshot() async throws -> Data {
    let result = try await send("Page.captureScreenshot", ["format": "png"])
    guard let base64 = result["data"].string, let data = Data(base64Encoded: base64) else {
      throw WebTestError("Chrome returned no screenshot.")
    }
    return data
  }

  func drainDiagnostics() async throws -> [Diagnostic] {
    state.withLock { state in
      defer { state.diagnostics.removeAll() }
      return state.diagnostics
    }
  }

  func close() async {
    let alreadyClosed = state.withLock { state in
      defer { state.closed = true }
      return state.closed
    }
    guard !alreadyClosed else { return }
    browser.connection.removeListeners(sessionID: sessionID)
    _ = try? await browser.connection.send("Target.closeTarget", ["targetId": .string(targetID)], timeout: .seconds(5))
  }
}
