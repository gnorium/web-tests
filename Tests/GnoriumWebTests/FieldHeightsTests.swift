import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Every control of a row ends the same height (user, 2026-10-21): a large
/// control is 48, and steps down one size on a phone, to 40—the dropdown
/// trigger, a text input, a date and a time field alike, none left at 48
/// beside a trigger at 40. Read on Submit Testament, whose rows hold all of
/// them. Needs an admin, made for the test and removed after (see
/// `TestAdmin`).
@Suite("Field heights", .serialized)
struct FieldHeightsTests {
  static let form = "/mission-control/submit/bibliographic/testament"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func fieldsStepDownTogetherOnAPhone(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(Self.form)
        let heights = try await page.evaluate(
          """
          (() => {
            const box = (selector) => [...document.querySelectorAll(selector)]
              .filter(e => e.getBoundingClientRect().height > 0)
              .map(e => Math.round(e.getBoundingClientRect().height));
            return {
              text: box('.submit-testament-form .text-input-input'),
              trigger: box('.submit-testament-form .dropdown-trigger'),
            };
          })()
          """, as: [String: [Int]].self)
        let triggers = Set(heights["trigger"] ?? [])
        let texts = Set(heights["text"] ?? [])
        #expect(triggers.count == 1, "Dropdown triggers share a height: \(triggers)")
        #expect(texts.count == 1, "Text inputs share a height: \(texts)")
        #expect(triggers == texts, "Triggers \(triggers) and text inputs \(texts) end the same height")
        let phone = try await page.controlSize("large") == "medium"
        #expect(texts == [phone ? 40 : 48], "Fields are \(phone ? 40 : 48) here: \(texts)")
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }
}
