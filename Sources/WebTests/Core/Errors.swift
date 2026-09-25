import Foundation

/// Where in a test a failing call was written, so a test framework can point
/// its failure at that line rather than at the test as a whole.
public struct CodeLocation: Sendable, Hashable, CustomStringConvertible {
  public var fileID: String
  public var filePath: String
  public var line: Int
  public var column: Int

  public init(fileID: String, filePath: String, line: Int, column: Int) {
    self.fileID = fileID
    self.filePath = filePath
    self.line = line
    self.column = column
  }

  public var description: String { "\(fileID):\(line):\(column)" }
}

/// A failed action, wait or assertion, worded for the person reading the
/// test log: what was asked, of which locator, and which condition never
/// held.
public struct WebTestError: Error, Sendable, CustomStringConvertible, LocalizedError {
  public var message: String
  public var location: CodeLocation?

  public init(_ message: String, location: CodeLocation? = nil) {
    self.message = message
    self.location = location
  }

  public var description: String { message }
  public var errorDescription: String? { message }
}

/// The browser cannot run here at all: not installed, or not set up for
/// automation. A test framework should skip rather than fail.
public struct BrowserUnavailable: Error, Sendable, CustomStringConvertible, LocalizedError {
  public var engine: BrowserEngine
  public var reason: String

  public init(engine: BrowserEngine, reason: String) {
    self.engine = engine
    self.reason = reason
  }

  public var description: String { "\(engine) is unavailable: \(reason)" }
  public var errorDescription: String? { description }
}

/// The engine cannot do what the test asked (touch emulation in Safari, say).
/// A test framework should skip the test on that engine rather than fail it.
public struct EngineLimitation: Error, Sendable, CustomStringConvertible, LocalizedError {
  public var engine: BrowserEngine
  public var reason: String

  public init(engine: BrowserEngine, reason: String) {
    self.engine = engine
    self.reason = reason
  }

  public var description: String { "\(engine) cannot run this: \(reason)" }
  public var errorDescription: String? { description }
}

/// A script threw in the page.
public struct JavaScriptError: Error, Sendable, CustomStringConvertible, LocalizedError {
  public var message: String
  /// The page was mid-navigation and the script's document went away; a
  /// retrying wait tries again rather than failing.
  public var isTransient: Bool

  public init(_ message: String, isTransient: Bool = false) {
    self.message = message
    self.isTransient = isTransient
  }

  public var description: String { "JavaScript error: \(message)" }
  public var errorDescription: String? { description }
}
