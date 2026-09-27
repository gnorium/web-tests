import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The testament form is the testament tree's four levels (user,
/// 2026-09-27): the work first, then an edition's Publication, a copy's
/// Production and a manifest's Digitization, each an accordion of its date,
/// place and agents and its own fields, parted by dividers; no level named,
/// no Creation. The Production (the copy) shows only while the type is
/// Manuscript and is not posted otherwise. A level dated before the work is
/// warned of as it is typed, never refused. Nothing is submitted (the submit
/// event is dispatched by hand, which runs the form's script but never
/// posts). Needs a signed-in account, made for the test and removed after.
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
            '#work-language', '#work-title', "[data-item-list='work-progenitor']", "[name='year']", '#work-place',
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

      // The copy: hidden until the type is Manuscript, hidden again after.
      let copy = form.locator(".activity-statement-view[data-as-namespace='production']")
      try await expect(copy).toBeHidden()
      let type = form.locator(".dropdown-view:has(#work-type)").first
      try await choose("manuscript", "Manuscript", in: type)
      try await expect(copy).toBeVisible()
      try await expect(form.locator("#as-accordion-production .accordion-title").first).toContainText("Production")
      try await shoot(page, "manuscript", layout)
      try await choose("book", "Book", in: type)
      try await expect(copy).toBeHidden()

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

      // What the form posts: each level's statement by its kind, the hidden
      // copy's left out.
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
}
