import Foundation
import Network

/// A tiny HTTP server on this machine serving fixed files, for what the
/// Gnorium server must fetch itself—a testament's IIIF manifest. It listens
/// on 127.0.0.1 at a port the system picks, answers GET with the file at the
/// path (404 for any other), and closes each connection after its answer.
///
/// The dev server fetches it only because `.env.dev` sets
/// `MANIFEST_FETCH_ALLOW_LOOPBACK=true` (gnorium-server `ManifestFetch`),
/// which production never honors.
final class FixtureServer: @unchecked Sendable {
  struct File: Sendable {
    let contentType: String
    let body: Data
  }

  private let listener: NWListener
  private var files: [String: File]
  private let queue = DispatchQueue(label: "web-tests.fixture-server")
  /// The port the system picked.
  private(set) var port: UInt16 = 0

  /// `http://127.0.0.1:<port>`.
  var baseURL: String { "http://127.0.0.1:\(port)" }

  init(files: [String: File]) async throws {
    self.files = files
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    listener = try NWListener(using: parameters)
    listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
    let listener = self.listener
    port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, any Error>) in
      let resumed = Resumed()
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
          if resumed.claim() { continuation.resume(returning: listener.port?.rawValue ?? 0) }
        case .failed(let error):
          if resumed.claim() { continuation.resume(throwing: error) }
        default: break
        }
      }
      listener.start(queue: queue)
    }
  }

  func stop() { listener.cancel() }

  /// A one-page IIIF v3 manifest at `path`, for a form whose Source URL the
  /// server reads before it takes the submission: the testament's source is
  /// `baseURL + path`, a path no other test names.
  static func manifest(at path: String) async throws -> FixtureServer {
    try await manifests(at: [path])
  }

  /// A one-page IIIF v3 manifest at each of `paths`.
  static func manifests(at paths: [String]) async throws -> FixtureServer {
    var files: [String: File] = [:]
    for path in paths {
      let service = "\(path)/page-1"
      files[path] = File(
        contentType: "application/ld+json",
        body: Data(
          #"{"type":"Manifest","label":{"none":["Web tests"]},"items":[{"type":"Canvas","width":1000,"height":1400,"label":{"none":["p1"]},"items":[{"items":[{"body":{"id":"\#(service)/full/max/0/default.jpg","service":[{"id":"\#(service)"}]}}]}]}]}"#
            .utf8))
    }
    return try await FixtureServer(files: files)
  }

  /// A locally served, identified three-page witness. Configured before any
  /// caller receives the server; no live data or external host is involved.
  static func formulationManifest() async throws -> FixtureServer {
    let server = try await FixtureServer(files: [:])
    let base = server.baseURL
    let items = (1...3).map { n in
      #"{"id":"\#(base)/canvas/\#(n)","type":"Canvas","width":800,"height":1100,"label":{"en":["\#(n == 3 ? "Colophon" : "Title page")"]},"items":[{"type":"AnnotationPage","items":[{"body":{"id":"\#(base)/page-\#(n)/full/max/0/default.jpg","service":[{"id":"\#(base)/page-\#(n)","type":"ImageService3"}]}}]}]}"#
    }.joined(separator: ",")
    var files: [String: File] = ["/manifest.json": .init(contentType: "application/json", body: Data(#"{"id":"\#(base)/manifest.json","type":"Manifest","label":{"en":["Evidence test"]},"items":[\#(items)]}"#.utf8))]
    for n in 1...3 {
      files["/page-\(n)/info.json"] = .init(contentType: "application/json", body: Data(#"{"@context":"http://iiif.io/api/image/3/context.json","id":"\#(base)/page-\#(n)","type":"ImageService3","protocol":"http://iiif.io/api/image","profile":"level0","width":800,"height":1100}"#.utf8))
      files["/page-\(n)/*"] = .init(contentType: "image/svg+xml", body: Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="800" height="1100"><rect width="800" height="1100" fill="white"/><text x="80" y="100">Evidence fixture \#(n)</text></svg>"#.utf8))
    }
    server.files = files
    return server
  }

  private func serve(_ connection: NWConnection) {
    connection.start(queue: queue)
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [files] data, _, _, _ in
      let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
      let target = request.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init) ?? "/"
      let path = String(target.split(separator: "?", maxSplits: 1).first ?? "/")
      let file = files[path] ?? files.first { key, _ in key.hasSuffix("*") && path.hasPrefix(String(key.dropLast())) }?.value
      let status = file == nil ? "404 Not Found" : "200 OK"
      let body = file?.body ?? Data("Not found".utf8)
      var head = "HTTP/1.1 \(status)\r\n"
      head += "Content-Type: \(file?.contentType ?? "text/plain")\r\n"
      head += "Access-Control-Allow-Origin: *\r\n"
      head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
      connection.send(
        content: Data(head.utf8) + body,
        completion: .contentProcessed { _ in connection.cancel() })
    }
  }

  /// Resumes a continuation once, whatever states follow.
  private final class Resumed: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
      lock.lock()
      defer { lock.unlock() }
      if done { return false }
      done = true
      return true
    }
  }
}
