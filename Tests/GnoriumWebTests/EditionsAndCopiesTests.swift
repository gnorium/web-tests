import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An edition's format and extent and a copy's dimension and former owners
/// (user, 2026-11-01), on Submit Testament: the format a combobox of the
/// listed formats, its units' options capitalized; "+ Former owner" adds a
/// row, each its name, its Certainty (certain to start with) and its
/// period, a Start and an End card each a whole date (user, 2026-11-03),
/// posted as one list and kept with the draft across a reload. Activities nest by level: the edition's
/// agents are offered the printer only once its impression and issue are
/// taken out, their activities folding into it. Signed out: nothing is
/// posted.
@Suite("Editions and copies described in full")
struct EditionsAndCopiesTests {
  static let form = "/mission-control/submit/bibliographic/testament"

  @Test(arguments: gnorium.engines)
  func formerOwnersAreRowsKeptWithTheDraft(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated(Self.form)
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.openHydrated(Self.form)

      // The edition's physical description; the copy's dimension.
      try await expect(page.locator("#testament-format")).toHaveCount(1)
      try await expect(page.locator(".dropdown-view:has(#testament-format) [data-value='quarto']")).toHaveCount(1)
      try await expect(page.locator(".dropdown-view:has(#testament-format) [data-value='other']")).toHaveCount(0)
      try await expect(page.locator(".dropdown-view:has(#testament-extent-unit) .dropdown-selected-text"))
        .toContainText("Leaves")
      try await expect(page.locator(".dropdown-view:has(#testament-dimension-unit) .dropdown-selected-text"))
        .toContainText("Centimeter")

      let section = page.locator("[data-item-list='former-owner'] > [data-item-section='true']")
      try await expect(section).toHaveCount(1)
      try await expect(page.locator("[data-item-list='former-owner'] .item-add-btn").first)
        .toHaveAttribute("aria-label", "Add Former Owner")
      try await page.locator("input[name='former-owner-item1-text-input']").fill("Duke of Devonshire")
      let start = section.locator(".form-items-period-start .form-item-legend")
      try await expect(start).toHaveCount(1)
      try await expect(start).toContainText("Start")
      try await expect(section.locator(".form-items-period-end .form-item-legend")).toContainText("End")
      try await expect(page.locator("input[name='former-owner-item1-end-year']")).toHaveCount(1)
      try await page.locator("input[name='former-owner-item1-start-year']").fill("1800")
      try await page.locator("[data-item-list='former-owner'] > [data-item-add-btn='true'] .item-add-btn").click()
      try await expect(section).toHaveCount(2)
      try await page.locator("input[name='former-owner-item2-text-input']").fill("Henry E. Huntington")
      try await page.locator("input[name='former-owner-item2-start-year']").fill("1914")
      // The added row's dates stay optional.
      try await expect(page.locator("input[name='former-owner-item2-start-year']")).not.toHaveAttribute("required", "")
      // Each row posts its own id, given as it was added, so a claim names
      // it (user, 2026-11-03), after its name, its Certainty and its period.
      let rows =
        #"[{"value":"Duke of Devonshire","certainty":"certain","start":{"era":"anno_domini","year":1800}},"#
        + #"{"value":"Henry E. Huntington","certainty":"certain","start":{"era":"anno_domini","year":1914}}]"#
      var posted = try await Self.formerOwners(page)
      for _ in 0..<20 where posted.rest != rows {
        try await Task.sleep(for: .milliseconds(250))
        posted = try await Self.formerOwners(page)
      }
      #expect(posted.rest == rows, "the rows as posted: \(posted.rest)")
      let ids = try #require(posted.ids, "each row its own id")

      // Kept a moment after the last change, and back after a reload.
      var kept = ""
      for _ in 0..<20 {
        kept = try await page.evaluate("localStorage.getItem('gnorium:draft:' + location.pathname) || ''", as: String.self)
        if kept.contains("Henry E. Huntington") { break }
        try await Task.sleep(for: .milliseconds(250))
      }
      _ = try await page.reload()
      try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
      try await expect(section, timeout: .seconds(15)).toHaveCount(2)
      try await expect(page.locator("input[name='former-owner-item2-text-input']")).toHaveValue("Henry E. Huntington")
      try await expect(page.locator("input[name='former-owner-item2-start-year']")).toHaveValue("1914")
      // The rows back with their ids: a claim made before still names them.
      var back = try await Self.formerOwners(page)
      for _ in 0..<20 where back.ids != ids {
        try await Task.sleep(for: .milliseconds(250))
        back = try await Self.formerOwners(page)
      }
      #expect(back.ids == ids, "the ids kept with the draft: \(back.ids ?? "none")")
      #expect(back.rest == rows, "the rows kept with the draft: \(back.rest)")
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.expectNoErrors()
    }
  }

  /// The former owners' list as posted (`former-owner-json`): its rows
  /// without their ids, as JSON, and their ids in order, nil unless each
  /// is a UUID of its own, in upper case.
  static func formerOwners(_ page: Page) async throws -> (rest: String, ids: String?) {
    let read = try await page.evaluate(
      """
      (() => { const input = document.querySelector("input[name='former-owner-json']");
        let rows = []; try { rows = JSON.parse(input?.value || '[]'); } catch (e) { return { rest: input.value, ids: '' }; }
        const uuid = /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/;
        const ids = rows.map((row) => row.id);
        const own = ids.every((id) => typeof id === 'string' && uuid.test(id)) && new Set(ids).size === ids.length;
        return { rest: JSON.stringify(rows.map(({ id, ...rest }) => rest)), ids: own ? ids.join(',') : '' }; })()
      """)
    let ids = read["ids"].string ?? ""
    return (read["rest"].string ?? "", ids.isEmpty ? nil : ids)
  }

  @Test(arguments: gnorium.engines)
  func anEditionTakesTheRolesOfTheLevelsItsTreeSkips(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated(Self.form)
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.openHydrated(Self.form)
      let publication = page.locator(".activity-statement-view[data-as-namespace='publication']").first
      let printer = publication.locator("[data-item-section='true'] .dropdown-option[data-value='printer']").first
      let publisher = publication.locator("[data-item-section='true'] .dropdown-option[data-value='publisher']").first
      try await expect(printer).toHaveAttribute("data-unoffered", "true")
      try await expect(publisher).not.toHaveAttribute("data-unoffered", "true")
      // The impression (1.1) out, then the issue (1.1 again): their
      // manufacture and distribution fold into the edition.
      let stepper = TreeStepper(page, tree: TreeStepper.submission)
      // The volume (1.1) first: it has no activity, so nothing folds.
      try await stepper.remove("Remove testament 1.1.")
      try await expect(printer).toHaveAttribute("data-unoffered", "true")
      try await stepper.remove("Remove testament 1.1.")
      try await expect(printer).toHaveAttribute("data-unoffered", "false")
      let distributor = publication.locator("[data-item-section='true'] .dropdown-option[data-value='distributor']").first
      try await expect(distributor).toHaveAttribute("data-unoffered", "true")
      let issue = page.locator(".outliner-item[data-testament-draft='true'][data-draft-level='4']")
      try await stepper.remove(node: issue, noun: "testament")
      try await expect(issue).toHaveAttribute("data-outliner-removed", "true")
      try await expect(distributor).toHaveAttribute("data-unoffered", "false")
      // The impression's manufacture is its own activity, named so.
      try await expect(page.locator(".activity-statement-view[data-as-namespace='manufacture']")).toHaveCount(1)
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.expectNoErrors()
    }
  }
}
