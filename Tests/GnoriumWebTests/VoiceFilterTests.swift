import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A voice is a role and a name, typed (user, 2026-10-03): no metadata
/// field links to a record. A record page's sidebar lists its Voices, each
/// its role and its name as plain text, never a link. The whole records
/// list does not filter by a voice: the sidebar's Author search finds one.
/// A title's and a class's page—whose records their voice names tell
/// apart—show a Voice names column, a list, filtered by the prefix's
/// Voice names (user, 2026-10-08), the whole set one address takes, a
/// combobox suggesting the sets the class's records take. There are no person
/// pages. A throwaway admin owns a scratch work, removed after.
@Suite("Voice filter", .serialized)
struct VoiceFilterTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aVoiceIsPlainText(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    do {
      try await run(engine: engine, viewport: layout.viewport(for: engine), work: work)
    } catch {
      work.remove()
      try await admin.remove(after: error)
    }
    work.remove()
    try await admin.remove()
  }

  @Test(arguments: gnorium.engines, Layout.allCases)
  func aClassPageFiltersItsVoiceNames(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let (work, namesake) = try ScratchRecord.pair()
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        let group = "/" + work.path.split(separator: "/").prefix(4).joined(separator: "/")
        try await page.openHydrated(group)
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
        try await expect(page.locator("[data-table-column-id='voice-names']").first).toBeVisible()
        let options = page.locator(".filter-bar-view .filter-bar-field-picker .dropdown-option")
        // The set, Voice names; no atomic Voice name filter.
        try await expect(options.filter(hasText: "Voice names", exact: true)).not.toHaveCount(0)
        try await expect(options.filter(hasText: "Voice name", exact: true)).toHaveCount(0)
        // A row switched to Voice names is a combobox: typed words, in any
        // order and case, suggest the sets its records take; one picked
        // and applied is its address.
        try await page.locator(".filter-bar-add-btn").click()
        let row = page.locator(".filter-bar-row").last
        try await row.locator(".filter-bar-field-picker .dropdown-trigger").click()
        try await row.locator(".filter-bar-field-picker .dropdown-option[data-value='voice-names']").click()
        let field = row.locator("input[data-combobox-input='true']")
        try await expect(field).toBeVisible()
        let size = try await field.evaluate("(e) => getComputedStyle(e).fontSize").string
        #expect(size == "16px", "the combobox's text is 16px, as the bar's other fields: \(size ?? "")")
        let words = work.author.split(separator: " ").reversed().joined(separator: " ").uppercased()
        try await field.fill(words)
        let suggestion = row.locator(".combobox-option").filter(hasText: work.author)
        try await expect(suggestion).toBeVisible()
        try await suggestion.click()
        try await page.locator(".filter-bar-apply").click()
        try await expect(page).toHaveURL(work.path) { url in url.path == work.path }
        try await page.expectNoHorizontalOverflow()
        // Voice names, typed in another case: the set's canonical address.
        try await page.openHydrated(
          "/biblio-records?language=eng&titled=\(group.split(separator: "/")[2])&typed=report&voice-names="
            + (work.author.uppercased().addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""))
        try await expect(page).toHaveURL(work.path) { url in url.path == work.path }
      }
    } catch {
      work.remove()
      namesake.remove()
      throw error
    }
    work.remove()
    namesake.remove()
  }

  private func run(engine: BrowserEngine, viewport: Viewport, work: ScratchWork) async throws {
    try await withPage(engine, gnorium, viewport: viewport) { page in
      try await page.openHydrated(work.path)
      // The sidebar is drawn once, and again in the phone's menu: its
      // Voices a role and a name, no link among them.
      let voices = page.locator(".record-sidebar-section").filter(hasText: "Voices").first
      try await expect(voices).toContainText("Author")
      try await expect(voices).toContainText(work.author)
      try await expect(voices.locator("a")).toHaveCount(0)
      // Nowhere on the page is a voice's name a link.
      try await expect(page.locator("a").filter(hasText: work.author)).toHaveCount(0)
      var overflow = try await page.evaluate("document.documentElement.scrollWidth > window.innerWidth").bool
      #expect(overflow == false)

      // The records lists filter by no voice: the sidebar's Author search
      // finds one. The bar offers no Voice field.
      try await page.openHydrated("/biblio-records")
      let filter = page.locator(".filter-bar-view")
      try await expect(filter.locator(".filter-bar-field-picker .dropdown-option")).not.toHaveCount(0)
      try await expect(filter.locator(".filter-bar-field-picker .dropdown-option").filter(hasText: "Voice", exact: true))
        .toHaveCount(0)
      try await expect(filter.locator("input[name='voice']")).toHaveCount(0)
      overflow = try await page.evaluate("document.documentElement.scrollWidth > window.innerWidth").bool
      #expect(overflow == false)

      // No person page: an address nobody held is the normal 404.
      let status = try await page.evaluate(
        "fetch('/persons/nobody/unknown/unknown', { redirect: 'manual' }).then((r) => r.status)"
      ).double
      #expect(status == 404)
    }
  }
}
