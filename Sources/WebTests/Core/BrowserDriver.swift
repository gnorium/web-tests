import Foundation

// The three driver protocols are the only place a browser engine shows
// through. Everything a test sees (Page, Locator, expect) is written against
// them: a locator's auto-wait is a script and some pointer events, whichever
// wire carries them. A new backend (WebDriver BiDi, the iOS Simulator)
// implements these three and nothing else.

/// A browser engine web-tests can drive.
public enum BrowserEngine: String, Sendable, Hashable, CaseIterable, CustomStringConvertible {
  /// Google Chrome, over the Chrome DevTools Protocol.
  case chrome
  /// Safari, over W3C WebDriver (classic) through /usr/bin/safaridriver.
  case safari

  public var description: String {
    switch self {
    case .chrome: return "Chrome"
    case .safari: return "Safari"
    }
  }
}

/// What an engine's driver can and cannot do, so a test can skip a check the
/// engine has no way to make rather than fail it.
public struct DriverCapabilities: Sendable, Hashable {
  /// Touch events and a mobile user agent (`Viewport.touch`).
  public var touchEmulation: Bool
  /// Console errors and exceptions thrown before the page's first script
  /// runs are seen, not only those after the driver could hook in.
  public var earlyErrorCapture: Bool
  /// The HTTP status of every request the page makes, not only fetches.
  public var responseStatuses: Bool
  /// Several contexts may be open at once. Safari allows one session.
  public var parallelContexts: Bool

  public init(touchEmulation: Bool, earlyErrorCapture: Bool, responseStatuses: Bool, parallelContexts: Bool) {
    self.touchEmulation = touchEmulation
    self.earlyErrorCapture = earlyErrorCapture
    self.responseStatuses = responseStatuses
    self.parallelContexts = parallelContexts
  }
}

/// A running browser. Contexts come from it; it outlives them.
public protocol BrowserDriver: AnyObject, Sendable {
  var engine: BrowserEngine { get }
  var capabilities: DriverCapabilities { get }
  /// A fresh, isolated profile: no cookies, storage or cache shared with any
  /// other context.
  func newContext() async throws -> any ContextDriver
  func close() async
}

/// One isolated profile in a browser.
public protocol ContextDriver: AnyObject, Sendable {
  func newPage() async throws -> any PageDriver
  func addCookies(_ cookies: [Cookie]) async throws
  func close() async
}

/// One tab. Every call is the raw engine operation; waiting and retrying live
/// above, in `Page` and `Locator`.
public protocol PageDriver: AnyObject, Sendable {
  /// Loads `url` and returns once `waitUntil` holds for the new document.
  func navigate(to url: URL, waitUntil: LoadState, timeout: Duration) async throws -> NavigationResult
  func reload(waitUntil: LoadState, timeout: Duration) async throws -> NavigationResult
  /// Waits for `state` on the document now loading or loaded.
  func waitForLoadState(_ state: LoadState, timeout: Duration) async throws
  /// Evaluates a JavaScript expression in the page and returns its value as
  /// JSON, awaiting it when it is a promise.
  func evaluate(_ expression: String) async throws -> JSONValue
  func setViewport(_ viewport: Viewport) async throws
  /// Pointer events at viewport coordinates, in CSS pixels.
  func dispatchMouse(_ actions: [MouseAction]) async throws
  /// A tap: touch start and end at one point.
  func tap(x: Double, y: Double) async throws
  func dispatchKeys(_ actions: [KeyAction]) async throws
  /// Text as an input method would commit it: one input event, no keys.
  func insertText(_ text: String) async throws
  /// A PNG of the viewport.
  func screenshot() async throws -> Data
  /// The console errors, exceptions and failed requests seen since the last
  /// call.
  func drainDiagnostics() async throws -> [Diagnostic]
  func close() async
}

/// When a navigation counts as finished.
public enum LoadState: String, Sendable, Hashable {
  /// The `load` event: the document and its subresources.
  case load
  /// `load`, then no network request for half a second.
  case networkIdle
}

/// What a navigation led to.
public struct NavigationResult: Sendable, Hashable {
  /// The main document's HTTP status, when the engine reports it.
  public var status: Int?
  public init(status: Int?) { self.status = status }
}

/// A pointer event, in viewport CSS pixels.
public enum MouseAction: Sendable, Hashable {
  case move(x: Double, y: Double)
  case down(x: Double, y: Double, button: MouseButton, clickCount: Int)
  case up(x: Double, y: Double, button: MouseButton, clickCount: Int)
}

public enum MouseButton: String, Sendable, Hashable {
  case left, middle, right
}

/// A key going down or up.
public enum KeyAction: Sendable, Hashable {
  case down(KeyDefinition)
  case up(KeyDefinition)
}

/// A viewport: its size, pixel density, and whether it emulates a touch
/// phone.
public struct Viewport: Sendable, Hashable, CustomStringConvertible {
  public var width: Int
  public var height: Int
  public var deviceScaleFactor: Double
  /// Touch events, `pointer: coarse`, a mobile user agent and the meta
  /// viewport honoured, as on a phone.
  public var touch: Bool

  public init(width: Int, height: Int, deviceScaleFactor: Double = 1, touch: Bool = false) {
    self.width = width
    self.height = height
    self.deviceScaleFactor = deviceScaleFactor
    self.touch = touch
  }

  /// A 1400×900 desktop window.
  public static let desktop = Viewport(width: 1400, height: 900)
  /// A 375×812 touch phone (the iPhone's CSS width), at 3× density.
  public static let phone = Viewport(width: 375, height: 812, deviceScaleFactor: 3, touch: true)
  /// A 375×812 window with a mouse: the narrow layout where touch cannot be
  /// emulated.
  public static let narrow = Viewport(width: 375, height: 812)

  public var description: String {
    "\(width)×\(height)\(touch ? " touch" : "")"
  }
}

/// A cookie to set in a context before its pages load.
public struct Cookie: Sendable, Hashable {
  public var name: String
  public var value: String
  /// The URL the cookie is for; its host and path scope it.
  public var url: URL
  public var httpOnly: Bool
  public var secure: Bool

  public init(name: String, value: String, url: URL, httpOnly: Bool = true, secure: Bool = false) {
    self.name = name
    self.value = value
    self.url = url
    self.httpOnly = httpOnly
    self.secure = secure
  }
}

/// Something that went wrong in the page: an error logged, an exception
/// thrown, a request that failed.
public struct Diagnostic: Sendable, Hashable, CustomStringConvertible {
  public enum Kind: String, Sendable, Hashable {
    /// `console.error` (or a console assertion that failed).
    case consoleError
    /// An exception nobody caught, or a promise rejection nobody handled.
    case pageError
    /// A request that never got a response: refused, blocked, DNS.
    case requestFailed
    /// A response with a status of 400 or more.
    case httpError
  }

  public var kind: Kind
  public var message: String
  /// The request's URL, or the script's for an error.
  public var url: String?
  public var status: Int?
  /// The page's own URL when it happened, to tell same-origin requests from
  /// third-party ones.
  public var documentURL: String?

  public init(kind: Kind, message: String, url: String? = nil, status: Int? = nil, documentURL: String? = nil) {
    self.kind = kind
    self.message = message
    self.url = url
    self.status = status
    self.documentURL = documentURL
  }

  public var description: String {
    var text = "[\(kind.rawValue)] \(message)"
    if let url, !message.contains(url) { text += " (\(url))" }
    return text
  }

  /// Whether the request went to the page's own origin. Errors that are not
  /// requests count as same-origin.
  public var isSameOrigin: Bool {
    guard kind == .requestFailed || kind == .httpError else { return true }
    guard let url, let documentURL,
      let request = URLComponents(string: url), let page = URLComponents(string: documentURL)
    else { return true }
    return request.scheme == page.scheme && request.host == page.host && request.port == page.port
  }
}
