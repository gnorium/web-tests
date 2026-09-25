import Foundation

/// A value behind a lock, for state that event callbacks write and async
/// callers read.
final class Locked<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value

  init(_ value: Value) { self.value = value }

  func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
    lock.lock()
    defer { lock.unlock() }
    return try body(&value)
  }

  var current: Value { withLock { $0 } }
}

/// A point in time a wait gives up at.
struct Deadline: Sendable {
  let instant: ContinuousClock.Instant
  let timeout: Duration

  init(_ timeout: Duration) {
    self.timeout = timeout
    self.instant = .now + timeout
  }

  var hasPassed: Bool { ContinuousClock.now >= instant }
  var remaining: Duration { max(.zero, instant - .now) }
}

extension Duration {
  /// Seconds, for messages: "5s", "0.5s".
  var secondsText: String {
    let (seconds, attoseconds) = components
    let value = Double(seconds) + Double(attoseconds) / 1e18
    return value.rounded() == value ? "\(Int(value))s" : String(format: "%.1fs", value)
  }

  var milliseconds: Double {
    let (seconds, attoseconds) = components
    return Double(seconds) * 1000 + Double(attoseconds) / 1e15
  }
}

/// The pauses between tries of a retrying wait: quick at first, for a UI that
/// settles within a frame, then every 100ms, as Playwright does.
struct Backoff {
  private var index = 0
  private static let steps: [Duration] = [.zero, .milliseconds(20), .milliseconds(50), .milliseconds(100), .milliseconds(100)]

  mutating func next() -> Duration {
    defer { index += 1 }
    return index < Self.steps.count ? Self.steps[index] : .milliseconds(100)
  }
}

/// Runs `operation`, failing with `error()` if it has not finished within
/// `timeout`. The operation is cancelled on timeout.
func withTimeout<T: Sendable>(
  _ timeout: Duration,
  error: @escaping @Sendable () -> any Error,
  operation: @escaping @Sendable () async throws -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask { try await operation() }
    group.addTask {
      try await Task.sleep(for: timeout)
      throw error()
    }
    defer { group.cancelAll() }
    return try await group.next()!
  }
}

/// A one-at-a-time lock for async code: Safari allows one automation
/// session, so contexts queue for it.
actor AsyncGate {
  private var busy = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func acquire() async {
    if !busy {
      busy = true
      return
    }
    await withCheckedContinuation { waiters.append($0) }
  }

  func release() {
    if waiters.isEmpty {
      busy = false
    } else {
      waiters.removeFirst().resume()
    }
  }
}
