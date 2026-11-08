import Darwin
import Foundation
import WebTests

/// The Gnorium server the web tests run against: one made for this run, never
/// the dev server (user, 2026-11-08: "dont clutter web test shit in dev bro
/// maintain dev hygiene"). The tests register accounts, submit, commit and
/// permit, so whatever server they reach is written to; it must never be the
/// dev server on :8080 or its database, gnorium_dev.
///
/// On first use (the `gnorium` configuration, `TestAdmin`) the run gets:
///
/// - **its own database**, `gnorium_webtests_<pid>_<hex>` on the local
///   PostgreSQL, made by the cluster's superuser (`GNORIUM_WEB_TESTS_ADMIN_URL`,
///   default the OS user over localhost) with the `vector` extension that only a
///   superuser may create, owned by `gnorium`, migrated by the server's own
///   `migrate --yes` as `gnorium` and granted to `gnorium_app`
///   (`grant-app-role`), exactly as `make dev-local-migrate` builds dev's;
/// - **its own server**: gnorium-web's built `.bin/Server` (`make server`),
///   serving that database as `gnorium_app` on a free port of 127.0.0.1, with
///   gnorium-web's `.env.dev`, `.env.dev.secrets` and `.env.worker-controls`
///   as `make serve` loads them, but nothing that reaches what the dev server
///   shares: no Computorium dispatch or worker-control sync to the Python
///   services, no re-derivation sweep, no citation indexing into the quotes
///   service, no Elsewhere checks, no Wayback saves, no provider keys (no paid
///   model call can start), and its avatars in this run's own folder;
///
/// and both go when the test process ends (exit, Ctrl-C, SIGTERM): the server
/// stopped, the database dropped. A run killed harder leaves them; the next
/// run sweeps every `gnorium_webtests_` database whose process is gone, and
/// the server it recorded.
///
/// - `WEB_TESTS_SERVER_<NAME>=value` sets `<NAME>` for the run's server (e.g.
///   `WEB_TESTS_SERVER_COMPUTORIUM_DISPATCHER_ENABLED=true`).
/// - `GNORIUM_WEB_TESTS_KEEP=1` keeps the database (its name is printed).
/// - `GNORIUM_BASE_URL` with `GNORIUM_DATABASE_URL` runs against a server
///   someone else started instead (its database's owner URL, for the tests'
///   own SQL). Either alone is refused, as is any that names gnorium_dev or
///   the dev server's port 8080: the run stops before a test starts.
enum WebTestServer {
  /// Where the tests point, and the database they seed and read as its owner.
  struct Target: Sendable {
    let baseURL: URL
    let databaseURL: String
  }

  static var baseURL: URL { target.baseURL }
  static var databaseURL: String { target.databaseURL }

  /// Resolved once, on first use: every test of the run shares it.
  static let target: Target = resolve()

  /// The database the dev server serves; never this run's.
  static let devDatabase = "gnorium_dev"

  private static func resolve() -> Target {
    let environment = ProcessInfo.processInfo.environment
    let base = environment["GNORIUM_BASE_URL"].flatMap { $0.isEmpty ? nil : $0 }
    let database = environment["GNORIUM_DATABASE_URL"].flatMap { $0.isEmpty ? nil : $0 }
    switch (base, database) {
    case (let base?, let database?):
      guard let url = URL(string: base) else { refuse("GNORIUM_BASE_URL is not a URL: \(base)") }
      refuseDev(baseURL: url, databaseURL: database)
      return Target(baseURL: url, databaseURL: database)
    case (_?, nil):
      refuse(
        "GNORIUM_BASE_URL is set without GNORIUM_DATABASE_URL: the tests seed and read the database their server "
          + "serves, and must be told which, to be sure it is not gnorium_dev. Unset both to let the run make its own.")
    case (nil, _?):
      refuse("GNORIUM_DATABASE_URL is set without GNORIUM_BASE_URL. Unset both to let the run make its own.")
    case (nil, nil):
      return Harness.start()
    }
  }

  /// Stops the run before any test reaches the dev server or its database.
  static func refuseDev(baseURL: URL, databaseURL: String) {
    if databaseName(of: databaseURL) == devDatabase {
      refuse("GNORIUM_DATABASE_URL names gnorium_dev, the dev database. Web tests never write it.")
    }
    let host = baseURL.host ?? ""
    if ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host), baseURL.port == 8080 {
      refuse("GNORIUM_BASE_URL is the dev server (port 8080), which serves gnorium_dev. Web tests never write it.")
    }
  }

  /// A connection URL's database name ("" for none).
  static func databaseName(of url: String) -> String {
    let path = url.split(separator: "?", maxSplits: 1).first.map(String.init) ?? url
    guard let slash = path.lastIndex(of: "/") else { return "" }
    return String(path[path.index(after: slash)...])
  }

  static func refuse(_ message: String) -> Never {
    FileHandle.standardError.write(Data("web-tests: \(message)\n".utf8))
    fatalError("web-tests refused to start: \(message)")
  }

  /// This run's own database and server.
  enum Harness {
    /// The package's root (web-tests), and Gnorium's packages beside it.
    static let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static var webDirectory: URL {
      ProcessInfo.processInfo.environment["GNORIUM_WEB_DIR"].map { URL(fileURLWithPath: $0) }
        ?? root.deletingLastPathComponent().appendingPathComponent("gnorium-web")
    }
    /// The run's files: its server's log, its avatars, the record a later
    /// run sweeps by.
    static let stateDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("gnorium-web-tests")

    static let adminURL =
      ProcessInfo.processInfo.environment["GNORIUM_WEB_TESTS_ADMIN_URL"].flatMap { $0.isEmpty ? nil : $0 }
      ?? "postgresql://localhost:5432/postgres"
    /// The roles dev uses (gnorium-web Makefile, `.env.dev`): the owner
    /// migrates and seeds, the app's role serves.
    static func ownerURL(_ database: String) -> String { "postgresql://gnorium:password@localhost:5432/\(database)" }
    static func appURL(_ database: String) -> String { "postgresql://gnorium_app:password@localhost:5432/\(database)" }

    /// What the stop at exit needs.
    nonisolated(unsafe) private static var server: Process?
    nonisolated(unsafe) private static var database: String?
    nonisolated(unsafe) private static var stopped = false
    nonisolated(unsafe) private static var served = false
    nonisolated(unsafe) private static var signalSources: [any DispatchSourceSignal] = []
    private static let lock = NSLock()

    static func start() -> Target {
      try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
      sweepStale()
      let name = "gnorium_webtests_\(getpid())_\(randomHex(4))"
      refuseDevName(name)
      let runDirectory = stateDirectory.appendingPathComponent(name)
      try? FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
      let log = runDirectory.appendingPathComponent("server.log")
      let binary = webDirectory.appendingPathComponent(".bin/Server")
      guard FileManager.default.isExecutableFile(atPath: binary.path) else {
        refuse("no server binary at \(binary.path): build it in gnorium-web with `make server`.")
      }

      // Its database: made, given pgvector, migrated and granted as dev's.
      lock.withLock { database = name }
      installStop()
      do {
        try psql(adminURL, "CREATE DATABASE \"\(name)\" OWNER gnorium;")
        try psql(replacingDatabase(of: adminURL, with: name), "CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;")
      } catch {
        stop()
        refuse("could not make the run's database \(name) as \(adminURL) (set GNORIUM_WEB_TESTS_ADMIN_URL to a superuser's URL): \(error)")
      }
      var environment = serverEnvironment(runDirectory: runDirectory)
      environment["POSTGRES_CONNECTION_STRING"] = ownerURL(name)
      if let failure = run(binary, ["migrate", "--yes"], environment: environment, log: log) {
        stop()
        refuse("migrating the run's database failed (\(failure)); its log: \(log.path)")
      }
      environment["APP_ROLE_PASSWORD"] = "password"
      if let failure = run(binary, ["grant-app-role"], environment: environment, log: log) {
        stop()
        refuse("granting the app's role on the run's database failed (\(failure)); its log: \(log.path)")
      }
      environment["APP_ROLE_PASSWORD"] = nil

      // Its server, on a port of its own.
      let port = freePort()
      let base = "http://127.0.0.1:\(port)"
      environment["POSTGRES_CONNECTION_STRING"] = appURL(name)
      environment["APP_BASE_URL"] = base
      environment["COMPUTORIUM_CONTROL_CALLBACK_URL"] = base
      for (key, value) in ProcessInfo.processInfo.environment where key.hasPrefix("WEB_TESTS_SERVER_") {
        environment[String(key.dropFirst("WEB_TESTS_SERVER_".count))] = value
      }
      let process = Process()
      process.executableURL = binary
      process.arguments = ["serve", "--env", "development", "--hostname", "127.0.0.1", "--port", "\(port)"]
      process.currentDirectoryURL = webDirectory
      process.environment = environment
      FileManager.default.createFile(atPath: log.path, contents: nil)
      if let handle = try? FileHandle(forWritingTo: log) {
        handle.seekToEndOfFile()
        process.standardOutput = handle
        process.standardError = handle
      }
      do {
        try process.run()
      } catch {
        stop()
        refuse("could not start the run's server: \(error)")
      }
      lock.withLock { server = process }
      record(name: name, serverPID: process.processIdentifier)
      guard waitUntilServing(URL(string: base)!, process: process) else {
        stop()
        refuse("the run's server did not come up on \(base); its log: \(log.path)")
      }
      lock.withLock { served = true }
      FileHandle.standardError.write(Data("web-tests: serving \(name) at \(base) (log \(log.path))\n".utf8))
      return Target(baseURL: URL(string: base)!, databaseURL: ownerURL(name))
    }

    private static func refuseDevName(_ name: String) {
      if name == devDatabase { refuse("the run's database would be gnorium_dev.") }
    }

    // MARK: - The server's environment

    /// `make serve`'s: gnorium-web's dotenv files over this process's
    /// environment, less what reaches beyond the run.
    static func serverEnvironment(runDirectory: URL) -> [String: String] {
      var environment = ProcessInfo.processInfo.environment
      for file in [".env.dev", ".env.dev.secrets", ".env.worker-controls"] {
        for (key, value) in dotenv(webDirectory.appendingPathComponent(file)) { environment[key] = value }
      }
      // No paid model call, upload or payment can start from a test.
      for key in environment.keys
      where key.hasSuffix("_API_KEY") || key.hasSuffix("_SECRET_KEY") || key.hasSuffix("_ACCESS_KEY")
        || key.hasPrefix("RAZORPAY_") || key.hasPrefix("OPENROUTER_") || key.hasPrefix("GOOGLE_APPLICATION")
      {
        environment[key] = nil
      }
      // Nothing that the dev server shares: the Python services' controls
      // and sessions, the quotes service's index, the Internet's archives.
      environment["COMPUTORIUM_DISPATCHER_ENABLED"] = "false"
      environment["CONTROL_SYNC_ENABLED"] = "false"
      environment["REDERIVATION_ENABLED"] = "false"
      environment["CITATION_INDEX_ENABLED"] = "false"
      environment["ELSEWHERE_CHECKER_ENABLED"] = "false"
      environment["QUOTES_SERVICE_URL"] = "http://127.0.0.1:9"
      environment["RAZORPAY_SPONSORSHIP_ENABLED"] = "false"
      environment["AVATARS_DIRECTORY"] = runDirectory.appendingPathComponent("avatars").path
      return environment
    }

    /// KEY=VALUE lines, quotes stripped, comments and blanks skipped.
    static func dotenv(_ file: URL) -> [(String, String)] {
      guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
      var out: [(String, String)] = []
      for raw in text.split(whereSeparator: \.isNewline) {
        var line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { continue }
        if line.hasPrefix("export ") { line = String(line.dropFirst(7)) }
        guard let equals = line.firstIndex(of: "=") else { continue }
        let key = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
        var value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
          value = String(value.dropFirst().dropLast())
        }
        out.append((key, value))
      }
      return out
    }

    // MARK: - Processes

    /// Runs `binary` to the end; the reason it failed, or nil.
    private static func run(_ binary: URL, _ arguments: [String], environment: [String: String], log: URL) -> String? {
      let process = Process()
      process.executableURL = binary
      process.arguments = arguments
      process.currentDirectoryURL = webDirectory
      process.environment = environment
      FileManager.default.createFile(atPath: log.path, contents: nil)
      if let handle = try? FileHandle(forWritingTo: log) {
        handle.seekToEndOfFile()
        process.standardOutput = handle
        process.standardError = handle
      }
      do {
        try process.run()
      } catch {
        return "\(error)"
      }
      process.waitUntilExit()
      return process.terminationStatus == 0 ? nil : "\(arguments.joined(separator: " ")) exited \(process.terminationStatus)"
    }

    @discardableResult
    static func psql(_ url: String, _ sql: String) throws -> String {
      guard let path = TestAdmin.psqlPath else { throw WebTestError("psql was not found (set GNORIUM_PSQL).") }
      let process = Process()
      process.executableURL = URL(fileURLWithPath: path)
      process.arguments = [url, "-v", "ON_ERROR_STOP=1", "-q", "-At", "-c", sql]
      let output = Pipe()
      let errors = Pipe()
      process.standardOutput = output
      process.standardError = errors
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw WebTestError("psql failed: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
      }
      return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func replacingDatabase(of url: String, with database: String) -> String {
      let parts = url.split(separator: "?", maxSplits: 1).map(String.init)
      guard let slash = parts[0].lastIndex(of: "/") else { return url }
      return String(parts[0][...slash]) + database + (parts.count > 1 ? "?" + parts[1] : "")
    }

    /// Polls the server until it answers (a page, any status but none) or
    /// exits.
    private static func waitUntilServing(_ base: URL, process: Process) -> Bool {
      let deadline = Date().addingTimeInterval(300)
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 5
      let session = URLSession(configuration: configuration)
      while Date() < deadline {
        guard process.isRunning else { return false }
        let done = DispatchSemaphore(value: 0)
        let answered = Answered()
        session.dataTask(with: base) { _, response, _ in
          if let http = response as? HTTPURLResponse, http.statusCode < 500 { answered.set() }
          done.signal()
        }.resume()
        done.wait()
        if answered.value { return true }
        Thread.sleep(forTimeInterval: 0.5)
      }
      return false
    }

    private final class Answered: @unchecked Sendable {
      private let lock = NSLock()
      private var answered = false
      func set() { lock.withLock { answered = true } }
      var value: Bool { lock.withLock { answered } }
    }

    static func freePort() -> UInt16 {
      let fd = socket(AF_INET, SOCK_STREAM, 0)
      defer { close(fd) }
      var address = sockaddr_in()
      address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
      address.sin_family = sa_family_t(AF_INET)
      address.sin_port = 0
      address.sin_addr.s_addr = inet_addr("127.0.0.1")
      var length = socklen_t(MemoryLayout<sockaddr_in>.size)
      withUnsafeMutablePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
          _ = bind(fd, socketAddress, length)
          _ = getsockname(fd, socketAddress, &length)
        }
      }
      return UInt16(bigEndian: address.sin_port)
    }

    // MARK: - Ending

    /// Stops the server and drops the database, once, at exit or on a signal.
    private static func installStop() {
      atexit { WebTestServer.Harness.stop() }
      for number in [SIGINT, SIGTERM, SIGHUP] {
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
        source.setEventHandler {
          WebTestServer.Harness.stop()
          exit(128 + number)
        }
        source.resume()
        lock.withLock { signalSources.append(source) }
      }
    }

    static func stop() {
      let (process, name, already) = lock.withLock { () -> (Process?, String?, Bool) in
        let state = (server, database, stopped)
        stopped = true
        return state
      }
      guard !already else { return }
      if let process, process.isRunning {
        process.terminate()
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
      }
      guard let name else { return }
      if ProcessInfo.processInfo.environment["GNORIUM_WEB_TESTS_KEEP"] == "1" {
        FileHandle.standardError.write(Data("web-tests: kept the run's database \(name)\n".utf8))
        return
      }
      drop(name)
      // A run that served: its folder (log, avatars) goes too. One that
      // never came up keeps its log for the refusal that names it.
      if lock.withLock({ served }) {
        try? FileManager.default.removeItem(at: stateDirectory.appendingPathComponent(name))
      }
    }

    /// The database dropped and its server's record removed; the run's log
    /// stays until the folder is swept.
    private static func drop(_ name: String) {
      guard name.hasPrefix("gnorium_webtests_"), name != devDatabase else { return }
      _ = try? psql(adminURL, "DROP DATABASE IF EXISTS \"\(name)\" WITH (FORCE);")
      try? FileManager.default.removeItem(
        at: stateDirectory.appendingPathComponent(name).appendingPathComponent("server.pid"))
    }

    /// The record a later run sweeps by: the server's process id.
    private static func record(name: String, serverPID: Int32) {
      let file = stateDirectory.appendingPathComponent(name).appendingPathComponent("server.pid")
      try? Data("\(serverPID)".utf8).write(to: file)
    }

    /// Every run database whose test process is gone: its server stopped (if
    /// it is still Gnorium's server), the database dropped.
    private static func sweepStale() {
      guard
        let names = try? psql(
          adminURL, "SELECT datname FROM pg_database WHERE datname LIKE 'gnorium\\_webtests\\_%' ORDER BY 1;")
      else { return }
      for name in names.split(whereSeparator: \.isNewline).map(String.init) {
        let parts = name.split(separator: "_")
        guard parts.count >= 4, let owner = Int32(parts[2]) else { continue }
        if kill(owner, 0) == 0 || errno == EPERM { continue }  // its test process still runs
        let pidFile = stateDirectory.appendingPathComponent(name).appendingPathComponent("server.pid")
        if let text = try? String(contentsOf: pidFile, encoding: .utf8), let pid = Int32(text), isGnoriumServer(pid) {
          kill(pid, SIGTERM)
        }
        drop(name)
      }
      let live = Set(names.split(whereSeparator: \.isNewline).map(String.init))
      let dayAgo = Date().addingTimeInterval(-86_400)
      for folder in (try? FileManager.default.contentsOfDirectory(
        at: stateDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
      where folder.lastPathComponent.hasPrefix("gnorium_webtests_") && !live.contains(folder.lastPathComponent) {
        let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let modified, modified < dayAgo { try? FileManager.default.removeItem(at: folder) }
      }
    }

    private static func isGnoriumServer(_ pid: Int32) -> Bool {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/ps")
      process.arguments = ["-p", "\(pid)", "-o", "command="]
      let output = Pipe()
      process.standardOutput = output
      guard (try? process.run()) != nil else { return false }
      process.waitUntilExit()
      let command = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      return command.contains("/.bin/Server") && command.contains(" serve")
    }

    private static func randomHex(_ bytes: Int) -> String {
      (0..<bytes).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
  }
}
