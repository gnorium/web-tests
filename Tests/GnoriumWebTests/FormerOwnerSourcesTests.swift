import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Evidence first (user, 2026-11-03): a node's claims rest on its
/// Incoming supports, one accordion a node under its Note. On Submit
/// Testament a copy's "+ Support" stamps a card: its Claim (the copy's
/// fields, and each former owner by name as it is typed), its Source
/// accordion holding its fields, its Quote cards (a sourceless work's
/// text-only reader, its quote typed there) and its own row, "+ Quote" and
/// "− Support": a citation holds exactly one source (user, 2026-11-03). A typed quote's words naming the claim
/// are picked as any quote's (a text selection and "+ Form"), never
/// matched by the owner's name. The copy's list posts as JSON, each new
/// card its claim and its Source, its forms by place.
@Suite("Incoming supports")
struct FormerOwnerSourcesTests {
  static let form = "/mission-control/submit/bibliographic/testament"

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aCopyCitesItsOwner(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated(Self.form)
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.openHydrated(Self.form)

      try await page.locator("input[name='former-owner-item1-text-input']").fill("Sir Henry Bunbury")
      let view = page.locator(".outgoing-citations-view:has(#outgoing-citations-5)")
      try await expect(view).toHaveCount(1)
      // Its owners' Start and End cards stacked, one column.
      let owner = page.locator("[data-item-list='former-owner'] > [data-item-section='true']").first
      let stacked = try await owner.evaluate(
        """
        (o) => { const s = o.querySelector('.form-items-period-start').getBoundingClientRect();
          const e = o.querySelector('.form-items-period-end').getBoundingClientRect();
          return e.top >= s.bottom - 0.5 && Math.abs(e.left - s.left) < 1; }
        """
      ).bool
      #expect(stacked == true, "Start over End, one column")

      // "+ Support": a card, its Claim offering the owner by name.
      let add = view.locator(".outgoing-citations-actions .outgoing-citations-add")
      try await expect(add).toHaveText("Support")
      try await expect(add).toHaveAttribute("aria-label", "Add support")
      try await add.click()
      let cards = view.locator(".outgoing-citations-list > .outgoing-citation-group")
      try await expect(cards).toHaveCount(1)
      let card = cards.first
      let claim = card.locator(".outgoing-citation-claim")
      // A trail (`BreadcrumbLabelView`): "Former owner", its chevron, the
      // owner's name.
      let offered = claim.locator(".dropdown-option[data-value^='formerOwners:'] .breadcrumb-label-view")
      try await expect(offered.locator(".breadcrumb-label-context")).toHaveText("Former owner")
      try await expect(offered.locator(".breadcrumb-separator-view")).toHaveCount(1)
      try await expect(offered.locator(".breadcrumb-label-text")).toHaveText("Sir Henry Bunbury")
      try await claim.locator(".dropdown-trigger").click()
      try await claim.locator(".dropdown-option[data-value^='formerOwners:']").filter(visible: true).first.click()

      // Its Source: a sourceless work, its quote typed in its card.
      let source = card.locator(".evidence-source-view")
      try await expect(source.locator(".source-accordion-view .accordion-title").first).toHaveText("Source")
      try await source.locator("input[name$='-source-url-title']").fill("A Catalogue of the Library")
      let quotes = source.locator(".quote-passage-quotes > .quote-passage-quote")
      try await expect(quotes).toHaveCount(1)
      // Inside its Source accordion (user, 2026-11-11: "quotes go back
      // inside the source accordions"), then its own row: "+ Quote", then
      // "− Source", its card holding "+ Source" and "− Support".
      try await expect(source.locator(".source-accordion-view .quote-passage-quote")).toHaveCount(1)
      try await expect(source.locator(".quote-passage-body > .quote-passage-quotes > .quote-passage-quote")).toHaveCount(1)
      try await expect(source.locator(".quote-passage-body .quote-passage-actions .button-label"))
        .toHaveTexts(["Quote", "Quote", "Source"])
      let pane = quotes.first.locator(".quote-passage-text .tei-page-text")
      try await expect(pane, timeout: .seconds(15)).toBeAttached()
      // The I-beam over the text alone (user, 2026-11-05): its text and its
      // placeholder show it, the room off the text the pane's pan (a drag
      // there pans); a click there still puts the caret at the end of the
      // text.
      let markup = quotes.first.locator(".quote-passage-text .artifact-markup")
      let beams = try await markup.evaluate(
        """
        (m) => { const p = m.querySelector('.tei-page-text');
          return [getComputedStyle(m).cursor, getComputedStyle(p).cursor, getComputedStyle(p, '::before').cursor,
            getComputedStyle(p, '::before').content].join('|'); }
        """
      ).string ?? ""
      #expect(beams == "grab|text|text|\"Quote\"", "the I-beam over the text alone, its placeholder Quote: \(beams)")
      try await pane.fill("Bought of Sir")
      let room = try await markup.evaluate(
        """
        (m) => { m.scrollIntoView({ block: 'center' });
          const p = m.querySelector('.tei-page-text').getBoundingClientRect(), b = m.getBoundingClientRect();
          const x = b.left + b.width / 2, y = Math.min(b.bottom - 2, p.bottom + 8);
          const off = document.elementFromPoint(x, y)?.closest('.tei-page-text') === null;
          // The pointer lands in the visual viewport (a phone's page laid
          // out wider than its screen is drawn smaller).
          const v = window.visualViewport;
          return [(x - v.offsetLeft) * v.scale, (y - v.offsetTop) * v.scale, b.bottom > p.bottom + 4 && off]; }
        """)
      if case .array(let point) = room, point.count == 3, point[2].bool == true,
        let x = point[0].double, let y = point[1].double
      {
        try await page.mouse.click(x: x, y: y)
        let focused = try await pane.evaluate("(p) => document.activeElement === p").bool
        #expect(focused == true, "a click in the empty room focuses the quote")
        try await page.keyboard.type(" Henry Bunbury.")
      } else {
        try await pane.fill("Bought of Sir Henry Bunbury.")
      }
      try await expect(pane).toHaveText("Bought of Sir Henry Bunbury.")

      // Its words picked as a form as any quote's, by a selection and "+
      // Form": never matched by the owner's name (user, 2026-11-03).
      let typedWords = quotes.first.locator(".quote-typed-word")
      try await expect(typedWords).toHaveCount(5)
      // All it holds is the quote: violet, the spaces between its words too,
      // as typed (user, 2026-11-03); no form till one is picked.
      try await expect(quotes.first.locator(".quote-typed-word.tei-highlight")).toHaveCount(5)
      try await expect(quotes.first.locator(".quote-typed-space.tei-highlight")).toHaveCount(4)
      try await expect(quotes.first.locator("[data-highlight='title']")).toHaveCount(0)
      // Drawn violet, a ground, Reflow off and on (user, 2026-11-05).
      let ground = "(w) => getComputedStyle(w).backgroundColor"
      let unflowed = try await typedWords.first.evaluate(ground).string ?? ""
      #expect(!unflowed.isEmpty && unflowed != "rgba(0, 0, 0, 0)", "violet: \(unflowed)")
      let reflow = quotes.first.locator(".artifact-reflow-toggle button")
      try await reflow.click()
      try await expect(quotes.first.locator(".artifact-view")).toHaveAttribute("data-reflow", "true")
      let reflowed = try await typedWords.first.evaluate(ground).string ?? ""
      #expect(reflowed == unflowed, "violet with Reflow on: \(reflowed)")
      try await reflow.click()
      try await expect(quotes.first.locator(".artifact-view")).toHaveAttribute("data-reflow", "false")
      try await page.addForm(
        in: source, from: ".quote-typed-word[data-typed-word='3']", to: ".quote-typed-word[data-typed-word='5']")
      try await expect(quotes.first.locator(".quote-typed-word[data-highlight='title']")).toHaveTexts(
        ["Sir", "Henry", "Bunbury."])
      // One strip (user, 2026-11-03): the spaces between its words filled,
      // its first word opening it and its last closing it.
      try await expect(quotes.first.locator(".quote-typed-space[data-quote-strip]")).toHaveCount(2)
      try await expect(quotes.first.locator("[data-quote-strip-start]")).toHaveText("Sir")
      try await expect(quotes.first.locator("[data-quote-strip-end]")).toHaveText("Bunbury.")

      // Posted as the copy's list: its claim the owner's row, its Source,
      // its form by place.
      let json = page.locator("input[name='outgoing-citations-json-5']")
      let posted = try await json.evaluate("(i) => i.value").string ?? ""
      #expect(posted.contains("\"claim\":\"formerOwners:"), "its claim the owner's row: \(posted)")
      #expect(posted.contains("\"source\":"), "a new card posts its Source: \(posted)")
      #expect(posted.contains("Bought of Sir Henry Bunbury."), "its quote: \(posted)")
      #expect(
        posted.contains(#""forms":[[[{"surface":"Sir","word":3},{"surface":"Henry","word":4},{"surface":"Bunbury.","word":5}]]]"#),
        "its form by place: \(posted)")
      // Typed over, a pick that no longer stands is let go, never moved.
      try await pane.fill("Bought of Sir H. Bunbury.")
      try await expect(quotes.first.locator("[data-highlight='title']")).toHaveCount(0)
      let retyped = try await json.evaluate("(i) => i.value").string ?? ""
      #expect(!retyped.contains("\"forms\""), "its stale form let go: \(retyped)")

      // Its card holds "+ Source" and "− Support" (user, 2026-11-11);
      // its one source's "− Source" lets the source go, and its card with
      // its last.
      try await expect(card.locator(".outgoing-citation-card-actions .button-label")).toHaveTexts(["Source", "Support"])
      let remove = card.locator(".quote-passage-actions .quote-passage-citation-remove")
      try await expect(remove).toHaveText("Source")
      try await expect(remove).toHaveAttribute("aria-label", "Remove source")
      try await expect(card.locator(".quote-sources-add-btn, .quote-passage-source-remove")).toHaveCount(0)
      try await remove.click()
      try await expect(cards).toHaveCount(0)
      try await expect(json).toHaveValue("")
      try await page.expectNoHorizontalOverflow()
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.expectNoErrors()
    }
  }

  /// A typed form is exactly what was selected (user, 2026-11-05: "keep
  /// selected text"): "Cavendish" selected inside "(Cavendish)," is the
  /// form "Cavendish", marked on those characters alone, the rest of its
  /// word beside it; "'tis" selected whole stays "'tis". Each posts by
  /// place with its surface as selected.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aTypedFormIsWhatWasSelected(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated(Self.form)
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.openHydrated(Self.form)

      try await page.locator("input[name='former-owner-item1-text-input']").fill("Sir Henry Cavendish")
      let view = page.locator(".outgoing-citations-view:has(#outgoing-citations-5)")
      try await view.locator(".outgoing-citations-actions .outgoing-citations-add").click()
      let card = view.locator(".outgoing-citations-list > .outgoing-citation-group").first
      let claim = card.locator(".outgoing-citation-claim")
      try await claim.locator(".dropdown-trigger").click()
      try await claim.locator(".dropdown-option[data-value^='formerOwners:']").filter(visible: true).first.click()
      let source = card.locator(".evidence-source-view")
      try await source.locator("input[name$='-source-url-title']").fill("A Catalogue of the Library")
      let quote = source.locator(".quote-passage-quotes > .quote-passage-quote").first
      let pane = quote.locator(".quote-passage-text .tei-page-text")
      try await expect(pane, timeout: .seconds(15)).toBeAttached()
      try await pane.fill("Bought of (Cavendish), 'tis said")
      try await expect(quote.locator(".quote-typed-word")).toHaveCount(5)

      // Inside "(Cavendish),": "Cavendish" alone.
      try await page.addForm(in: source, typedWord: 3, from: 1, to: 10)
      let marked = quote.locator(".quote-typed-word[data-highlight='title']")
      try await expect(marked).toHaveTexts(["Cavendish"])
      try await expect(quote.locator(".quote-typed-rest")).toHaveTexts(["(", "),"])
      try await expect(pane).toHaveText("Bought of (Cavendish), 'tis said")
      // "'tis" whole: "'tis", its apostrophe kept.
      try await page.addForm(in: source, from: ".quote-typed-word[data-typed-word='4']")
      try await expect(marked).toHaveTexts(["Cavendish", "'tis"])

      let json = page.locator("input[name='outgoing-citations-json-5']")
      let posted = try await json.evaluate("(i) => i.value").string ?? ""
      #expect(
        posted.contains(#""forms":[[[{"surface":"Cavendish","word":3}],[{"surface":"'tis","word":4}]]]"#),
        "each form as selected, by place: \(posted)")
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.expectNoErrors()
    }
  }

  /// A citation cites only what Gnorium can hold (user, 2026-11-05): a
  /// biblio-record, a IIIF manifest's Source URL or a sourceless work. A
  /// URL that is no IIIF manifest (here a web page) is refused under its
  /// field in one vague sentence, nothing read into its Quote card, and the
  /// Source asks no Accessed; the URL cleared, the refusal goes with it.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWebPageIsNoSource(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let html = Data("<!doctype html><html lang=\"en\"><head><title>Shakespeare Census</title></head><body><p>Found by Sir H. E. Bunbury at Barton, 1823.</p></body></html>".utf8)
    let fixture = try await FixtureServer(files: ["/sc/29/": .init(contentType: "text/html; charset=utf-8", body: html)])
    defer { fixture.stop() }
    // Signed in: the Source URL's check is a signed-in person's.
    let account = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [account.cookie]) { page in
        try await page.openHydrated(Self.form)
        _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
        try await page.openHydrated(Self.form)

        try await page.locator("input[name='former-owner-item1-text-input']").fill("Sir Henry Bunbury")
        let view = page.locator(".outgoing-citations-view:has(#outgoing-citations-5)")
        try await view.locator(".outgoing-citations-actions .outgoing-citations-add").click()
        let card = view.locator(".outgoing-citations-list > .outgoing-citation-group").first
        let source = card.locator(".evidence-source-view")
        try await expect(source.locator(".quote-passage-accessed, input[name$='-source-url-accessed']")).toHaveCount(0)

        let url = source.locator(".quote-passage-url input[type='url']")
        try await url.fill(fixture.baseURL + "/sc/29/")
        let message = source.locator(".quote-passage-url .field-validation-message-text")
        try await expect(message, timeout: .seconds(15)).toHaveText("This URL can't be read.")
        try await expect(url).toHaveAttribute("aria-invalid", "true")
        try await expect(source.locator(".quote-passage-reader[data-shown='true']")).toHaveCount(0)
        // Its Title, Language and Class as typed: nothing filled from the page.
        try await expect(source.locator("input[name$='-source-url-title']")).toHaveValue("")
        try await expect(source.locator("input[name$='-source-url-class']")).toHaveValue("")

        // Its URL cleared: the refusal goes with it.
        try await url.fill("")
        try await expect(message, timeout: .seconds(15)).toHaveCount(0)
        try await page.expectNoHorizontalOverflow()
        _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
        try await page.expectNoErrors()
      }
    } catch {
      try await account.remove(after: error)
    }
    try await account.remove()
  }
}
