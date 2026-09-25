import Foundation

/// A launched browser: the engine's process, shared by every context a test
/// run opens.
///
/// ```swift
/// let browser = try await Browser.launch(.chrome)
/// let context = try await browser.newContext()
/// let page = try await context.newPage()
/// ```
public final class Browser: Sendable {
  public let driver: any BrowserDriver

  public var engine: BrowserEngine { driver.engine }
  public var capabilities: DriverCapabilities { driver.capabilities }

  public init(driver: any BrowserDriver) {
    self.driver = driver
  }

  /// Options for launching a browser.
  public struct LaunchOptions: Sendable {
    /// Run Chrome without a window. Safari has no headless mode.
    public var headless: Bool
    /// The Chrome binary, when not the installed app.
    public var chromePath: String?

    public init(headless: Bool = true, chromePath: String? = nil) {
      self.headless = headless
      self.chromePath = chromePath
    }

    /// `WEB_TESTS_HEADED=1` shows Chrome's window; `WEB_TESTS_CHROME`
    /// points at another Chrome binary.
    public static func fromEnvironment() -> LaunchOptions {
      let environment = ProcessInfo.processInfo.environment
      return LaunchOptions(
        headless: environment["WEB_TESTS_HEADED"].map { $0.isEmpty || $0 == "0" } ?? true,
        chromePath: environment["WEB_TESTS_CHROME"])
    }
  }

  /// Launches `engine`. Throws `BrowserUnavailable` when it is not installed
  /// or not set up for automation.
  public static func launch(_ engine: BrowserEngine, options: LaunchOptions = .init()) async throws -> Browser {
    switch engine {
    case .chrome:
      return Browser(driver: try await ChromeBrowser.launch(executablePath: options.chromePath, headless: options.headless))
    case .safari:
      return Browser(driver: try await SafariBrowser.launch())
    }
  }

  /// A fresh, isolated context: its own cookies, storage and cache.
  public func newContext(baseURL: URL? = nil) async throws -> BrowserContext {
    BrowserContext(driver: try await driver.newContext(), engine: engine, capabilities: capabilities, baseURL: baseURL)
  }

  public func close() async {
    await driver.close()
  }
}

/// An isolated browser profile. Open one per test, close it after.
public final class BrowserContext: Sendable {
  public let driver: any ContextDriver
  public let engine: BrowserEngine
  public let capabilities: DriverCapabilities
  /// What relative URLs in `Page.goto` resolve against.
  public let baseURL: URL?

  init(driver: any ContextDriver, engine: BrowserEngine, capabilities: DriverCapabilities, baseURL: URL?) {
    self.driver = driver
    self.engine = engine
    self.capabilities = capabilities
    self.baseURL = baseURL
  }

  public func newPage() async throws -> Page {
    Page(driver: try await driver.newPage(), context: self)
  }

  /// Sets cookies for the pages this context loads from now on: how a test
  /// signs in without typing a password.
  public func addCookies(_ cookies: [Cookie]) async throws {
    try await driver.addCookies(cookies)
  }

  public func close() async {
    await driver.close()
  }
}
