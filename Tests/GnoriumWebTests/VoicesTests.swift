import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Submit Testament's voices: a person a row ("Voice", "+ Add voice") under
/// a heading that counts them ("Voice" over one row, "Voices" over two, kept
/// in step as rows come and go), each with a role (Author, Translator,
/// Compiler: an editor is the edition's), a row added starting as an author;
/// the form posts each row's role and name. In a translation the rows stay, and
/// the Submitted card has no translator of its own. Every chain step has a
/// Biblio-record at its top, which fills that step in from the record it
/// picks; the form's own Biblio-record comes first.
/// Nothing is submitted (the submit event is dispatched by hand, which runs
/// the form's script but never posts). A throwaway admin owns a scratch
/// work, removed after.
@Suite("Voices", .serialized)
struct VoicesTests {
  static let form = "/mission-control/submit/bibliographic/evidence-testament"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func typedRowsAndTheTranslationOfPicker(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    do {
      try await run(engine: engine, viewport: layout.viewport(for: engine), admin: admin, work: work)
    } catch {
      work.remove()
      await admin.remove()
      throw error
    }
    work.remove()
    await admin.remove()
  }

  private func run(engine: BrowserEngine, viewport: Viewport, admin: TestAdmin, work: ScratchWork) async throws {
    try await withPage(engine, gnorium, viewport: viewport, cookies: [admin.cookie]) { page in
      try await page.openHydrated(Self.form)
      let form = page.locator(".submit-testament-form")
      let list = form.locator("[data-item-list='work-voice']")
      let rows = list.locator("[data-item-section='true']:not([data-item-template] *)")
      let heading = list.locator(":scope > .form-items-heading")

      // One row to start, an author, headed "Voice", labeled "Voice"; three
      // roles, Title Case, no editor.
      try await expect(rows).toHaveCount(1)
      try await expect(heading).toHaveText("Voice")
      try await expect(rows.first.locator(".text-input-label").first).toContainText("Voice name")
      try await expect(rows.first.locator(".text-input-input")).toHaveAttribute("placeholder", "Voice name")
      try await expect(rows.first).toContainText("Voice role")
      let firstType = rows.first.locator(".dropdown-view")
      try await expect(firstType.locator(".dropdown-selected-text")).toHaveText("Author")
      try await expect(rows.first.locator("input[id$='-dropdown']")).toHaveValue("author")
      for (value, display) in [("author", "Author"), ("translator", "Translator"), ("compiler", "Compiler")] {
        try await expect(firstType.locator(".dropdown-option[data-value='\(value)']")).toHaveAttribute("data-display", display)
      }
      try await expect(firstType.locator(".dropdown-option[data-value='editor']")).toHaveCount(0)
      try await expect(list.locator("[data-item-add-btn='true'] button")).toHaveText("+ Add voice")
      try await rows.first.locator(".text-input-input").fill("Homer")

      // A second row starts as an author; made a translator.
      try await list.locator("[data-item-add-btn='true'] button").click()
      try await expect(rows).toHaveCount(2)
      try await expect(heading).toHaveText("Voices")
      let second = rows.nth(1)
      try await expect(second.locator("input[id$='-dropdown']")).toHaveValue("author")
      try await second.locator(".dropdown-trigger").click()
      try await second.locator(".dropdown-option[data-value='translator']").click()
      try await expect(second.locator(".dropdown-selected-text")).toHaveText("Translator")
      try await second.locator(".text-input-input").fill("Alexander Pope")

      // A third row, taken away again: "Voices" still over two.
      try await list.locator("[data-item-add-btn='true'] button").click()
      try await expect(rows).toHaveCount(3)
      try await rows.nth(2).locator(".item-remove-btn").click()
      try await expect(rows).toHaveCount(2)
      try await expect(heading).toHaveText("Voices")

      // What the form posts: each row's role and name, in order.
      let posted = try await list.evaluate(
        """
        (group) => {
          group.closest('form').dispatchEvent(new Event('submit', { cancelable: true }));
          return group.querySelector('.work-voice-json').value;
        }
        """
      ).string ?? ""
      let items = try JSONDecoder().decode([[String: String]].self, from: Data(posted.utf8))
      #expect(items == [["role": "author", "value": "Homer"], ["role": "translator", "value": "Alexander Pope"]])

      // The record field comes first, above the fields it fills in.
      let first = try await form.evaluate(
        """
        (form) => {
          const field = form.querySelector('.record-choice-field-view');
          const language = form.querySelector('#work-language');
          return !!(field.compareDocumentPosition(language) & Node.DOCUMENT_POSITION_FOLLOWING);
        }
        """
      ).bool
      #expect(first == true, "the Biblio-record field is not above Language")

      // A translation: the rows stay; the Submitted card asks for no
      // translator; every step has its Biblio-record at its top.
      try await form.locator(".is-translation-checkbox-wrapper .checkbox-input").check()
      try await expect(rows.first.locator(".text-input-input")).toBeVisible()
      try await expect(form.locator("[data-item-list='chain-testament-translator']")).toHaveCount(0)
      let original = form.locator(".chain-original-card")
      let picker = original.locator(".chain-record-field-view")
      try await expect(picker.locator("legend")).toContainText("Biblio-record")
      try await expect(form.locator(".chain-testament-card .chain-record-field-view")).toHaveCount(1)
      let dropdown = picker.locator(".dropdown-view")
      try await expect(dropdown.locator(".dropdown-selected-text")).toHaveText("—")
      try await expect(dropdown.locator(".dropdown-option[data-value='\(work.recordID)']")).toHaveCount(1)

      // Found by typing, picked: the Original card is the record's.
      try await dropdown.locator(".dropdown-trigger").click()
      try await dropdown.locator(".dropdown-search-input").fill(work.suffix)
      let results = dropdown.locator(".dropdown-options-list[data-dropdown-results='true']")
      let found = results.locator(".dropdown-option[data-value='\(work.recordID)']")
      try await expect(found.locator(".breadcrumb-label-context")).toHaveText("English")
      try await expect(found.locator(".breadcrumb-label-text")).toHaveText(work.title)
      try await expect(found.locator(".dropdown-option-alt-text")).toHaveText("\(work.author) · report")
      try await found.click()
      try await expect(original.locator("input[name='chain-original-record']")).toHaveValue(work.recordID)
      try await expect(original.locator("[name='chain-original-work[]']")).toHaveValue(work.title)
      try await expect(original.locator("#chain-original-language-0")).toHaveValue("eng")
      try await expect(original.locator("#chain-original-year")).toHaveValue("1958")
      let authors = original.locator(
        "[data-item-list='chain-original-author'] [data-item-section='true']:not([data-item-template] *) .text-input-input")
      try await expect(authors).toHaveCount(1)
      try await expect(authors.first).toHaveValue(work.author)

      // Unset: "—", and what the pick filled in, untouched since, goes
      // with it; what was edited after the pick stays.
      try await original.locator("[name='chain-original-work[]']").fill("\(work.title), revised")
      try await dropdown.locator(".dropdown-trigger").click()
      try await dropdown.locator(".dropdown-option[data-value='\(work.recordID)']").first.click()
      try await expect(dropdown.locator(".dropdown-selected-text")).toHaveText("—")
      try await expect(original.locator("input[name='chain-original-record']")).toHaveValue("")
      try await expect(original.locator("[name='chain-original-work[]']")).toHaveValue("\(work.title), revised")
      try await expect(original.locator("#chain-original-language-0")).toHaveValue("")
      try await expect(original.locator("#chain-original-year")).toHaveValue("")
      try await expect(authors).toHaveCount(1)
      try await expect(authors.first).toHaveValue("")

      // A translated step: its own picker at its top, its Remove button the
      // house one; a pick fills that step in, and the chain keeps it.
      try await form.locator("[data-add-chain-node='true'] button").click()
      let step = form.locator(".chain-node-item").first
      try await expect(step.locator("button.button-view.chain-node-remove")).toHaveCount(1)
      try await expect(step.locator(".chain-node-remove")).toContainText("Remove translation step")
      let stepPicker = step.locator(".chain-record-field-view .dropdown-view")
      try await expect(stepPicker.locator(".dropdown-option[data-value='\(work.recordID)']")).toHaveCount(1)
      try await stepPicker.locator(".dropdown-trigger").click()
      try await stepPicker.locator(".dropdown-search-input").fill(work.suffix)
      try await stepPicker.locator(".dropdown-options-list[data-dropdown-results='true'] .dropdown-option[data-value='\(work.recordID)']").click()
      try await expect(step.locator(".chain-node-work")).toHaveValue(work.title)
      try await expect(step.locator("input[id$='-lang']")).toHaveValue("eng")
      let chain = try await form.evaluate(
        """
        (form) => {
          form.dispatchEvent(new Event('submit', { cancelable: true }));
          return form.querySelector('.translation-chain-json').value;
        }
        """
      ).string ?? ""
      #expect(chain.contains("\"record\":\"\(work.recordID)\""), "the chain keeps the step's pick: \(chain)")
    }
  }
}
