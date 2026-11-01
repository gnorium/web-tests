import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A sentiment's quotes sit in Source boxes (user, 2026-11-01), the same
/// pattern as the Voice and Agent boxes: each legended "Source", its fields
/// in order Source (a permitted record › testament, asked for as the page
/// opens, or a Source URL), its Images start and optional Images end (the
/// start or the next), Quote (one sentence). "+ Source" stamps
/// another from the page's template, each "− Source" shown while there is
/// more than one; the boxes' keys post in order. No Image URL field, and
/// no "range" anywhere in the form.
@Suite("Quote sources")
struct QuoteSourcesTests {
  static let sentimentForm = "/mission-control/submit/lexicographic/sentiment"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func aSentimentsQuotesSitInSourceBoxes(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated(Self.sentimentForm)
      let sources = page.locator(".submit-sentiment-form .quote-sources-view")
      let boxes = sources.locator(".quote-source")
      try await expect(boxes).toHaveCount(1)
      let first = boxes.first
      try await expect(first.locator(".form-item-legend").first).toHaveText("Source")
      // Its record field, asked for as the page opens: Record, then
      // Testament once a record is picked.
      try await expect(first.locator(".quote-passage-record .origin-record-field-view"), timeout: .seconds(15))
        .toHaveCount(1)
      try await expect(first.locator(".quote-passage-record input[name='quote-s1-record']")).toHaveCount(1)
      // No Image URL; Source, Images, Quote in that order.
      try await expect(sources.locator("[name$='image-url']")).toHaveCount(0)
      let order = try await first.evaluate(
        """
        (box) => ['.quote-passage-record', "[name='quote-s1-source-url']", "[name='quote-s1-start-image']",
          "[name='quote-s1-end-image']", "[name='quote-s1-quote']"]
          .map((s) => box.querySelector(s))
          .every((el, i, all) => el && (i === 0 || (all[i - 1].compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING)))
        """
      ).bool
      #expect(order == true, "the Source box reads Source, Images, Quote")
      let text = try await sources.evaluate("(el) => el.textContent.toLowerCase()").string ?? ""
      #expect(!text.contains("range"), "the Source box says range")
      // One box: no "− Source".
      try await expect(first.locator(".quote-source-remove-btn")).toBeHidden()

      // "+ Source": a second box at once, both removable, the keys in order.
      let add = sources.locator(".quote-sources-add-btn")
      try await expect(add).toHaveText("Source")
      try await expect(add).toHaveAttribute("aria-label", "Add source")
      try await add.click()
      try await expect(boxes).toHaveCount(2)
      let second = boxes.nth(1)
      try await expect(second.locator(".form-item-legend").first).toHaveText("Source")
      try await expect(second.locator(".quote-passage-record .origin-record-field-view"), timeout: .seconds(15))
        .toHaveCount(1)
      let keys = sources.locator("input[name='quote-keys']")
      let key = try await second.getAttribute("data-quote-source-key") ?? ""
      #expect(key.hasPrefix("quote-sn"), "a stamped box's key: \(key)")
      try await expect(keys).toHaveValue("quote-s1,\(key)")
      try await expect(first.locator(".quote-source-remove-btn")).toBeVisible()
      try await expect(second.locator(".quote-source-remove-btn")).toBeVisible()
      try await expect(second.locator(".quote-source-remove-btn")).toHaveAttribute("aria-label", "Remove source")
      try await page.expectNoHorizontalOverflow()

      // "− Source": the first goes, the second stays, alone again.
      try await first.locator(".quote-source-remove-btn").click()
      try await expect(boxes).toHaveCount(1)
      try await expect(keys).toHaveValue(key)
      try await expect(boxes.first.locator(".quote-source-remove-btn")).toBeHidden()
      try await page.expectNoErrors()
    }
  }

  /// A testament's digitization has the same Source box: its Source URL,
  /// then its Images start and Images end, frozen (its source's first and
  /// last, filled once the Source URL is read), and no Quote.
  @Test(arguments: gnorium.engines)
  func aTestamentsDigitizationHasASourceBox(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine)) { page in
      try await page.openHydrated("/mission-control/submit/bibliographic/testament")
      let box = page.locator(".testament-source")
      try await expect(box).toHaveCount(1)
      try await expect(box.locator(".form-item-legend").first).toHaveText("Source")
      let shape = try await box.evaluate(
        """
        (b) => {
          const url = b.querySelector("[name='source-url']"), start = b.querySelector("[name='testament-start-image']"),
            end = b.querySelector("[name='testament-end-image']");
          return !!url && !!start && !!end && !b.querySelector("textarea") && start.disabled && end.disabled
            && !!(url.compareDocumentPosition(start) & Node.DOCUMENT_POSITION_FOLLOWING)
            && !!(start.compareDocumentPosition(end) & Node.DOCUMENT_POSITION_FOLLOWING) && start.value === '';
        }
        """
      ).bool
      #expect(shape == true, "Source URL, then Images start and Images end frozen and empty until it is read, and no Quote")
      try await page.expectNoErrors()
    }
  }
}
