import Foundation

/// One browser per engine for the whole test process, launched on first use
/// and shut down when the process exits.
///
/// Launching Chrome costs about a second; a context costs milliseconds. So
/// tests share the browser and each gets its own context, as in Playwright.
public actor BrowserPool {
  public static let shared = BrowserPool()

  private var browsers: [BrowserEngine: Task<Browser, any Error>] = [:]

  /// The shared browser for `engine`, launching it the first time. A launch
  /// that failed fails the same way for every later caller rather than
  /// being retried (a missing Safari setup costs its timeout once).
  public func browser(_ engine: BrowserEngine, options: Browser.LaunchOptions = .fromEnvironment()) async throws -> Browser {
    if let existing = browsers[engine] { return try await existing.value }
    let launch = Task { try await Browser.launch(engine, options: options) }
    browsers[engine] = launch
    let browser = try await launch.value
    ExitCleanup.register(browser.driver)
    return browser
  }
}

/// Kills the browsers this process started, and removes their temporary
/// profiles, when the process exits: a test runner has no teardown hook
/// after its last test.
enum ExitCleanup {
  private static let drivers = Locked<[any BrowserDriver]>([])
  private static let installed = Locked(false)

  static func register(_ driver: any BrowserDriver) {
    drivers.withLock { $0.append(driver) }
    let install = installed.withLock { installed in
      defer { installed = true }
      return !installed
    }
    if install {
      atexit {
        ExitCleanup.run()
      }
    }
  }

  static func run() {
    for driver in drivers.withLock({ drivers in
      defer { drivers.removeAll() }
      return drivers
    }) {
      if let chrome = driver as? ChromeBrowser { chrome.closeSynchronously() }
      if let safari = driver as? SafariBrowser { safari.closeSynchronously() }
    }
  }
}
