import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A component's variants are each its own rule, keyed by a data attribute or
/// a custom property, never a value that depends on an instance inside a
/// shared selector rule (the later variant's rule won for every instance).
/// Each variant is checked by its computed style on the page that shows it.
@Suite("Shared style variants", .serialized)
struct SharedStyleVariantsTests {
  /// A column group (the navbar menu's color scheme and contrast) is the
  /// row's full width with 4 between its buttons; a row group (the dashboard's
  /// submit buttons) is a row with the button gap.
  @Test(arguments: [BrowserEngine.chrome])
  func buttonGroupsKeepTheirOwnDirectionAndGap(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let measure = """
      (selector => [...document.querySelectorAll(selector)]
        .filter(group => group.getClientRects().length > 0)
        .map(group => {
          const style = getComputedStyle(group);
          const probe = document.createElement('div');
          probe.style.width = 'var(--spacing-horizontal-button)';
          group.append(probe);
          const buttonGap = getComputedStyle(probe).width;
          probe.remove();
          return [style.flexDirection, style.rowGap, buttonGap,
            Math.abs(group.getBoundingClientRect().width - group.parentElement.clientWidth) <= 1 ? 'parent-width' : 'own-width'].join(' ');
        }))
      """
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated("/")
        try await page.locator("[data-navbar-ellipsis]").filter(visible: true).first.click()
        try await expect(page.locator("#navbar-ellipsis-menu")).toHaveAttribute("data-state", "open")
        let columns = try await page.evaluate("\(measure)('#navbar-ellipsis-menu .button-group-view[data-direction=\"column\"]')", as: [String].self)
        #expect(columns.count == 2, "the menu's color scheme and contrast groups: \(columns)")
        for column in columns {
          #expect(column.hasPrefix("column 4px "), "a column group: \(column)")
          #expect(column.hasSuffix(" parent-width"), "a column group is the row's width: \(column)")
        }

        try await page.openHydrated("/mission-control")
        let rows = try await page.evaluate("\(measure)('.button-group-view[data-direction=\"row\"]')", as: [String].self)
        #expect(!rows.isEmpty, "the dashboard's row group is in view")
        for row in rows {
          let parts = row.split(separator: " ").map(String.init)
          #expect(parts.first == "row", "a row group: \(row)")
          #expect(parts.count == 4 && parts[1] == parts[2], "a row group's gap is the button gap: \(row)")
          #expect(parts.count == 4 && parts[1] != "4px", "a row group does not take a column's gap: \(row)")
        }
        try await page.expectNoErrors()
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }

  /// HomeView's search bar opens the search dialog, so its field is a
  /// pointer; a sidebar's bar is a text field.
  @Test(arguments: [BrowserEngine.chrome])
  func onlyTheTriggerSearchBarIsAPointer(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: .desktop) { page in
      let cursor = "(selector => getComputedStyle(document.querySelector(selector)).cursor)"
      try await page.openHydrated("/")
      #expect(try await page.evaluate("\(cursor)('.search-bar-input[data-search-trigger=\"true\"]')", as: String.self) == "pointer")
      try await page.openHydrated("/biblio-records")
      #expect(try await page.evaluate("\(cursor)('.sidebar-view .search-bar-input[data-search-trigger=\"false\"]')", as: String.self) != "pointer")
      try await page.expectNoErrors()
    }
  }

  /// Each sidebar reads its own width: the records list's and a record
  /// page's are both 256 (the width is a per-instance custom property).
  @Test(arguments: [BrowserEngine.chrome])
  func eachSidebarKeepsItsOwnWidth(engine: BrowserEngine) async throws {
    guard gnorium.engines.contains(engine) else { return }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work: ScratchWork
    do {
      work = try ScratchWork(owner: admin)
    } catch {
      try await admin.remove(after: error)
    }
    do {
      try await withPage(engine, gnorium, viewport: .desktop) { page in
        let width = "(selector => getComputedStyle(document.querySelector(selector)).width)"
        try await page.openHydrated("/biblio-records")
        #expect(try await page.evaluate("\(width)('.biblio-records-sidebar-view')", as: String.self) == "256px")
        try await page.openHydrated(work.path)
        #expect(try await page.evaluate("\(width)('.record-sidebar-view')", as: String.self) == "256px")
        try await page.expectNoErrors()
      }
    } catch {
      work.remove()
      try await admin.remove(after: error)
    }
    work.remove()
    try await admin.remove()
  }
}
