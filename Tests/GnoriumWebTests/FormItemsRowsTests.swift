import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A repeated field's rows stay numbered by their place in the list: add a
/// third author on the Submit Amendment form, take the middle one away, and
/// every name, id, label, attribute key and live diff is the row's place
/// now, and the form serializes both rows. Nothing is submitted (the submit
/// event is dispatched by hand, which runs the form's script but never
/// posts). Needs a signed-in account, made for the test and removed after.
@Suite("Form item rows", .serialized)
struct FormItemsRowsTests {
  /// The Bosworth–Toller record, kept on the dev database: two authors.
  static let form =
    "/biblio-records/ang/an-anglo-saxon-dictionary/joseph-bosworth-and-thomas-northcote-toller/book/amendments/new"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func removingAMiddleRowRenumbersTheRest(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await run(engine: engine, viewport: layout.viewport(for: engine), admin: admin)
    } catch {
      await admin.remove()
      throw error
    }
    await admin.remove()
  }

  /// Every row of the author list as the page holds it now.
  static let rowsScript = """
    (group) => {
      const rows = [...group.querySelectorAll('[data-item-section="true"]')].filter((r) => !r.closest('[data-item-template]'));
      return JSON.stringify(rows.map((row) => {
        const input = row.querySelector('.text-input-input');
        // Every id a row's elements name — a label's, a dropdown's, a
        // tooltip's — is one of the row's own.
        const dangling = [];
        for (const el of row.querySelectorAll('[for], [aria-describedby], [aria-controls], [aria-labelledby], [aria-activedescendant]')) {
          for (const attr of ['for', 'aria-describedby', 'aria-controls', 'aria-labelledby', 'aria-activedescendant']) {
            for (const ref of (el.getAttribute(attr) || '').split(' ').filter(Boolean)) {
              const target = document.getElementById(ref);
              if (!target || !row.contains(target)) dangling.push(attr + '=' + ref);
            }
          }
        }
        const field = row.querySelector('.attribute-field-view');
        const box = field && field.querySelector('.attribute-field-view-checkbox .checkbox-input');
        return {
          index: row.getAttribute('data-item-index'),
          id: input.id, name: input.name, value: input.value, dangling,
          key: field ? field.getAttribute('data-attribute-key') : null,
          boxValue: box ? box.value : null, ticked: box ? box.checked : null,
          diff: input.getAttribute('data-diff-state'),
          original: input.getAttribute('data-form-item-original')
        };
      }));
    }
    """

  struct Row: Decodable {
    let index: String?
    let id: String
    let name: String
    let value: String
    let dangling: [String]
    let key: String?
    let boxValue: String?
    let ticked: Bool?
    let diff: String?
    let original: String?
  }

  private func rows(_ group: Locator) async throws -> [Row] {
    let json = try await group.evaluate(Self.rowsScript).string ?? "[]"
    return try JSONDecoder().decode([Row].self, from: Data(json.utf8))
  }

  private func run(engine: BrowserEngine, viewport: Viewport, admin: TestAdmin) async throws {
    try await withPage(engine, gnorium, viewport: viewport, cookies: [admin.cookie]) { page in
      try await page.openHydrated(Self.form)
      let work = page.locator(".submit-amendment-work").first
      let authors = work.locator("[data-item-list='work-author']")
      let active = authors.locator("[data-item-section='true']:not([data-item-template] *)")
      let firstInput = active.first.locator(".text-input-input")
      if !(try await firstInput.isVisible()) {
        try await work.locator(".accordion-summary").first.click()
      }
      try await expect(firstInput).toBeVisible()

      let loaded = try await rows(authors)
      try #require(loaded.count == 2, "the record should load with two authors: \(loaded.map(\.value))")
      let first = loaded[0].value
      let second = loaded[1].value

      // A third author, then the middle one taken away.
      try await authors.locator("[data-item-add-btn='true'] button").click()
      try await expect(active).toHaveCount(3)
      try await active.nth(2).locator(".text-input-input").fill("Third Author")
      try await active.nth(1).locator(".item-remove-btn").click()
      try await expect(active).toHaveCount(2)
      // Attribution keys follow a moment after (the attribution script
      // renumbers once the click has run).
      try await expect(active.nth(1).locator(".attribute-field-view").first)
        .toHaveAttribute("data-attribute-key", "author[2]")

      // Each row is its place now: names, ids, labels, attribute keys.
      var now = try await rows(authors)
      #expect(now.map(\.value) == [first, "Third Author"])
      #expect(now.map(\.index) == ["1", "2"])
      #expect(now[0].name == "work-author-item1-text-input")
      #expect(now[1].name == "work-author-item2-text-input")
      #expect(now[0].id.hasSuffix("work-author-item1-text-input"))
      #expect(now[1].id.hasSuffix("work-author-item2-text-input"))
      for row in now { #expect(row.dangling.isEmpty, "row \(row.index ?? "?") names ids it does not hold: \(row.dangling)") }
      #expect(now.map(\.key) == ["author[1]", "author[2]"])
      #expect(now.map(\.boxValue) == ["author[1]", "author[2]"])

      // Author 2 was the second author and is now "Third Author": a change
      // at that place, diffed against it and ticked for attribution.
      // Author 1 is untouched.
      #expect(now[1].original == second)
      #expect(now[1].diff == "changed")
      #expect(now[1].ticked == true)
      #expect(now[0].ticked == false)

      // What saving posts: both rows, in order, and nothing stops it.
      let posted = try await authors.evaluate(
        """
        (group) => {
          const form = group.closest('form');
          const event = new Event('submit', { cancelable: true });
          form.dispatchEvent(event);
          return JSON.stringify({ prevented: event.defaultPrevented, json: group.querySelector('.work-author-json').value });
        }
        """
      ).string ?? ""
      struct Posted: Decodable { let prevented: Bool; let json: String }
      let result = try JSONDecoder().decode(Posted.self, from: Data(posted.utf8))
      #expect(!result.prevented, "saving is stopped: \(result.json)")
      let items = try JSONDecoder().decode([[String: String]].self, from: Data(result.json.utf8))
      #expect(items.map { $0["value"] } == [first, "Third Author"])

      // Another row after that is the third, not a second "item3".
      try await authors.locator("[data-item-add-btn='true'] button").click()
      try await expect(active).toHaveCount(3)
      try await expect(active.nth(2).locator(".attribute-field-view").first)
        .toHaveAttribute("data-attribute-key", "author[3]")
      now = try await rows(authors)
      #expect(now.map(\.index) == ["1", "2", "3"])
      #expect(Set(now.map(\.id)).count == 3, "row ids repeat: \(now.map(\.id))")
      #expect(now[2].name == "work-author-item3-text-input")
      #expect(now.map(\.key) == ["author[1]", "author[2]", "author[3]"])
      for row in now { #expect(row.dangling.isEmpty, "row \(row.index ?? "?") names ids it does not hold: \(row.dangling)") }
      // No author stood third: the row is new.
      #expect(now[2].original == "" || now[2].original == nil)
    }
  }
}
