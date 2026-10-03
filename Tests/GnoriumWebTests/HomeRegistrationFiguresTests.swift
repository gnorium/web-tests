import Testing
import WebTests
import WebTestsTesting

@Suite("Public weekly registration figures", .serialized)
struct HomeRegistrationFiguresTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func weeklyCardsAndChartsShareThreeColumnsAndDates(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/")
      let region = page.locator(".watchtower-visitors-view")
      try await expect(region).toContainText("Registrations this week")
      try await expect(region).toContainText("Registrations last week")
      try await expect(page.locator(".watchtower-visitors-trend")).toHaveCount(3)
      #expect(try await page.evaluate("""
        (()=>{const cards=document.querySelector('.watchtower-visitors-cards');
          const c=[...cards.children].map(e=>e.getBoundingClientRect());
          const charts=[...document.querySelectorAll('.watchtower-visitors-trend')];
          const weeks=charts.map(e=>[...e.querySelectorAll('[data-week]')].map(w=>w.dataset.week));
          const chartRects=charts.map(e=>e.getBoundingClientRect());
          return chartRects.slice(1).every((r,i)=>r.top-chartRects[i].bottom>=23)
            && c.length===6 && Math.abs(c[0].top-c[2].top)<2 && c[2].left>c[1].left
            && Math.abs(c[3].top-c[5].top)<2 && c[3].top>c[0].top
            && weeks.every(w=>w.length===52 && JSON.stringify(w)===JSON.stringify(weeks[0]))
            && charts.every(e=>e.getBoundingClientRect().width>0);})()
        """, as: Bool.self))
      try await expect(page.locator(".watchtower-visitors-how")).toContainText("How visitors, page views, and registrations are counted")
      try await expect(page.locator(".watchtower-visitors-how")).toHaveAttribute("href", "/privacy-policy#visitor-count")
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
      try await page.openHydrated("/privacy-policy#visitor-count")
      try await expect(page.locator("#visitor-count")).toContainText("Registrations count completed accounts")
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }
}
