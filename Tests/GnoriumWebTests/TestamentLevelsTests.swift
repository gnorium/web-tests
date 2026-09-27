import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The testament form is the testament tree's four levels (user,
/// 2026-09-27): the work first, then an edition's Publication, a copy's
/// Acquisition and a manifest's Digitization, each an accordion of its date,
/// place and agents and its own fields, parted by dividers; no level named,
/// no Creation. Every copy has its holding (institution, shelf mark, copy
/// label); only a manuscript's has its production: those rows show only
/// while the type is Manuscript and are not posted otherwise, and a
/// production already stored is kept when a testament that does not record
/// it is modified. A level dated before the work is warned of as it is
/// typed, never refused. On Submit Testament nothing is submitted (the
/// submit event is dispatched by hand, which runs the form's script but
/// never posts); the modify test posts a modification of its own scratch
/// overture and removes both. Needs a signed-in account, made for the test
/// and removed after.
///
/// `GNORIUM_SCREENSHOT_DIR` set, it saves what it sees there.
@Suite("Testament levels")
struct TestamentLevelsTests {
  static let form = "/mission-control/submit/bibliographic/evidence-testament"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func theWorkThenItsLevels(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await run(engine: engine, layout: layout, admin: admin)
    } catch {
      await admin.remove()
      throw error
    }
    await admin.remove()
  }

  private func shoot(_ page: Page, _ name: String, _ layout: Layout) async throws {
    guard let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"] else { return }
    try await page.screenshot(to: URL(fileURLWithPath: directory).appendingPathComponent("levels-\(layout)-\(name).png"))
  }

  /// Chosen as a reader chooses in a long list: the menu opened, the
  /// option's name typed into its search, the match clicked.
  private func choose(_ value: String, _ display: String, in dropdown: Locator) async throws {
    try await dropdown.locator(".dropdown-trigger").click()
    try await dropdown.locator(".dropdown-search-input").fill(display)
    try await dropdown.locator(".dropdown-option[data-value='\(value)']").filter(visible: true).first.click()
  }

  private func run(engine: BrowserEngine, layout: Layout, admin: TestAdmin) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
      try await page.openHydrated(Self.form)
      let form = page.locator(".submit-testament-form")
      try await shoot(page, "top", layout)

      // The work, whole and first; then the three levels, in the tree's
      // order, each its date, its place, its agents, then its own fields.
      let order = try await form.evaluate(
        """
        (form) => {
          const at = (selector) => form.querySelector(selector);
          const chain = [
            '#work-language', '#work-title', "[data-item-list='work-voice']", "[name='year']", '#work-place',
            '#work-type', "[data-item-list='work-genre']", '.bibliographic-level-divider',
            ".activity-statement-view[data-as-namespace='publication']", '#work-edition',
            ".activity-statement-view[data-as-namespace='production']", '#testament-copy-label',
            ".activity-statement-view[data-as-namespace='digitization']", '#testament-source-url', '#testament-license',
          ];
          for (let i = 1; i < chain.length; i++) {
            const a = at(chain[i - 1]), b = at(chain[i]);
            if (!a || !b) return 'missing ' + (a ? chain[i] : chain[i - 1]);
            if (!(a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING)) return chain[i] + ' before ' + chain[i - 1];
          }
          for (const kind of ['publication', 'production', 'digitization']) {
            const block = at(`.activity-statement-view[data-as-namespace='${kind}']`);
            const parts = [`[name='as-${kind}-year']`, `[name='as-${kind}-place']`, `[data-item-list='as-${kind}']`]
              .map((s) => block.querySelector(s));
            if (parts.some((p) => !p)) return kind + ' lacks a part';
            if (!(parts[0].compareDocumentPosition(parts[1]) & Node.DOCUMENT_POSITION_FOLLOWING)
              || !(parts[1].compareDocumentPosition(parts[2]) & Node.DOCUMENT_POSITION_FOLLOWING)) return kind + ' out of order';
          }
          return 'ok';
        }
        """
      ).string
      #expect(order == "ok", "\(order ?? "")")
      try await expect(form.locator("[data-as-namespace='creation']")).toHaveCount(0)
      for (kind, heading) in [("publication", "Publication"), ("digitization", "Digitization")] {
        try await expect(form.locator("#as-accordion-\(kind) .accordion-title").first).toContainText(heading)
      }
      try await expect(form.locator(".section-legend").filter(hasText: "Provision")).toHaveCount(0)

      // The copy's holding, for every type; its production rows hidden
      // until the type is Manuscript, hidden again after.
      let copy = form.locator(".activity-statement-view[data-as-namespace='production']")
      let production = copy.locator(".as-event")
      try await expect(copy).toBeVisible()
      try await expect(form.locator("#as-accordion-production .accordion-title").first).toContainText("Acquisition")
      let holding = form.locator("#as-accordion-production")
      if !(try await form.locator("#testament-copy-label").isVisible()) {
        try await holding.locator(".accordion-summary").first.click()
      }
      try await expect(form.locator("#testament-copy-label")).toBeVisible()
      try await expect(copy.locator("input[name='holding-institution-dropdown']")).toHaveCount(1)
      try await expect(copy.locator(".section-legend").filter(hasText: "Shelf mark or call number")).toBeVisible()
      try await expect(production).toBeHidden()
      let type = form.locator(".dropdown-view:has(#work-type)").first
      try await choose("book", "Book", in: type)
      try await expect(form.locator("#testament-copy-label")).toBeVisible()
      try await expect(production).toBeHidden()
      try await choose("manuscript", "Manuscript", in: type)
      try await expect(production).toBeVisible()
      try await expect(copy.locator("input[name='as-production-place']")).toBeVisible()
      try await shoot(page, "manuscript", layout)
      try await choose("book", "Book", in: type)
      try await expect(production).toBeHidden()
      try await expect(form.locator("#testament-copy-label")).toBeVisible()

      // The date check: a publication before the work is warned of under
      // its date, and the warning goes when the date is mended.
      _ = try await form.evaluate(
        """
        (form) => {
          for (const id of ['#work-year-qualifier', '#as-publication-year-qualifier']) {
            const input = form.querySelector(id);
            input.value = 'exact';
            input.dispatchEvent(new Event('change', { bubbles: true }));
          }
          return true;
        }
        """)
      try await form.locator("input[name='year']").fill("1600")
      let publication = form.locator("#as-accordion-publication")
      let publicationYear = form.locator("input[name='as-publication-year']")
      if !(try await publicationYear.isVisible()) {
        try await publication.locator(".accordion-summary").first.click()
      }
      try await expect(publicationYear).toBeVisible()
      try await publicationYear.fill("1590")
      let warning = form.locator(
        ".activity-statement-date-check[data-date-check='publication'] .field-validation-message-view[data-status='warning']")
      try await expect(warning).toBeVisible()
      try await expect(warning).toContainText("Earlier than the work's date")
      // Under the publication's own date.
      let yearBox = try await publicationYear.boundingBox()
      let warningBox = try await warning.boundingBox()
      #expect((yearBox?.maxY ?? .infinity) <= (warningBox?.minY ?? 0), "the warning is not under the date")
      try await expect(publication).toHaveAttribute("data-open-finished", "true")
      _ = try await warning.evaluate("(el) => { el.scrollIntoView({ block: 'center' }); return true; }")
      try await shoot(page, "warning", layout)
      try await publicationYear.fill("1610")
      try await expect(warning).toHaveCount(0)

      // What the form posts: each level's statement by its kind, a book's
      // production left out.
      let posted = try await form.evaluate(
        """
        (form) => {
          form.dispatchEvent(new Event('submit', { cancelable: true }));
          return form.querySelector('.activity-statements-json').value;
        }
        """
      ).string ?? ""
      let statements = try JSONSerialization.jsonObject(with: Data(posted.utf8)) as? [[String: Any]] ?? []
      #expect(statements.map { $0["kind"] as? String } == ["publication", "digitization"])
      #expect(statements.first?["year"] as? Int == 1610)
      #expect(statements.allSatisfy { $0["type"] == nil }, "No creation, no provision tag.")

      try await page.expectNoErrors()
      try await page.expectNoHorizontalOverflow()
    }
  }

  /// A book's overture, modified: its holding shown and posted, its stored
  /// production hidden, not posted, and kept by the server as it stood.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aModifiedBookKeepsItsHoldingAndItsProduction(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let submission = UUID().uuidString.lowercased()
    let evidence = UUID().uuidString.lowercased()
    let overture = UUID().uuidString.lowercased()
    func remove() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM modifications WHERE modifiable_id = '\(overture)';
        DELETE FROM bibliographic_overtures WHERE id = '\(overture)';
        DELETE FROM bibliographic_evidences WHERE id = '\(evidence)';
        DELETE FROM submissions WHERE id = '\(submission)';
        COMMIT;
        """)
    }
    do {
      let user = try admin.column("id")
      let statements = """
        [{"kind":"publication","place":"London","agents":[],"year":1623},\
        {"kind":"production","place":"Web tests scriptorium","agents":[{"role":"scribe","name":"Web Tests Scribe"}],"year":1601}]
        """
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO submissions (id, user_id) VALUES ('\(submission)', '\(user)');
        INSERT INTO bibliographic_evidences (id, batch_id, source_url, language, processing_status, title, type, year)
          VALUES ('\(evidence)', '\(submission)', 'https://example.org/web-tests/levels', 'eng', 'pending',
            'Web tests levels \(overture.prefix(8))', 'book', 1623);
        INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_evidence_id, source_url, language, processing_status, title, type,
          year_qualifier, era, year, provider, holding_institution, copy_label, shelf_mark_json, activity_statements_json)
          VALUES ('\(overture)', '\(submission)', '\(evidence)', 'https://example.org/web-tests/levels', 'eng', 'pending',
            'Web tests levels \(overture.prefix(8))', 'book', 'exact', 'anno_domini', 1623, 'folger_shakespeare_library',
            'folger_shakespeare_library', 'Web tests copy 9', '{"scheme":"stc","value":"22273"}', '\(statements)');
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/overtures/bibliographic/\(overture)/modify")
        let form = page.locator(".modify-bibliographic-overture-form")
        let copy = form.locator(".activity-statement-view[data-as-namespace='production']")
        try await expect(form.locator("#as-accordion-production .accordion-title").first).toContainText("Acquisition")
        let label = form.locator("#testament-copy-label")
        if !(try await label.isVisible()) {
          try await form.locator("#as-accordion-production .accordion-summary").first.click()
        }
        try await expect(label).toBeVisible()
        try await expect(label).toHaveValue("Web tests copy 9")
        try await expect(copy.locator("input[name='shelf_mark_value']")).toHaveValue("22273")
        try await expect(copy.locator("input[name='holding_institution']")).toHaveValue("folger_shakespeare_library")
        let production = copy.locator(".as-event")
        try await expect(production).toBeHidden()
        // Set to Manuscript, the stored production shows; back to Book, it hides.
        let type = form.locator(".dropdown-view:has(#work-type)").first
        try await choose("manuscript", "Manuscript", in: type)
        try await expect(copy.locator("input[name='as-production-place']")).toHaveValue("Web tests scriptorium")
        try await choose("book", "Book", in: type)
        try await expect(production).toBeHidden()
        try await shoot(page, "modify-book", layout)
        try await label.fill("Web tests copy 10")

        try await form.locator("button[type='submit']").first.click()
        // The post answers with a redirect off the form.
        var left = false
        for _ in 0..<60 where !left {
          left = !(try await page.url()).contains("/modify")
          if !left { try await Task.sleep(for: .milliseconds(250)) }
        }
        #expect(left, "The modification was not posted.")
      }
      let content = try TestAdmin.query(
        "SELECT content_json FROM modifications WHERE modifiable_id = '\(overture)' ORDER BY created_at DESC LIMIT 1")
      let json = try JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any] ?? [:]
      #expect(json["copyLabel"] as? String == "Web tests copy 10", "A book's copy label is posted and kept.")
      #expect(json["holdingInstitution"] as? String == "folger_shakespeare_library")
      #expect((json["shelfMarkOrCallNumber"] as? [String: Any])?["value"] as? String == "22273")
      let kept = (json["activityStatements"] as? [[String: Any]] ?? []).first { $0["kind"] as? String == "production" }
      #expect(kept?["place"] as? String == "Web tests scriptorium", "The stored production is not wiped.")
      #expect(kept?["year"] as? Int == 1601)
    } catch {
      remove()
      await admin.remove()
      throw error
    }
    remove()
    await admin.remove()
  }
}
