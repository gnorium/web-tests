import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A work's ORIGIN: on Submit Testament an Origin block in the work (no
/// "This is a translation" box), "+ Add origin" rows, each a relation, a
/// record field (searched, two rows an option) and, once a record is picked,
/// its testaments to name one by; with no record, the work as typed and
/// "+ Add origin" under it for its own origin. The form posts the rows as
/// one JSON list (the submit event is dispatched by hand, which runs the
/// form's script but never posts). On a record page, the Origin accordion
/// after the Metadata reads the chain ("Translation of — …", deeper steps
/// "which is a translation of …"), and the source record lists its
/// translations. A throwaway admin owns two scratch works, removed after.
@Suite("Origin", .serialized)
struct OriginTests {
  static let form = "/mission-control/submit/bibliographic/evidence-testament"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func originRowsAndTheRecordPage(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let original = try ScratchWork(owner: admin)
    let translation = try ScratchWork(owner: admin)
    let typed = "Web tests Old English \(translation.suffix)"
    do {
      // The translation's origin, as a permit writes it: a typed Old
      // English step, which is a translation of the original's record.
      let step = UUID().uuidString.lowercased()
      _ = try TestAdmin.query(
        """
        INSERT INTO biblio_record_origins (id, biblio_record_id, parent_id, position, relation, target_record_id, typed_json, created_at)
          VALUES ('\(step)', '\(translation.recordID.lowercased())', NULL, 0, 'translation_of', NULL,
            '{"language":"ang","title":"\(typed)"}', now());
        INSERT INTO biblio_record_origins (id, biblio_record_id, parent_id, position, relation, target_record_id, typed_json, created_at)
          VALUES ('\(UUID().uuidString.lowercased())', '\(translation.recordID.lowercased())', '\(step)', 0,
            'translation_of', '\(original.recordID.lowercased())', NULL, now());
        """)
      try await run(
        engine: engine, viewport: layout.viewport(for: engine), admin: admin, original: original,
        translation: translation, typed: typed)
    } catch {
      translation.remove()
      original.remove()
      await admin.remove()
      throw error
    }
    translation.remove()
    original.remove()
    await admin.remove()
  }

  private func run(
    engine: BrowserEngine, viewport: Viewport, admin: TestAdmin, original: ScratchWork, translation: ScratchWork,
    typed: String
  ) async throws {
    try await withPage(engine, gnorium, viewport: viewport, cookies: [admin.cookie]) { page in
      try await page.openHydrated(Self.form)
      let form = page.locator(".submit-testament-form")
      // No translation box and no chain: an Origin block in the work.
      try await expect(form.locator(".is-translation-checkbox-wrapper")).toHaveCount(0)
      try await expect(form.locator(".translation-chain-view")).toHaveCount(0)
      let block = form.locator(".origin-field-view")
      try await expect(block).toHaveCount(1)
      try await expect(block.locator(".origin-field-view-heading")).toHaveText("Origin")
      let top = block.locator(":scope > [data-origin-list='true']")
      let rows = top.locator(":scope > [data-origin-row='true']")
      try await expect(rows).toHaveCount(0)

      // "+ Add origin": a row, its relation, its record field, its typed
      // fields while no record is picked.
      try await top.locator(":scope > div > .origin-add-btn").click()
      try await expect(rows).toHaveCount(1)
      let first = rows.first
      try await expect(first).toContainText("Origin relation")
      let relation = first.locator(".dropdown-view").first
      try await relation.locator(".dropdown-trigger").click()
      try await relation.locator(".dropdown-option[data-value='translation_of']").click()
      try await expect(relation.locator(".dropdown-selected-text")).toHaveText("Translation of")
      let record = first.locator(":scope > .origin-field-view-record .origin-record-field-view")
      try await expect(record.locator("legend")).toContainText("Origin record")
      let typedFields = first.locator(":scope > .origin-field-view-typed")
      try await expect(typedFields).toBeVisible()

      // Pick the original's record: the typed fields go; its testaments
      // follow, to name one by.
      let picker = record.locator(".dropdown-view").first
      try await picker.locator(".dropdown-trigger").click()
      try await picker.locator(".dropdown-search-input").fill(original.suffix)
      let found = picker.locator(
        ".dropdown-options-list[data-dropdown-results='true'] .dropdown-option[data-value='\(original.recordID)']")
      try await expect(found.locator(".breadcrumb-label-text")).toHaveText(original.title)
      try await found.click()
      try await expect(typedFields).toBeHidden()
      let node = first.locator(".origin-record-field-view .dropdown-view").nth(1)
      try await expect(first.locator(".origin-record-field-view")).toContainText("Origin testament")
      let edition = node.locator(".dropdown-option[data-value^='edition-']")
      try await expect(edition).toHaveCount(1)
      try await node.locator(".dropdown-trigger").click()
      try await edition.click()

      // A second row, typed: its own "+ Add origin" gives it an origin of
      // its own.
      try await top.locator(":scope > div > .origin-add-btn").click()
      try await expect(rows).toHaveCount(2)
      let second = rows.nth(1)
      // Its record field is asked for once it is on the page: settled, the
      // row stops moving what is under it.
      try await expect(second.locator(".origin-record-field-view")).toHaveCount(1)
      let secondRelation = second.locator(".dropdown-view").first
      try await secondRelation.locator(".dropdown-trigger").click()
      try await secondRelation.locator(".dropdown-option[data-value='adaptation_of']").click()
      try await second.locator("input[name$='-title']").first.fill("Web tests typed work")
      try await second.locator("input[name$='-voices']").first.fill("Ann Author; Bea Author")
      let nestedList = second.locator(":scope > .origin-field-view-typed > [data-origin-list='true']")
      try await nestedList.locator(":scope > div > .origin-add-btn").click()
      let nested = nestedList.locator(":scope > [data-origin-row='true']")
      try await expect(nested).toHaveCount(1)
      try await expect(nested.first.locator(".origin-record-field-view")).toHaveCount(1)
      let nestedRelation = nested.first.locator(".dropdown-view").first
      try await nestedRelation.locator(".dropdown-trigger").click()
      try await nestedRelation.locator(".dropdown-option[data-value='translation_of']").click()
      try await nested.first.locator("input[name$='-title']").first.fill("Web tests deeper work")

      // What the form posts: the rows in order, the typed row's own under it.
      let posted = try await form.evaluate(
        """
        (form) => {
          form.dispatchEvent(new Event('submit', { cancelable: true }));
          return form.querySelector('.origin-field-view-json').value;
        }
        """
      ).string ?? ""
      let json = try JSONSerialization.jsonObject(with: Data(posted.utf8)) as? [[String: Any]] ?? []
      #expect(json.count == 2, "\(posted)")
      #expect(json.first?["relation"] as? String == "translation_of")
      #expect(json.first?["record"] as? String == original.recordID)
      #expect((json.first?["node"] as? String)?.hasPrefix("edition-") == true, "\(posted)")
      let secondPosted = json.count > 1 ? json[1] : [:]
      #expect(secondPosted["relation"] as? String == "adaptation_of")
      let secondTyped = secondPosted["typed"] as? [String: Any] ?? [:]
      #expect(secondTyped["title"] as? String == "Web tests typed work")
      let voices = (secondTyped["voices"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
      #expect(voices == ["Ann Author", "Bea Author"])
      let deeper = secondPosted["origins"] as? [[String: Any]] ?? []
      #expect(deeper.count == 1)
      #expect((deeper.first?["typed"] as? [String: Any])?["title"] as? String == "Web tests deeper work")

      // Unset the pick: "—", the testaments go, the typed fields come back.
      try await picker.locator(".dropdown-trigger").click()
      // The menu settled open before its option is aimed at.
      let chosen = picker.locator(".dropdown-option[data-value='\(original.recordID)']").first
      try await expect(chosen).toBeVisible()
      try await chosen.click()
      try await expect(first.locator(".origin-record-field-view")).not.toContainText("Origin testament")
      try await expect(typedFields).toBeVisible()
      // A row removed.
      try await second.locator(":scope > div > .origin-remove-btn").click()
      try await expect(rows).toHaveCount(1)

      // Nothing scrolls sideways.
      let overflow = try await page.evaluate("document.documentElement.scrollWidth > window.innerWidth").bool
      #expect(overflow == false)

      // The translation's page: Origin after Metadata, closed; opened, the
      // chain, the typed step plain, the original linked under it.
      try await page.openHydrated(translation.path)
      let accordion = page.locator("#record-origin")
      try await expect(accordion).toHaveCount(1)
      try await expect(accordion).not.toHaveAttribute("open", "")
      let order = try await page.evaluate(
        """
        (() => {
          const metadata = document.querySelector('#record-metadata');
          const origin = document.querySelector('#record-origin');
          return !!(metadata && origin && (metadata.compareDocumentPosition(origin) & Node.DOCUMENT_POSITION_FOLLOWING));
        })()
        """
      ).bool
      #expect(order == true, "Origin is not after Metadata")
      try await page.locator("#record-origin > .accordion-summary").click()
      let steps = accordion.locator(".origin-list-view-line")
      try await expect(steps.first).toContainText("Translation of — \(typed) (Old English) · — · —")
      try await expect(steps.nth(1)).toContainText("which is a translation of — \(original.title) (English)")
      try await expect(steps.nth(1).locator("a[href='\(original.path)']")).toHaveCount(1)

      // The original lists it among its translations.
      try await page.openHydrated(original.path)
      try await expect(page.locator(".record-sidebar-view a[href='\(translation.path)']").first).toBeAttached()
    }
  }
}
