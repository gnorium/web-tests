import Foundation

/// An error a WebDriver endpoint returned: the spec's error code and its
/// message.
struct WebDriverError: Error, CustomStringConvertible {
  let error: String
  let message: String
  var description: String { "\(error): \(message)" }
}

/// W3C WebDriver (classic) over HTTP: JSON in, `{"value": …}` out.
struct WebDriverClient: Sendable {
  let baseURL: URL
  private let session: URLSession

  init(baseURL: URL) {
    self.baseURL = baseURL
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 120
    configuration.timeoutIntervalForResource = 300
    session = URLSession(configuration: configuration)
  }

  /// Sends a command and returns its `value`.
  func command(_ method: String, _ path: String, _ body: JSONValue? = nil, timeout: TimeInterval = 120) async throws -> JSONValue {
    var request = URLRequest(url: baseURL.appendingPathComponent(path))
    request.httpMethod = method
    request.timeoutInterval = timeout
    if method != "GET" && method != "DELETE" {
      request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
      request.httpBody = Data((body ?? [:]).jsonText.utf8)
    }
    let (data, _) = try await session.data(for: request)
    let value = (try? JSONDecoder().decode(JSONValue.self, from: data))?["value"] ?? .null
    if let error = value["error"].string {
      throw WebDriverError(error: error, message: value["message"].string ?? "")
    }
    return value
  }
}
