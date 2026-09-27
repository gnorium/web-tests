import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The testament form is the testament tree's levels (user, 2026-09-28):
/// the work first, then cards named for events, each on the node the event
/// happened to — an edition's Publication, a copy's Production and its
/// Acquisition (holding institution, shelf mark, copy label), a
/// Digitization — each event as an imprint gives it (place, agents, date);
/// no level named, no Creation, no type check. A level dated before the
/// work is warned of as it is
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
      // order, each as a title page gives it: an edition's forms and
      // statement, then each level's imprint — its place, its agents, its
      // date (ISBD area 4, MARC 264) — then its own fields.
      let order = try await form.evaluate(
        """
        (form) => {
          const at = (selector) => form.querySelector(selector);
          const chain = [
            '#work-language', '#work-title', "[data-item-list='work-voice']", "[name='year']", '#work-place',
            '#work-type', "[data-item-list='work-genre']",
            ".activity-statement-view[data-as-namespace='publication']", "[data-item-list='title-form']",
            '#work-edition', "[name='as-publication-place']",
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
            const parts = [`[name='as-${kind}-place']`, `[data-item-list='as-${kind}']`, `[name='as-${kind}-year']`]
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
      // Each level a framed card, open on a new testament, parted from the
      // next by the form's gap: no rule anywhere between them.
      try await expect(form.locator(".bibliographic-level-divider, .accordion-divider")).toHaveCount(0)
      for kind in ["publication", "production", "digitization"] {
        let card = form.locator(".framed-accordion-view:has(> .accordion-view > #as-accordion-\(kind))")
        try await expect(card).toHaveCount(1)
        try await expect(card.locator(":scope > .accordion-view")).toHaveAttribute("data-separation", "outline")
        try await expect(form.locator("#as-accordion-\(kind)")).toHaveAttribute("data-expanded", "true")
        try await expect(card.locator(".framed-accordion-content").first).toBeVisible()
      }
      let surfaces = try await form.evaluate(
        """
        (form) => {
          const card = form.querySelector('.framed-accordion-view');
          const box = card.querySelector('.framed-accordion-content');
          const row = box.querySelector('.item-section');
          const color = (el) => getComputedStyle(el).backgroundColor;
          return [color(card), color(box), row ? color(row) : ''];
        }
        """
      ).array?.compactMap(\.string) ?? []
      #expect(surfaces.count == 3 && surfaces[0] != surfaces[1] && surfaces[1] != surfaces[2], "\(surfaces)")
      try await expect(form.locator("[data-as-namespace='creation']")).toHaveCount(0)
      for (kind, heading) in [("publication", "Publication"), ("digitization", "Digitization")] {
        try await expect(form.locator("#as-accordion-\(kind) .accordion-title").first).toContainText(heading)
      }
      try await expect(form.locator(".section-legend").filter(hasText: "Provision")).toHaveCount(0)

      // The copy's Production, then its Acquisition, whatever the type.
      try await expect(form.locator("#as-accordion-production .accordion-title").first).toContainText("Production")
      let acquisition = form.locator("#acquisition-accordion")
      try await expect(acquisition.locator(".accordion-title").first).toContainText("Acquisition")
      try await expect(acquisition).toContainText("Who holds this copy and where, with its shelf mark and copy label.")
      if !(try await form.locator("#testament-copy-label").isVisible()) {
        try await acquisition.locator(".accordion-summary").first.click()
      }
      try await expect(form.locator("#testament-copy-label")).toBeVisible()
      try await expect(acquisition.locator("input[name='holding-institution-dropdown']")).toHaveCount(1)
      try await expect(acquisition.locator(".section-legend").filter(hasText: "Shelf mark or call number")).toBeVisible()
      try await expect(form.locator("input[name='as-production-place']")).toHaveCount(1)

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

      // What the form posts: each event's statement by its kind, an empty
      // production a slot.
      let posted = try await form.evaluate(
        """
        (form) => {
          form.dispatchEvent(new Event('submit', { cancelable: true }));
          return form.querySelector('.activity-statements-json').value;
        }
        """
      ).string ?? ""
      let statements = try JSONSerialization.jsonObject(with: Data(posted.utf8)) as? [[String: Any]] ?? []
      #expect(statements.map { $0["kind"] as? String } == ["publication", "production", "digitization"])
      #expect(statements.first?["year"] as? Int == 1610)
      #expect(statements.allSatisfy { $0["type"] == nil }, "No creation, no provision tag.")

      try await page.expectNoErrors()
      try await page.expectNoHorizontalOverflow()
    }
  }

  /// A manuscript's overture, modified: no edition, its Production shown
  /// and posted as it stands, its Acquisition shown and posted.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aModifiedManuscriptKeepsItsProductionAndItsAcquisition(engine: BrowserEngine, layout: Layout) async throws {
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
        [{"kind":"production","place":"Web tests scriptorium","agents":[{"role":"scribe","name":"Web Tests Scribe"}],"year":1601}]
        """
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO submissions (id, user_id) VALUES ('\(submission)', '\(user)');
        INSERT INTO bibliographic_evidences (id, batch_id, source_url, language, processing_status, title, type, year)
          VALUES ('\(evidence)', '\(submission)', 'https://example.org/web-tests/levels', 'eng', 'pending',
            'Web tests levels \(overture.prefix(8))', 'manuscript', 1623);
        INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_evidence_id, source_url, language, processing_status, title, type,
          year_qualifier, era, year, provider, holding_institution, copy_label, shelf_mark_json, activity_statements_json)
          VALUES ('\(overture)', '\(submission)', '\(evidence)', 'https://example.org/web-tests/levels', 'eng', 'pending',
            'Web tests levels \(overture.prefix(8))', 'manuscript', 'exact', 'anno_domini', 1623, 'folger_shakespeare_library',
            'folger_shakespeare_library', 'Web tests copy 9', '{"scheme":"stc","value":"22273"}', '\(statements)');
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/overtures/bibliographic/\(overture)/modify")
        let form = page.locator(".modify-bibliographic-overture-form")
        let copy = form.locator(".activity-statement-view[data-as-namespace='production']")
        try await expect(form.locator("#as-accordion-production .accordion-title").first).toContainText("Production")
        let acquisition = form.locator("#acquisition-accordion")
        let label = form.locator("#testament-copy-label")
        if !(try await label.isVisible()) {
          try await acquisition.locator(".accordion-summary").first.click()
        }
        try await expect(label).toBeVisible()
        try await expect(label).toHaveValue("Web tests copy 9")
        try await expect(acquisition.locator("input[name='shelf_mark_value']")).toHaveValue("22273")
        try await expect(acquisition.locator("input[name='holding_institution']")).toHaveValue("folger_shakespeare_library")
        if !(try await copy.locator("input[name='as-production-place']").isVisible()) {
          try await form.locator("#as-accordion-production .accordion-summary").first.click()
        }
        try await expect(copy.locator("input[name='as-production-place']")).toHaveValue("Web tests scriptorium")
        try await shoot(page, "modify-manuscript", layout)
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
      #expect(json["copyLabel"] as? String == "Web tests copy 10", "Its copy label is posted and kept.")
      #expect(json["holdingInstitution"] as? String == "folger_shakespeare_library")
      #expect((json["shelfMarkOrCallNumber"] as? [String: Any])?["value"] as? String == "22273")
      let kept = (json["activityStatements"] as? [[String: Any]] ?? []).first { $0["kind"] as? String == "production" }
      #expect(kept?["place"] as? String == "Web tests scriptorium", "Its production is posted as it stands.")
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
