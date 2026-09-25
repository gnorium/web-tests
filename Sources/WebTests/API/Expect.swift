import Foundation

// Web-first assertions: each one reads the page again and again until what
// it expects holds or its timeout passes, so a test never sleeps to let the
// UI settle. A failure reports what was expected and what the page last
// showed.

/// Assertions about a locator, retried until they hold.
///
/// ```swift
/// try await expect(page.getByRole(.dialog)).toBeVisible()
/// try await expect(page.locator(".footer-link")).toHaveCount(5)
/// ```
public func expect(
  _ locator: Locator, timeout: Duration? = nil,
  fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column
) -> LocatorAssertions {
  LocatorAssertions(
    locator: locator, timeout: timeout ?? locator.page.defaultTimeout,
    location: CodeLocation(fileID: fileID, filePath: filePath, line: line, column: column))
}

/// Assertions about a page, retried until they hold.
public func expect(
  _ page: Page, timeout: Duration? = nil,
  fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column
) -> PageAssertions {
  PageAssertions(
    page: page, timeout: timeout ?? page.defaultTimeout,
    location: CodeLocation(fileID: fileID, filePath: filePath, line: line, column: column))
}

/// Polls `read` until `check` accepts what it returns, or fails with
/// `expected` and the last reading.
func poll(
  _ assertion: String, subject: String, timeout: Duration, location: CodeLocation,
  read: () async throws -> JSONValue,
  check: (JSONValue) -> (pass: Bool, actual: String)
) async throws {
  let deadline = Deadline(timeout)
  var backoff = Backoff()
  var actual = "nothing was read"
  while true {
    do {
      let value = try await read()
      let (pass, seen) = check(value)
      if pass { return }
      actual = seen
    } catch let error as JavaScriptError where error.isTransient {
      actual = "the page was navigating"
    }
    if deadline.hasPassed {
      throw WebTestError(
        "expect(\(subject)).\(assertion) failed after \(timeout.secondsText): \(actual).", location: location)
    }
    try await Task.sleep(for: backoff.next())
  }
}

public struct LocatorAssertions: Sendable {
  let locator: Locator
  let timeout: Duration
  let location: CodeLocation
  var negated = false

  /// The same assertions, expecting the opposite:
  /// `expect(field).not.toHaveValue("")`.
  public var not: LocatorAssertions {
    var copy = self
    copy.negated.toggle()
    return copy
  }

  private func check(
    _ assertion: String, options: JSONValue = [:], _ predicate: @escaping (JSONValue) -> (pass: Bool, actual: String)
  ) async throws {
    let negated = negated
    try await poll(
      (negated ? "not." : "") + assertion, subject: locator.description, timeout: timeout, location: location,
      read: { try await locator.inspect(options) },
      check: { value in
        let (pass, actual) = predicate(value)
        return (pass != negated, actual)
      })
  }

  /// One element matches, and it is visible.
  public func toBeVisible() async throws {
    try await check("toBeVisible()") { result in
      (result["count"].int == 1 && result["visible"].bool == true, Locator.stateText(result))
    }
  }

  /// No element matches, or the one that does is not visible.
  public func toBeHidden() async throws {
    try await check("toBeHidden()") { result in
      let count = result["count"].int ?? 0
      return (count == 0 || (count == 1 && result["visible"].bool == false), Locator.stateText(result))
    }
  }

  public func toBeAttached() async throws {
    try await check("toBeAttached()") { result in ((result["count"].int ?? 0) >= 1, Locator.stateText(result)) }
  }

  public func toBeEnabled() async throws {
    try await check("toBeEnabled()") { result in
      (result["count"].int == 1 && result["enabled"].bool == true, Self.describe(result, "enabled"))
    }
  }

  public func toBeDisabled() async throws {
    try await check("toBeDisabled()") { result in
      (result["count"].int == 1 && result["enabled"].bool == false, Self.describe(result, "enabled"))
    }
  }

  public func toBeChecked(_ checked: Bool = true) async throws {
    try await check("toBeChecked(\(checked))") { result in
      (result["count"].int == 1 && result["checked"].bool == checked, Self.describe(result, "checked"))
    }
  }

  public func toBeFocused() async throws {
    try await check("toBeFocused()") { result in
      (result["count"].int == 1 && result["focused"].bool == true, Self.describe(result, "focused"))
    }
  }

  /// The element's text, whitespace collapsed, is exactly `text`.
  ///
  /// - Parameter useInnerText: Compare the rendered text (`innerText`),
  ///   leaving out hidden descendants, rather than `textContent`.
  public func toHaveText(_ text: String, useInnerText: Bool = false) async throws {
    let expected = Self.normalize(text)
    try await check("toHaveText(\(JSONValue.quoted(text)))") { result in
      guard result["count"].int == 1 else { return (false, Locator.stateText(result)) }
      let actual = result[useInnerText ? "innerText" : "text"].string ?? ""
      return (actual == expected, "its text is \(JSONValue.quoted(actual))")
    }
  }

  /// The element's text contains `text`.
  public func toContainText(_ text: String, useInnerText: Bool = false) async throws {
    let expected = Self.normalize(text)
    try await check("toContainText(\(JSONValue.quoted(text)))") { result in
      guard result["count"].int == 1 else { return (false, Locator.stateText(result)) }
      let actual = result[useInnerText ? "innerText" : "text"].string ?? ""
      return (actual.contains(expected), "its text is \(JSONValue.quoted(actual))")
    }
  }

  /// The texts of all matches, in order, are exactly `texts`.
  public func toHaveTexts(_ texts: [String]) async throws {
    let expected = texts.map(Self.normalize)
    try await check("toHaveTexts(\(expected))", options: ["all": true]) { result in
      let actual = (result["texts"].array ?? []).compactMap(\.string)
      return (actual == expected, "the texts are \(actual)")
    }
  }

  /// The attribute is present with exactly `value`; with nil, present at
  /// all.
  public func toHaveAttribute(_ name: String, _ value: String? = nil) async throws {
    try await check(
      "toHaveAttribute(\(JSONValue.quoted(name))\(value.map { ", \(JSONValue.quoted($0))" } ?? ""))",
      options: ["attribute": .string(name)]
    ) { result in
      guard result["count"].int == 1 else { return (false, Locator.stateText(result)) }
      let actual = result["attribute"]
      guard let string = actual.string else { return (false, "it has no \(name) attribute") }
      return (value == nil || string == value, "\(name) is \(JSONValue.quoted(string))")
    }
  }

  /// Exactly `count` elements match.
  public func toHaveCount(_ count: Int) async throws {
    try await check("toHaveCount(\(count))") { result in
      let actual = result["count"].int ?? 0
      return (actual == count, "\(actual) element\(actual == 1 ? "" : "s") match")
    }
  }

  /// The computed value of a CSS property is exactly `value` (as
  /// `getComputedStyle` gives it: "flex", "rgb(0, 0, 0)", "16px").
  public func toHaveCSS(_ property: String, _ value: String) async throws {
    try await check("toHaveCSS(\(JSONValue.quoted(property)), \(JSONValue.quoted(value)))", options: ["css": .string(property)]) { result in
      guard result["count"].int == 1 else { return (false, Locator.stateText(result)) }
      let actual = result["css"].string ?? ""
      return (actual == value, "\(property) is \(JSONValue.quoted(actual))")
    }
  }

  /// A form control's value is exactly `value`.
  public func toHaveValue(_ value: String) async throws {
    try await check("toHaveValue(\(JSONValue.quoted(value)))") { result in
      guard result["count"].int == 1 else { return (false, Locator.stateText(result)) }
      let actual = result["value"].string ?? ""
      return (actual == value, "its value is \(JSONValue.quoted(actual))")
    }
  }

  /// The accessible name is exactly `name`.
  public func toHaveAccessibleName(_ name: String) async throws {
    let expected = Self.normalize(name)
    try await check("toHaveAccessibleName(\(JSONValue.quoted(name)))", options: ["name": true]) { result in
      guard result["count"].int == 1 else { return (false, Locator.stateText(result)) }
      let actual = result["name"].string ?? ""
      return (actual == expected, "its name is \(JSONValue.quoted(actual))")
    }
  }

  static func normalize(_ text: String) -> String {
    text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
  }

  static func describe(_ result: JSONValue, _ key: String) -> String {
    guard result["count"].int == 1 else { return Locator.stateText(result) }
    return "\(result["description"].string ?? "the element") has \(key) = \(result[key].bool.map(String.init) ?? "unknown")"
  }
}

public struct PageAssertions: Sendable {
  let page: Page
  let timeout: Duration
  let location: CodeLocation

  /// The document's URL is exactly `url`: absolute, or a path resolved
  /// against the base URL ("/lexico-records?treatment=translated").
  public func toHaveURL(_ url: String) async throws {
    let expected = try page.resolve(url).absoluteString
    try await poll(
      "toHaveURL(\(JSONValue.quoted(url)))", subject: "page", timeout: timeout, location: location,
      read: { try await page.evaluate("location.href") },
      check: { value in (value.string == expected, "the URL is \(JSONValue.quoted(value.string ?? ""))") })
  }

  /// The document's URL satisfies `predicate`, described by `description`
  /// in a failure.
  public func toHaveURL(_ description: String, where predicate: @escaping @Sendable (URL) -> Bool) async throws {
    try await poll(
      "toHaveURL(\(description))", subject: "page", timeout: timeout, location: location,
      read: { try await page.evaluate("location.href") },
      check: { value in
        let text = value.string ?? ""
        return (URL(string: text).map(predicate) ?? false, "the URL is \(JSONValue.quoted(text))")
      })
  }

  public func toHaveTitle(_ title: String) async throws {
    try await poll(
      "toHaveTitle(\(JSONValue.quoted(title)))", subject: "page", timeout: timeout, location: location,
      read: { try await page.evaluate("document.title") },
      check: { value in (value.string == title, "the title is \(JSONValue.quoted(value.string ?? ""))") })
  }
}
