import Foundation
import Security
import WebTests

/// A throwaway admin account for one test (or, with `admin: false`, a plain
/// one), signed in by cookie.
///
/// Nobody's password is typed or stored. The account is registered over
/// HTTP with a random password generated here and held only in memory, so
/// the server hashes it its own way; it is made an admin with one UPDATE in
/// the dev database, and signed in over HTTP.
///
/// `remove()` never touches the event log, which is history: its rows name
/// their user, and `event_logs.user_id` is ON DELETE RESTRICT (server
/// migration 0385). Submitted input is history too: a submission's user is
/// frozen, so an account that submitted can't lose its row either. An
/// account neither names is deleted outright (one DELETE of its row, as the
/// dev database's owner; its sessions go by cascade). An account either
/// names is deleted the way its owner deletes it, through Delete account
/// with its password (`AccountDeletion`: private data erased, the row kept
/// for the username, as for every deleted account). Either way a failure
/// throws; nothing is left behind silently. The leftovers of killed runs are swept in `create` by the same rule.
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

  /// `admin: false` leaves the account a plain contributor (the same
  /// throwaway rules; only the role differs).
  /// A mailbox's proof, as the emailed link would set it: a throwaway
  /// address's challenge written already verified, and the cookie that opens
  /// the register page's second step—the account's name, password and terms.
  static func registrationProof(baseURL: URL) throws -> Cookie {
    let email = "web_tests_\(randomHex(bytes: 5))@gnorium.test"
    let proof = randomHex(bytes: 32)
    try runSQL(
      "INSERT INTO registration_challenges (id, email, token_hash, completion_hash, verified_at, expires_at, created_at) VALUES (gen_random_uuid(), '\(email)', encode(sha256(convert_to('\(randomHex(bytes: 32))', 'UTF8')), 'hex'), encode(sha256(convert_to('\(proof)', 'UTF8')), 'hex'), now(), now() + interval '15 minutes', now());"
    )
    return Cookie(name: "registration_proof", value: proof, url: baseURL)
  }

  static func create(baseURL: URL, admin: Bool = true) async throws -> TestAdmin {
    // A run killed mid-test leaves its account behind; sweep those (and only
    // those: web_tests_ accounts on the reserved .test domain, an hour old,
    // that the event log doesn't name; one it names is history, and without
    // its password can't be deleted through the site, so it stays).
    try runSQL(
      "DELETE FROM users WHERE username LIKE 'web\\_tests\\_%' AND email LIKE 'web\\_tests\\_%@gnorium.test' AND created_at < now() - interval '1 hour' AND NOT EXISTS (SELECT 1 FROM event_logs WHERE event_logs.user_id = users.id) AND NOT EXISTS (SELECT 1 FROM submissions WHERE submissions.user_id = users.id);"
    )
    let suffix = randomHex(bytes: 5)
    // The username rule: 3–20 lowercase letters, digits and underscores.
    let username = "web_tests_\(suffix)"
    let email = "\(username)@gnorium.test"
    let password = randomPassword()

    // Registration needs a proof that the mailbox is owned: the row the
    // emailed link would have verified, written here already verified, and
    // its completion token sent as the cookie the link would have set
    // (`RegistrationProof`). The token is held in memory only.
    let proof = randomHex(bytes: 32)
    try runSQL(
      "INSERT INTO registration_challenges (id, email, token_hash, completion_hash, verified_at, expires_at, created_at) VALUES (gen_random_uuid(), '\(email)', encode(sha256(convert_to('\(randomHex(bytes: 32))', 'UTF8')), 'hex'), encode(sha256(convert_to('\(proof)', 'UTF8')), 'hex'), now(), now() + interval '15 minutes', now());"
    )
    let (registered, _) = try await post(
      baseURL.appendingPathComponent("auth/register"),
      ["full-name": "Web Tests", "email": email, "username": username, "password": password],
      cookie: Cookie(name: "registration_proof", value: proof, url: baseURL))
    guard registered.statusCode == 201 else {
      throw WebTestError("Registering the test admin failed with HTTP \(registered.statusCode).")
    }

    if admin {
      try runSQL("UPDATE users SET role = 'admin' WHERE username = '\(username)' AND email = '\(email)';")
    }

    let (signedIn, _) = try await post(
      baseURL.appendingPathComponent("auth/sign-in"), ["email-or-username": username, "password": password])
    guard signedIn.statusCode == 200,
      let token = HTTPCookie.cookies(
        withResponseHeaderFields: signedIn.allHeaderFields as? [String: String] ?? [:], for: baseURL
      ).first(where: { $0.name == "auth_token" })?.value
    else {
      try runSQL(deleteStatement(username))
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

  /// Deletes this account and only this one (see the type's note): its row
  /// when neither the event log nor a submission names it, otherwise through
  /// Delete account.
  /// An account a test already deleted through the site is left as it is.
  /// Throws when the account isn't gone.
  func remove() async throws {
    let state = try Self.query(
      "SELECT (deleted_at IS NOT NULL)::text || ' ' || (EXISTS (SELECT 1 FROM event_logs WHERE event_logs.user_id = users.id) OR EXISTS (SELECT 1 FROM submissions WHERE submissions.user_id = users.id))::text FROM users WHERE username = '\(username)';"
    )
    switch state {
    case "":
      return  // no row: already gone
    case "false false":
      try Self.runSQL(Self.deleteStatement(username))
    case "false true":
      // A fresh sign-in: the test may have signed its own session out.
      let (deleted, _) = try await Self.post(
        baseURL.appendingPathComponent("account/delete"), ["password": password, "confirm": "on"],
        cookie: try await signIn())
      let now = try Self.query("SELECT (deleted_at IS NOT NULL AND email IS NULL)::text FROM users WHERE username = '\(username)';")
      guard deleted.statusCode == 200, now == "true" else {
        throw WebTestError("Deleting the test account \(username) through Delete account failed (HTTP \(deleted.statusCode)).")
      }
    default:
      return  // "true …": a test deleted it through the site; the row stays, as for every deleted account
    }
  }

  /// For a test's error path: removes the account, then throws `error`; a
  /// removal that fails too is added to it, not hidden.
  func remove(after error: any Error) async throws -> Never {
    do {
      try await remove()
    } catch let removal {
      throw WebTestError("\(error)\n…and removing the test account failed too: \(removal)")
    }
    throw error
  }

  /// This throwaway account's own row, while it is live (it has its email).
  private static func deleteStatement(_ username: String) -> String {
    "DELETE FROM users WHERE username = '\(username)' AND email = '\(username)@gnorium.test';"
  }

  /// A new sign-in over HTTP, as its cookie: another session row of this
  /// account's (a throwaway row for a test to delete).
  @discardableResult
  func signIn() async throws -> Cookie {
    let (signedIn, _) = try await Self.post(
      baseURL.appendingPathComponent("auth/sign-in"), ["email-or-username": username, "password": password])
    guard signedIn.statusCode == 200,
      let token = HTTPCookie.cookies(
        withResponseHeaderFields: signedIn.allHeaderFields as? [String: String] ?? [:], for: baseURL
      ).first(where: { $0.name == "auth_token" })?.value
    else {
      throw WebTestError("Signing the test account in again failed with HTTP \(signedIn.statusCode).")
    }
    return Cookie(name: "auth_token", value: token, url: baseURL)
  }

  /// This account's newest session row's id.
  func newestSessionID() throws -> String {
    try Self.query(
      "SELECT sessions.id FROM sessions JOIN users ON users.id = sessions.user_id WHERE users.username = '\(username)' ORDER BY sessions.created_at DESC LIMIT 1;"
    )
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

  private static func post(_ url: URL, _ form: [String: String], cookie: Cookie? = nil) async throws -> (HTTPURLResponse, Data) {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    if let cookie { request.setValue("\(cookie.name)=\(cookie.value)", forHTTPHeaderField: "Cookie") }
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
