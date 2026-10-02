import Testing
import WebTests
import WebTestsTesting

@Suite("Full-width Unicode grid", .serialized)
struct UnicodeGridTests {
  struct Geometry: Decodable {
    let columns: Int
    let rows: Int
    let count: Int
    let unique: Int
    let width: Double
    let parentWidth: Double
    let gap: String
  }

  @Test
  func fitsSixKAndShrinksBackToPhone() async throws {
    guard gnorium.engines.contains(.chrome) else { return }
    try await withPage(.chrome, gnorium, viewport: .init(width: 3008, height: 1692)) { page in
      try await page.openHydrated("/")
      for (width, height) in [(3008, 1692), (6016, 3384), (390, 844)] {
        try await page.setViewport(width: width, height: height)
        let size = try await page.evaluate("""
          (async () => {
            await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
            const grid = document.querySelector('.unicode-grid-view');
            const parent = grid.parentElement;
            // Exercise the actual pointer handler before the next resize. The
            // old whole-pool cycle introduced duplicates after pointer moves.
            const rect = grid.getBoundingClientRect();
            for (let pass = 0; pass < 3; pass++) {
              for (let y = 16; y < rect.height; y += 256) {
                for (let x = 16; x < rect.width; x += 256) {
                  document.dispatchEvent(new MouseEvent('mousemove', {
                    clientX: rect.x + x, clientY: rect.y + y, bubbles: true
                  }));
                }
              }
            }
            return {
              columns: Math.floor(parent.clientWidth / 32), rows: Math.floor(parent.clientHeight / 32),
              count: grid.children.length,
              unique: new Set(Array.from(grid.children, cell => cell.textContent)).size,
              width: grid.getBoundingClientRect().width, parentWidth: parent.clientWidth,
              gap: getComputedStyle(document.querySelector('.home-content-outer')).rowGap
            };
          })()
          """, as: Geometry.self)
        #expect(size.count == size.columns * size.rows)
        #expect(size.unique == size.count)
        #expect(size.width == Double(size.columns * 32))
        #expect(size.parentWidth - size.width < 32)
        #expect(size.gap == "16px")
        try await page.expectNoHorizontalOverflow()
      }
    }
  }
}
