import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The Origin field on Submit Testament: its date is the work date model (an
/// exact date offers Month and Day, posted in `origins-json`); "+ Origin",
/// "+ Origin 1.1" and "+ Quote" stamp their rows from the page's templates,
/// so each is there within one frame of the click, its own date with a Month
/// and a Day; and a native name in another script never waits on Noto's
/// symbol faces.
@Suite("Origin form stamps")
struct OriginFormStampTests {
  static let form = "/mission-control/submit/bibliographic/testament"

  /// What a click leaves within one animation frame: rows added.
  static func addedWithinAFrame(_ selector: String, _ rows: String) -> String {
    """
    new Promise((done) => {
      const count = () => document.querySelectorAll(\(rows)).length;
      const before = count();
      document.querySelector(\(selector)).click();
      requestAnimationFrame(() => done(count() - before));
    })
    """
  }

  @Test(arguments: gnorium.engines)
  func originsHaveMonthAndDayAndAddAtOnce(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated(Self.form)
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.openHydrated(Self.form)
      let field = page.locator(".origin-field-view").first
      let rows = field.locator("[data-origin-row='true']")
      try await expect(rows).toHaveCount(1)
      let row = rows.first
      let key = try #require(try await row.getAttribute("data-origin-key"))

      // An exact date offers a Month and a Day, as a work's date does.
      let date = row.locator(".form-date-view")
      try await expect(date.locator(".form-date-month-group")).toHaveCount(1)
      try await expect(date.locator(".form-date-day-group")).toHaveCount(1)
      let qualifier = date.locator(".dropdown-view:has(#\(key)-year-qualifier)")
      try await qualifier.locator(".dropdown-trigger").click()
      try await qualifier.locator(".dropdown-option[data-value='exact']").filter(visible: true).first.click()
      try await expect(date.locator(".form-date-month-group")).toBeVisible()
      try await expect(date.locator(".form-date-day-group")).toBeVisible()
      try await row.locator("#\(key)-title").fill("Web tests origin dated")
      try await row.locator("input[name='\(key)-year']").fill("1754")
      let month = date.locator(".dropdown-view:has(#\(key)-month)")
      try await month.locator(".dropdown-trigger").click()
      try await month.locator(".dropdown-option[data-value='january']").filter(visible: true).first.click()
      try await row.locator("input[name='\(key)-day']").fill("28")
      let json = field.locator("input[name='origins-json']")
      let posted = try await json.inputValue()
      #expect(posted.contains("\"month\":\"january\",\"day\":28"))

      // "+ Origin": the new step is there within one frame of the click,
      // with its own Month and Day.
      let added = try await page.evaluate(
        Self.addedWithinAFrame(
          "'.origin-field-view .origin-field-add .origin-add-btn'", "'.origin-field-view [data-origin-row=\"true\"]'"), as: Int.self)
      #expect(added == 1)
      try await expect(rows).toHaveCount(2)
      let second = try #require(try await rows.nth(1).getAttribute("data-origin-key"))
      #expect(second != key)
      try await expect(rows.nth(1).locator("input[name='\(second)-day']")).toHaveCount(1)
      try await expect(rows.nth(1).locator("input[name='\(second)-month']")).toHaveCount(1)
      // Its controls bound: its date's qualifier works.
      let secondQualifier = rows.nth(1).locator(".dropdown-view:has(#\(second)-year-qualifier)")
      try await secondQualifier.locator(".dropdown-trigger").click()
      try await secondQualifier.locator(".dropdown-option[data-value='exact']").filter(visible: true).first.click()
      try await expect(rows.nth(1).locator(".form-date-day-group")).toBeVisible()

      // "+ Origin 2.1": a step under it, at once too.
      let nested = try await page.evaluate(
        Self.addedWithinAFrame(
          "'button[aria-label=\"Add Origin 2.1.\"]'", "'.origin-field-view [data-origin-row=\"true\"]'"), as: Int.self)
      #expect(nested == 1)
      try await expect(rows).toHaveCount(3)

      // No quotes yet: the empty list takes no gap above "+ Quote".
      try await expect(row.locator(".origin-field-quotes")).toHaveCSS("display", "none")
      // "+ Quote": its box, legended, at once.
      let quotes = try await page.evaluate(
        Self.addedWithinAFrame(
          "'.origin-field-view [data-origin-row=\"true\"] .origin-add-quote-btn'",
          "'.origin-field-view .origin-quote-field-view'"), as: Int.self)
      #expect(quotes == 1)
      try await expect(field.locator(".origin-quote-field-view .form-item-legend").first).toHaveText("Quote")
      try await expect(field.locator(".origin-quote-field-view .origin-quote-remove-btn")).toHaveCount(1)
    }
  }

  /// A native name in another script never waits on Noto's symbol faces:
  /// their ranges leave it out, so nothing is left to load for it.
  @Test(arguments: gnorium.engines)
  func nativeNamesWaitOnNoSymbolFace(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated(Self.form)
      let ready = try await page.evaluate(
        "document.fonts.check('16px \"Noto Sans Symbols\", \"Noto Sans Symbols 2\"', 'हिन्दी 中文 العربية ქართული')",
        as: Bool.self)
      #expect(ready)
    }
  }
}
