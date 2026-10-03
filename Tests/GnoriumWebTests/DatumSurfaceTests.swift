import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Read-only datum backgrounds", .serialized)
struct DatumSurfaceTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func labelsStayTransparentAndValuesKeepDisabledBackground(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    guard let path = ProcessInfo.processInfo.environment["GNORIUM_DATUM_SURFACE_FIXTURE_PATH"] else {
      try Test.cancel("Export the actual DatumSurfaceFixtureTests page first.")
    }
    let name = "datum-surface-\(UUID().uuidString).html"
    let file = URL(fileURLWithPath: "/Users/Madhavik/Downloads/Gnorium/gnorium-web/Public").appendingPathComponent(name)
    try Data(contentsOf: URL(fileURLWithPath: path)).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/\(name)")
      let colors = try await page.evaluate("""
        (() => {
          const root = document.querySelector('#datum-surface-fixture');
          const color = s => getComputedStyle(root.querySelector(s)).backgroundColor;
          const clear = c => c === 'rgba(0, 0, 0, 0)' || c === 'transparent';
          const gray = color('.gray-frame');
          const white = color('.white-frame');
          return gray !== white && !clear(gray) && !clear(white)
            && [...root.querySelectorAll('.datum-view, .datum-label')].every(e => clear(getComputedStyle(e).backgroundColor))
            && [...root.querySelectorAll('.datum-value')].every(e =>
              getComputedStyle(e).backgroundColor === color('#disabled-reference'))
            && !root.querySelector('.datum-value.surface')
            && color('.root-datum > .datum-value') !== white
            && color('.frozen-frame') === gray
            && color('.root-card') === gray && color('.nested-card') === white;
        })()
        """, as: Bool.self)
      #expect(colors, "Read-only datum values match disabled controls at every depth while labels stay transparent")
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }
}
