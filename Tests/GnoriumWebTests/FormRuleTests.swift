import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A submission form is the record page in edit mode: its switches sit on
/// the record page's rule under its header (`ApparatusRuleView`), never in the
/// header: Submit Testament and Submit Sentiment. Pressed, Verbose opens
/// every accordion; it sits inside the record's column at every width.
@Suite("Form rule", .serialized)
struct FormRuleTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func theVerboseSwitchIsOnARuleUnderTheHeader(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        for (path, card) in [
          ("/mission-control/submit/bibliographic/evidence-testament", ".submit-testament-form .record-view"),
          ("/mission-control/submit/lexicographic/evidence-sentiment", ".submit-sentiment-form .record-view"),
        ] {
          try await page.openHydrated(path)
          try await check(page, card: card)
        }
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }

  private func check(_ page: Page, card: String) async throws {
    let box = page.locator(card)
    try await expect(box.locator(".form-header-view .verbose-toggle-button-view")).toHaveCount(0)
    try await expect(box.locator(":scope > .record-identity > .apparatus-rule-view")).toHaveCount(1)
    try await expect(box.locator(":scope > .record-identity > .apparatus-rule-view .verbose-toggle-button-view"))
      .toHaveCount(1)
    // The rule straight under the header, the switch within the card.
    let placed = try await box.evaluate(
      """
      (card) => {
        const header = card.querySelector(':scope > .record-identity > .form-header-view');
        const rule = card.querySelector(':scope > .record-identity > .apparatus-rule-view');
        const toggle = rule.querySelector('.verbose-toggle-button-control').getBoundingClientRect();
        const outer = card.getBoundingClientRect();
        return {
          next: header.nextElementSibling === rule,
          inside: toggle.right <= outer.right && toggle.left >= outer.left,
          onRule: Math.abs((toggle.top + toggle.bottom) / 2 - rule.getBoundingClientRect().top) < 4,
        };
      }
      """)
    #expect(placed["next"].bool == true, "the rule is not straight under the header")
    #expect(placed["inside"].bool == true, "the switch leaves the record's column")
    #expect(placed["onRule"].bool == true, "the switch is not on the rule")
    // Pressed, every accordion opens: the new node's, closed by hand first.
    let control = box.locator(".apparatus-rule-view .verbose-toggle-button-control")
    try await box.locator("[data-submission-draft='true'] .record-row > .accordion-details > .accordion-summary")
      .first.click()
    try await expect(box.locator(".accordion-details[data-expanded='false']").first).toBeAttached()
    try await expect(control).toHaveAttribute("aria-pressed", "false")
    try await control.click()
    try await expect(control).toHaveAttribute("aria-pressed", "true")
    try await expect(box.locator(".accordion-details[data-expanded='false']")).toHaveCount(0)
  }
}
