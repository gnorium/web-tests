import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Code panel", .serialized)
struct CodePanelTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func rawFileHasOneRoundedScrollSurface(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let longText = String(repeating: "long_identifier_", count: 120)
    let tei = "<TEI xmlns=\"http://www.tei-c.org/ns/1.0\"><text><body><pb n=\"1\" facs=\"https://example.org/code-fixture/full/max/0/default.jpg\"/>"
      + (1...150).map { "<p><s><w lemma=\"\(longText)\" pos=\"NOUN\">Token \($0)</w></s></p>" }.joined(separator: "\n")
      + "</body></text></TEI>"
    let reading = try ScratchReading(owner: admin, tei: tei)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(reading.path)
        try await page.locator("#notation-raw-xml .accordion-summary").click()
        try await expect(page.locator(".notation-raw-xml-body .code-view")).toBeVisible()
        // Wait on geometry, not an arbitrary animation delay.
        let coherent = try await page.evaluate("""
          new Promise(resolve => {
            let attempts = 0;
            function check() {
              const pane = document.querySelector('.notation-raw-xml-body');
              if (pane.getBoundingClientRect().height > 100 || attempts++ > 90) return resolve(true);
              requestAnimationFrame(check);
            }
            check();
          })
          """, as: Bool.self)
        #expect(coherent)
        let geometry = try await page.evaluate("""
          (() => {
            const pane = document.querySelector('.notation-raw-xml-body');
            const code = pane.querySelector('.code-view');
            const gutter = code.querySelector('.code-view-gutter');
            const ps = getComputedStyle(pane), cs = getComputedStyle(code), gs = getComputedStyle(gutter);
            return ps.backgroundColor === cs.backgroundColor && cs.backgroundColor === gs.backgroundColor
              && parseFloat(ps.borderRadius) > 0 && parseFloat(ps.paddingLeft) === 16
              && pane.scrollWidth > pane.clientWidth && pane.scrollHeight > pane.clientHeight
              && pane.getBoundingClientRect().height <= 481
              && cs.overflowX === 'visible' && cs.paddingLeft === '0px';
          })()
          """, as: Bool.self)
        #expect(geometry, "one scroll owner clips rounded, consistently colored code and gutter")
        let intact = try await page.evaluate("""
          document.querySelector('.notation-raw-xml-body .code-view-code').textContent.includes('\(longText)')
          """, as: Bool.self)
        #expect(intact, "long XML identifiers are preserved; they scroll without wrapping or truncation")
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      reading.remove()
      try await admin.remove(after: error)
    }
    reading.remove()
    try await admin.remove()
  }
}
