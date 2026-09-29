import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The Graph page (user, 2026-09-29): how records relate, asked as one
/// query row read as a sentence — "[subject] [relation] [object]", "Letters
/// citation of Hamlet" — each slot a record (a combobox of both halves'
/// records) or left empty to find the records that stand there, the
/// relation a dropdown of the relations stored between records, each named
/// once by a noun ending in "of" ("citation of", "translation of",
/// "container of", "equivalent of"). The query is the address; its answer the pairs as the records
/// lists list records, each count linking to where the pair is shown, over
/// a drawing of them. The home page links it between the two records lists;
/// both records sidebars link it first, above their own sections; a
/// record's Citations and its Origin open it filled with the record. The
/// empty page is indexed, a query's answer (as a filtered records list) is
/// not. Phone and desktop, Chrome headless.
@Suite("Graph", .serialized)
struct GraphTests {
  /// A step of `work`'s origin: translated from `source`.
  static func translated(_ work: ScratchWork, from source: ScratchWork) -> String {
    """
    INSERT INTO biblio_record_origins (id, biblio_record_id, parent_id, position, relation, target_record_id, typed_json, created_at)
      VALUES (gen_random_uuid(), '\(work.recordID.lowercased())', NULL, 0, 'translation_of', '\(source.recordID.lowercased())', NULL, now());
    """
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
      _ = try TestAdmin.query(
        "BEGIN;\n" + EntriesAndCitationsTests.read(citing)
          + EntriesAndCitationsTests.cite(3, by: citing, work: cited.recordID.lowercased())
          + Self.translated(translation, from: cited) + "\nCOMMIT;")
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        // Home: between the two records lists.
        try await page.openHydrated("/")
        let links = page.locator(".home-nav-links a")
        try await expectTexts(links, ["Biblio-records", "Graph", "Lexico-records"])
        try await expect(links.nth(1)).toHaveAttribute("href", "/graph")

        // The empty page: indexed; the query row, its relations by verb phrase.
        try await page.openHydrated("/graph")
        try await expect(page.locator("meta[name='robots']")).toHaveAttribute("content", "index, follow")
        try await expect(page.locator(".graph-view-title")).toHaveText("Graph")
        let query = page.locator("form.graph-view-query")
        try await expect(query.getByRole(.combobox, name: "Subject")).toHaveCount(1)
        try await expect(query.getByRole(.combobox, name: "Object")).toHaveCount(1)
        let relations = query.locator(".graph-relation [data-dropdown-option='true']")
        try await expect(relations.first).toHaveAttribute("data-display", "citation of")
        for noun in [
          "translation of", "exposition of", "derivative of", "borrowing of", "affix of", "back-formation of",
          "eponym of", "container of", "equivalent of",
        ] {
          try await expect(query.locator(".graph-relation [data-display='\(noun)']")).toHaveCount(1)
        }
        // Every noun ends in "of" (user, 2026-09-29).
        let odd = try await page.evaluate(
          "[...document.querySelectorAll(\"form.graph-view-query .graph-relation [data-dropdown-option='true']\")]"
            + ".map(o => o.dataset.display).filter(noun => !noun.endsWith(' of'))")
        #expect(odd == .array([]), "Nouns not ending in of: \(odd)")
        try await expect(page.locator(".relation-graph-view")).toHaveCount(0)
        await shoot(page, "empty", layout)

        // "— citation of [the cited work]", the object chosen from its suggestions.
        let object = query.getByRole(.combobox, name: "Object")
        try await object.fill(cited.suffix)
        let suggestion = query.locator("#graph-object-listbox [role='option']").filter(hasText: cited.title)
        try await expect(suggestion.first).toBeVisible()
        try await suggestion.first.click()
        try await expect(query.locator("input[name='object']")).toHaveValue(cited.path)
        try await page.goto(
          "/graph?subject=&relation=citation-of&object=\(cited.path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"
        )
        try await expect(page.locator("meta[name='robots']")).toHaveAttribute("content", "noindex, follow")
        try await expect(page.locator(".records-count-view")).toContainText("1 pair")
        let row = page.locator(".graph-view-table tbody tr")
        try await expect(row).toHaveCount(1)
        try await expect(row.locator("a[href='\(citing.path)']")).toHaveCount(1)
        try await expect(row).toContainText("English")
        let count = row.locator("a.graph-view-count")
        try await expect(count).toHaveText("3 citations")
        try await expect(count).toHaveAttribute(
          "href", "\(cited.path)/citations?work=\(citing.recordID)&direction=citations")
        // The drawing: the object a hub, the subject under it, the edge named.
        let drawing = page.locator(".relation-graph-view svg")
        try await expect(drawing).toHaveCount(1)
        try await expectTexts(drawing.locator(".relation-graph-title"), [cited.title, citing.title])
        try await expectTexts(drawing.locator(".relation-graph-label"), ["citation of"])
        let fits = try await drawing.evaluate("svg => svg.getBoundingClientRect().right <= window.innerWidth + 1")
        #expect(fits == .bool(true), "The drawing fits the page's width.")
        await shoot(page, "citation-of", layout)
        // No pairs: said in words, no drawing.
        try await page.goto(
          "/graph?subject=&relation=container-of&object=\(cited.path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"
        )
        try await expect(page.locator(".records-count-view")).toContainText("0 pairs")
        try await expect(page.locator(".graph-view-empty-message")).toHaveText("No pairs.")
        try await expect(page.locator(".relation-graph-view")).toHaveCount(0)
        await shoot(page, "no-pairs", layout)
        try await page.goto(
          "/graph?subject=&relation=citation-of&object=\(cited.path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"
        )
        try await count.click()
        try await expect(page.locator(".record-citations-view-citation")).toHaveCount(3)

        // "[the translation] translation of —", as its Origin opens it.
        try await page.openHydrated(translation.path)
        let fromOrigin = page.locator("#origin a.origin-section-graph")
        try await expect(fromOrigin).toHaveText("View in graph")
        try await fromOrigin.click()
        try await expect(page.locator("input[name='subject']")).toHaveValue(translation.path)
        let translated = page.locator(".graph-view-table tbody tr")
        try await expect(translated).toHaveCount(1)
        try await expect(translated.locator("a[href='\(cited.path)']")).toHaveCount(1)
        try await expect(translated.locator("a.graph-view-count")).toHaveAttribute("href", "\(translation.path)#origin")
        try await expectTexts(page.locator(".relation-graph-label"), ["translation of"])

        // "— citation of [the cited work]", as its Citations open it.
        try await page.openHydrated(cited.path)
        try await page.locator("#record-citations .accordion-summary").first.click()
        let fromCitations = page.locator("#record-citations a.citations-view-graph")
        try await expect(fromCitations).toHaveText("View in graph")
        // Opened by its address: the accordion is still opening under a tap.
        try await page.goto(try await fromCitations.getAttribute("href") ?? "")
        try await expect(page.locator("input[name='object']")).toHaveValue(cited.path)
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
        // No Cites filter any more.
        try await page.openHydrated("/biblio-records")
        try await expect(page.locator(".filter-bar-view").getByText("Cites", exact: true)).toHaveCount(0)
        await shoot(page, "biblio-records", layout)
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
