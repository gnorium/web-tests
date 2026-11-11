import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A kept draft (`ActionGateView.keepsDraft`) puts back the Sources and
/// Quote cards a form added (user, 2026-11-03), not only their fields:
/// Submit Sentiment's Source boxes, each with its Quote cards and the quote
/// typed in each; Submit Testament's citation of a copy's former owner, its
/// claim the owner's row (back with its id), its Quote cards and their
/// Certainty, and an origin step's citation; each posted again as before.
/// Signed out: the forms are drawn and kept the same, nothing is posted.
@Suite("Draft sources")
struct DraftSourcesTests {
  static let sentimentForm = "/mission-control/submit/lexicographic/sentiment"
  static let testamentForm = "/mission-control/submit/bibliographic/testament"

  /// The draft kept for this page once it holds `text`.
  static func kept(_ page: Page, holding text: String) async throws -> String {
    var kept = ""
    for _ in 0..<24 {
      kept = try await page.evaluate("localStorage.getItem('gnorium:draft:' + location.pathname) || ''", as: String.self)
      if kept.contains(text) { break }
      try await Task.sleep(for: .milliseconds(250))
    }
    return kept
  }

  /// The value of the field `selector` names once it holds `text`.
  static func posted(_ page: Page, _ selector: String, holding text: String) async throws -> String {
    var value = ""
    for _ in 0..<24 {
      value = try await page.locator(selector).evaluate("(i) => i.value").string ?? ""
      if value.contains(text) { break }
      try await Task.sleep(for: .milliseconds(250))
    }
    return value
  }

  static func cards(_ source: Locator) -> Locator { source.locator(".quote-passage-quotes > .quote-passage-quote") }
  static func pane(_ card: Locator) -> Locator { card.locator(".quote-passage-text .tei-page-text") }

  @Test(arguments: [BrowserEngine.chrome])
  func aSentimentsSourcesAndQuotesComeBack(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated(Self.sentimentForm)
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.openHydrated(Self.sentimentForm)

      let sources = page.locator(".submit-sentiment-form .quote-sources-view")
      let boxes = sources.locator(".quote-source")
      let first = boxes.first
      // A sourceless work: its Title typed, two quotes, each typed in its
      // own card's text-only reader.
      try await first.locator("input[name='quote-s1-source-url-title']").fill("Web tests draft work")
      try await expect(Self.pane(Self.cards(first).first), timeout: .seconds(15)).toBeAttached()
      try await Self.pane(Self.cards(first).first).fill("The first kept quote.")
      try await first.locator(".quote-passage-actions .quote-passage-quote-add").click()
      try await expect(Self.cards(first)).toHaveCount(2)
      try await expect(Self.pane(Self.cards(first).nth(1)), timeout: .seconds(15)).toBeAttached()
      try await Self.pane(Self.cards(first).nth(1)).fill("The second kept quote.")
      // Its second quote's form picked (user, 2026-11-03), by place.
      try await page.addForm(in: first, from: ".quote-passage-quote:nth-child(2) .quote-typed-word[data-typed-word='2']")
      try await expect(first.locator("input[name='quote-s1-forms']"))
        .toHaveValue(#"[[],[[{"surface":"second","word":2}]]]"#)
      // A second Source, its own quote.
      try await sources.locator(".quote-sources-add-btn").click()
      try await expect(boxes).toHaveCount(2)
      let second = boxes.nth(1)
      let key = try #require(try await second.getAttribute("data-quote-source-key"))
      try await second.locator("input[name='\(key)-source-url-title']").fill("Web tests draft other work")
      try await expect(Self.pane(Self.cards(second).first), timeout: .seconds(15)).toBeAttached()
      try await Self.pane(Self.cards(second).first).fill("A quote of the other work.")

      let kept = try await Self.kept(page, holding: "A quote of the other work.")
      #expect(kept.contains("rows:quote-lists") && kept.contains("rows:quote-cards"), "the draft records the boxes and cards")

      _ = try await page.reload()
      try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")

      // Both boxes back, each its cards, each card its quote in its reader.
      try await expect(boxes, timeout: .seconds(15)).toHaveCount(2)
      try await expect(boxes.nth(1)).toHaveAttribute("data-quote-source-key", key)
      try await expect(first.locator("input[name='quote-s1-source-url-title']")).toHaveValue("Web tests draft work")
      try await expect(second.locator("input[name='\(key)-source-url-title']")).toHaveValue("Web tests draft other work")
      try await expect(Self.cards(first)).toHaveCount(2)
      try await expect(Self.pane(Self.cards(first).first), timeout: .seconds(15)).toHaveText("The first kept quote.")
      try await expect(Self.pane(Self.cards(first).nth(1)), timeout: .seconds(15)).toHaveText("The second kept quote.")
      try await expect(Self.cards(second)).toHaveCount(1)
      try await expect(Self.pane(Self.cards(second).first), timeout: .seconds(15)).toHaveText("A quote of the other work.")
      try await expect(first.locator(".quote-passage-quote-remove").first).toBeVisible()
      // Posted as before: every card's quote, a blank line between two.
      try await expect(first.locator("input[name='quote-s1-quote']"))
        .toHaveValue("The first kept quote.\n\nThe second kept quote.")
      try await expect(second.locator("input[name='\(key)-quote']")).toHaveValue("A quote of the other work.")
      // Its form back on the card that held it, magenta, posted as before.
      try await expect(Self.cards(first).nth(1).locator(".quote-typed-word[data-highlight='title']"), timeout: .seconds(15))
        .toHaveText("second")
      try await expect(Self.cards(first).first.locator("[data-highlight='title']")).toHaveCount(0)
      try await expect(first.locator("input[name='quote-s1-forms']"))
        .toHaveValue(#"[[],[[{"surface":"second","word":2}]]]"#)

      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.expectNoErrors()
    }
  }

  @Test(arguments: [BrowserEngine.chrome])
  func aCopysAndAStepsCitationsComeBack(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated(Self.testamentForm)
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.openHydrated(Self.testamentForm)

      // A former owner, its row's id what a claim names it by.
      let name = page.locator("input[name='former-owner-item1-text-input']")
      try await name.fill("Sir Henry Bunbury")
      let owner = page.locator("[data-item-list='former-owner'] > [data-item-section='true']").first
      let row = try #require(try await owner.getAttribute("data-row-id"))
      // The copy cites the owner: a sourceless work, two quotes, the second
      // only probable.
      let view = page.locator(".outgoing-citations-view:has(#outgoing-citations-5)")
      try await view.locator(".outgoing-citations-actions .outgoing-citations-add").click()
      let citations = view.locator(".outgoing-citations-list > .outgoing-citation-group")
      try await expect(citations).toHaveCount(1)
      let card = citations.first
      let claim = card.locator(".outgoing-citation-claim")
      try await claim.locator(".dropdown-trigger").click()
      try await claim.locator(".dropdown-option[data-value='formerOwners:\(row)']").filter(visible: true).first.click()
      let source = card.locator(".evidence-source-view")
      try await source.locator("input[name$='-source-url-title']").fill("A Catalogue of the Library")
      let quotes = Self.cards(source)
      try await expect(Self.pane(quotes.first), timeout: .seconds(15)).toBeAttached()
      try await Self.pane(quotes.first).fill("Bought of Sir Henry Bunbury.")
      try await source.locator(".quote-passage-actions .quote-passage-quote-add").click()
      try await expect(quotes).toHaveCount(2)
      try await expect(Self.pane(quotes.nth(1)), timeout: .seconds(15)).toBeAttached()
      try await Self.pane(quotes.nth(1)).fill("Sold by Sir Henry Bunbury.")
      // Origin 1 cites its own source, its claim the step itself.
      try await page.locator(".origin-field-view input[name='origin-1-title']").fill("Web tests draft origin")
      let step = page.locator(".origin-field-view [data-origin-row='true']").first
      let stepView = step.locator(".outgoing-citations-view")
      try await stepView.locator(".outgoing-citations-actions .outgoing-citations-add").click()
      let stepCitations = stepView.locator(".outgoing-citations-list > .outgoing-citation-group")
      try await expect(stepCitations).toHaveCount(1)
      let stepSource = stepCitations.first.locator(".evidence-source-view")
      try await stepSource.locator("input[name$='-source-url-title']").fill("A History of the Origin")
      try await expect(Self.pane(Self.cards(stepSource).first), timeout: .seconds(15)).toBeAttached()
      try await Self.pane(Self.cards(stepSource).first).fill("Translated from the Latin.")

      let kept = try await Self.kept(page, holding: "Translated from the Latin.")
      #expect(kept.contains("rows:citations") && kept.contains("rows:row-ids"), "the draft records the citations and rows")

      _ = try await page.reload()
      try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")

      // The owner back with its id; the copy's citation, its claim the
      // owner by name, its Source, both Quote cards and the second's
      // Certainty.
      try await expect(name, timeout: .seconds(15)).toHaveValue("Sir Henry Bunbury")
      try await expect(owner).toHaveAttribute("data-row-id", row)
      try await expect(citations, timeout: .seconds(15)).toHaveCount(1)
      try await expect(card.locator("input[name$='-claim']"), timeout: .seconds(15)).toHaveValue("formerOwners:\(row)")
      // The claim a trail (`BreadcrumbLabelView`): "Former owner", its
      // chevron, the owner's name.
      let chosen = claim.locator(".dropdown-selected-text .breadcrumb-label-view")
      try await expect(chosen.locator(".breadcrumb-label-context")).toHaveText("Former owner")
      try await expect(chosen.locator(".breadcrumb-separator-view")).toHaveCount(1)
      try await expect(chosen.locator(".breadcrumb-label-text")).toHaveText("Sir Henry Bunbury")
      try await expect(source.locator("input[name$='-source-url-title']")).toHaveValue("A Catalogue of the Library")
      try await expect(quotes).toHaveCount(2)
      try await expect(Self.pane(quotes.first), timeout: .seconds(15)).toHaveText("Bought of Sir Henry Bunbury.")
      try await expect(Self.pane(quotes.nth(1)), timeout: .seconds(15)).toHaveText("Sold by Sir Henry Bunbury.")
      // A quote asks no Certainty (user, 2026-11-11).
      try await expect(quotes.locator("input[name$='-certainty']")).toHaveCount(0)
      // Posted again as it was: the owner's row, both quotes, the second's
      // Certainty.
      let posted = try await Self.posted(page, "input[name='outgoing-citations-json-5']", holding: "Sold by Sir Henry Bunbury.")
      #expect(posted.contains("\"claim\":\"formerOwners:\(row)\""), "its claim: \(posted)")
      #expect(posted.contains("Bought of Sir Henry Bunbury.") && posted.contains("Sold by Sir Henry Bunbury."), "both quotes: \(posted)")
      #expect(!posted.contains("certaint"), "no quote's certainty is posted: \(posted)")
      // The step's citation back, posted in its row.
      try await expect(stepCitations).toHaveCount(1)
      try await expect(stepSource.locator("input[name$='-source-url-title']")).toHaveValue("A History of the Origin")
      try await expect(Self.pane(Self.cards(stepSource).first), timeout: .seconds(15))
        .toHaveText("Translated from the Latin.")
      let origins = try await Self.posted(page, "input[name='origins-json']", holding: "Translated from the Latin.")
      #expect(origins.contains("Translated from the Latin."), "the step posts its citation: \(origins)")

      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.expectNoErrors()
    }
  }
}
