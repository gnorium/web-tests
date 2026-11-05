import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Every list of a form's own (`FormItemsView`) comes back from a kept draft
/// with its values (user, 2026-11-05: a Submit Testament draft came back
/// after a deploy with its Class and Script but no voice Name and no
/// genres): Submit Testament's voices (one with its role), genres (one
/// chosen, one typed), domains, a copy's former owner (its certainty and its
/// period's start) and an origin step's voices; Submit Sentiment's
/// pronunciations; a biblio-record amendment's voices and genres; a
/// lexico-record amendment's pronunciations. A combobox's field shows its
/// value whichever way the value came back: from the draft, or put back by
/// a browser that restores a page's form state (a tab reopened or brought
/// back, a history entry), which writes a hidden value before the page
/// hydrates and never the combobox's own field (`autocomplete="off"`);
/// `restored` writes them at DOMContentLoaded as such a browser does. A
/// draft kept before a deploy (its values alone, no rows recorded) comes
/// back the same, and is never written over before it has. Signed out on
/// Submit Testament and Submit Sentiment; a throwaway admin owns the
/// amendments' scratch records. Chrome headless.
@Suite("Draft lists", .serialized)
struct DraftListsTests {
  static let testamentForm = "/mission-control/submit/bibliographic/testament"
  static let sentimentForm = "/mission-control/submit/lexicographic/sentiment"

  // MARK: - Helpers

  /// A list's own rows.
  static func rows(_ scope: Locator, _ list: String) -> Locator {
    scope.locator("[data-item-list='\(list)'] > [data-item-section='true']")
  }

  /// The field named `name` (a combobox's or a dropdown's hidden value, a
  /// text field).
  static func field(_ page: Page, _ name: String) -> Locator {
    page.locator("input[name='\(name)']")
  }

  /// The text a combobox whose value is `name` shows.
  static func shown(_ page: Page, _ name: String) -> Locator {
    page.locator(".combobox-view:has(input[name='\(name)']) input[data-combobox-input='true']")
  }

  /// The text a dropdown whose value is `name` shows.
  static func chosen(_ page: Page, _ name: String) -> Locator {
    page.locator(".dropdown-view:has(input[name='\(name)']) .dropdown-selected-text").first
  }

  /// `value` chosen in the dropdown whose value is `name`, through its
  /// option, once its menu stands open.
  static func pick(_ page: Page, _ name: String, _ value: String) async throws {
    let dropdown = page.locator(".dropdown-view:has(input[name='\(name)'])").first
    let option = dropdown.locator(".dropdown-option[data-value='\(value)']")
    for _ in 0..<3 {
      if try await field(page, name).inputValue() == value { break }
      if !(try await option.filter(visible: true).first.isVisible()) {
        try await dropdown.locator(".dropdown-trigger").click()
      }
      try await option.filter(visible: true).first.click()
    }
    try await expect(field(page, name)).toHaveValue(value)
  }

  /// The draft kept for this page once it holds every one of `texts`.
  static func kept(_ page: Page, holding texts: [String]) async throws -> String {
    var kept = ""
    for _ in 0..<24 {
      kept = try await page.evaluate("localStorage.getItem('gnorium:draft:' + location.pathname) || ''", as: String.self)
      if texts.allSatisfy({ kept.contains($0) }) { break }
      try await Task.sleep(for: .milliseconds(250))
    }
    return kept
  }

  static func dropDraft(_ page: Page) async throws {
    _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
  }

  /// At DOMContentLoaded, before the page hydrates, each named hidden field
  /// given its value, as a browser that restores a page's form state does.
  static func restoring(_ page: Page, _ values: [(String, String)]) async throws {
    let entries = values.map { name, value in
      "['\(name)', \(String(data: try! JSONEncoder().encode(value), encoding: .utf8)!)]"
    }.joined(separator: ",")
    try await page.addInitScript(
      """
      document.addEventListener('DOMContentLoaded', () => {
        for (const [name, value] of [\(entries)]) {
          const input = document.querySelector(`input[type='hidden'][name='${name}']`);
          if (input) input.value = value;
        }
      });
      """)
  }

  // MARK: - Submit Testament

  @Test(arguments: [BrowserEngine.chrome], [false, true])
  func submitTestamentsListsComeBack(engine: BrowserEngine, restored: Bool) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated(Self.testamentForm)
      try await Self.dropDraft(page)
      try await page.openHydrated(Self.testamentForm)
      let body = page.locator("body")

      // Two voices, the second a translator.
      try await Self.shown(page, "work-voice-item1-text-input").fill("Web tests Voice One")
      try await page.locator("[data-item-list='work-voice'] > [data-item-add-btn='true'] .item-add-btn").click()
      try await expect(Self.rows(body, "work-voice")).toHaveCount(2)
      try await Self.shown(page, "work-voice-item2-text-input").fill("Web tests Voice Two")
      try await Self.pick(page, "work-voice-item2-dropdown", "translator")
      // Two genres: one of the list's, by its name; one typed.
      try await Self.shown(page, "work-genre-item1-text-input").fill("Comedy")
      try await expect(Self.field(page, "work-genre-item1-text-input")).toHaveValue("comedy")
      try await page.locator("[data-item-list='work-genre'] > [data-item-add-btn='true'] .item-add-btn").click()
      try await expect(Self.rows(body, "work-genre")).toHaveCount(2)
      try await Self.shown(page, "work-genre-item2-text-input").fill("Web tests typed genre")
      // A domain.
      try await Self.pick(page, "work-domain-item1-text-input", "classA")
      // A former owner of the copy: its name, its certainty, its start.
      try await Self.field(page, "former-owner-item1-text-input").fill("Web tests Owner")
      try await Self.pick(page, "former-owner-item1-certainty", "probable")
      try await Self.field(page, "former-owner-item1-start-year").fill("1821")
      // Origin 1's voice.
      try await Self.field(page, "origin-1-voice-item1-text-input").fill("Web tests Origin Voice")

      let kept = try await Self.kept(
        page, holding: ["Web tests Origin Voice", "\"work-domain-item1-text-input\":\"classA\"", "probable", "rows:"])
      #expect(kept.contains("Web tests typed genre") && kept.contains("1821"), "the draft keeps every list: \(kept)")

      if restored {
        try await Self.restoring(
          page,
          [
            ("work-voice-item1-text-input", "Web tests Voice One"), ("work-genre-item1-text-input", "comedy"),
            ("work-domain-item1-text-input", "classA"), ("former-owner-item1-certainty", "probable"),
          ])
      }
      _ = try await page.reload()
      try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")

      // The voices, each row its value and its field showing it.
      try await expect(Self.rows(body, "work-voice"), timeout: .seconds(15)).toHaveCount(2)
      try await expect(Self.field(page, "work-voice-item1-text-input")).toHaveValue("Web tests Voice One")
      try await expect(Self.shown(page, "work-voice-item1-text-input")).toHaveValue("Web tests Voice One")
      try await expect(Self.field(page, "work-voice-item2-text-input")).toHaveValue("Web tests Voice Two")
      try await expect(Self.shown(page, "work-voice-item2-text-input")).toHaveValue("Web tests Voice Two")
      try await expect(Self.field(page, "work-voice-item2-dropdown")).toHaveValue("translator")
      try await expect(Self.chosen(page, "work-voice-item2-dropdown")).toHaveText("Translator")
      // The genres: the list's one by its name, the typed one as typed.
      try await expect(Self.rows(body, "work-genre")).toHaveCount(2)
      try await expect(Self.field(page, "work-genre-item1-text-input")).toHaveValue("comedy")
      try await expect(Self.shown(page, "work-genre-item1-text-input")).toHaveValue("Comedy")
      try await expect(Self.field(page, "work-genre-item2-text-input")).toHaveValue("Web tests typed genre")
      try await expect(Self.shown(page, "work-genre-item2-text-input")).toHaveValue("Web tests typed genre")
      // The domain, the former owner, the origin's voice.
      try await expect(Self.field(page, "work-domain-item1-text-input")).toHaveValue("classA")
      try await expect(Self.chosen(page, "work-domain-item1-text-input")).toContainText("General works")
      try await expect(Self.field(page, "former-owner-item1-text-input")).toHaveValue("Web tests Owner")
      try await expect(Self.field(page, "former-owner-item1-certainty")).toHaveValue("probable")
      try await expect(Self.chosen(page, "former-owner-item1-certainty")).toHaveText("Probable")
      try await expect(Self.field(page, "former-owner-item1-start-year")).toHaveValue("1821")
      try await expect(Self.field(page, "origin-1-voice-item1-text-input")).toHaveValue("Web tests Origin Voice")

      try await Self.dropDraft(page)
      try await page.expectNoErrors()
    }
  }

  /// A draft kept before a deploy holds the values alone, by the names the
  /// fields still have, and no rows (`rows:<part>`): its lists grow from
  /// the values, and it is not written over before it is back.
  @Test(arguments: [BrowserEngine.chrome], [false, true])
  func aDraftKeptBeforeTheDeployComesBack(engine: BrowserEngine, restored: Bool) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated(Self.testamentForm)
      try await Self.dropDraft(page)
      _ = try await page.evaluate(
        #"localStorage.setItem('gnorium:draft:' + location.pathname, JSON.stringify({"title": "Web tests kept title", "type": "play", "script": "Latn", "work-voice-item1-dropdown": "author", "work-voice-item1-text-input": "William Shakespeare", "work-voice-item2-dropdown": "translator", "work-voice-item2-text-input": "Web tests Voice Two", "work-genre-item1-text-input": "tragedy", "work-genre-item2-text-input": "Web tests typed genre"}))"#
      )
      if restored {
        // The tab brought back: the page's parsed fields put back by the
        // browser, the rows the page added nowhere to go.
        try await Self.restoring(
          page,
          [
            ("type", "play"), ("script", "Latn"), ("work-voice-item1-text-input", "William Shakespeare"),
            ("work-genre-item1-text-input", "tragedy"),
          ])
      }
      try await page.openHydrated(Self.testamentForm)
      let body = page.locator("body")

      try await expect(Self.field(page, "title"), timeout: .seconds(15)).toHaveValue("Web tests kept title")
      try await expect(Self.field(page, "type")).toHaveValue("play")
      try await expect(Self.chosen(page, "type")).toHaveText("Play")
      try await expect(Self.field(page, "script")).toHaveValue("Latn")
      try await expect(Self.chosen(page, "script")).toContainText("Latin")
      try await expect(Self.rows(body, "work-voice")).toHaveCount(2)
      try await expect(Self.shown(page, "work-voice-item1-text-input")).toHaveValue("William Shakespeare")
      try await expect(Self.field(page, "work-voice-item1-text-input")).toHaveValue("William Shakespeare")
      try await expect(Self.shown(page, "work-voice-item2-text-input")).toHaveValue("Web tests Voice Two")
      try await expect(Self.field(page, "work-voice-item2-dropdown")).toHaveValue("translator")
      try await expect(Self.rows(body, "work-genre")).toHaveCount(2)
      try await expect(Self.shown(page, "work-genre-item1-text-input")).toHaveValue("Tragedy")
      try await expect(Self.field(page, "work-genre-item1-text-input")).toHaveValue("tragedy")
      try await expect(Self.shown(page, "work-genre-item2-text-input")).toHaveValue("Web tests typed genre")

      // Kept again, in today's shape, with every value it came back with.
      try await Self.field(page, "title").fill("Web tests kept title, typed again")
      let kept = try await Self.kept(page, holding: ["typed again", "rows:"])
      #expect(kept.contains("William Shakespeare") && kept.contains("Web tests Voice Two"), "the voices kept: \(kept)")
      #expect(kept.contains("\"work-genre-item1-text-input\":\"tragedy\""), "the genre kept: \(kept)")
      #expect(kept.contains("Web tests typed genre"), "the typed genre kept: \(kept)")

      try await Self.dropDraft(page)
      try await page.expectNoErrors()
    }
  }

  // MARK: - Submit Sentiment

  @Test(arguments: [BrowserEngine.chrome])
  func submitSentimentsPronunciationsComeBack(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated(Self.sentimentForm)
      try await Self.dropDraft(page)
      try await page.openHydrated(Self.sentimentForm)
      let form = page.locator(".submit-sentiment-form")

      try await Self.pick(page, "pronunciation-item1-dropdown", "received_pronunciation")
      try await Self.field(page, "pronunciation-item1-text-input").fill("/ˈæŋkə/")
      try await form.locator("[data-item-list='pronunciation'] > [data-item-add-btn='true'] .item-add-btn").click()
      try await expect(Self.rows(form, "pronunciation")).toHaveCount(2)
      try await Self.field(page, "pronunciation-item2-text-input").fill("[ˈæŋkə]")
      _ = try await Self.kept(page, holding: ["[ˈæŋkə]"])

      _ = try await page.reload()
      try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
      try await expect(Self.rows(form, "pronunciation"), timeout: .seconds(15)).toHaveCount(2)
      try await expect(Self.field(page, "pronunciation-item1-dropdown")).toHaveValue("received_pronunciation")
      try await expect(Self.chosen(page, "pronunciation-item1-dropdown")).toHaveText("Received Pronunciation")
      try await expect(Self.field(page, "pronunciation-item1-text-input")).toHaveValue("/ˈæŋkə/")
      try await expect(Self.field(page, "pronunciation-item2-text-input")).toHaveValue("[ˈæŋkə]")

      try await Self.dropDraft(page)
      try await page.expectNoErrors()
    }
  }

  // MARK: - The amendments

  @Test(arguments: [BrowserEngine.chrome])
  func anAmendmentsListsComeBack(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let word = try ScratchWord(owner: admin)
    func clean() async throws {
      work.remove()
      word.remove()
      try await admin.remove()
    }
    do {
      try await withPage(engine, gnorium, cookies: [admin.cookie]) { page in
        // A biblio-record's: a second voice and a typed genre on its work.
        try await page.openHydrated("\(work.path)/amendments/new")
        try await Self.dropDraft(page)
        try await page.openHydrated("\(work.path)/amendments/new")
        let workFields = page.locator(".submit-amendment-work")
        let add = workFields.locator("[data-item-list='work-voice'] > [data-item-add-btn='true'] .item-add-btn")
        if !(try await add.isVisible()) {
          try await workFields.locator(".accordion-summary").first.click()
        }
        try await expect(add).toBeVisible()
        let voices = try await Self.rows(workFields, "work-voice").count()
        try await add.click()
        try await expect(Self.rows(workFields, "work-voice")).toHaveCount(voices + 1)
        let added = "work-voice-item\(voices + 1)-text-input"
        try await Self.shown(page, added).fill("Web tests Amended Voice")
        try await Self.shown(page, "work-genre-item1-text-input").fill("Web tests amended genre")
        _ = try await Self.kept(page, holding: ["Web tests Amended Voice", "Web tests amended genre"])

        _ = try await page.reload()
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
        try await expect(Self.rows(workFields, "work-voice"), timeout: .seconds(15)).toHaveCount(voices + 1)
        try await expect(Self.field(page, added)).toHaveValue("Web tests Amended Voice")
        try await expect(Self.shown(page, added)).toHaveValue("Web tests Amended Voice")
        try await expect(Self.field(page, "work-genre-item1-text-input")).toHaveValue("Web tests amended genre")
        try await expect(Self.shown(page, "work-genre-item1-text-input")).toHaveValue("Web tests amended genre")
        try await Self.dropDraft(page)

        // A lexico-record's: two pronunciations on its root.
        try await page.openHydrated("\(word.path)/amendments/new")
        try await Self.dropDraft(page)
        try await page.openHydrated("\(word.path)/amendments/new")
        let form = page.locator("form.submit-lexicographic-amendment-form")
        let list = form.locator("[data-item-list='pronunciation']")
        let more = list.locator(":scope > [data-item-add-btn='true'] .item-add-btn")
        if !(try await more.isVisible()) {
          try await form.locator("#record-metadata .accordion-summary").first.click()
        }
        try await expect(more).toBeVisible()
        try await Self.pick(page, "pronunciation-item1-dropdown", "received_pronunciation")
        try await Self.field(page, "pronunciation-item1-text-input").fill("/ˈæŋkə/")
        try await more.click()
        try await expect(Self.rows(form, "pronunciation")).toHaveCount(2)
        try await Self.field(page, "pronunciation-item2-text-input").fill("[ˈæŋkə]")
        _ = try await Self.kept(page, holding: ["[ˈæŋkə]"])

        _ = try await page.reload()
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
        try await expect(Self.rows(form, "pronunciation"), timeout: .seconds(15)).toHaveCount(2)
        try await expect(Self.field(page, "pronunciation-item1-dropdown")).toHaveValue("received_pronunciation")
        try await expect(Self.field(page, "pronunciation-item1-text-input")).toHaveValue("/ˈæŋkə/")
        try await expect(Self.field(page, "pronunciation-item2-text-input")).toHaveValue("[ˈæŋkə]")
        try await Self.dropDraft(page)
      }
    } catch {
      try await clean()
      throw error
    }
    try await clean()
  }
}
