import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Submit Testament keeps its draft in `localStorage` as it is typed
/// (`ActionGateView.keepsDraft`), and a reload puts back the form as it was
/// left: not only the values, but the rows the page added and removed
/// (`DraftRows`)—Origin steps at every depth, two Voices, two Genres, a
/// step's two Relations—numbered as before, and a testament node taken out
/// stays out. Signed out: the form is drawn and kept the same, and nothing
/// is posted.
@Suite("Submit Testament draft")
struct SubmitTestamentDraftTests {
  static let form = "/mission-control/submit/bibliographic/testament"

  @Test(arguments: gnorium.engines)
  func aReloadPutsBackTheRows(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated(Self.form)
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.openHydrated(Self.form)

      let field = page.locator(".origin-field-view")
      let rows = field.locator("[data-origin-row='true']")
      let title = { (key: String) in field.locator("input[name='\(key)-title']") }
      let section = { (list: String) in page.locator("[data-item-list='\(list)'] > [data-item-section='true']") }
      let typed = { (list: String, index: Int) in
        section(list).nth(index).locator(".combobox-view input[type='text']").first
      }

      // Two voices, two genres.
      try await typed("work-voice", 0).fill("Web tests Voice One")
      try await page.locator("[data-item-list='work-voice'] > [data-item-add-btn='true'] .item-add-btn").click()
      try await expect(section("work-voice")).toHaveCount(2)
      try await typed("work-voice", 1).fill("Web tests Voice Two")
      try await typed("work-genre", 0).fill("Web tests genre one")
      try await page.locator("[data-item-list='work-genre'] > [data-item-add-btn='true'] .item-add-btn").click()
      try await expect(section("work-genre")).toHaveCount(2)
      try await typed("work-genre", 1).fill("Web tests genre two")

      // Origins 1, 2 (with 2.1 under it) and 3.
      try await title("origin-1").fill("Web tests origin one")
      // The tree's steppers add and remove (user, 2026-11-03).
      let origins = TreeStepper(in: field)
      let testaments = TreeStepper(page, tree: "submission-tree-outliner")
      try await origins.add("Add origin 2.")
      try await expect(rows).toHaveCount(2)
      let second = try #require(try await rows.nth(1).getAttribute("data-origin-key"))
      try await title(second).fill("Web tests origin two")
      // Two relations on origin 2.
      let relation = rows.nth(1).locator(".origin-field-relation")
      try await relation.locator(".dropdown-trigger").click()
      try await relation.locator(".dropdown-option[data-value='translation_of']").filter(visible: true).first.click()
      try await relation.locator(".dropdown-option[data-value='abridgment_of']").filter(visible: true).first.click()
      try await page.keyboard.press("Escape")
      try await expect(field.locator("input[name='\(second)-relation']"))
        .toHaveValue("translation_of,abridgment_of")
      try await origins.add("Add origin 2.1.")
      try await expect(rows).toHaveCount(3)
      let nested = try #require(try await rows.nth(2).getAttribute("data-origin-key"))
      try await title(nested).fill("Web tests origin two one")
      try await origins.add("Add origin 3.")
      try await expect(rows).toHaveCount(4)
      let third = try #require(try await rows.nth(3).getAttribute("data-origin-key"))
      try await title(third).fill("Web tests origin three")

      // A testament node taken out: the impression (1.1).
      // The volume (1.1) first: the level right under an edition.
      try await testaments.remove("Remove testament 1.1.")
      try await expect(page.locator(".outliner-item[data-testament-draft='true'][data-draft-level='2']"))
        .toHaveAttribute("data-outliner-removed", "true")
      try await testaments.remove("Remove testament 1.1.")
      let impression = page.locator(".outliner-item[data-testament-draft='true'][data-draft-level='3']")
      try await expect(impression).toHaveAttribute("data-outliner-removed", "true")

      // Kept a moment after the last change.
      try await expect(page.locator("html"), timeout: .seconds(5)).toHaveAttribute("data-wasm-status", "started")
      var kept = ""
      for _ in 0..<20 {
        kept = try await page.evaluate("localStorage.getItem('gnorium:draft:' + location.pathname) || ''", as: String.self)
        if kept.contains("rows:testament") && kept.contains("Web tests origin three") { break }
        try await Task.sleep(for: .milliseconds(250))
      }
      #expect(kept.contains("rows:origins-biblio-record"), "the draft records the origin steps")

      _ = try await page.reload()
      try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")

      // Every step back, by its own key, numbered as before.
      try await expect(rows, timeout: .seconds(15)).toHaveCount(4)
      try await expect(title("origin-1")).toHaveValue("Web tests origin one")
      try await expect(title(second)).toHaveValue("Web tests origin two")
      try await expect(title(nested)).toHaveValue("Web tests origin two one")
      try await expect(title(third)).toHaveValue("Web tests origin three")
      try await expect(field.locator(".origin-field-steps .record-node-number")).toHaveTexts(["1.", "2.", "2.1.", "3."])
      // 2.1 stands under origin 2.
      let parent = try await rows.nth(2).evaluate(
        "(row) => row.closest('.outliner-item').parentElement.closest('.outliner-item').querySelector('[data-origin-row]').dataset.originKey"
      ).string
      #expect(parent == second, "2.1 is under origin 2")
      try await expect(field.locator("input[name='\(second)-relation']")).toHaveValue("translation_of,abridgment_of")
      try await expect(relation.locator(".dropdown-selected-text")).toContainText("Abridgment")
      try await expect(origins.addButton).toHaveAttribute("aria-label", "Add origin 4.")
      #expect(try await origins.choices("add").contains("Add origin 2.2."))
      try await expect(field.locator(".origin-sentence-view")).toContainText("Web tests origin two one")

      // The voices and genres, each row back with its value.
      try await expect(section("work-voice")).toHaveCount(2)
      try await expect(page.locator("input[name='work-voice-item1-text-input']")).toHaveValue("Web tests Voice One")
      try await expect(page.locator("input[name='work-voice-item2-text-input']")).toHaveValue("Web tests Voice Two")
      try await expect(typed("work-voice", 1)).toHaveValue("Web tests Voice Two")
      try await expect(section("work-genre")).toHaveCount(2)
      try await expect(page.locator("input[name='work-genre-item1-text-input']")).toHaveValue("Web tests genre one")
      try await expect(page.locator("input[name='work-genre-item2-text-input']")).toHaveValue("Web tests genre two")

      // The impression stays out; the issue is 1.1 now.
      try await expect(impression).toHaveAttribute("data-outliner-removed", "true")
      let issue = page.locator(".outliner-item[data-testament-draft='true'][data-draft-level='4']")
      try await expect(issue).toHaveAttribute("data-outliner-removed", "false")
      try await expect(issue.locator(":scope > .outliner-row .record-node-number")).toHaveText("1.1")
      #expect(try await testaments.choices("remove").contains("Remove testament 1.1."))

      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
    }
  }

  /// The Carrier comes back from a kept draft chosen, its control showing
  /// it and not only its value (user, 2026-11-03). A browser that restores
  /// the page's form state (a tab reopened or brought back, a history
  /// entry; Firefox on a reload) puts the hidden value back before the page
  /// hydrates: the draft's value was then already there, and the control
  /// kept the "Carrier" the page drew while the Publication the choice
  /// reveals came back with its place. `restored` writes the value at
  /// DOMContentLoaded, as such a browser does.
  @Test(arguments: gnorium.engines, [false, true])
  func aReloadShowsTheCarrierChosen(engine: BrowserEngine, restored: Bool) async throws {
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated(Self.form)
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.openHydrated(Self.form)

      let carrier = page.locator(".dropdown-view:has(#testament-carrier)")
      let publication = page.locator(".activity-statement-view[data-as-namespace='publication']").first
      let place = publication.locator("input[name='as-publication-place-item1-text-input']")
      try await carrier.locator(".dropdown-trigger").click()
      try await carrier.locator(".dropdown-option[data-value='print']").click()
      try await expect(carrier.locator(".dropdown-selected-text")).toHaveText("Print")
      try await expect(publication).toBeVisible()
      try await place.fill("London, England")

      var kept = ""
      for _ in 0..<20 {
        kept = try await page.evaluate("localStorage.getItem('gnorium:draft:' + location.pathname) || ''", as: String.self)
        if kept.contains("\"carrier\":\"print\"") && kept.contains("London, England") { break }
        try await Task.sleep(for: .milliseconds(250))
      }
      #expect(kept.contains("\"carrier\":\"print\""), "the draft keeps the Carrier")

      if restored {
        try await page.addInitScript(
          "document.addEventListener('DOMContentLoaded', () => { const c = document.getElementById('testament-carrier'); if (c) c.value = 'print'; });"
        )
      }
      _ = try await page.reload()
      try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")

      try await expect(place, timeout: .seconds(15)).toHaveValue("London, England")
      try await expect(publication).toBeVisible()
      try await expect(page.locator("#testament-carrier")).toHaveValue("print")
      try await expect(carrier.locator(".dropdown-selected-text")).toHaveText("Print")
      try await expect(carrier.locator(".dropdown-selected-text")).toHaveAttribute("data-selected", "true")
      try await expect(carrier.locator(".dropdown-option[data-value='print']")).toHaveAttribute("data-selected", "true")

      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
    }
  }

  /// A draft that does not read (rows naming keys no selector may hold,
  /// levels that do not exist, a truncated object) never breaks the page:
  /// it hydrates, the rows stay as the server drew them, and the form works.
  @Test(arguments: gnorium.engines)
  func aBrokenDraftKeepsThePage(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated(Self.form)
      _ = try await page.evaluate(
        #"localStorage.setItem('gnorium:draft:' + location.pathname, '{"rows:origins-biblio-record":"|origin-1\'];x|||\n|a|b|c|d|e\nzz","rows:testament":"9:3,abc","origin-1-title":"Kept", "x":')"#)
      try await page.openHydrated(Self.form)
      let field = page.locator(".origin-field-view")
      try await expect(field.locator("[data-origin-row='true']")).toHaveCount(1)
      try await expect(field.locator("input[name='origin-1-title']")).toHaveValue("Kept")
      try await expect(page.locator(".outliner-item[data-testament-draft='true'][data-outliner-removed='true']"))
        .toHaveCount(0)
      try await TreeStepper(in: field).add("Add origin 2.")
      try await expect(field.locator("[data-origin-row='true']")).toHaveCount(2)
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
    }
  }

  /// A Submit the server turns back draws the form again with every entry
  /// posted, and the rows the page had added come back from them
  /// (`DraftRows.carry`): the origins at every depth, numbered as left, the
  /// voices, the Carrier chosen as it was, and the testament node taken out
  /// stays out. Signed out, the
  /// server refuses the post ("Sign in…"); the form's own submit listeners
  /// run as for a real Submit, then the form posts.
  @Test(arguments: gnorium.engines)
  func aRefusedSubmitPutsBackTheRows(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated(Self.form)
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.openHydrated(Self.form)

      let field = page.locator(".origin-field-view")
      let rows = field.locator("[data-origin-row='true']")
      let title = { (key: String) in field.locator("input[name='\(key)-title']") }
      let voices = page.locator("[data-item-list='work-voice'] > [data-item-section='true']")

      try await voices.nth(0).locator(".combobox-view input[type='text']").first.fill("Web tests Voice One")
      try await page.locator("[data-item-list='work-voice'] > [data-item-add-btn='true'] .item-add-btn").click()
      try await expect(voices).toHaveCount(2)
      try await voices.nth(1).locator(".combobox-view input[type='text']").first.fill("Web tests Voice Two")
      try await title("origin-1").fill("Web tests origin one")
      // The tree's steppers add and remove (user, 2026-11-03).
      let origins = TreeStepper(in: field)
      let testaments = TreeStepper(page, tree: "submission-tree-outliner")
      try await origins.add("Add origin 2.")
      try await expect(rows).toHaveCount(2)
      let second = try #require(try await rows.nth(1).getAttribute("data-origin-key"))
      try await title(second).fill("Web tests origin two")
      try await origins.add("Add origin 2.1.")
      try await expect(rows).toHaveCount(3)
      let nested = try #require(try await rows.nth(2).getAttribute("data-origin-key"))
      try await title(nested).fill("Web tests origin two one")
      try await origins.add("Add origin 3.")
      try await expect(rows).toHaveCount(4)
      let third = try #require(try await rows.nth(3).getAttribute("data-origin-key"))
      try await title(third).fill("Web tests origin three")
      let carrier = page.locator(".dropdown-view:has(#testament-carrier)")
      try await carrier.locator(".dropdown-trigger").click()
      try await carrier.locator(".dropdown-option[data-value='print']").click()
      // The volume (1.1) first: the level right under an edition.
      try await testaments.remove("Remove testament 1.1.")
      try await expect(page.locator(".outliner-item[data-testament-draft='true'][data-draft-level='2']"))
        .toHaveAttribute("data-outliner-removed", "true")
      try await testaments.remove("Remove testament 1.1.")
      let impression = page.locator(".outliner-item[data-testament-draft='true'][data-draft-level='3']")
      try await expect(impression).toHaveAttribute("data-outliner-removed", "true")
      // No kept draft to fall back on: only the post brings them back.
      try await Task.sleep(for: .milliseconds(600))
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")

      _ = try await page.evaluate(
        """
        (() => {
          const form = document.querySelector('form.submit-testament-form');
          form.dispatchEvent(new Event('submit', { cancelable: true, bubbles: true }));
          HTMLFormElement.prototype.submit.call(form);
          return true;
        })()
        """)
      try await expect(page.locator(".submit-testament-posted"), timeout: .seconds(20)).toHaveCount(1)
      try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
      try await expect(page.locator(".alert-view").filter(hasText: "Sign in to submit a testament.")).toHaveCount(1)

      try await expect(rows, timeout: .seconds(15)).toHaveCount(4)
      try await expect(title("origin-1")).toHaveValue("Web tests origin one")
      try await expect(title(second)).toHaveValue("Web tests origin two")
      try await expect(title(nested)).toHaveValue("Web tests origin two one")
      try await expect(title(third)).toHaveValue("Web tests origin three")
      try await expect(field.locator(".origin-field-steps .record-node-number")).toHaveTexts(["1.", "2.", "2.1.", "3."])
      try await expect(origins.addButton).toHaveAttribute("aria-label", "Add origin 4.")
      try await expect(voices).toHaveCount(2)
      try await expect(page.locator("input[name='work-voice-item2-text-input']")).toHaveValue("Web tests Voice Two")
      try await expect(page.locator("#testament-carrier")).toHaveValue("print")
      try await expect(carrier.locator(".dropdown-selected-text")).toHaveText("Print")
      try await expect(impression).toHaveAttribute("data-outliner-removed", "true")

      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
    }
  }
}
