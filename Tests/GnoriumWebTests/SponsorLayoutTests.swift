import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Public sponsorship layout", .serialized)
struct SponsorLayoutTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func publicReadingAndPooledSpending(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    guard let path = ProcessInfo.processInfo.environment["GNORIUM_SPONSOR_FIXTURE_PATH"],
      FileManager.default.fileExists(atPath: path) else {
      try Test.cancel("Export the actual SponsorGnoriumView fixture first.")
    }
    let name = "sponsor-layout-\(UUID().uuidString).html"
    let file = URL(fileURLWithPath: "/Users/Madhavik/Downloads/Gnorium/gnorium-web/Public").appendingPathComponent(name)
    try Data(contentsOf: URL(fileURLWithPath: path)).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/\(name)")
      try await expect(page.locator(".sponsor-content h1")).toHaveText("Sponsor Gnorium")
      try await expect(page.locator(".sponsor-content h2").first).toHaveText("Shared Sponsorship Pool")
      try await expect(page.locator(".sponsor-content")).toContainText("Online sponsorship is not available yet")
      try await expect(page.locator(".sponsor-content")).toContainText("$12.50")
      try await expect(page.locator(".sponsor-content a[href='/mission-control/antiphons/bibliographic/fixture-run']")).toHaveText("Bibliographic antiphon")
      let readable = try await page.evaluate("""
        (() => {
          const main = document.querySelector('main.sponsor-content');
          const summary = main.querySelector('.sponsor-summary');
          const links = [...document.querySelectorAll('footer a')];
          const last = links[links.length - 1];
          const rect = main.getBoundingClientRect();
          return getComputedStyle(main).rowGap === '24px'
            && getComputedStyle(summary).rowGap === '16px'
            && rect.width > 0
            && rect.left >= -1 && rect.right <= innerWidth + 1
            && !main.querySelector('form, textarea, input')
            && last?.textContent.trim() === 'Sponsor Gnorium'
            && last?.getAttribute('href') === '/sponsor-gnorium';
        })()
        """, as: Bool.self)
      if !readable {
        let diagnostic = try await page.evaluate("""
          (() => {
            const main = document.querySelector('main.sponsor-content');
            const summary = main.querySelector('.sponsor-summary');
            const last = [...document.querySelectorAll('footer a')].at(-1);
            const rect = main.getBoundingClientRect();
            return JSON.stringify({mainGap:getComputedStyle(main).rowGap,
              summaryGap:getComputedStyle(summary).rowGap,left:rect.left,right:rect.right,
              viewport:innerWidth,controls:!!main.querySelector('form,textarea,input'),
              footer:last?.textContent.trim(),href:last?.getAttribute('href')});
          })()
          """, as: String.self)
        print("Sponsor layout diagnostic: \(diagnostic)")
      }
      #expect(readable, "Public pooled accounting is readable without checkout or administrative controls")
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }
}
