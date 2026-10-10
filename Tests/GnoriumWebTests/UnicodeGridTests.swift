import Testing
import WebTests
import WebTestsTesting

@Suite("Full-width Unicode grid", .serialized)
struct UnicodeGridTests {
  struct BrandGeometry: Decodable {
    let available: Double
    let brand: Double
    let logo: Double
    let title: Double
    let search: Double
  }

  @Test
  func brandAndSearchKeepTheirInsetsOnSmallPhones() async throws {
    guard gnorium.engines.contains(.chrome) else { return }
    try await withPage(.chrome, gnorium, viewport: .init(width: 320, height: 568)) { page in
      try await page.openHydrated("/")
      for width in [320, 375, 1400] {
        try await page.setViewport(width: width, height: 900)
        let geometry = try await page.evaluate("""
          (() => {
            const width = selector => document.querySelector(selector).getBoundingClientRect().width;
            return {available: width('.home-hero'), brand: width('.home-brand'),
              logo: width('.home-brand .logo-view'), title: width('.home-brand .brand-title'),
              search: width('.home-search')};
          })()
          """, as: BrandGeometry.self)
        #expect(abs(geometry.brand - min(320, geometry.available - 64)) < 1)
        // The logo is its SVG's own 256 (user, 2026-10-10).
        #expect(abs(geometry.logo - min(256, geometry.brand)) < 1)
        #expect(geometry.title <= geometry.brand)
        #expect(abs(geometry.search - min(640, geometry.available - 64)) < 1)
        try await page.expectNoHorizontalOverflow()
      }
    }
  }

  struct Geometry: Decodable {
    let initialBalanced: Bool
    let initialUnique: Int
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
            const initialValues = Array.from(grid.children, c => c.textContent);
            const beforeUnique = new Set(initialValues).size;
            const capacities = grid.dataset.scriptCapacities.split(',').map(Number);
            const counts = capacities.map(() => 0);
            for (const cell of grid.children) counts[Number(cell.dataset.script)]++;
            const minimum = Math.min(...counts.filter((count, index) => count < capacities[index]));
            const initialBalanced = counts.every(count => count <= minimum + 1);
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
              initialBalanced, initialUnique: beforeUnique,
              columns: Math.floor(parent.clientWidth / 32), rows: Math.floor(parent.clientHeight / 32),
              count: grid.children.length,
              unique: new Set(Array.from(grid.children, cell => cell.textContent)).size,
              width: grid.getBoundingClientRect().width, parentWidth: parent.clientWidth,
              gap: getComputedStyle(document.querySelector('.home-content-outer')).rowGap
            };
          })()
          """, as: Geometry.self)
        #expect(size.initialBalanced)
        #expect(size.initialUnique == size.count)
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
