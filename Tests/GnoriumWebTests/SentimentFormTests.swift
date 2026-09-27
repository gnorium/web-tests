import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Submit Sentiment, the parallel of Submit Testament: the record first
/// (Lexico-record, Language, Script, Title, Type, then the earliest
/// attestation's Voice, Date and Place, derived and disabled), the Sentiment
/// card (its derived fields, Definition, labels, Placement), then an
/// Utterance card per passage (its derived fields, the passage, "This passage
/// coins the word"). The cards open, framed, parted by the form's gap. A
/// passage said to coin the word makes the earliest voice its coiner; at most
/// one box is ticked. A picked lexico-record's tree goes in the Sentiment
/// card; unset, the pick's untouched values go and an edited one stays.
/// Nothing is submitted.
@Suite("Sentiment form", .serialized)
struct SentimentFormTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func theRecordTheSentimentAndEachUtterance(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    if let reason = await ScratchPassage.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let passage = try await ScratchPassage(owner: admin)
    let word = try ScratchWord(owner: admin)
    do {
      try await run(engine: engine, layout: layout, admin: admin, passage: passage, word: word)
    } catch {
      word.remove()
      passage.remove()
      await admin.remove()
      throw error
    }
    word.remove()
    passage.remove()
    await admin.remove()
  }

  private func run(
    engine: BrowserEngine, layout: Layout, admin: TestAdmin, passage: ScratchPassage, word: ScratchWord
  ) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
      try await page.openHydrated(passage.formPath)
      let form = page.locator(".submit-sentiment-form")
      try await shoot(page, "top", layout)

      // The record, then the Sentiment card, then the two Utterance cards.
      let order = try await form.evaluate(
        """
        (form) => {
          const chain = [
            '.record-choice-field-view', '#language', '#script', '#title', '#type',
            "[data-derived-scope='record-derived']", '#sentiment-accordion',
            "[data-derived-scope='sentiment-derived']", '#definition', '#label-register', '#label-domain',
            '#label-region', '#label-currency', '#sentiment-placement', '#utterance-accordion-1',
            "[data-derived-scope='utterance-1-derived']", '.utterance-passage-view',
            '#coins-1', '#utterance-accordion-2', '#coins-2',
          ];
          for (let i = 1; i < chain.length; i++) {
            const a = form.querySelector(chain[i - 1]), b = form.querySelector(chain[i]);
            if (!a || !b) return 'missing ' + (a ? chain[i] : chain[i - 1]);
            if (!(a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING)) return chain[i] + ' before ' + chain[i - 1];
          }
          return 'ok';
        }
        """
      ).string
      #expect(order == "ok", "\(order ?? "")")
      try await expect(form.locator("#utterance-accordion-1 .accordion-title").first).toContainText("Utterance 1")
      for id in ["sentiment-accordion", "utterance-accordion-1", "utterance-accordion-2"] {
        try await expect(form.locator("#\(id)")).toHaveAttribute("data-expanded", "true")
        try await expect(form.locator(".framed-accordion-view:has(> .accordion-view > #\(id))")).toHaveCount(1)
      }
      try await expect(form.locator(".accordion-divider")).toHaveCount(0)
      // Language a dropdown, English; placeholders their labels.
      try await expect(form.locator("#language")).toHaveValue("eng")
      try await expect(form.locator("[data-dropdown-id='language'] .dropdown-selected-text")).toHaveText("English")
      try await expect(form.locator("input[name='title']")).toHaveAttribute("placeholder", "Title")
      try await expect(form.locator("#definition")).toHaveAttribute("placeholder", "Definition")

      // Derived: disabled, from the earliest attestation (the work's, AD
      // 1976 at Oxford, its voice the first user until a passage coins it).
      for prefix in ["record-derived", "sentiment-derived", "utterance-1-derived", "utterance-2-derived"] {
        try await expect(form.locator("#\(prefix)-date")).toBeDisabled()
        try await expect(form.locator("#\(prefix)-date")).toHaveValue("AD 1976")
        try await expect(form.locator("#\(prefix)-place")).toHaveValue("Oxford")
        try await expect(
          form.locator("[data-item-list='\(prefix)-voice'] [data-item-section='true'] .text-input-input").first
        ).toHaveValue(passage.author)
      }
      let recordRole = form.locator(
        "[data-item-list='record-derived-voice'] [data-item-section='true'] input[id$='-dropdown']")
      let sentimentRole = form.locator(
        "[data-item-list='sentiment-derived-voice'] [data-item-section='true'] input[id$='-dropdown']")
      try await expect(recordRole).toHaveValue("first_user")
      try await expect(sentimentRole).toHaveValue("first_user")
      // The passage: its testament linked to the reader, its page, the word.
      let card = form.locator(".submit-sentiment-passage").first
      try await expect(card.locator("a")).toHaveText(passage.title)
      try await expect(card.locator("a")).toHaveAttribute(
        "href", "/biblio-records/eng/web-tests-passage-\(passage.recordID.prefix(8).lowercased())/book/versions/\(passage.versionID)")
      try await expect(card).toContainText("Page 192")
      try await expect(card.locator("mark")).toHaveText("meme")

      // Coined: the earliest voice is its coiner; one box at most.
      let first = form.locator("#coins-1"), second = form.locator("#coins-2")
      try await first.check()
      try await expect(recordRole, timeout: .seconds(10)).toHaveValue("coiner")
      try await expect(sentimentRole).toHaveValue("coiner")
      try await second.check()
      try await expect(first).not.toBeChecked()
      try await expect(recordRole, timeout: .seconds(10)).toHaveValue("coiner")
      try await second.uncheck()
      try await expect(recordRole, timeout: .seconds(10)).toHaveValue("first_user")

      // Picked, the record fills in its title and type; its tree goes in
      // the Sentiment card, where the new sentiment is placed.
      let field = form.locator(".record-choice-field-view")
      let dropdown = field.locator(".dropdown-view")
      try await dropdown.locator(".dropdown-trigger").click()
      try await dropdown.locator(".dropdown-search-input").fill(word.title)
      let found = dropdown.locator(
        ".dropdown-options-list[data-dropdown-results='true'] .dropdown-option[data-value]").first
      try await found.click()
      try await expect(form.locator("input[name='title']"), timeout: .seconds(15)).toHaveValue(word.title)
      try await expect(form.locator("#type")).toHaveValue("noun")
      try await expect(form.locator("#sentiment-placement .record-placement-view")).toBeVisible()
      try await expect(field.locator(".record-placement-view")).toHaveCount(0)
      try await expect(form.locator("#sentiment-placement input[name='placement-version']")).toHaveCount(1)
      try await shoot(page, "picked", layout)

      // Edited, the title stays when the pick is unset; the type it
      // filled in, untouched, goes; the tree goes.
      try await form.locator("input[name='title']").fill("\(word.title)s")
      try await Task.sleep(for: .milliseconds(900))
      try await dropdown.locator(".dropdown-trigger").click()
      try await dropdown.locator(".dropdown-option.is-selected").first.click()
      try await expect(dropdown.locator(".dropdown-selected-text")).toHaveText("—")
      try await expect(form.locator("input[name='title']")).toHaveValue("\(word.title)s")
      try await expect(form.locator("#type")).toHaveValue("")
      try await expect(form.locator("[data-dropdown-id='type'] .dropdown-selected-text")).toHaveText("Type")
      try await expect(form.locator("#language")).toHaveValue("eng")
      try await expect(form.locator("#sentiment-placement .record-placement-view")).toHaveCount(0)
      try await expect(form.locator("#sentiment-placement")).toContainText("—")
    }
  }

  private func shoot(_ page: Page, _ name: String, _ layout: Layout) async throws {
    guard let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"] else { return }
    try await page.screenshot(to: URL(fileURLWithPath: directory).appendingPathComponent("sentiment-\(layout)-\(name).png"))
  }
}
