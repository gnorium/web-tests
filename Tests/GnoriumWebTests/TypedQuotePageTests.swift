import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A typed quote by a Source URL takes a Page (user, 2026-11-05): its
/// reader's header names the frame on screen ("326"), so the page printed
/// there ("318") is typed into its Source's Pages, open for a URL's typed
/// quote as for a sourceless work's; kept with the quote when it is
/// submitted, and drawn read-only wherever the quote is drawn. A throwaway
/// admin owns every row, removed after.
@Suite("Typed quote page", .serialized)
struct TypedQuotePageTests {
  static let sentimentForm = "/mission-control/submit/lexicographic/sentiment"

  /// Sets a dropdown by its hidden input, as a pick does.
  private func set(_ page: Page, _ values: [(String, String)]) async throws {
    let pairs = values.map { "['\($0.0)', '\($0.1)']" }.joined(separator: ", ")
    _ = try await page.evaluate(
      """
      (() => {
        for (const [id, value] of [\(pairs)]) {
          const input = document.getElementById(id);
          input.value = value;
          input.dispatchEvent(new Event('change'));
        }
      })()
      """)
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aTypedSourceURLQuoteTakesAndKeepsItsPage(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let suffix = String(UUID().uuidString.prefix(8)).lowercased()
    let title = "webtestspage\(suffix)"
    // The testament its quote is on: a manifest the server can read.
    let fixtures = try await FixtureServer.threePageManifest()
    defer { fixtures.stop() }
    let source = fixtures.baseURL + "/manifest.json"
    func clean() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM lexicographic_overtures WHERE lexicographic_figurant_id IN
          (SELECT id FROM lexicographic_figurants WHERE title_form_json::json ->> 'title' = '\(title)');
        UPDATE lexicographic_figurants SET discarded_at = now(), discarded_by = '\(admin.username)'
          WHERE title_form_json::json ->> 'title' = '\(title)' AND discarded_at IS NULL;
        DELETE FROM bibliographic_overtures WHERE bibliographic_figurant_id IN
          (SELECT id FROM bibliographic_figurants WHERE source_url = '\(source)');
        UPDATE bibliographic_figurants SET discarded_at = now(), discarded_by = '\(admin.username)'
          WHERE source_url = '\(source)' AND discarded_at IS NULL;
        COMMIT;
        """)
    }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(Self.sentimentForm)
        let form = page.locator(".submit-sentiment-form")
        let box = form.locator(".quote-sources-view .quote-source").first
        try await box.locator("input[name='quote-s1-source-url']").fill(source)
        // Its frames and the text pane its quote is typed in, one reader.
        try await expect(box.locator(".quote-passage-reader .quote-passage-text"), timeout: .seconds(20)).toBeVisible()
        // Its Pages typed, as a sourceless work's: a frame's number is not
        // the page printed on it.
        let pages = box.locator(".quote-passage-pages")
        try await expect(pages).toBeVisible()
        try await expect(box.locator(".quote-passage-pages-held")).toBeHidden()
        let row = pages.locator("[data-item-section='true']:not([data-item-template] *)").first
        let field = row.locator("input[name$='-text-input']").first
        try await expect(field).toBeEnabled()
        try await expect(field).toHaveAttribute("placeholder", "Page")
        // Its label, a text field's own (`TextInputView`), the placeholder's words.
        try await expect(row.locator(".text-input-label").first).toHaveText("Page")
        try await field.fill("318")
        try await expect(field).toHaveValue("318")
        try await page.expectNoHorizontalOverflow()

        // The rest of the sentiment.
        try await form.locator(".submit-sentiment-apparatus input[name='title']").fill(title)
        try await set(page, [("type", "noun")])
        try await form.locator("textarea[name='value']").fill("What the web tests page word means")
        // The quote as a person gives it. Its hidden fields are its Quote
        // card's, which its reader writes: the frame it opens on, read once
        // its manifest is (as it comes on screen), writes them again from
        // the card, so a quote put in them behind the card is gone by then.
        // On screen, its first frame taken, turned to frame 2 (a frame's
        // number, not the page printed on it), the sentence typed in its
        // text pane, a word of it its form.
        let card = box.locator(".quote-passage-quotes > .quote-passage-quote").first
        let viewer = card.locator(".quote-passage-reader .artifact-view").first
        _ = try await viewer.evaluate("(v) => { v.scrollIntoView({ block: 'center' }); return true; }")
        try await expect(viewer, timeout: .seconds(20)).toHaveAttribute("data-pages-known", "true")
        try await expect(card).toHaveAttribute("data-quote-starts", "1")
        try await viewer.locator(".pagination-next").first.click()
        try await expect(viewer.locator("#artifact-page-input")).toHaveValue("2")
        try await expect(card).toHaveAttribute("data-quote-starts", "2")
        try await card.locator(".quote-passage-text .tei-page-text").first.fill("A web tests quote.")
        try await page.addForm(in: card, from: ".quote-typed-word[data-typed-word='2']")
        try await expect(card.locator(".quote-typed-word[data-highlight='title']")).toHaveText("web")
        try await expect(box.locator("input[name='quote-s1-quote']")).toHaveValue("A web tests quote.")
        try await expect(box.locator("input[name='quote-s1-start-frame']")).toHaveValue("2")
        // Its page kept through it all.
        try await expect(field).toHaveValue("318")
        // A source Gnorium lacks gives its Title, Language and Class.
        _ = try await box.evaluate(
          """
          (b) => {
            for (const [k, v] of [['title', 'Web tests source'], ['language', 'eng'], ['class', 'report']]) {
              const f = b.querySelector(`[name='quote-s1-source-url-${k}']`); f.disabled = false; f.value = v; }
            return true; }
          """)
        try await set(page, [("quote-s1-rights-statement", "noc_us")])
        try await form.locator(".record-actions button[type='submit']").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("its overture's page") {
          $0.path.hasPrefix("/mission-control/overtures/lexicographic/")
        }
        // Kept with the quote, pending on its frame.
        let sentiment = try TestAdmin.query(
          "SELECT sentiment_json FROM lexicographic_figurants WHERE title_form_json::json ->> 'title' = '\(title)'")
        #expect(sentiment.contains(#""pending""#) && sentiment.contains(#""images":[2]"#), "\(sentiment)")
        #expect(sentiment.contains(#""pages":["318"]"#), "its page: \(sentiment)")
        try await page.expectNoErrors(ignoring: ["/page-"])
      }
    } catch {
      clean()
      try await admin.remove(after: error)
    }
    clean()
    try await admin.remove()
  }

  /// Drawn where the quote is (a Disputorium read, the overture's added
  /// quote in its diff): its Pages a field of its Source box, frozen, its
  /// value as typed, beside its URL, marked added as they are (a diff
  /// compares a quote's pages as one field, "Pages", as a read shows them;
  /// a frozen box draws a "Page" a page, as the form does).
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aTypedQuotesPageIsDrawnReadOnly(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    var holder: ScratchOverture?
    do {
      let overture = try ScratchOverture(owner: admin, sealed: false)
      holder = overture
      let source = "https://web-tests.invalid/typed-page.json"
      let step = UUID().uuidString
      let origins =
        #"[{"id":"\#(step)","relations":["based_on"],"typed":{"title":"Web tests source","voices":[]},"origins":[],"#
        + #""outgoingCitations":[{"id":"\#(UUID().uuidString)","claim":{"field":"origin","row":"\#(step)"},"#
        + #""quotes":[{"id":"\#(UUID().uuidString)","anchors":[],"#
        + #""pending":{"sourceURL":"\#(source)","images":[326],"pages":["318"],"text":"The pageword stood fast","title":"Typed page","language":"eng","class":"play","forms":[[{"word":2,"surface":"pageword"}]]}}]}]}]"#
      _ = try TestAdmin.query(
        "UPDATE bibliographic_overtures SET origins_json = '\(origins)' WHERE id = '\(overture.overtureID)';")
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(overture.path)
        let pending = page.locator(".pending-quote-view").first
        try await expect(pending, timeout: .seconds(15)).toBeAttached()
        let fields = pending.locator(".quote-source-fields")
        try await expect(fields.locator("input[placeholder='URL']")).toHaveValue(source)
        let printed = fields.locator("input[placeholder='Pages']")
        try await expect(printed).toHaveCount(1)
        try await expect(printed).toHaveValue("318")
        try await expect(printed).toBeDisabled()
        try await expect(fields.locator(".text-input-view:has(input[placeholder='Pages']) .text-input-label")).toHaveText("Pages")
        // Marked added, as its URL is.
        try await expect(fields.locator(".field-diff-view.diff-wrap-added:has(input[placeholder='Pages'])")).toHaveCount(1)
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      holder?.remove()
      try await admin.remove(after: error)
    }
    holder?.remove()
    try await admin.remove()
  }
}
