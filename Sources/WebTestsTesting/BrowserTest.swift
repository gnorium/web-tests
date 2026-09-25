import Foundation
import Testing
import WebTests

/// Where tests point and which engines they run on.
public struct BrowserTestConfiguration: Sendable {
  public var baseURL: URL
  public var engines: [BrowserEngine]
  public var defaultTimeout: Duration
  /// Where a failing test's screenshot and page text go.
  public var artifactsDirectory: URL

  public init(
    baseURL: URL, engines: [BrowserEngine] = BrowserEngine.allCases, defaultTimeout: Duration = .seconds(5),
    artifactsDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("web-tests-artifacts")
  ) {
    self.baseURL = baseURL
    self.engines = engines
    self.defaultTimeout = defaultTimeout
    self.artifactsDirectory = artifactsDirectory
  }

  /// Reads `<PREFIX>_BASE_URL` and `<PREFIX>_BROWSERS` (a comma-separated
  /// list: "chrome,safari"), falling back to `defaultBaseURL` and every
  /// engine. `WEB_TESTS_ARTIFACTS` moves the artifacts directory.
  public static func fromEnvironment(prefix: String, defaultBaseURL: String) -> BrowserTestConfiguration {
    let environment = ProcessInfo.processInfo.environment
    let base = environment["\(prefix)_BASE_URL"].flatMap { $0.isEmpty ? nil : $0 } ?? defaultBaseURL
    var engines = BrowserEngine.allCases
    if let list = environment["\(prefix)_BROWSERS"], !list.isEmpty {
      engines = list.split(separator: ",").compactMap {
        BrowserEngine(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased())
      }
    }
    var configuration = BrowserTestConfiguration(baseURL: URL(string: base)!, engines: engines)
    if let artifacts = environment["WEB_TESTS_ARTIFACTS"], !artifacts.isEmpty {
      configuration.artifactsDirectory = URL(fileURLWithPath: artifacts)
    }
    return configuration
  }
}

/// Runs `body` with a fresh page in a fresh context of `engine`'s shared
/// browser, then closes the context.
///
/// - A browser that cannot run here (not installed, Safari automation not
///   enabled) cancels the test with the reason, rather than failing it.
/// - So does a check the engine cannot make (`EngineLimitation`: touch in
///   Safari).
/// - Anything else that throws fails the test at the line that threw, after
///   a screenshot, the page's text and its diagnostics are saved to the
///   artifacts directory, whose path is printed.
///
/// ```swift
/// @Test(arguments: configuration.engines)
/// func signIn(engine: BrowserEngine) async throws {
///   try await withPage(engine, configuration) { page in
///     try await page.goto("/auth/sign-in")
///     try await expect(page.getByRole(.heading, name: "Sign in")).toBeVisible()
///   }
/// }
/// ```
public func withPage(
  _ engine: BrowserEngine,
  _ configuration: BrowserTestConfiguration,
  viewport: Viewport = .desktop,
  cookies: [Cookie] = [],
  sourceLocation: SourceLocation = #_sourceLocation,
  _ body: (Page) async throws -> Void
) async throws {
  guard configuration.engines.contains(engine) else {
    try Test.cancel("\(engine) is not in the configured engines.", sourceLocation: sourceLocation)
  }

  let browser: Browser
  do {
    browser = try await BrowserPool.shared.browser(engine)
  } catch let error as BrowserUnavailable {
    try Test.cancel("\(error)", sourceLocation: sourceLocation)
  }

  let context: BrowserContext
  do {
    context = try await browser.newContext(baseURL: configuration.baseURL)
  } catch let error as BrowserUnavailable {
    try Test.cancel("\(error)", sourceLocation: sourceLocation)
  }

  var page: Page?
  do {
    if !cookies.isEmpty { try await context.addCookies(cookies) }
    let opened = try await context.newPage()
    page = opened
    opened.defaultTimeout = configuration.defaultTimeout
    try await opened.setViewport(viewport)
    try await opened.clearDiagnostics()
    try await body(opened)
    await context.close()
  } catch let limitation as EngineLimitation {
    await context.close()
    try Test.cancel("\(limitation)", sourceLocation: sourceLocation)
  } catch {
    var message = "\(error)"
    if let page {
      if let artifacts = await saveArtifacts(page: page, error: error, configuration: configuration) {
        message += "\nArtifacts: \(artifacts.path)"
        print("web-tests: artifacts for the failure are in \(artifacts.path)")
      }
    }
    await context.close()
    let location = (error as? WebTestError)?.location.map {
      SourceLocation(fileID: $0.fileID, filePath: $0.filePath, line: $0.line, column: $0.column)
    }
    Issue.record(Comment(rawValue: message), sourceLocation: location ?? sourceLocation)
  }
}

/// Saves a screenshot, the page's text and URL, and its diagnostics.
private func saveArtifacts(page: Page, error: any Error, configuration: BrowserTestConfiguration) async -> URL? {
  let testName = (Test.current?.name ?? "test")
    .replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
  let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
  let directory = configuration.artifactsDirectory
    .appendingPathComponent("\(testName)-\(page.engine.rawValue)-\(stamp)-\(UUID().uuidString.prefix(4))")
  do {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = (try? await page.url()) ?? "unknown"
    let text = (try? await page.text()) ?? ""
    let diagnostics = ((try? await page.diagnostics()) ?? []).map { "\($0)" }.joined(separator: "\n")
    let report = """
      Test: \(Test.current?.name ?? "unknown")
      Engine: \(page.engine)
      Viewport: \(page.viewport.map { "\($0)" } ?? "default")
      URL: \(url)

      Error:
      \(error)

      Diagnostics:
      \(diagnostics.isEmpty ? "none" : diagnostics)
      """
    try Data(report.utf8).write(to: directory.appendingPathComponent("failure.txt"))
    try Data(text.utf8).write(to: directory.appendingPathComponent("page.txt"))
    if let png = try? await page.screenshot() {
      try png.write(to: directory.appendingPathComponent("screenshot.png"))
    }
    return directory
  } catch {
    return nil
  }
}
