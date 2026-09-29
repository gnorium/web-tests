import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A work's ORIGIN: on Submit Testament an Origin block in the work (no
/// "This is a translation" box), "+ Add origin step" rows, each a relation, a
/// record field (searched, two rows an option) and, once a record is picked,
/// its testaments to name one by; with no record, the work as typed and
/// "+ Add origin step" under it for its own origin. The form posts the rows as
/// one JSON list (the submit event is dispatched by hand, which runs the
/// form's script but never posts). On a record page, the Origin section
/// after the Metadata is a paragraph of prose ("A translation of the Old
/// English …, which is a translation of the English report …, authored by
/// …."), and the source record lists its translations. A throwaway admin owns two scratch works, removed after.
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
            '{"language":"ang","title":"\(typed)","type":"treatise","date":{"era":"anno_domini","year":890,"yearQualifier":"circa"}}', now());
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
      // No heading; one row to start, as the voices have.
      try await expect(block.locator(".origin-field-view-heading")).toHaveCount(0)
      let top = block.locator(":scope > [data-origin-list='true']")
      let rows = top.locator(":scope > [data-origin-row='true']")
      try await expect(rows).toHaveCount(1)

      // The row: its relation (a plain noun), its record field, its typed
      // fields while no record is picked, its own "+ Add origin step" beside
      // "× Remove origin step".
      let first = rows.first
      try await expect(first.locator(".origin-record-field-view")).toHaveCount(1)
      let actions = first.locator(":scope > .origin-field-view-actions")
      try await expect(actions.locator("button")).toHaveTexts(["+ Add origin step", "× Remove origin step"])
      let sideBySide = try await actions.evaluate(
        "(a) => { const [x, y] = a.querySelectorAll('button'); return Math.abs(x.getBoundingClientRect().top - y.getBoundingClientRect().top) < 4 }"
      ).bool
      // One row where there is room; a narrow phone wraps them.
      if viewport.width >= 768 { #expect(sideBySide == true, "the row's actions are one row") }
      try await expect(first).toContainText("Relation")
      let relation = first.locator(".dropdown-view").first
      // Its tooltip, as the bubble says it when shown.
      let tooltip = { () async throws -> String in
        try await relation.locator(".dropdown-label [data-tooltip='true']").hover()
        let bubble = page.locator(".tooltip-view[data-portal='true'][data-visible='true'] .tooltip-content")
        try await expect(bubble).toHaveCount(1)
        let text = try await bubble.evaluate("(e) => e.textContent.trim()").string ?? ""
        // Away again, so the bubble covers nothing the test clicks next.
        try await relation.locator(".dropdown-label-text").hover()
        try await expect(bubble).toHaveCount(0)
        return text
      }
      #expect(try await tooltip() == "How this record came from the one the row names.")
      // A work's relations in FRBR's order: Transformation (another type of
      // work) after Adaptation (the same type).
      try await expect(relation.locator(".dropdown-option .dropdown-option-display-text")).toHaveTexts([
        "Translation", "Adaptation", "Transformation", "Abridgment", "Continuation", "Exposition", "Derivation",
        "Compilation", "Conflation",
      ])
      try await relation.locator(".dropdown-trigger").click()
      try await relation.locator(".dropdown-option[data-value='translation_of']").click()
      try await expect(relation.locator(".dropdown-selected-text")).toHaveText("Translation")
      // The tooltip now says what a translation is.
      #expect(try await tooltip() == "A rendering of the work in another language.")
      // How sure it is: optional, certain unless said.
      let certainty = first.locator(".dropdown-view").nth(1)
      try await expect(first).toContainText("Certainty")
      try await certainty.locator(".dropdown-trigger").click()
      try await certainty.locator(".dropdown-option[data-value='probable']").click()
      try await expect(certainty.locator(".dropdown-selected-text")).toHaveText("Probable")
      let record = first.locator(":scope > .origin-field-view-record .origin-record-field-view")
      try await expect(record.locator("legend")).toContainText("Record")
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
      // A record's origin is its own: no "+ Add origin step" under a picked record.
      try await expect(actions.locator(".origin-add-own-btn")).toBeHidden()
      let node = first.locator(".origin-record-field-view .dropdown-view").nth(1)
      try await expect(first.locator(".origin-record-field-view")).toContainText("Testament")
      let edition = node.locator(".dropdown-option[data-value^='edition-']")
      try await expect(edition).toHaveCount(1)
      try await node.locator(".dropdown-trigger").click()
      try await edition.click()

      // A second row, typed: its own "+ Add origin step" gives it an origin of
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
      // Its type, from the work's closed list (no "Other"), and its date as
      // every date of ours: a range shows its end once chosen, in a row
      // added after the page loaded too.
      let secondKey = try await second.getAttribute("data-origin-key") ?? ""
      let secondType = second.locator(".dropdown-view:has(#\(secondKey)-type)")
      try await expect(secondType.locator(".dropdown-option[data-value='other']")).toHaveCount(0)
      try await secondType.locator(".dropdown-trigger").click()
      try await secondType.locator(".dropdown-search-input").fill("Treatise")
      try await secondType.locator(".dropdown-option[data-value='treatise']").filter(visible: true).first.click()
      let secondDate = second.locator(":scope > .origin-field-view-typed > .form-date-view")
      try await expect(secondDate).toHaveCount(1)
      let yearEnd = secondDate.locator("input[name='\(secondKey)-year-end']")
      try await expect(yearEnd).toBeHidden()
      let qualifier = secondDate.locator(".dropdown-view:has(#\(secondKey)-year-qualifier)")
      try await qualifier.locator(".dropdown-trigger").click()
      try await qualifier.locator(".dropdown-option[data-value='range']").click()
      try await expect(yearEnd).toBeVisible()
      try await secondDate.locator("input[name='\(secondKey)-year']").fill("1560")
      try await yearEnd.fill("1565")
      // Its voices a row each, as the work's own: a role and a name.
      let voiceList = second.locator(":scope > .origin-field-view-typed > .form-items-view")
      let voiceRows = voiceList.locator("[data-item-section='true']:not([data-item-template] *)")
      try await expect(voiceRows).toHaveCount(1)
      try await voiceRows.first.locator(".text-input-input").fill("Ann Author")
      try await voiceList.locator("[data-item-add-btn='true'] button").click()
      try await expect(voiceRows).toHaveCount(2)
      try await voiceRows.nth(1).locator(".dropdown-trigger").click()
      try await voiceRows.nth(1).locator(".dropdown-option[data-value='translator']").click()
      try await voiceRows.nth(1).locator(".text-input-input").fill("Bea Author")
      let nestedList = second.locator(":scope > .origin-field-view-typed > [data-origin-list='true']")
      try await second.locator(":scope > .origin-field-view-actions .origin-add-own-btn").click()
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
          // The page's own check would stop an unfinished form's submit
          // before its script writes the JSON: this reads the script alone.
          form.removeAttribute('novalidate');
          form.dispatchEvent(new Event('submit', { cancelable: true }));
          return form.querySelector('.origin-field-view-json').value;
        }
        """
      ).string ?? ""
      let json = try JSONSerialization.jsonObject(with: Data(posted.utf8)) as? [[String: Any]] ?? []
      #expect(json.count == 2, "\(posted)")
      #expect(json.first?["relation"] as? String == "translation_of")
      #expect(json.first?["certainty"] as? String == "probable")
      #expect(json.first?["record"] as? String == original.recordID)
      #expect((json.first?["node"] as? String)?.hasPrefix("edition-") == true, "\(posted)")
      let secondPosted = json.count > 1 ? json[1] : [:]
      #expect(secondPosted["relation"] as? String == "adaptation_of")
      let secondTyped = secondPosted["typed"] as? [String: Any] ?? [:]
      #expect(secondTyped["title"] as? String == "Web tests typed work")
      #expect(secondTyped["type"] as? String == "treatise", "\(posted)")
      let date = secondTyped["date"] as? [String: Any] ?? [:]
      #expect(date["yearQualifier"] as? String == "range", "\(posted)")
      #expect(date["era"] as? String == "anno_domini")
      #expect(date["year"] as? Int == 1560)
      #expect(date["yearEnd"] as? Int == 1565)
      #expect(date["eraEnd"] as? String == "anno_domini")
      let voices = (secondTyped["voices"] as? [[String: Any]] ?? []).map {
        "\($0["role"] as? String ?? ""):\($0["name"] as? String ?? "")"
      }
      #expect(voices == ["author:Ann Author", "translator:Bea Author"])
      let deeper = secondPosted["origins"] as? [[String: Any]] ?? []
      #expect(deeper.count == 1)
      #expect((deeper.first?["typed"] as? [String: Any])?["title"] as? String == "Web tests deeper work")

      // Unset the pick: "—", the testaments go, the typed fields come back.
      try await picker.locator(".dropdown-trigger").click()
      // The menu settled open before its option is aimed at.
      let chosen = picker.locator(".dropdown-option[data-value='\(original.recordID)']").first
      try await expect(chosen).toBeVisible()
      try await chosen.click()
      try await expect(first.locator(".origin-record-field-view")).not.toContainText("Testament")
      try await expect(typedFields).toBeVisible()
      // A row removed.
      try await second.locator(":scope > .origin-field-view-actions .origin-remove-btn").click()
      try await expect(rows).toHaveCount(1)

      // Nothing scrolls sideways.
      let overflow = try await page.evaluate("document.documentElement.scrollWidth > window.innerWidth").bool
      #expect(overflow == false)

      // The translation's page: an Origin section after the Metadata, a
      // paragraph of prose as a dictionary's etymology, the typed step plain
      // and the original linked.
      try await page.openHydrated(translation.path)
      let prose = page.locator("#origin .origin-view")
      try await expect(prose).toHaveCount(1)
      try await expect(page.locator("#origin .record-section-title")).toHaveText("Origin")
      try await expect(page.locator("#record-origin")).toHaveCount(0)
      let order = try await page.evaluate(
        """
        (() => {
          const metadata = document.querySelector('#record-metadata');
          const origin = document.querySelector('#origin');
          return !!(metadata && origin && (metadata.compareDocumentPosition(origin) & Node.DOCUMENT_POSITION_FOLLOWING));
        })()
        """
      ).bool
      #expect(order == true, "Origin is not after Metadata")
      try await expect(prose).toHaveText(
        "Translated from the Old English treatise \(typed) (c. AD 890), which was translated from the English report \(original.title), "
          + "authored by \(original.author).")
      try await expect(prose.locator("a[href='\(original.path)']")).toHaveCount(1)

      // The original lists it under "Translated into", as "Contains"
      // answers "Contained in".
      try await page.openHydrated(original.path)
      try await expect(page.locator(".record-sidebar-view a[href='\(translation.path)']").first).toBeAttached()
      try await expect(page.locator(".record-sidebar-view").first).toContainText("Translated into")

      // A word's origin may name nothing: an Imitation or a Coinage hides
      // the row's record field and typed fields; another relation brings
      // them back.
      try await page.openHydrated("/mission-control/submit/lexicographic/evidence-sentiment")
      let wordRow = page.locator(".origin-field-view [data-origin-row='true']").first
      try await expect(wordRow.locator(".origin-record-field-view")).toHaveCount(1)
      let wordRelation = wordRow.locator(".dropdown-view").first
      try await wordRelation.locator(".dropdown-trigger").click()
      try await wordRelation.locator(".dropdown-option[data-value='coinage']").click()
      try await expect(wordRow.locator(":scope > .origin-field-view-record")).toBeHidden()
      try await expect(wordRow.locator(":scope > .origin-field-view-typed")).toBeHidden()
      try await wordRelation.locator(".dropdown-trigger").click()
      try await wordRelation.locator(".dropdown-option[data-value='eponym_of']").click()
      try await expect(wordRow.locator(":scope > .origin-field-view-record")).toBeVisible()
      try await expect(wordRow.locator(":scope > .origin-field-view-typed")).toBeVisible()
      // A word's typed step: its word class from the closed list, and its
      // date as every date of ours.
      let wordKey = try await wordRow.getAttribute("data-origin-key") ?? ""
      let wordType = wordRow.locator(".dropdown-view:has(#\(wordKey)-type)")
      try await expect(wordType.locator(".dropdown-option[data-value='verb']")).toHaveCount(1)
      try await expect(wordType.locator(".dropdown-option[data-value='other']")).toHaveCount(0)
      try await expect(wordRow.locator(":scope > .origin-field-view-typed > .form-date-view")).toHaveCount(1)
    }
  }
}
