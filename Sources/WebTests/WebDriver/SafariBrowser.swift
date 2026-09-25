import Foundation

/// Safari, driven through the `safaridriver` that ships with macOS, over W3C
/// WebDriver (classic).
///
/// What Safari cannot do, and how this backend meets it:
/// - No headless mode: each session opens a real, automation-only Safari
///   window (striped address bar) that ignores the user's own browsing.
/// - One session at a time: contexts queue for it, so Safari tests run one
///   after another even when the suite runs in parallel.
/// - No touch or mobile emulation: a touch viewport is refused with an
///   `EngineLimitation`; `Viewport.narrow` gives the 375-wide layout with a
///   mouse. A real phone needs the iOS Simulator, a later backend.
/// - No console or network events: a capture script is injected after each
///   navigation (errors thrown while the document first loads are missed),
///   `fetch` is wrapped to see HTTP statuses, and failed subresources are
///   caught by their `error` events.
public final class SafariBrowser: BrowserDriver, @unchecked Sendable {
  public let engine = BrowserEngine.safari
  public let capabilities = DriverCapabilities(
    touchEmulation: false, earlyErrorCapture: false, responseStatuses: false, parallelContexts: false)

  let client: WebDriverClient
  private let process: Process
  /// Safari allows one automation session, so one context at a time.
  let gate = AsyncGate()
  private let closed = Locked(false)

  /// The one-time setup Safari needs before it can be automated.
  public static let setupHelp = """
    Safari's remote automation is off. Once, as an administrator: run `sudo safaridriver --enable`, \
    then in Safari open Settings → Advanced, tick "Show features for web developers", and in the \
    Develop menu tick "Allow Remote Automation". Quit Safari fully afterwards: a Safari that was \
    already running when automation was enabled times out when asked for a session.
    """

  public static let driverPath = "/usr/bin/safaridriver"

  /// Starts safaridriver on a free port.
  public static func launch() async throws -> SafariBrowser {
    guard FileManager.default.isExecutableFile(atPath: driverPath) else {
      throw BrowserUnavailable(engine: .safari, reason: "\(driverPath) is missing; Safari automation needs macOS.")
    }
    let port = try freePort()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: driverPath)
    process.arguments = ["--port", "\(port)"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    try process.run()

    let client = WebDriverClient(baseURL: URL(string: "http://127.0.0.1:\(port)")!)
    let deadline = Deadline(.seconds(10))
    while true {
      if let status = try? await client.command("GET", "status", timeout: 2), status["ready"].bool == true { break }
      if !process.isRunning || deadline.hasPassed {
        process.terminate()
        throw BrowserUnavailable(engine: .safari, reason: "safaridriver did not start. \(setupHelp)")
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    return SafariBrowser(client: client, process: process)
  }

  private init(client: WebDriverClient, process: Process) {
    self.client = client
    self.process = process
  }

  public func newContext() async throws -> any ContextDriver {
    await gate.acquire()
    do {
      let created = try await client.command(
        "POST", "session",
        ["capabilities": ["alwaysMatch": ["browserName": "safari", "pageLoadStrategy": "normal"]]],
        timeout: 90)
      guard let sessionID = created["sessionId"].string else {
        throw WebTestError("safaridriver created a session without an id.")
      }
      let context = SafariContext(browser: self, sessionID: sessionID)
      try await context.configure()
      return context
    } catch let error as WebDriverError where error.error == "session not created" {
      await gate.release()
      throw BrowserUnavailable(engine: .safari, reason: "\(error.message) \(Self.setupHelp)")
    } catch {
      await gate.release()
      throw error
    }
  }

  public func close() async {
    closeSynchronously()
  }

  func closeSynchronously() {
    guard closed.withLock({ closed in
      defer { closed = true }
      return !closed
    }) else { return }
    if process.isRunning {
      process.terminate()
      let deadline = Date().addingTimeInterval(3)
      while process.isRunning && Date() < deadline { usleep(20_000) }
    }
  }

  /// A TCP port nothing listens on: bind port 0, read what the kernel gave,
  /// close.
  private static func freePort() throws -> Int {
    let socketFD = socket(AF_INET, SOCK_STREAM, 0)
    guard socketFD >= 0 else { throw WebTestError("Could not open a socket to find a free port.") }
    defer { Darwin.close(socketFD) }
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let bound = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(socketFD, $0, length) == 0 && getsockname(socketFD, $0, &length) == 0
      }
    }
    guard bound else { throw WebTestError("Could not bind a socket to find a free port.") }
    return Int(UInt16(bigEndian: address.sin_port))
  }
}

/// A Safari context is a whole WebDriver session with its one window: a
/// fresh session is Safari's only isolated profile.
final class SafariContext: ContextDriver, @unchecked Sendable {
  let browser: SafariBrowser
  let sessionID: String
  private let page = Locked<SafariPage?>(nil)
  private let closed = Locked(false)

  init(browser: SafariBrowser, sessionID: String) {
    self.browser = browser
    self.sessionID = sessionID
  }

  func command(_ method: String, _ path: String, _ body: JSONValue? = nil, timeout: TimeInterval = 120) async throws -> JSONValue {
    let suffix = path.isEmpty ? "" : "/\(path)"
    return try await browser.client.command(method, "session/\(sessionID)\(suffix)", body, timeout: timeout)
  }

  func configure() async throws {
    _ = try await command("POST", "timeouts", ["script": 60_000, "pageLoad": 60_000, "implicit": 0])
  }

  func newPage() async throws -> any PageDriver {
    try page.withLock { page in
      if page != nil {
        throw EngineLimitation(engine: .safari, reason: "a Safari context holds one page (its session's window).")
      }
      let created = SafariPage(context: self)
      page = created
      return created
    }
  }

  func addCookies(_ cookies: [Cookie]) async throws {
    // WebDriver sets cookies only for the document showing, so visit each
    // cookie's origin first.
    for cookie in cookies {
      guard var components = URLComponents(url: cookie.url, resolvingAgainstBaseURL: false) else { continue }
      components.path = "/"
      components.query = nil
      _ = try await command("POST", "url", ["url": .string(components.url!.absoluteString)])
      _ = try await command(
        "POST", "cookie",
        [
          "cookie": [
            "name": .string(cookie.name), "value": .string(cookie.value), "path": "/",
            "httpOnly": .bool(cookie.httpOnly), "secure": .bool(cookie.secure),
          ]
        ])
    }
    _ = try? await page.withLock { $0 }?.drainDiagnostics()
  }

  func close() async {
    guard closed.withLock({ closed in
      defer { closed = true }
      return !closed
    }) else { return }
    _ = try? await command("DELETE", "", timeout: 30)
    await browser.gate.release()
  }
}
