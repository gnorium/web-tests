import Foundation

/// A tab: where a test navigates, finds elements and reads what went wrong.
///
/// ```swift
/// try await page.goto("/auth/sign-in")
/// try await page.getByRole(.button, name: "Sign in").click()
/// try await expect(page).toHaveURL("/")
/// ```
public final class Page: @unchecked Sendable {
  public let driver: any PageDriver
  public let context: BrowserContext
  public let keyboard: Keyboard
  public let mouse: Mouse

  private struct State {
    var defaultTimeout: Duration = .seconds(5)
    var navigationTimeout: Duration = .seconds(30)
    var viewport: Viewport?
    var diagnostics: [Diagnostic] = []
  }
  private let state = Locked(State())

  init(driver: any PageDriver, context: BrowserContext) {
    self.driver = driver
    self.context = context
    self.keyboard = Keyboard(driver: driver)
    self.mouse = Mouse(driver: driver)
  }

  public var engine: BrowserEngine { context.engine }
  public var capabilities: DriverCapabilities { context.capabilities }

  /// How long actions and assertions wait before failing. 5 seconds.
  public var defaultTimeout: Duration {
    get { state.withLock { $0.defaultTimeout } }
    set { state.withLock { $0.defaultTimeout = newValue } }
  }

  /// How long a navigation may take. 30 seconds.
  public var navigationTimeout: Duration {
    get { state.withLock { $0.navigationTimeout } }
    set { state.withLock { $0.navigationTimeout = newValue } }
  }

  /// The viewport last set, if any.
  public var viewport: Viewport? { state.withLock { $0.viewport } }

  // MARK: - Navigation

  /// `path` resolved against the context's base URL; absolute URLs pass
  /// through.
  public func resolve(_ path: String) throws -> URL {
    if let url = URL(string: path), url.scheme != nil { return url }
    guard let base = context.baseURL, let url = URL(string: path, relativeTo: base)?.absoluteURL else {
      throw WebTestError("\"\(path)\" is relative and the context has no base URL.")
    }
    return url
  }

  /// Loads `path` (relative to the base URL, or absolute) and waits for
  /// `waitUntil`.
  @discardableResult
  public func goto(_ path: String, waitUntil: LoadState = .load) async throws -> NavigationResult {
    try await collectDiagnostics()
    return try await driver.navigate(to: try resolve(path), waitUntil: waitUntil, timeout: navigationTimeout)
  }

  /// Shows `html` as the page, from a data URL.
  public func setContent(_ html: String, waitUntil: LoadState = .load) async throws {
    let url = URL(string: "data:text/html;charset=utf-8;base64," + Data(html.utf8).base64EncodedString())!
    _ = try await driver.navigate(to: url, waitUntil: waitUntil, timeout: navigationTimeout)
  }

  @discardableResult
  public func reload(waitUntil: LoadState = .load) async throws -> NavigationResult {
    try await collectDiagnostics()
    return try await driver.reload(waitUntil: waitUntil, timeout: navigationTimeout)
  }

  /// Waits for the current document to reach `state`: after a click that
  /// navigates, say.
  public func waitForLoadState(_ state: LoadState = .load) async throws {
    try await driver.waitForLoadState(state, timeout: navigationTimeout)
  }

  /// The document's URL.
  public func url() async throws -> String {
    try await evaluate("location.href").string ?? ""
  }

  public func title() async throws -> String {
    try await evaluate("document.title").string ?? ""
  }

  /// The page's visible text.
  public func text() async throws -> String {
    try await evaluate("document.body ? document.body.innerText : ''").string ?? ""
  }

  // MARK: - Scripts

  /// Evaluates a JavaScript expression and returns its JSON value, awaiting
  /// it when it is a promise. Wrap statements in an arrow function:
  /// `(() => { …; return x })()`.
  @discardableResult
  public func evaluate(_ expression: String) async throws -> JSONValue {
    try await driver.evaluate(expression)
  }

  /// Evaluates a JavaScript expression and decodes its value.
  public func evaluate<T: Decodable>(_ expression: String, as type: T.Type) async throws -> T {
    try await driver.evaluate(expression).decode(as: T.self)
  }

  // MARK: - Emulation

  /// Sizes the viewport. `Viewport.phone` also emulates touch and a mobile
  /// user agent where the engine can (see `capabilities.touchEmulation`).
  public func setViewport(_ viewport: Viewport) async throws {
    try await driver.setViewport(viewport)
    state.withLock { $0.viewport = viewport }
  }

  public func setViewport(width: Int, height: Int, touch: Bool = false, deviceScaleFactor: Double = 1) async throws {
    try await setViewport(Viewport(width: width, height: height, deviceScaleFactor: deviceScaleFactor, touch: touch))
  }

  /// Sets a cookie for this page's context.
  public func setCookie(name: String, value: String, url: URL? = nil, httpOnly: Bool = true) async throws {
    guard let target = url ?? context.baseURL else {
      throw WebTestError("setCookie needs a URL when the context has no base URL.")
    }
    try await context.addCookies([Cookie(name: name, value: value, url: target, httpOnly: httpOnly)])
  }

  // MARK: - Locators

  /// Elements matching a CSS selector.
  public func locator(_ css: String) -> Locator {
    Locator(page: self, steps: [.css(css)])
  }

  /// Elements with an ARIA role (explicit or implied by the tag) and, when
  /// given, an accessible name containing `name` (case-insensitive), or
  /// equal to it with `exact`. Hidden elements are left out.
  public func getByRole(_ role: AriaRole, name: String? = nil, exact: Bool = false) -> Locator {
    Locator(page: self, steps: [.role(role.rawValue, name: name, exact: exact)])
  }

  /// The smallest elements whose text contains `text` (case-insensitive,
  /// whitespace collapsed), or equals it with `exact`.
  public func getByText(_ text: String, exact: Bool = false) -> Locator {
    Locator(page: self, steps: [.text(text, exact: exact)])
  }

  /// Form controls labelled `text`: by a `<label>`, `aria-labelledby` or
  /// `aria-label`.
  public func getByLabel(_ text: String, exact: Bool = false) -> Locator {
    Locator(page: self, steps: [.label(text, exact: exact)])
  }

  // MARK: - Output

  /// Writes a PNG of the viewport to `url`.
  public func screenshot(to url: URL) async throws {
    let data = try await driver.screenshot()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
  }

  public func screenshot() async throws -> Data {
    try await driver.screenshot()
  }

  // MARK: - Diagnostics

  private func collectDiagnostics() async throws {
    let drained = (try? await driver.drainDiagnostics()) ?? []
    state.withLock { $0.diagnostics.append(contentsOf: drained) }
  }

  /// Every console error, uncaught exception and failed request since the
  /// page opened.
  public func diagnostics() async throws -> [Diagnostic] {
    try await collectDiagnostics()
    return state.withLock { $0.diagnostics }
  }

  /// Forgets the diagnostics collected so far.
  public func clearDiagnostics() async throws {
    try await collectDiagnostics()
    state.withLock { $0.diagnostics.removeAll() }
  }

  /// Fails if the page logged an error, threw, or had a same-origin request
  /// fail or answer 400 or more. Requests to other origins count only when
  /// `sameOriginOnly` is false. A diagnostic whose text contains any of
  /// `ignoring` is let through.
  public func expectNoErrors(
    sameOriginOnly: Bool = true,
    ignoring: [String] = [],
    fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column
  ) async throws {
    let problems = try await diagnostics().filter { diagnostic in
      if sameOriginOnly && !diagnostic.isSameOrigin { return false }
      return !ignoring.contains { diagnostic.message.contains($0) || (diagnostic.url?.contains($0) ?? false) }
    }
    guard !problems.isEmpty else { return }
    let where_ = (try? await url()) ?? "the page"
    throw WebTestError(
      "\(problems.count) error\(problems.count == 1 ? "" : "s") on \(where_) (\(engine)\(viewport.map { ", \($0)" } ?? "")):\n"
        + problems.map { "  • \($0)" }.joined(separator: "\n"),
      location: CodeLocation(fileID: fileID, filePath: filePath, line: line, column: column))
  }

  /// How the page overflows its viewport sideways, or nil when it does not.
  public struct HorizontalOverflow: Sendable, Decodable, CustomStringConvertible {
    public var scrollWidth: Double
    public var width: Double
    /// The deepest elements reaching past the viewport's right edge.
    public var offenders: [String]

    public var description: String {
      "the document is \(Int(scrollWidth))px wide in a \(Int(width))px viewport; sticking out:\n"
        + offenders.map { "  • \($0)" }.joined(separator: "\n")
    }
  }

  /// Whether the document is wider than the viewport
  /// (`documentElement.scrollWidth` against the width set, or
  /// `innerWidth`).
  public func horizontalOverflow() async throws -> HorizontalOverflow? {
    let value = try await evaluate(InjectedScript.call("overflow", viewport.map { JSONValue($0.width) } ?? .null))
    return value.isNull ? nil : try value.decode(as: HorizontalOverflow.self)
  }

  /// Fails if the page scrolls sideways, naming what sticks out.
  public func expectNoHorizontalOverflow(
    fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column
  ) async throws {
    guard let overflow = try await horizontalOverflow() else { return }
    throw WebTestError(
      "Horizontal overflow on \((try? await url()) ?? "the page") (\(engine)\(viewport.map { ", \($0)" } ?? "")): \(overflow)",
      location: CodeLocation(fileID: fileID, filePath: filePath, line: line, column: column))
  }

  public func close() async {
    await driver.close()
  }
}

/// An ARIA role, for `getByRole`. Any role string works; the common ones
/// have names.
public struct AriaRole: RawRepresentable, Sendable, Hashable, ExpressibleByStringLiteral {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { self.rawValue = value }

  public static let button: AriaRole = "button"
  public static let link: AriaRole = "link"
  public static let heading: AriaRole = "heading"
  public static let textbox: AriaRole = "textbox"
  public static let searchbox: AriaRole = "searchbox"
  public static let checkbox: AriaRole = "checkbox"
  public static let radio: AriaRole = "radio"
  public static let combobox: AriaRole = "combobox"
  public static let listbox: AriaRole = "listbox"
  public static let option: AriaRole = "option"
  public static let menu: AriaRole = "menu"
  public static let menuitem: AriaRole = "menuitem"
  public static let tab: AriaRole = "tab"
  public static let tablist: AriaRole = "tablist"
  public static let tabpanel: AriaRole = "tabpanel"
  public static let dialog: AriaRole = "dialog"
  public static let navigation: AriaRole = "navigation"
  public static let main: AriaRole = "main"
  public static let banner: AriaRole = "banner"
  public static let contentinfo: AriaRole = "contentinfo"
  public static let list: AriaRole = "list"
  public static let listitem: AriaRole = "listitem"
  public static let img: AriaRole = "img"
  public static let grid: AriaRole = "grid"
  public static let gridcell: AriaRole = "gridcell"
  public static let row: AriaRole = "row"
  public static let cell: AriaRole = "cell"
  public static let table: AriaRole = "table"
  public static let region: AriaRole = "region"
  public static let status: AriaRole = "status"
  public static let alert: AriaRole = "alert"
  public static let switch_: AriaRole = "switch"
}

/// The keyboard, sending real key events to whatever has focus.
public struct Keyboard: Sendable {
  let driver: any PageDriver

  /// Presses and releases a key or chord: "Enter", "Escape", "ArrowDown",
  /// "Shift+PageDown", "Control+a".
  public func press(_ chord: String) async throws {
    let keys = try KeyDefinition.chord(chord)
    try await driver.dispatchKeys(keys.map { .down($0) } + keys.reversed().map { .up($0) })
  }

  /// Types `text` a key at a time, as a person would.
  public func type(_ text: String) async throws {
    for character in text {
      let key = KeyDefinition.character(character)
      try await driver.dispatchKeys([.down(key), .up(key)])
    }
  }

  /// Commits `text` in one go, as an input method or paste would.
  public func insertText(_ text: String) async throws {
    try await driver.insertText(text)
  }

  public func down(_ key: String) async throws {
    try await driver.dispatchKeys([.down(try KeyDefinition.named(key))])
  }

  public func up(_ key: String) async throws {
    try await driver.dispatchKeys([.up(try KeyDefinition.named(key))])
  }
}

/// The mouse, at viewport coordinates in CSS pixels.
public struct Mouse: Sendable {
  let driver: any PageDriver

  public func move(x: Double, y: Double) async throws {
    try await driver.dispatchMouse([.move(x: x, y: y)])
  }

  public func click(x: Double, y: Double, button: MouseButton = .left, clickCount: Int = 1) async throws {
    var actions: [MouseAction] = [.move(x: x, y: y)]
    for count in 1...max(1, clickCount) {
      actions.append(.down(x: x, y: y, button: button, clickCount: count))
      actions.append(.up(x: x, y: y, button: button, clickCount: count))
    }
    try await driver.dispatchMouse(actions)
  }
}
