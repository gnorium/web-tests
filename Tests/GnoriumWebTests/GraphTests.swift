import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The Graph page (user, 2026-09-29): how records relate, asked as one
/// query row read as a phrase — "[Citations] of [Hamlet]" — a relation's
/// plural (a dropdown of the relations stored between records) and a record
/// (a combobox of both halves' records), left empty for every pair; "+"
/// adds a hop, "[Translations] of [citations] of [Hamlet]", the rows the
/// last layer with the path between. The query is the address; its answer
/// the records lists' filter bar, then the records the site's way
/// ("Language › Title" over the type), each count linking to where its hop
/// is shown, over a drawing whose arrows all run toward the record asked.
/// The relation list never breaks a word. The home page links it between
/// the two records lists; both records sidebars link it first; a record's
/// Citations and its Origin open it filled. The empty page is indexed, a
/// query's answer (as a filtered records list) is not. Phone and desktop,
/// Chrome headless.
@Suite("Graph", .serialized)
struct GraphTests {
  /// A step of `work`'s origin: translated from `source`.
  static func translated(_ work: ScratchWork, from source: ScratchWork) -> String {
    """
    INSERT INTO biblio_record_origins (id, biblio_record_id, parent_id, position, relation, target_record_id, typed_json, created_at)
      VALUES (gen_random_uuid(), '\(work.recordID.lowercased())', NULL, 0, 'translation_of', '\(source.recordID.lowercased())', NULL, now());
    """
  }

  static func query(_ relations: [String], record: String, extra: String = "") -> String {
    "/graph?" + relations.map { "relation=\($0)&" }.joined()
      + "record=\(record.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" + extra
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func theGraphAsksHowRecordsRelate(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let cited = try ScratchWork(owner: admin)
    let citing = try ScratchWork(owner: admin)
    let translation = try ScratchWork(owner: admin)
    let works = [cited, citing, translation]
    func cleanUp() async {
      _ = try? TestAdmin.query(
        EntriesAndCitationsTests.clean(works)
          + "\nDELETE FROM biblio_record_origins WHERE biblio_record_id = '\(translation.recordID.lowercased())';")
      for work in works { work.remove() }
      await admin.remove()
    }
    do {
      // The citing work cites the cited one three times; the translation
      // translates the citing work.
      _ = try TestAdmin.query(
        "BEGIN;\n" + EntriesAndCitationsTests.read(citing)
          + EntriesAndCitationsTests.cite(3, by: citing, work: cited.recordID.lowercased())
          + Self.translated(translation, from: citing) + "\nCOMMIT;")
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        // Home: between the two records lists.
        try await page.openHydrated("/")
        let links = page.locator(".home-nav-links a")
        try await expectTexts(links, ["Biblio-records", "Graph", "Lexico-records"])
        try await expect(links.nth(1)).toHaveAttribute("href", "/graph")

        // The empty page: indexed; one relation to choose, by its plural, "of" a record.
        try await page.openHydrated("/graph")
        try await expect(page.locator("meta[name='robots']")).toHaveAttribute("content", "index, follow")
        try await expect(page.locator(".graph-view-title")).toHaveText("Graph")
        let query = page.locator("form.graph-view-query")
        try await expect(query.locator(".graph-relation")).toHaveCount(1)
        try await expect(query.locator(".graph-view-of")).toHaveText("of")
        try await expect(query.getByRole(.combobox, name: "Record")).toHaveCount(1)
        let relations = query.locator(".graph-relation [data-dropdown-option='true']")
        try await expect(relations.first).toHaveAttribute("data-display", "Citations")
        for plural in [
          "Translations", "Expositions", "Derivatives", "Borrowings", "Affixes", "Back-formations", "Eponyms",
          "Containers", "Equivalents", "Etymons",
        ] {
          try await expect(query.locator(".graph-relation [data-display='\(plural)']")).toHaveCount(1)
        }
        try await expect(page.locator(".relation-graph-view")).toHaveCount(0)
        try await expect(page.locator(".filter-bar-view")).toHaveCount(0)
        // The open list never breaks a word: each word of each option on one line.
        try await query.locator(".graph-relation .dropdown-trigger").click()
        try await expect(query.locator(".graph-relation .dropdown-menu")).toBeVisible()
        let broken = try await page.evaluate(
          """
          [...document.querySelectorAll("form.graph-view-query .graph-relation .dropdown-option-display-text")].flatMap(el => {
            const text = el.firstChild; const out = []; let at = 0;
            for (const word of text.data.split(' ')) {
              const range = document.createRange(); range.setStart(text, at); range.setEnd(text, at + word.length);
              if (range.getClientRects().length > 1) out.push(word); at += word.length + 1;
            }
            return out;
          })
          """)
        #expect(broken == .array([]), "Words broken over lines: \(broken)")
        let inside = try await page.evaluate(
          "(() => { const m = document.querySelector('form.graph-view-query .graph-relation .dropdown-menu').getBoundingClientRect(); return m.left >= 0 && m.right <= window.innerWidth + 1 })()")
        #expect(inside == .bool(true), "The open list stays inside the viewport.")
        await shoot(page, "relations", layout)
        try await page.keyboard.press("Escape")

        // The record chosen from its suggestions.
        let record = query.getByRole(.combobox, name: "Record")
        try await record.fill(cited.suffix)
        let suggestion = query.locator("#graph-record-listbox [role='option']").filter(hasText: cited.title)
        try await expect(suggestion.first).toBeVisible()
        try await suggestion.first.click()
        try await expect(query.locator("input[name='record']")).toHaveValue(cited.path)

        // "Citations of [the cited work]".
        try await page.openHydrated(Self.query(["citation-of"], record: cited.path))
        try await expect(page.locator("meta[name='robots']")).toHaveAttribute("content", "noindex, follow")
        try await expect(page.locator(".records-count-view")).toContainText("1 citation")
        let row = page.locator(".graph-view-table tbody tr")
        try await expect(row).toHaveCount(1)
        // The record the site's way: "Language › Title" over its type.
        let listed = row.locator(".graph-record-view").first
        try await expect(listed.locator("a[href='\(citing.path)'] .breadcrumb-label-context")).toHaveText("English")
        try await expect(listed.locator("a[href='\(citing.path)'] .breadcrumb-label-text")).toHaveText(citing.title)
        try await expect(listed.locator(".record-type-view")).toHaveCount(1)
        let count = row.locator("a.graph-view-count")
        try await expect(count).toHaveText("3 citations")
        try await expect(count).toHaveAttribute(
          "href", "\(cited.path)/citations?work=\(citing.recordID)&direction=citations")
        // The drawing: the record asked at the root, the citing work under
        // it, the edge named, its arrowhead a marker at the root's end.
        let drawing = page.locator(".relation-graph-view svg")
        try await expect(drawing).toHaveCount(1)
        try await expectTexts(drawing.locator(".relation-graph-title"), [cited.title, citing.title])
        try await expectTexts(drawing.locator(".relation-graph-label"), ["citation of"])
        try await expect(drawing.locator("marker#relation-graph-arrowhead path")).toHaveCount(1)
        try await expect(drawing.locator(".relation-graph-edge")).toHaveAttribute(
          "marker-end", "url(#relation-graph-arrowhead)")
        let fits = try await drawing.evaluate("svg => svg.getBoundingClientRect().right <= window.innerWidth + 1")
        #expect(fits == .bool(true), "The drawing fits the page's width.")
        // The records lists' filter bar, "All" never an option.
        let filters = page.locator(".filter-bar-view")
        try await expect(filters).toHaveCount(1)
        try await expect(filters.getByText("All", exact: true)).toHaveCount(0)
        await shoot(page, "citations-of", layout)
        try await count.click()
        try await expect(page.locator(".record-citations-view-citation")).toHaveCount(3)

        // A filter narrows the records listed.
        try await page.openHydrated(Self.query(["citation-of"], record: cited.path, extra: "&language=eng"))
        try await expect(page.locator(".graph-view-table tbody tr a[href='\(citing.path)']")).toHaveCount(1)
        try await page.openHydrated(Self.query(["citation-of"], record: cited.path, extra: "&language=fra"))
        try await expect(page.locator(".records-count-view")).toContainText("0 citations")
        try await expect(page.locator(".graph-view-empty-message")).toHaveText("No citations.")

        // None: said in words, no drawing.
        try await page.openHydrated(Self.query(["container-of"], record: cited.path))
        try await expect(page.locator(".records-count-view")).toContainText("0 containers")
        try await expect(page.locator(".graph-view-empty-message")).toHaveText("No containers.")
        try await expect(page.locator(".relation-graph-view")).toHaveCount(0)

        // No record: every pair, the record each is of in its own column.
        try await page.openHydrated(Self.query(["translation-of"], record: ""))
        try await expect(page.locator(".records-count-view")).toContainText("pair")
        let pair = page.locator(".graph-view-table tbody tr").filter(hasText: translation.title)
        try await expect(pair).toHaveCount(1)
        try await expect(pair.locator("a[href='\(citing.path)']")).toHaveCount(1)

        // "+" adds a hop: "Translations of citations of [the cited work]".
        try await page.openHydrated(Self.query(["translation-of"], record: cited.path))
        try await expect(page.locator(".graph-view-empty-message")).toHaveText("No translations.")
        try await page.locator("form.graph-view-query button[aria-label='Add a relation']").click()
        let second = page.locator("form.graph-view-query .graph-view-hop").nth(1)
        try await expect(second).toBeVisible()
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
        try await expect(page.locator("form.graph-view-query input[name='record']")).toHaveValue(cited.path)
        try await second.locator(".dropdown-trigger").click()
        try await second.locator(".dropdown-option[data-value='citation-of']").click()
        try await page.locator("form.graph-view-query button[type='submit']").filter(hasText: "Search").click()
        try await expect(page.locator(".records-count-view")).toContainText("1 translation")
        let chained = page.locator(".graph-view-table tbody tr")
        try await expect(chained).toHaveCount(1)
        try await expect(chained.locator("a[href='\(translation.path)']")).toHaveCount(1)
        try await expect(chained.locator(".graph-view-via a[href='\(citing.path)']")).toHaveCount(1)
        try await expectTexts(
          page.locator(".relation-graph-view .relation-graph-title"), [cited.title, citing.title, translation.title])
        try await expectTexts(page.locator(".relation-graph-view .relation-graph-label"), ["citation of", "translation of"])
        await shoot(page, "chain", layout)
        // Each hop removable while there are two.
        let removes = page.locator("form.graph-view-query a[aria-label='Remove this relation']")
        try await expect(removes).toHaveCount(2)
        try await removes.nth(1).click()
        try await expect(page.locator("form.graph-view-query .graph-view-hop")).toHaveCount(1)
        try await expect(page.locator(".graph-view-empty-message")).toHaveText("No translations.")

        // A work's Origin opens the record-first form: "[this work] is a
        // translation of" → what it translates, the arrow from it.
        try await page.openHydrated(translation.path)
        let fromOrigin = page.locator("#origin a.origin-section-graph")
        try await expect(fromOrigin).toHaveText("View in graph")
        try await fromOrigin.click()
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
        let sentence = page.locator("form.graph-view-query")
        try await expect(sentence.locator("input[name='record']")).toHaveValue(translation.path)
        try await expect(sentence.locator(".graph-view-of")).toHaveText("is")
        try await expect(sentence.locator(".graph-relation .dropdown-selected-text")).toHaveText("a translation of")
        try await expect(sentence.locator(".graph-relation [data-display='an adaptation of']")).toHaveCount(1)
        try await expect(page.locator(".records-count-view")).toContainText("1 record")
        let translated = page.locator(".graph-view-table tbody tr")
        try await expect(translated).toHaveCount(1)
        try await expect(translated.locator("a[href='\(citing.path)']")).toHaveCount(1)
        try await expect(translated.locator("a.graph-view-count")).toHaveAttribute("href", "\(translation.path)#origin")
        try await expectTexts(page.locator(".relation-graph-title"), [translation.title, citing.title])
        try await expectTexts(page.locator(".relation-graph-label"), ["translation of"])
        // The arrow runs subject to object: it starts at the root (the translation).
        let edge = try await page.locator(".relation-graph-edge").getAttribute("d") ?? ""
        #expect(edge.hasPrefix("M 8"), "The edge leaves the root: \(edge)")
        await shoot(page, "record-first", layout)
        // The swap control turns it round, the relation and the record kept.
        try await sentence.locator("button[aria-label='Put the relation first']").click()
        try await expect(page.locator("form.graph-view-query .graph-view-of")).toHaveText("of")
        try await expect(page.locator("form.graph-view-query input[name='record']")).toHaveValue(translation.path)
        try await expect(page.locator(".graph-view-empty-message")).toHaveText("No translations.")

        // "Citations of [the cited work]", as its Citations open it.
        try await page.openHydrated(cited.path)
        try await page.locator("#record-citations .accordion-summary").first.click()
        let fromCitations = page.locator("#record-citations a.citations-view-graph")
        try await expect(fromCitations).toHaveText("View in graph")
        // Opened by its address: the accordion is still opening under a tap.
        try await page.goto(try await fromCitations.getAttribute("href") ?? "")
        try await expect(page.locator("form.graph-view-query input[name='record']")).toHaveValue(cited.path)
        try await expect(page.locator(".graph-view-table tbody tr a[href='\(citing.path)']")).toHaveCount(1)

        // Both records sidebars link it first; the bare list is indexed, a
        // filtered one not.
        for list in ["/biblio-records", "/lexico-records"] {
          try await page.openHydrated(list)
          try await expect(page.locator("meta[name='robots']")).toHaveAttribute("content", "index, follow")
          let sidebarLinks = page.locator("aside .sidebar-link")
          try await expect(sidebarLinks.first).toHaveAttribute("href", "/graph")
          try await expect(sidebarLinks.first).toHaveText("Graph")
          try await page.openHydrated("\(list)?treatment=attributed")
          try await expect(page.locator("meta[name='robots']")).toHaveAttribute("content", "noindex, follow")
        }
      }
      await cleanUp()
    } catch {
      await cleanUp()
      throw error
    }
  }

  /// Each of `locator`'s elements has its text, in order, and no more.
  private func expectTexts(_ locator: Locator, _ texts: [String]) async throws {
    try await expect(locator).toHaveCount(texts.count)
    for (index, text) in texts.enumerated() {
      try await expect(locator.nth(index)).toHaveText(text)
    }
  }

  private func shoot(_ page: Page, _ name: String, _ layout: Layout) async {
    guard let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"] else { return }
    try? await page.screenshot(to: URL(fileURLWithPath: directory).appendingPathComponent("graph-\(layout)-\(name).png"))
  }
}
