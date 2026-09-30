import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A work's ORIGIN: on Submit Testament an Origin block in the work (no
/// "This is a translation" box), a tree of steps (the site's one tree,
/// `OutlinerView`), each a card: a relation, a record field (searched, two
/// rows an option) and, once a record is picked, its testaments to name one
/// by; with no record, the work as typed and its own icon-only +,
/// which puts a step under it, indented. Deep steps keep their width and
/// the tree scrolls sideways, never the page; a menu opened in a deep step
/// stands over the page by its field. Removing a step with steps under it
/// asks first. The form posts the tree as one JSON list (the submit event is
/// dispatched by hand, which runs the form's script but never posts). On a
/// record page, the Origin section after the Metadata is the same tree, each
/// step its relations, what it came from (Language › Title, linked where it
/// is a record; its type), date, certainty and voices, "—" where unknown;
/// and the source record lists its translations. A throwaway admin owns two
/// scratch works, removed after.
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
      let deeper = UUID().uuidString.lowercased()
      _ = try TestAdmin.query(
        """
        INSERT INTO biblio_record_origins (id, biblio_record_id, parent_id, position, target_record_id, typed_json, created_at)
          VALUES ('\(step)', '\(translation.recordID.lowercased())', NULL, 0, NULL,
            '{"language":"ang","title":"\(typed)","type":"treatise","date":{"era":"anno_domini","year":890,"yearQualifier":"circa"}}', now());
        INSERT INTO biblio_record_origin_relations (id, origin_id, position, relation)
          VALUES ('\(UUID().uuidString.lowercased())', '\(step)', 0, 'translation_of'),
            ('\(UUID().uuidString.lowercased())', '\(step)', 1, 'abridgment_of');
        INSERT INTO biblio_record_origins (id, biblio_record_id, parent_id, position, target_record_id, typed_json, created_at)
          VALUES ('\(deeper)', '\(translation.recordID.lowercased())', '\(step)', 0,
            '\(original.recordID.lowercased())', NULL, now());
        INSERT INTO biblio_record_origin_relations (id, origin_id, position, relation)
          VALUES ('\(UUID().uuidString.lowercased())', '\(deeper)', 0, 'translation_of');
        """)
      try await run(
        engine: engine, viewport: layout.viewport(for: engine), admin: admin, original: original,
        translation: translation, typed: typed)
    } catch {
      translation.remove()
      original.remove()
      try await admin.remove(after: error)
    }
    translation.remove()
    original.remove()
    try await admin.remove()
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
      // A step's card in a list of the tree: the top level's, or a step's own.
      let cards = ":scope > .outliner-item > .outliner-row > .outliner-node > [data-origin-row='true']"
      let top = block.locator(":scope > .outliner-view > .outliner-scroll > .outliner-list")
      let rows = top.locator(cards)
      try await expect(rows).toHaveCount(1)

      // The row: its relation (a plain noun), its record field, its typed
      // fields while no record is picked, its own + ("Add Origin Step") then
      // the step's − ("Remove Origin Step"): add first, a press of the first
      // button never removes; icon-only, as the filter bar's row controls
      // (user, 2026-09-30), named for assistive technology.
      let first = rows.first
      try await expect(first.locator(".origin-record-field-view")).toHaveCount(1)
      let actions = first.locator(".origin-field-view-actions")
      try await expect(actions.locator(".origin-add-own-btn")).toHaveAttribute("aria-label", "Add Origin Step")
      try await expect(actions.locator(".origin-add-own-btn")).toHaveText("")
      try await expect(actions.locator(".origin-add-own-btn svg.add-icon-view")).toHaveCount(1)
      try await expect(actions.locator(".origin-remove-btn")).toHaveAttribute("aria-label", "Remove Origin Step")
      try await expect(actions.locator(".origin-remove-btn svg.subtract-icon-view")).toHaveCount(1)
      // The form keeps one step at least (user, 2026-09-29): a lone step
      // has no "− Remove Origin Step", so the box can never go.
      try await expect(actions.locator(".origin-remove-btn")).toBeHidden()
      // The Biblio-record field and the Metadata under it, a field's gap
      // apart (spacing16), never touching.
      let apart = try await form.evaluate(
        "(f) => { const b = f.querySelector('#metadata > .record-section-body'); const [x, y] = b.children; return Math.round(y.getBoundingClientRect().top - x.getBoundingClientRect().bottom) }"
      ).int
      #expect(apart == 16, "the Biblio-record field and the Metadata should be 16px apart, not \(String(describing: apart))")
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
      // Several relations to one work (user, 2026-09-29): the menu stays
      // open while they are chosen, the closed field names them in order.
      try await relation.locator(".dropdown-trigger").click()
      try await relation.locator(".dropdown-option[data-value='translation_of']").click()
      try await relation.locator(".dropdown-option[data-value='abridgment_of']").click()
      try await expect(relation.locator(".dropdown-menu")).toHaveAttribute("data-open", "true")
      try await expect(relation.locator(".dropdown-option.is-selected")).toHaveCount(2)
      try await relation.locator(".dropdown-trigger").click()
      try await expect(relation.locator(".dropdown-selected-text")).toHaveText("Translation, Abridgment")
      // The tooltip now says what each means.
      #expect(try await tooltip() == "A rendering of the work in another language. A shortened version of the work.")
      // How sure it is: optional, certain unless said.
      let certainty = first.locator(".dropdown-view").nth(1)
      try await expect(first).toContainText("Certainty")
      try await certainty.locator(".dropdown-trigger").click()
      try await certainty.locator(".dropdown-option[data-value='probable']").click()
      try await expect(certainty.locator(".dropdown-selected-text")).toHaveText("Probable")
      let record = first.locator(".origin-field-view-record .origin-record-field-view")
      try await expect(record.locator("legend")).toContainText("Record")
      let typedFields = first.locator(".origin-field-view-typed")
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
      // A record's origin is its own: no "+ Add Origin Step" under a picked record.
      try await expect(actions.locator(".origin-add-own-btn")).toBeHidden()
      let node = first.locator(".origin-record-field-view .dropdown-view").nth(1)
      try await expect(first.locator(".origin-record-field-view")).toContainText("Testament")
      let edition = node.locator(".dropdown-option[data-value^='edition-']")
      try await expect(edition).toHaveCount(1)
      try await node.locator(".dropdown-trigger").click()
      try await edition.click()

      // A second row, typed: its own "+ Add Origin Step" gives it an origin of
      // its own.
      try await block.locator(":scope > .origin-field-view-add .origin-add-btn").click()
      try await expect(rows).toHaveCount(2)
      let second = rows.nth(1)
      // Its record field is asked for once it is on the page: settled, the
      // row stops moving what is under it.
      try await expect(second.locator(".origin-record-field-view")).toHaveCount(1)
      // Two steps: each has its −; the typed one's own + first, then it:
      // side by side and content-width on wider screens, full width and
      // stacked (+ above −) on a phone, as the filter bar's (user,
      // 2026-09-30). The form's own list-end "+ Add Origin Step" keeps its
      // words.
      try await expect(first.locator(".origin-field-view-actions .origin-remove-btn")).toBeVisible()
      let secondActions = second.locator(".origin-field-view-actions")
      try await expect(secondActions.locator(".origin-remove-btn")).toHaveText("")
      try await expect(secondActions.locator(".origin-remove-btn svg.subtract-icon-view")).toHaveCount(1)
      let named = try await secondActions.evaluate(
        "(a) => [...a.querySelectorAll('button')].map((b) => b.getAttribute('aria-label')).join('|')"
      ).string
      #expect(named == "Add Origin Step|Remove Origin Step", "add first, then remove: \(named ?? "")")
      try await expect(block.locator(":scope > .origin-field-view-add .origin-add-btn")).toHaveText("Add Origin Step")
      if viewport.width < 768 {
        let stacked = try await secondActions.evaluate(
          "(a) => { const [x, y] = a.querySelectorAll('button'); const r = (b) => b.getBoundingClientRect(); const w = a.getBoundingClientRect().width; return r(x).bottom <= r(y).top && Math.abs(r(x).width - w) < 2 && Math.abs(r(y).width - w) < 2 }"
        ).bool
        #expect(stacked == true, "on a phone the step's + and − are full width, stacked, add first")
      } else {
        let compact = try await secondActions.evaluate(
          "(a) => { const [x, y] = a.querySelectorAll('button'); const r = (b) => b.getBoundingClientRect(); return Math.abs(r(x).top - r(y).top) < 4 && r(x).right <= r(y).left && r(x).width < 64 && r(y).width < 64 && r(x).left - a.getBoundingClientRect().left < 2 }"
        ).bool
        #expect(compact == true, "the step's + and − are compact, one row, start-aligned, add first")
      }
      // A record one step names is not offered to another (user,
      // 2026-09-29): the original, picked in the first, is withheld from the
      // second's record field, searched for by name too.
      let secondPicker = second.locator(".origin-record-field-view .dropdown-view").first
      try await expect(secondPicker).toHaveAttribute("data-excluded-values", original.recordID)
      try await secondPicker.locator(".dropdown-trigger").click()
      try await secondPicker.locator(".dropdown-search-input").fill(original.suffix)
      let withheld = secondPicker.locator(
        ".dropdown-options-list[data-dropdown-results='true'] .dropdown-option[data-value='\(original.recordID)']")
      try await expect(withheld).toHaveAttribute("data-excluded", "true")
      try await expect(withheld).toBeHidden()
      try await page.keyboard.press("Escape")
      let secondRelation = second.locator(".dropdown-view").first
      try await secondRelation.locator(".dropdown-trigger").click()
      try await secondRelation.locator(".dropdown-option[data-value='adaptation_of']").click()
      try await secondRelation.locator(".dropdown-trigger").click()
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
      let secondDate = second.locator(".origin-field-view-typed > .form-date-view")
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
      let voiceList = second.locator(".origin-field-view-typed > .form-items-view")
      let voiceRows = voiceList.locator("[data-item-section='true']:not([data-item-template] *)")
      try await expect(voiceRows).toHaveCount(1)
      try await voiceRows.first.locator(".text-input-input").fill("Ann Author")
      try await voiceList.locator("[data-item-add-btn='true'] button").click()
      try await expect(voiceRows).toHaveCount(2)
      try await voiceRows.nth(1).locator(".dropdown-trigger").click()
      try await voiceRows.nth(1).locator(".dropdown-option[data-value='translator']").click()
      try await voiceRows.nth(1).locator(".text-input-input").fill("Bea Author")
      // Its own step goes under it in the tree, inside its card.
      let secondItem = block.locator(".outliner-item[data-origin-step='\(secondKey)']")
      try await second.locator(".origin-field-view-actions .origin-add-own-btn").click()
      let nested = secondItem.locator(":scope > .outliner-list").locator(cards)
      try await expect(nested).toHaveCount(1)
      let indent = try await secondItem.evaluate(
        "(item) => { const own = item.querySelector(':scope > .outliner-row > .outliner-node'); const under = item.querySelector(':scope > .outliner-list .outliner-node'); return Math.round(under.getBoundingClientRect().left - own.getBoundingClientRect().left) }"
      ).int
      // Inside its card: the card's 1px border and 16px padding in.
      #expect(indent == 17, "a step under a step stands inside its card (17px in), not \(String(describing: indent))")
      try await expect(nested.first.locator(".origin-record-field-view")).toHaveCount(1)
      let nestedRelation = nested.first.locator(".dropdown-view").first
      try await nestedRelation.locator(".dropdown-trigger").click()
      try await nestedRelation.locator(".dropdown-option[data-value='translation_of']").click()
      try await nestedRelation.locator(".dropdown-trigger").click()
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
      #expect(json.first?["relations"] as? [String] == ["translation_of", "abridgment_of"], "\(posted)")
      #expect(json.first?["certainty"] as? String == "probable")
      #expect(json.first?["record"] as? String == original.recordID)
      #expect((json.first?["node"] as? String)?.hasPrefix("edition-") == true, "\(posted)")
      let secondPosted = json.count > 1 ? json[1] : [:]
      #expect(secondPosted["relations"] as? [String] == ["adaptation_of"])
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
      // A step with a step under it asks before it goes: Cancel keeps both.
      let removeDialog = block.locator(".origin-field-view-remove-dialog")
      try await second.locator(".origin-field-view-actions .origin-remove-btn").click()
      try await expect(removeDialog).toHaveAttribute("data-open", "true")
      try await removeDialog.locator(".dialog-default-button button").click()
      try await expect(removeDialog).toHaveAttribute("data-open", "false")
      try await expect(rows).toHaveCount(2)
      try await expect(nested).toHaveCount(1)
      // Remove confirms it: the step goes with the one under it.
      try await second.locator(".origin-field-view-actions .origin-remove-btn").click()
      try await removeDialog.locator(".dialog-primary-button button").click()
      try await expect(rows).toHaveCount(1)
      try await expect(block.locator("[data-origin-row='true']")).toHaveCount(1)
      // The last step stays: its "− Remove Origin Step" is gone again.
      try await expect(first.locator(".origin-field-view-actions .origin-remove-btn")).toBeHidden()

      // Nothing scrolls sideways.
      let overflow = try await page.evaluate("document.documentElement.scrollWidth > window.innerWidth").bool
      #expect(overflow == false)

      // A deep origin, six steps each under the last (user, 2026-09-30):
      // every step keeps the tree's least node width (14rem), the tree's
      // scrollport scrolls sideways on a phone, and the page never does.
      for depth in 1..<6 {
        let deepest = block.locator("[data-origin-row='true']").last
        try await deepest.locator(".origin-field-view-actions .origin-add-own-btn").click()
        try await expect(block.locator("[data-origin-row='true']")).toHaveCount(depth + 1)
        try await expect(block.locator("[data-origin-row='true']").last.locator(".origin-record-field-view"))
          .toHaveCount(1)
      }
      let deep = try await block.evaluate(
        """
        (block) => {
          const scroll = block.querySelector('.outliner-scroll');
          const widths = [...block.querySelectorAll('.outliner-node')].map((n) => n.getBoundingClientRect().width);
          const least = parseFloat(getComputedStyle(document.documentElement).fontSize) * 14;
          return {
            narrowest: Math.round(Math.min(...widths)), least: Math.round(least),
            scrolls: scroll.scrollWidth > scroll.clientWidth,
            page: document.documentElement.scrollWidth > window.innerWidth,
          };
        }
        """)
      #expect((deep["narrowest"].int ?? 0) >= (deep["least"].int ?? 0), "a deep step keeps the least node width: \(deep)")
      #expect(deep["page"].bool == false, "the page never scrolls sideways")
      if viewport.width < 768 { #expect(deep["scrolls"].bool == true, "the tree scrolls sideways on a phone") }
      // A menu opened in the deepest step stands over the page by its
      // field, not cut off at the scrollport's edge.
      let deepest = block.locator("[data-origin-row='true']").last
      _ = try await deepest.evaluate("(row) => row.scrollIntoView({ block: 'center' })")
      let deepRelation = deepest.locator(".dropdown-view").first
      try await deepRelation.locator(".dropdown-trigger").click()
      let placed = try await deepRelation.evaluate(
        """
        (view) => {
          const menu = view.querySelector('.dropdown-menu');
          const field = view.querySelector('.dropdown-container').getBoundingClientRect();
          const box = menu.getBoundingClientRect();
          return {
            fixed: getComputedStyle(menu).position === 'fixed',
            start: Math.abs(Math.round(box.left - field.left)) <= 1,
            under: Math.abs(Math.round(box.top - field.bottom)) <= 6,
            inside: box.right <= window.innerWidth + 1,
          };
        }
        """)
      #expect(placed["fixed"].bool == true && placed["start"].bool == true && placed["under"].bool == true, "\(placed)")
      #expect(placed["inside"].bool == true, "the deep step's menu stays on the screen: \(placed)")
      try await deepRelation.locator(".dropdown-trigger").click()

      // The translation's page: an Origin section after the Metadata, the
      // tree of its steps—the typed step, and under it, indented, the
      // original's record, linked.
      try await page.openHydrated(translation.path)
      let tree = page.locator("#origin .origin-view")
      try await expect(tree).toHaveCount(1)
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
      let steps = tree.locator(".origin-step-view")
      try await expect(steps).toHaveCount(2)
      let typedStep = steps.first
      try await expect(typedStep.locator(".datum-label")).toHaveTexts(["Relation", "Date", "Certainty", "Voices"])
      try await expect(typedStep.locator(".datum-value")).toHaveTexts([
        "Translation, Abridgment", "c. AD 890", "Certain", "—",
      ])
      try await expect(typedStep.locator(".breadcrumb-label-context")).toHaveText("Old English")
      try await expect(typedStep.locator(".breadcrumb-label-text")).toHaveText(typed)
      try await expect(typedStep.locator(".record-type-view")).toHaveText("treatise")
      try await expect(typedStep.locator("a")).toHaveCount(0)
      // The original, a step under the typed one: its record linked, its
      // voices its own.
      let recordStep = tree.locator(
        ".outliner-scroll > .outliner-list > .outliner-item > .outliner-list > .outliner-item .origin-step-view")
      try await expect(recordStep).toHaveCount(1)
      try await expect(recordStep.locator("a[href='\(original.path)'] .breadcrumb-label-text")).toHaveText(original.title)
      try await expect(recordStep.locator(".record-type-view")).toHaveText("report")
      try await expect(recordStep.locator(".datum-value")).toHaveTexts([
        "Translation", "—", "Certain", "\(original.author) (Author)",
      ])

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
      // A word may be a calque (a loan translation), with a borrowing too.
      try await expect(wordRelation.locator(".dropdown-option[data-value='calque_of']")).toHaveAttribute(
        "data-display", "Calque")
      try await wordRelation.locator(".dropdown-trigger").click()
      try await wordRelation.locator(".dropdown-option[data-value='coinage']").click()
      try await expect(wordRow.locator(".origin-field-view-record")).toBeHidden()
      try await expect(wordRow.locator(".origin-field-view-typed")).toBeHidden()
      // Unchosen, and another chosen: the fields come back.
      try await wordRelation.locator(".dropdown-option[data-value='coinage']").click()
      try await wordRelation.locator(".dropdown-option[data-value='eponym_of']").click()
      try await wordRelation.locator(".dropdown-trigger").click()
      try await expect(wordRow.locator(".origin-field-view-record")).toBeVisible()
      try await expect(wordRow.locator(".origin-field-view-typed")).toBeVisible()
      // A word's typed step: its word class from the closed list, and its
      // date as every date of ours.
      let wordKey = try await wordRow.getAttribute("data-origin-key") ?? ""
      let wordType = wordRow.locator(".dropdown-view:has(#\(wordKey)-type)")
      try await expect(wordType.locator(".dropdown-option[data-value='verb']")).toHaveCount(1)
      try await expect(wordType.locator(".dropdown-option[data-value='other']")).toHaveCount(0)
      try await expect(wordRow.locator(".origin-field-view-typed > .form-date-view")).toHaveCount(1)
    }
  }
}
