import Foundation
import WebTests
import WebTestsTesting

/// The Gnorium server under test: this run's own (`WebTestServer`: its own
/// database and process, never the dev server or gnorium_dev), on the engines
/// in `BROWSERS` (default chrome; safari only when named).
let gnorium: BrowserTestConfiguration = {
  var configuration = BrowserTestConfiguration.fromEnvironment(
    prefix: "GNORIUM", defaultBaseURL: WebTestServer.baseURL.absoluteString)
  configuration.baseURL = WebTestServer.baseURL
  return configuration
}()

/// The layouts every page must hold up in.
enum Layout: String, CaseIterable, Sendable, CustomStringConvertible {
  /// A 375-wide phone: touch in Chrome, a narrow mouse window in Safari.
  case phone
  case desktop

  func viewport(for engine: BrowserEngine) -> Viewport {
    switch self {
    case .phone: return engine == .chrome ? .phone : .narrow
    case .desktop: return .desktop
    }
  }

  var description: String { rawValue }
}

/// Every engine against every layout, for parameterised tests.
let enginesAndLayouts: [(BrowserEngine, Layout)] = gnorium.engines.flatMap { engine in
  Layout.allCases.map { (engine, $0) }
}
