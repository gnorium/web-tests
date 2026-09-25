import Foundation

/// An event from the browser: a method name, its parameters, and the session
/// (tab) it came from, or none for the browser itself.
struct CDPEvent: Sendable {
  let method: String
  let params: JSONValue
  let sessionID: String?
}

/// An error the browser returned for a command.
struct CDPError: Error, CustomStringConvertible {
  let method: String
  let code: Int
  let message: String
  var description: String { "\(method) failed: \(message) (\(code))" }
}

/// One WebSocket to the browser, in CDP's flat mode: every tab's commands and
/// events share it, told apart by session id.
///
/// URLSessionWebSocketTask rather than swift-nio: the protocol needs nothing
/// but text frames in order, and Foundation already has that on every Apple
/// platform, so the package stays free of dependencies.
final class CDPConnection: @unchecked Sendable {
  typealias Listener = @Sendable (CDPEvent) -> Void

  private struct State {
    var nextID = 1
    var pending: [Int: CheckedContinuation<JSONValue, any Error>] = [:]
    var methods: [Int: String] = [:]
    var listeners: [String: [UUID: Listener]] = [:]
    var closed: (any Error)?
  }

  private let session: URLSession
  private let task: URLSessionWebSocketTask
  private let state = Locked(State())
  /// The key listeners are filed under for the browser's own events.
  private static let browserKey = ""

  init(url: URL) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 3600
    session = URLSession(configuration: configuration)
    task = session.webSocketTask(with: url)
    // Screenshots arrive as one base64 frame, well past the 1 MB default.
    task.maximumMessageSize = 256 * 1024 * 1024
    task.resume()
    receive()
  }

  /// Sends a command and waits for its result.
  func send(
    _ method: String, _ params: JSONValue = [:], sessionID: String? = nil, timeout: Duration = .seconds(30)
  ) async throws -> JSONValue {
    let id: Int = try state.withLock { state in
      if let error = state.closed { throw error }
      defer { state.nextID += 1 }
      return state.nextID
    }
    var message: [String: JSONValue] = ["id": JSONValue(id), "method": .string(method), "params": params]
    if let sessionID { message["sessionId"] = .string(sessionID) }
    let text = JSONValue.object(message).jsonText

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let closed: (any Error)? = state.withLock { state in
          if let error = state.closed { return error }
          state.pending[id] = continuation
          state.methods[id] = method
          return nil
        }
        if let closed {
          continuation.resume(throwing: closed)
          return
        }
        task.send(.string(text)) { [weak self] error in
          if let error { self?.complete(id, with: .failure(error)) }
        }
        Task { [weak self] in
          try? await Task.sleep(for: timeout)
          self?.complete(id, with: .failure(WebTestError("Chrome did not answer \(method) within \(timeout.secondsText).")))
        }
      }
    } onCancel: {
      complete(id, with: .failure(CancellationError()))
    }
  }

  /// Calls `listener` for every event from `sessionID` (nil: the browser)
  /// until the returned token is passed to `removeListener`.
  @discardableResult
  func addListener(sessionID: String?, _ listener: @escaping Listener) -> UUID {
    let token = UUID()
    state.withLock { $0.listeners[sessionID ?? Self.browserKey, default: [:]][token] = listener }
    return token
  }

  func removeListeners(sessionID: String?) {
    _ = state.withLock { $0.listeners.removeValue(forKey: sessionID ?? Self.browserKey) }
  }

  func close() {
    fail(WebTestError("The connection to Chrome is closed."))
    task.cancel(with: .normalClosure, reason: nil)
    session.invalidateAndCancel()
  }

  // MARK: - Receiving

  private func receive() {
    task.receive { [weak self] result in
      guard let self else { return }
      switch result {
      case .success(let message):
        self.handle(message)
        self.receive()
      case .failure(let error):
        self.fail(WebTestError("The connection to Chrome dropped: \(error.localizedDescription)"))
      }
    }
  }

  private func handle(_ message: URLSessionWebSocketTask.Message) {
    let data: Data
    switch message {
    case .string(let text): data = Data(text.utf8)
    case .data(let bytes): data = bytes
    @unknown default: return
    }
    guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return }

    if let id = value["id"].int {
      let error = value["error"]
      if error.isNull {
        complete(id, with: .success(value["result"]))
      } else {
        complete(
          id,
          with: .failure(
            CDPError(method: methodName(id), code: error["code"].int ?? 0, message: error["message"].string ?? "unknown error")))
      }
      return
    }

    guard let method = value["method"].string else { return }
    let sessionID = value["sessionId"].string
    let event = CDPEvent(method: method, params: value["params"], sessionID: sessionID)
    let listeners = state.withLock { Array(($0.listeners[sessionID ?? Self.browserKey] ?? [:]).values) }
    for listener in listeners { listener(event) }
  }

  private func methodName(_ id: Int) -> String {
    state.withLock { $0.methods[id] } ?? "command \(id)"
  }

  private func complete(_ id: Int, with result: Result<JSONValue, any Error>) {
    guard
      let continuation = state.withLock({ state -> CheckedContinuation<JSONValue, any Error>? in
        state.methods.removeValue(forKey: id)
        return state.pending.removeValue(forKey: id)
      })
    else { return }
    continuation.resume(with: result)
  }

  private func fail(_ error: any Error) {
    let pending = state.withLock { state -> [CheckedContinuation<JSONValue, any Error>] in
      if state.closed == nil { state.closed = error }
      defer {
        state.pending.removeAll()
        state.methods.removeAll()
      }
      return Array(state.pending.values)
    }
    for continuation in pending { continuation.resume(throwing: error) }
  }
}
