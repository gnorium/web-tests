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
      let addTop = field.locator(".origin-field-add .origin-add-btn")
      try await addTop.click()
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
      try await page.locator("button[aria-label='Add Origin 2.1.']").click()
      try await expect(rows).toHaveCount(3)
      let nested = try #require(try await rows.nth(2).getAttribute("data-origin-key"))
      try await title(nested).fill("Web tests origin two one")
      try await addTop.click()
      try await expect(rows).toHaveCount(4)
      let third = try #require(try await rows.nth(3).getAttribute("data-origin-key"))
      try await title(third).fill("Web tests origin three")

      // A testament node taken out: the impression (1.1).
      try await page.locator("button.testament-draft-remove-level[aria-label='Remove Testament 1.1.']").click()
      let impression = page.locator(".outliner-item[data-testament-draft='true'][data-draft-level='2']")
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
      try await expect(field.locator(".origin-field-steps .record-row-number")).toHaveTexts(["1", "2", "2.1", "3"])
      // 2.1 stands under origin 2.
      let parent = try await rows.nth(2).evaluate(
        "(row) => row.closest('.outliner-item').parentElement.closest('.outliner-item').querySelector('[data-origin-row]').dataset.originKey"
      ).string
      #expect(parent == second, "2.1 is under origin 2")
      try await expect(field.locator("input[name='\(second)-relation']")).toHaveValue("translation_of,abridgment_of")
      try await expect(relation.locator(".dropdown-selected-text")).toContainText("Abridgment")
      try await expect(addTop).toHaveAttribute("aria-label", "Add Origin 4.")
      try await expect(page.locator("button[aria-label='Add Origin 2.2.']")).toHaveCount(1)
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
      let issue = page.locator(".outliner-item[data-testament-draft='true'][data-draft-level='3']")
      try await expect(issue).toHaveAttribute("data-outliner-removed", "false")
      try await expect(issue.locator(":scope > .outliner-footer .testament-draft-remove-level"))
        .toHaveAttribute("aria-label", "Remove Testament 1.1.")

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
      try await field.locator(".origin-field-add .origin-add-btn").click()
      try await expect(field.locator("[data-origin-row='true']")).toHaveCount(2)
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
    }
  }

  /// A Submit the server turns back draws the form again with every entry
  /// posted, and the rows the page had added come back from them
  /// (`DraftRows.carry`): the origins at every depth, numbered as left, the
  /// voices, and the testament node taken out stays out. Signed out, the
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
      let addTop = field.locator(".origin-field-add .origin-add-btn")
      try await addTop.click()
      try await expect(rows).toHaveCount(2)
      let second = try #require(try await rows.nth(1).getAttribute("data-origin-key"))
      try await title(second).fill("Web tests origin two")
      try await page.locator("button[aria-label='Add Origin 2.1.']").click()
      try await expect(rows).toHaveCount(3)
      let nested = try #require(try await rows.nth(2).getAttribute("data-origin-key"))
      try await title(nested).fill("Web tests origin two one")
      try await addTop.click()
      try await expect(rows).toHaveCount(4)
      let third = try #require(try await rows.nth(3).getAttribute("data-origin-key"))
      try await title(third).fill("Web tests origin three")
      try await page.locator("button.testament-draft-remove-level[aria-label='Remove Testament 1.1.']").click()
      let impression = page.locator(".outliner-item[data-testament-draft='true'][data-draft-level='2']")
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
      try await expect(field.locator(".origin-field-steps .record-row-number")).toHaveTexts(["1", "2", "2.1", "3"])
      try await expect(addTop).toHaveAttribute("aria-label", "Add Origin 4.")
      try await expect(voices).toHaveCount(2)
      try await expect(page.locator("input[name='work-voice-item2-text-input']")).toHaveValue("Web tests Voice Two")
      try await expect(impression).toHaveAttribute("data-outliner-removed", "true")

      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
    }
  }
}
