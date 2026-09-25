import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A former owner keeps its date through the rows around it changing: on
/// the Modify overture form, add two owners with dates, take the first
/// owner away, and what the form would post still dates both. Nothing is
/// posted: the submit event is dispatched by hand, which runs the form's
/// script (the serializer fills `former-owners[]`) but never sends it.
/// Needs a signed-in account, made for the test and removed after.
@Suite("Former owner rows", .serialized)
struct FormerOwnersRowsTests {
  /// A dev overture that holds former owners.
  static let form = "/mission-control/overtures/bibliographic/de000000-0000-4000-8000-000000000006/modify"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func removingAnOwnerKeepsTheOthersDates(engine: BrowserEngine, layout: Layout) async throws {
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

  struct Posted: Decodable {
    let prevented: Bool
    let json: String
    let ids: [String]
  }

  struct Owner: Decodable, Equatable {
    let name: String
    let place: String?
    let yearQualifier: String?
    let era: String?
    let year: Int?
    let eraEnd: String?
    let yearEnd: Int?
  }

  private func run(engine: BrowserEngine, viewport: Viewport, admin: TestAdmin) async throws {
    try await withPage(engine, gnorium, viewport: viewport, cookies: [admin.cookie]) { page in
      try await page.openHydrated(Self.form)
      let list = page.locator("[data-item-list='former-owner']").first
      let rows = list.locator("[data-item-section='true']:not([data-item-template] *)")
      let loaded = try await rows.count()
      try #require(loaded >= 1, "the overture should load with a former owner")

      // Two owners added, each named and dated, as a reader fills them in:
      // the qualifier and era are dropdowns (their hidden inputs, changed),
      // the year a text field.
      let result = try await list.evaluate(
        """
        async (list) => {
          const frame = () => new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));
          const form = list.closest('form');
          const add = form.querySelector('[data-item-add-target="former-owner"] button');
          const rows = () => [...list.querySelectorAll('[data-item-section="true"]')]
            .filter((row) => !row.closest('[data-item-template]'));
          const set = (input, value, type) => {
            input.value = value;
            input.dispatchEvent(new Event(type, { bubbles: true }));
          };
          const owners = [
            { name: 'Added Owner One', qualifier: 'exact', era: 'anno_domini', year: '1650' },
            { name: 'Added Owner Two', qualifier: 'circa', era: 'anno_domini', year: '1700' },
          ];
          for (const owner of owners) {
            add.click();
            await frame();
            const row = rows()[rows().length - 1];
            set(row.querySelector('[data-fo-field="name"] .text-input-input'), owner.name, 'input');
            const date = row.querySelector('[data-fo-field="date"]');
            // Found by place and class, not by name: names are what is
            // under test.
            set(date.querySelector('.form-date-view input[type=hidden]'), owner.qualifier, 'change');
            set(date.querySelector('[class*="-era-dropdown"] input[type=hidden]'), owner.era, 'change');
            set(date.querySelector('[class*="-year-start"] .text-input-input'), owner.year, 'input');
            await frame();
          }
          // The first owner taken away: every row after it moves up.
          rows()[0].querySelector('.item-remove-btn').click();
          await frame();

          const event = new Event('submit', { cancelable: true });
          form.dispatchEvent(event);
          const ids = rows().flatMap((row) => [...row.querySelectorAll('[id]')].map((el) => el.id));
          return JSON.stringify({
            prevented: event.defaultPrevented,
            json: form.querySelector('.former-owners-json').value,
            ids,
          });
        }
        """
      ).string ?? ""
      let posted = try JSONDecoder().decode(Posted.self, from: Data(result.utf8))
      let owners = try JSONDecoder().decode([Owner].self, from: Data(posted.json.utf8))

      #expect(owners.count == loaded + 1, "one owner removed, two added: \(posted.json)")
      let added = owners.suffix(2)
      #expect(added.map(\.name) == ["Added Owner One", "Added Owner Two"])
      #expect(added.map(\.yearQualifier) == ["exact", "circa"], "the qualifiers are dropped: \(posted.json)")
      #expect(added.map(\.era) == ["anno_domini", "anno_domini"], "the eras are dropped: \(posted.json)")
      #expect(added.map(\.year) == [1650, 1700], "the years are dropped: \(posted.json)")
      // Every row's ids are its own: none repeats another row's.
      #expect(Set(posted.ids).count == posted.ids.count, "row ids repeat: \(posted.ids)")
    }
  }
}
