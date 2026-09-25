import Foundation
import WebTests
import WebTestsTesting

/// The Gnorium dev server under test: `GNORIUM_BASE_URL` (default
/// http://localhost:8080) on the engines in `GNORIUM_BROWSERS` (default
/// chrome,safari).
let gnorium = BrowserTestConfiguration.fromEnvironment(prefix: "GNORIUM", defaultBaseURL: "http://localhost:8080")

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
