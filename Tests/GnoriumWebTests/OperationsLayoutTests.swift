import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Geometry of actual server-rendered components, exported by the native
/// OperationsRendering fixture test. No accounts, DB writes or model calls.
@Suite("Operations layout", .serialized)
struct OperationsLayoutTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func disclosureAttachmentsRosterAndTimeline(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    guard let path = ProcessInfo.processInfo.environment["GNORIUM_OPERATIONS_FIXTURE_PATH"],
      FileManager.default.fileExists(atPath: path) else {
      try Test.cancel("Export the actual operations fixture with GNORIUM_OPERATIONS_FIXTURE_PATH first.")
    }
    let html = try Data(contentsOf: URL(fileURLWithPath: path))
    let fixture = try await FixtureServer(files: ["/operations.html": .init(contentType: "text/html", body: html)])
    defer { fixture.stop() }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.goto(fixture.baseURL + "/operations.html")
      try await expect(page.locator(".session-failed-alert")).toBeVisible()
      let disclosure = try await page.evaluate("""
        (() => {
          const alert = document.querySelector('.session-failed-alert.alert-red');
          const message = alert?.querySelector('.alert-content');
          if (!message) return false;
          const a = getComputedStyle(alert), m = getComputedStyle(message);
          return message.closest('.alert-content') !== null
            && !alert.querySelector('.accordion-view, pre')
            && parseFloat(a.borderTopWidth) > 0
            && a.backgroundColor !== 'rgba(0, 0, 0, 0)'
            && parseFloat(m.fontSize) === 14
            && Number(m.fontWeight) === 400
            && message.textContent.includes('(')
            && message.textContent.includes('NIOHTTP1.HTTPParserError');
        })()
        """, as: Bool.self)
      #expect(disclosure, "One normal-weight message includes diagnostics in parentheses inside the red alert")
      let attachments = try await page.evaluate("""
        (() => {
          const group = document.querySelector('.session-input-attachments');
          const cards = [...group.children].map(el => el.getBoundingClientRect());
          const s = getComputedStyle(group), rect = group.getBoundingClientRect();
          if (cards.length !== 2 || s.flexDirection !== 'row' || s.flexWrap !== 'wrap') return false;
          const room = cards.reduce((sum, card) => sum + card.width, 0) + parseFloat(s.columnGap);
          const fits = room <= rect.width + 1;
          return (!fits || Math.abs(cards[0].top - cards[1].top) <= 1)
            && cards.every(card => card.left >= rect.left - 1 && card.right <= rect.right + 1);
        })()
        """, as: Bool.self)
      #expect(attachments, "Attachments share a row whenever they fit and wrap without overflowing")
      if layout == .desktop {
        let oneRow = try await page.evaluate("""
          (() => { const cards = [...document.querySelector('.session-input-attachments').children];
            return Math.abs(cards[0].getBoundingClientRect().top - cards[1].getBoundingClientRect().top) <= 1; })()
          """, as: Bool.self)
        #expect(oneRow, "Wide screens use one attachment row")
      }
      let roster = try await page.evaluate("""
        (() => {
          const roster = document.querySelector('#fixture-semblances');
          const search = roster?.querySelector('.roster-search-input-wrapper');
          const list = roster?.closest('.mission-control-sidebar-list');
          if (!search || !list) return false;
          const box = roster.querySelector('.roster-search-input .search-input');
          return box.placeholder === 'Search semblances'
            && getComputedStyle(box).fontSize === '16px'
            && parseFloat(getComputedStyle(search).borderBottomWidth) === 0
            && getComputedStyle(list).rowGap === '16px';
        })()
        """, as: Bool.self)
      #expect(roster, "Semblance search is a 16px search input with no divider; sidebar sections use 16px spacing")
      try await expect(page.locator(".locution-thread-count")).toHaveText("1")
      try await expect(page.locator(".locution-thread-event")).toHaveCount(1)
      let events = try await page.evaluate("""
        (() => {
          const line = document.querySelector('.locution-thread-event-line');
          const css = getComputedStyle(line);
          return css.marginTop === '0px' && css.marginBottom === '0px'
            && line.innerText.includes('fixture-admin created Bibliographic madrigal.');
        })()
        """, as: Bool.self)
      #expect(events, "Creation is one timeline entry with normal sentence spacing and no paragraph margins")
      try await page.expectNoHorizontalOverflow()
    }
  }
}
