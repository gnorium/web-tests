import Foundation
import Security
import WebTests

/// A throwaway admin account for one test, signed in by cookie.
///
/// Nobody's password is typed or stored. The account is registered over
/// HTTP with a random password generated here and held only in memory, so
/// the server hashes it its own way; it is made an admin with one UPDATE in
/// the dev database, and signed in over HTTP. `remove()` signs it out and
/// deletes that one row (its sessions go with it by cascade); nothing else
/// in the database is touched, bar the leftovers of killed runs (see
/// `create`).
///
/// `GNORIUM_DATABASE_URL` overrides the dev database; `GNORIUM_PSQL` the
/// psql binary.
struct TestAdmin: Sendable {
  let username: String
  let cookie: Cookie
  /// The random password, in memory only, for a test that types it (Delete
  /// account asks for it). Never printed.
  let password: String
  private let baseURL: URL

  /// Why an admin cannot be made here, if it cannot: the tests that need
  /// one skip with this.
  static func unavailableReason() -> String? {
    psqlPath == nil ? "psql was not found (set GNORIUM_PSQL); signed-in tests need it to make a test admin." : nil
  }

  static func create(baseURL: URL) async throws -> TestAdmin {
    // A run killed mid-test leaves its account behind; sweep those (and only
    // those: web_tests_ accounts on the reserved .test domain, an hour old).
    // A deleted one has no email left.
    try? runSQL(
      "DELETE FROM users WHERE username LIKE 'web\\_tests\\_%' AND (email LIKE 'web\\_tests\\_%@gnorium.test' OR (email IS NULL AND deleted_at IS NOT NULL)) AND created_at < now() - interval '1 hour';"
    )
    let suffix = randomHex(bytes: 5)
    // The username rule: 3–20 lowercase letters, digits and underscores.
    let username = "web_tests_\(suffix)"
    let email = "\(username)@gnorium.test"
    let password = randomPassword()

    let (registered, _) = try await post(
      baseURL.appendingPathComponent("auth/register"),
      ["first-name": "Web", "last-name": "Tests", "email": email, "username": username, "password": password])
    guard registered.statusCode == 201 else {
      throw WebTestError("Registering the test admin failed with HTTP \(registered.statusCode).")
    }

    try runSQL("UPDATE users SET role = 'admin' WHERE username = '\(username)' AND email = '\(email)';")

    let (signedIn, _) = try await post(
      baseURL.appendingPathComponent("auth/sign-in"), ["email-or-username": username, "password": password])
    guard signedIn.statusCode == 200,
      let token = HTTPCookie.cookies(
        withResponseHeaderFields: signedIn.allHeaderFields as? [String: String] ?? [:], for: baseURL
      ).first(where: { $0.name == "auth_token" })?.value
    else {
      try? runSQL(deleteStatement(username))
      throw WebTestError("Signing the test admin in failed with HTTP \(signedIn.statusCode).")
    }
    return TestAdmin(
      username: username, cookie: Cookie(name: "auth_token", value: token, url: baseURL), password: password,
      baseURL: baseURL)
  }

  private init(username: String, cookie: Cookie, password: String, baseURL: URL) {
    self.username = username
    self.cookie = cookie
    self.password = password
    self.baseURL = baseURL
  }

  /// Signs out and deletes this account's row, and only that.
  func remove() async {
    var request = URLRequest(url: baseURL.appendingPathComponent("auth/sign-out"))
    request.httpMethod = "POST"
    request.setValue("auth_token=\(cookie.value)", forHTTPHeaderField: "Cookie")
    _ = try? await Self.session.data(for: request)
    try? Self.runSQL(Self.deleteStatement(username))
  }

  /// The account's row, whether or not a test deleted the account through
  /// the site (which keeps the row and erases its email).
  private static func deleteStatement(_ username: String) -> String {
    "DELETE FROM users WHERE username = '\(username)' AND (email = '\(username)@gnorium.test' OR (email IS NULL AND deleted_at IS NOT NULL));"
  }

  /// How many sign-in sessions this account has on the server.
  func sessionCount() throws -> Int {
    Int(
      try Self.query(
        "SELECT COUNT(*) FROM sessions JOIN users ON users.id = sessions.user_id WHERE users.username = '\(username)';"
      ).trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
  }

  /// One column of this account's row, as psql prints it ("" for null).
  func column(_ name: String) throws -> String {
    try Self.query("SELECT COALESCE(\(name)::text, '') FROM users WHERE username = '\(username)';")
  }

  // MARK: - HTTP

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    configuration.httpCookieAcceptPolicy = .never
    return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
  }()

  private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
      _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
      newRequest request: URLRequest
    ) async -> URLRequest? { nil }
  }

  private static func post(_ url: URL, _ form: [String: String]) async throws -> (HTTPURLResponse, Data) {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    request.httpBody = Data(
      form.map { key, value in
        "\(key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
      }.joined(separator: "&").utf8)
    let (data, response) = try await session.data(for: request)
    return (response as! HTTPURLResponse, data)
  }

  // MARK: - Database

  private static let psqlPath: String? = {
    let candidates = [
      ProcessInfo.processInfo.environment["GNORIUM_PSQL"],
      "/opt/homebrew/opt/postgresql@18/bin/psql",
      "/opt/homebrew/opt/postgresql@17/bin/psql",
      "/opt/homebrew/bin/psql",
      "/usr/local/bin/psql",
      "/Applications/Postgres.app/Contents/Versions/latest/bin/psql",
    ]
    return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
  }()

  private static let databaseURL =
    ProcessInfo.processInfo.environment["GNORIUM_DATABASE_URL"]
    ?? "postgresql://gnorium:password@localhost:5432/gnorium_dev"

  private static func runSQL(_ sql: String) throws {
    _ = try query(sql)
  }

  /// Runs `sql` against the dev database and returns what psql prints,
  /// unaligned and without headers. A test's own fixtures only: rows it
  /// makes under its throwaway account and removes after.
  static func query(_ sql: String) throws -> String {
    guard let psqlPath else { throw WebTestError(unavailableReason() ?? "psql is missing.") }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: psqlPath)
    process.arguments = [databaseURL, "-v", "ON_ERROR_STOP=1", "-q", "-At", "-c", sql]
    let output = Pipe()
    process.standardOutput = output
    let errors = Pipe()
    process.standardError = errors
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      throw WebTestError("psql failed: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    let printed = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return printed.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Randomness

  private static func randomBytes(_ count: Int) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: count)
    precondition(SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess)
    return bytes
  }

  private static func randomHex(bytes: Int) -> String {
    randomBytes(bytes).map { String(format: "%02x", $0) }.joined()
  }

  private static func randomPassword() -> String {
    // Letters, digits and symbols, so any password rule is met.
    Data(randomBytes(24)).base64EncodedString() + "aZ9!"
  }
}
