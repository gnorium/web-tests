import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A prefix page is the records list itself (user, 2026-09-28): no heading
/// of its own, its tab naming it, its prefix the filters in force —
/// Language, then Title — removable as any filter is. The Title row's −
/// and Apply go to the language's page; the language picked again (cleared)
/// and Apply, to the whole list. The breadcrumbs keep the prefix. A scratch
/// work made by SQL, removed after (`ScratchRecord`).
@Suite("Record prefix filters", .serialized)
struct RecordPrefixFiltersTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aPrefixIsTheListsFilters(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let work = try ScratchRecord()
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await Self.run(page, work: work)
      }
    } catch {
      work.remove()
      throw error
    }
    work.remove()
  }

  static func run(_ page: Page, work: ScratchRecord) async throws {
    let titlePrefix = "/" + work.path.split(separator: "/").prefix(3).joined(separator: "/")
    try await page.openHydrated(titlePrefix)
    try await page.expectNoErrors()
    try await page.expectNoHorizontalOverflow()
    try await expect(page.locator("main a[href='\(work.path)']")).toHaveCount(1)
    // The list's own look: no heading, its tab selected.
    try await expect(page.locator(".page-heading")).toHaveCount(0)
    try await expect(page.locator(".records-tabs #tab-biblio-records")).toHaveAttribute("aria-selected", "true")
    let filter = page.locator(".filter-bar-view")
    let fields = filter.locator(".filter-bar-field-picker .dropdown-selected-text")
    let values = filter.locator(".filter-bar-value-select .dropdown-selected-text")
    try await expect(fields).toHaveTexts(["Language", "Title"])
    try await expect(values).toHaveTexts(["English", work.title])
    // The crumbs keep the prefix.
    let trail = page.locator("footer .footer-breadcrumbs")
    try await expect(trail.locator(".breadcrumb-current")).toHaveText(work.title)

    // The bar's + and − are icon-only: the Codex add and subtract icons, no
    // "+"/"−" character, named for what they do. A row the client adds wears
    // the same −, and takes itself away.
    let add = filter.locator(".filter-bar-add-btn")
    try await expect(add).toHaveText("")
    try await expect(add.locator("svg.add-icon-view")).toHaveCount(1)
    try await expect(add).toHaveAttribute("aria-label", "Add filter")
    let secondRemove = filter.locator(".filter-bar-row").nth(1).locator(".filter-bar-remove-btn")
    try await expect(secondRemove).toHaveText("")
    try await expect(secondRemove.locator("svg.subtract-icon-view")).toHaveCount(1)
    try await expect(secondRemove).toHaveAttribute("aria-label", "Remove filter")
    try await add.click()
    try await expect(filter.locator(".filter-bar-row")).toHaveCount(3)
    let addedRemove = filter.locator(".filter-bar-row").nth(2).locator(".filter-bar-remove-btn")
    try await expect(addedRemove.locator("svg.subtract-icon-view")).toHaveCount(1)
    try await expect(addedRemove).toHaveAttribute("aria-label", "Remove filter")
    try await addedRemove.click()
    try await expect(filter.locator(".filter-bar-row")).toHaveCount(2)

    // The title removed: the language's page.
    try await filter.locator(".filter-bar-row").nth(1).locator(".filter-bar-remove-btn").click()
    try await filter.locator(".filter-bar-apply").click()
    try await expect(page).toHaveURL("/biblio-records/eng") { url in url.path == "/biblio-records/eng" }
    try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
    try await page.expectNoErrors()
    try await page.expectNoHorizontalOverflow()
    try await expect(page.locator(".page-heading")).toHaveCount(0)
    try await expect(fields).toHaveTexts(["Language"])
    try await expect(values).toHaveTexts(["English"])
    try await expect(page.locator("main a[href='\(work.path)']")).toHaveCount(1)

    // The language cleared: the whole list.
    try await filter.locator(".filter-bar-value-select .dropdown-trigger").first.click()
    try await filter.locator(".filter-bar-value-select .dropdown-option").filter(hasText: "English", exact: true).click()
    try await filter.locator(".filter-bar-apply").click()
    try await expect(page).toHaveURL("/biblio-records") { url in url.path == "/biblio-records" }
    try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
    try await page.expectNoErrors()
    try await expect(page.locator(".filter-bar-value-select input[name='language']")).toHaveCount(0)
  }
}
