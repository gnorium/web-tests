import Foundation

/// Google Chrome, launched from its installed app with a throwaway profile
/// and driven over the Chrome DevTools Protocol.
public final class ChromeBrowser: BrowserDriver, @unchecked Sendable {
  public let engine = BrowserEngine.chrome
  public let capabilities = DriverCapabilities(
    touchEmulation: true, earlyErrorCapture: true, responseStatuses: true, parallelContexts: true)

  let connection: CDPConnection
  private let process: Process
  private let profileDirectory: URL
  /// The browser's own user agent, restored when a context leaves a phone
  /// viewport.
  let userAgent: String
  private let closed = Locked(false)

  /// The places Chrome is installed, in the order they are tried.
  public static let defaultExecutablePaths = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "\(NSHomeDirectory())/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  ]

  /// Chrome's headless shell, newest first: Chrome for Testing's (as
  /// Puppeteer installs it), then Playwright's build of it.
  ///
  /// Headless runs prefer it to the app. Every launch of Google Chrome.app
  /// clones the app bundle into the temporary folder
  /// (`X/com.google.Chrome.code_sign_clone`) and removes the clone only when
  /// Chrome quits on its own: a run that ends in a signal leaves a full copy
  /// of Chrome behind. The shell is a bare binary and makes no clone.
  public static func headlessShellPaths() -> [String] {
    let fileManager = FileManager.default
    let home = NSHomeDirectory()
    let roots = [
      ("\(home)/.cache/puppeteer/chrome-headless-shell", ""),
      ("\(home)/Library/Caches/ms-playwright", "chromium_headless_shell-"),
    ]
    return roots.flatMap { root, prefix -> [String] in
      let versions = ((try? fileManager.contentsOfDirectory(atPath: root)) ?? [])
        .filter { prefix.isEmpty || $0.hasPrefix(prefix) }
        .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
      return versions.flatMap { version -> [String] in
        let directory = "\(root)/\(version)"
        return ((try? fileManager.contentsOfDirectory(atPath: directory)) ?? [])
          .filter { $0.hasPrefix("chrome-headless-shell-") }
          .map { "\(directory)/\($0)/chrome-headless-shell" }
      }
    }
  }

  /// Launches Chrome.
  ///
  /// - Parameters:
  ///   - executablePath: The Chrome binary; when nil, the headless shell
  ///     for a headless run if one is installed, else the installed app.
  ///   - headless: Run without a window. The app runs as `--headless=new`;
  ///     the headless shell has no window to hide.
  public static func launch(executablePath: String? = nil, headless: Bool = true) async throws -> ChromeBrowser {
    let fileManager = FileManager.default
    let candidates = [executablePath].compactMap { $0 } + (headless ? headlessShellPaths() : []) + defaultExecutablePaths
    guard let executable = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
      throw BrowserUnavailable(
        engine: .chrome, reason: "Google Chrome is not installed in /Applications (set WEB_TESTS_CHROME to its binary).")
    }

    let profile = fileManager.temporaryDirectory.appendingPathComponent("web-tests-chrome-\(UUID().uuidString)")
    try fileManager.createDirectory(at: profile, withIntermediateDirectories: true)

    var arguments = [
      "--remote-debugging-port=0",
      "--user-data-dir=\(profile.path)",
      "--no-first-run",
      "--no-default-browser-check",
      // Keep the Mac keychain out of it: no prompt, no stored secrets.
      "--use-mock-keychain",
      "--password-store=basic",
      "--disable-background-networking",
      "--disable-component-update",
      "--disable-default-apps",
      "--disable-extensions",
      "--disable-sync",
      "--disable-features=Translate,MediaRouter,OptimizationHints,AutofillServerCommunication",
      // A context's page is never "in the background": timers, animation
      // frames and hydration run as in a front tab.
      "--disable-background-timer-throttling",
      "--disable-backgrounding-occluded-windows",
      "--disable-renderer-backgrounding",
      "--mute-audio",
      "--window-size=1400,900",
    ]
    let isHeadlessShell = URL(fileURLWithPath: executable).lastPathComponent == "chrome-headless-shell"
    if headless && !isHeadlessShell { arguments.append("--headless=new") }
    arguments.append("about:blank")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      try? fileManager.removeItem(at: profile)
      throw BrowserUnavailable(engine: .chrome, reason: "Chrome would not start: \(error.localizedDescription)")
    }

    // Chrome writes the port it chose, and the browser endpoint's path, to
    // DevToolsActivePort in the profile once it listens.
    let portFile = profile.appendingPathComponent("DevToolsActivePort")
    let deadline = Deadline(.seconds(30))
    var endpoint: URL?
    while endpoint == nil {
      if let text = try? String(contentsOf: portFile, encoding: .utf8) {
        let lines = text.split(separator: "\n").map(String.init)
        if lines.count >= 2, let port = Int(lines[0]) {
          endpoint = URL(string: "ws://127.0.0.1:\(port)\(lines[1])")
        }
      }
      if endpoint != nil { break }
      if !process.isRunning || deadline.hasPassed {
        process.terminate()
        try? fileManager.removeItem(at: profile)
        throw BrowserUnavailable(engine: .chrome, reason: "Chrome started but never opened its DevTools port.")
      }
      try await Task.sleep(for: .milliseconds(50))
    }

    let connection = CDPConnection(url: endpoint!)
    let version = try await connection.send("Browser.getVersion")
    return ChromeBrowser(
      connection: connection, process: process, profileDirectory: profile,
      userAgent: version["userAgent"].string ?? "")
  }

  private init(connection: CDPConnection, process: Process, profileDirectory: URL, userAgent: String) {
    self.connection = connection
    self.process = process
    self.profileDirectory = profileDirectory
    self.userAgent = userAgent
  }

  public func newContext() async throws -> any ContextDriver {
    let result = try await connection.send("Target.createBrowserContext", ["disposeOnDetach": true])
    guard let id = result["browserContextId"].string else {
      throw WebTestError("Chrome created a browser context without an id.")
    }
    return ChromeContext(browser: self, contextID: id)
  }

  public func close() async {
    guard closed.withLock({ closed in
      defer { closed = true }
      return !closed
    }) else { return }
    _ = try? await connection.send("Browser.close", timeout: .seconds(5))
    connection.close()
    let deadline = Deadline(.seconds(5))
    while process.isRunning && !deadline.hasPassed {
      try? await Task.sleep(for: .milliseconds(50))
    }
    closeSynchronously()
  }

  /// Ends the process and removes the profile, blocking: what an exit
  /// handler can still do. Chrome is first asked to quit (`Browser.close`),
  /// as only a Chrome that quits on its own removes its app clone; a signal
  /// is the fallback.
  func closeSynchronously() {
    let unclosed = closed.withLock { closed in
      defer { closed = true }
      return !closed
    }
    if unclosed && process.isRunning {
      let asked = DispatchSemaphore(value: 0)
      Task.detached { [connection] in
        _ = try? await connection.send("Browser.close", timeout: .seconds(3))
        asked.signal()
      }
      _ = asked.wait(timeout: .now() + 4)
      connection.close()
      let deadline = Date().addingTimeInterval(5)
      while process.isRunning && Date() < deadline { usleep(20_000) }
    }
    if process.isRunning {
      process.terminate()
      let deadline = Date().addingTimeInterval(3)
      while process.isRunning && Date() < deadline { usleep(20_000) }
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
    // Only ever the directory this launch created.
    if profileDirectory.lastPathComponent.hasPrefix("web-tests-chrome-") {
      try? FileManager.default.removeItem(at: profileDirectory)
    }
  }
}

/// One `Target.createBrowserContext`: an incognito-like profile of its own.
final class ChromeContext: ContextDriver, @unchecked Sendable {
  let browser: ChromeBrowser
  let contextID: String
  private let pages = Locked<[ChromePage]>([])

  init(browser: ChromeBrowser, contextID: String) {
    self.browser = browser
    self.contextID = contextID
  }

  func newPage() async throws -> any PageDriver {
    let connection = browser.connection
    let target = try await connection.send(
      "Target.createTarget", ["url": "about:blank", "browserContextId": .string(contextID)])
    guard let targetID = target["targetId"].string else {
      throw WebTestError("Chrome opened a tab without a target id.")
    }
    let attached = try await connection.send("Target.attachToTarget", ["targetId": .string(targetID), "flatten": true])
    guard let sessionID = attached["sessionId"].string else {
      throw WebTestError("Chrome attached to a tab without a session id.")
    }
    let page = ChromePage(browser: browser, targetID: targetID, sessionID: sessionID)
    try await page.initialize()
    pages.withLock { $0.append(page) }
    return page
  }

  func addCookies(_ cookies: [Cookie]) async throws {
    let params: [JSONValue] = cookies.map { cookie in
      [
        "name": .string(cookie.name),
        "value": .string(cookie.value),
        "url": .string(cookie.url.absoluteString),
        "httpOnly": .bool(cookie.httpOnly),
        "secure": .bool(cookie.secure),
      ]
    }
    _ = try await browser.connection.send(
      "Storage.setCookies", ["cookies": .array(params), "browserContextId": .string(contextID)])
  }

  func close() async {
    for page in pages.withLock({ $0 }) { await page.close() }
    _ = try? await browser.connection.send("Target.disposeBrowserContext", ["browserContextId": .string(contextID)])
  }
}
