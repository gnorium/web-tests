import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An overture's Semblances roster, its testament's pager and its prompt
/// preview stay on one semblance (user, 2026-10-07): the pager moves the
/// roster's current row, a row moves the reader, and the preview always
/// shows the page on screen. An admin ticks the semblances its commit sends
/// to explication; a tick never moves the reader. An object with two
/// processes has a toggle leading its header's actions (a segmented slider
/// whose pill glides to the pressed button) choosing whose prompts show; one
/// with a single process has none. The solid kind tabs carry the same pill.
/// Nothing is committed here.
@Suite("Overture semblances", .serialized)
struct OvertureSemblancesTests {
  /// Whether `inner` sits on `outer` within a pixel.
  static func sameBox(_ inner: BoundingBox, _ outer: BoundingBox) -> Bool {
    abs(inner.x - outer.x) < 1.5 && abs(inner.y - outer.y) < 1.5
      && abs(inner.width - outer.width) < 1.5 && abs(inner.height - outer.height) < 1.5
  }

  /// The pill has glided (its transition is the base duration).
  static func settle() async throws { try await Task.sleep(for: .milliseconds(600)) }

  private func shoot(_ page: Page, _ name: String, _ layout: Layout) async throws {
    guard let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"] else { return }
    try await page.screenshot(to: URL(fileURLWithPath: directory).appendingPathComponent("overture-\(layout)-\(name).png"))
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func rosterPagerAndPreviewShareTheSemblance(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch: ScratchCommit
    do { scratch = try ScratchCommit(owner: admin, sourceURL: fixture.baseURL + "/manifest.json") }
    catch { try await admin.remove(after: error) }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(scratch.overturePath)
        let viewer = page.locator(".disputorium-core-work .artifact-view").first
        try await expect(viewer).toHaveAttribute("data-artifact-hydrated", "true")
        try await expect(viewer.locator("#artifact-page-total")).toHaveText("3")
        let roster = page.locator(".overture-semblances").first
        let rows = roster.locator(".roster-row")
        try await expect(rows).toHaveCount(3)
        try await expect(rows.nth(0)).toHaveAttribute("class", "roster-row roster-row-check roster-row-selected")
        // Each row is ticked for the commit, with the image service it names.
        try await expect(roster.locator("input[name='semblance[]'][value='\(fixture.baseURL)/page-2']")).toHaveCount(1)

        // The preview is the page on screen's, never a notice.
        let task = page.locator(".prompt-instance-task .prompt-text-source").first
        try await expect(page.locator(".prompt-instances-slot")).toHaveAttribute("aria-busy", "false")
        try await expect(page.locator(".prompt-instances-notice")).toHaveCount(0)
        try await expect(page.locator(".prompt-instances-content .accordion-view")).toHaveCount(2)
        try await expect(task).toContainText("Title page")

        // The pager moves the roster and the address.
        try await viewer.locator(".pagination-next").first.click()
        try await expect(viewer.locator("#artifact-page-input")).toHaveValue("2")
        try await expect(rows.nth(1)).toHaveAttribute("class", "roster-row roster-row-check roster-row-selected")
        try await expect(rows.nth(0)).toHaveAttribute("class", "roster-row roster-row-check")
        #expect(try await page.url().hasSuffix("?semblance=1"))

        if layout == .desktop {
          // A row moves the reader, and the preview follows; it ticks nothing.
          try await rows.nth(2).locator(".roster-label").click()
          try await expect(viewer.locator("#artifact-page-input")).toHaveValue("3")
          try await expect(rows.nth(2)).toHaveAttribute("class", "roster-row roster-row-check roster-row-selected")
          try await expect(rows.nth(2).locator("input")).toBeChecked(false)
          try await expect(task).toContainText("Colophon")
          // A tick ticks, and leaves the reader where it is.
          try await rows.nth(0).locator("input").click()
          try await expect(rows.nth(0).locator("input")).toBeChecked()
          try await expect(viewer.locator("#artifact-page-input")).toHaveValue("3")
          try await expect(rows.nth(2)).toHaveAttribute("class", "roster-row roster-row-check roster-row-selected")
        }

        // One process: no toggle anywhere; the heading names it.
        try await expect(page.locator(".process-toggle-view")).toHaveCount(0)
        try await expect(page.locator(".prompt-instances-heading")).toHaveText("Prompts")
        try await expect(page.locator(".prompt-instances-content .accordion-title").first)
          .toContainText("System Prompt")
        try await shoot(page, "roster", layout)
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()

        // Two processes (an Italian witness is translated): the toggle leads
        // the header's actions, explication first, one always chosen, its
        // pill gliding to the one pressed; the prompts follow it.
        _ = try TestAdmin.query("""
          UPDATE bibliographic_madrigals SET metadata_json =
            (metadata_json::jsonb || '{"language":"ita"}'::jsonb)::text WHERE id = '\(scratch.madrigalID)'
          """)
        try await page.openHydrated(scratch.madrigalPath)
        try await expect(page.locator(".prompt-instances-heading")).toHaveText("Prompts")
        let processes = page.locator(".mission-control-object-header-view .process-toggle-view")
        try await expect(processes).toHaveAttribute("data-mode", "slider")
        try await expect(processes).toHaveAttribute("data-sliding-pill", "ready")
        let buttons = processes.locator(".toggle-button-group-button")
        try await expect(buttons).toHaveCount(2)
        let explication = buttons.nth(0)
        let translation = buttons.nth(1)
        try await expect(explication).toHaveAttribute("data-value", "bibliographic_explication")
        try await expect(explication).toHaveAttribute("aria-pressed", "true")
        let pill = processes.locator(".sliding-pill-thumb")
        #expect(Self.sameBox(try #require(try await pill.boundingBox()), try #require(try await explication.boundingBox())),
          "the pill is not under the chosen process")
        try await translation.click()
        try await expect(translation).toHaveAttribute("aria-pressed", "true")
        try await expect(explication).toHaveAttribute("aria-pressed", "false")
        try await expect(page.locator(".prompt-instances-content")).toHaveAttribute("data-selected-pipeline", "bibliographic_translation")
        try await Self.settle()
        #expect(Self.sameBox(try #require(try await pill.boundingBox()), try #require(try await translation.boundingBox())),
          "the pill did not glide to the pressed process")
        try await translation.click()
        try await expect(translation).toHaveAttribute("aria-pressed", "true")
        let toggleBox = try #require(try await processes.boundingBox())
        let actions = page.locator(".mission-control-object-header-grouped-actions")
        let row = try #require(try await actions.boundingBox())
        let modify = try #require(try await actions.locator(".button-group-button[data-value='modify']").boundingBox())
        let commit = try #require(try await actions.locator(".commit-view-trigger").boundingBox())
        let permit = try #require(try await actions.locator(".button-group-button[data-value='madrigal-permit']").boundingBox())
        if layout == .phone {
          // A phone: the toggle a full-width row of its own, its segments
          // sharing it, then each action a full-width row, in order.
          #expect(abs(toggleBox.width - row.width) < 2, "the toggle does not span the header")
          let first = try #require(try await explication.boundingBox())
          let second = try #require(try await translation.boundingBox())
          #expect(abs(first.width - second.width) < 2, "the segments do not share the width")
          for (name, box) in [("Modify", modify), ("Commit", commit), ("Permit", permit)] {
            #expect(abs(box.width - row.width) < 2, "\(name) does not span its row")
          }
          #expect(toggleBox.maxY <= modify.y && modify.maxY <= commit.y && commit.maxY <= permit.y, "out of order")
        } else {
          // Wider: one row, the toggle leading.
          #expect(abs((toggleBox.y + toggleBox.height / 2) - (commit.y + commit.height / 2)) < 2, "the toggle is not in the actions' row")
          #expect(toggleBox.maxX <= modify.x && modify.maxX <= commit.x && commit.maxX <= permit.x, "out of order")
          #expect(abs(toggleBox.height - commit.height) < 1, "the toggle is not the buttons' height")
        }
        try await shoot(page, "processes", layout)
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
      #expect(try scratch.stillPending(), "nothing was committed")
    } catch {
      scratch.remove()
      try await admin.remove(after: error)
    }
    scratch.remove()
    try await admin.remove()
  }

  /// The solid kind tabs: the active tab's pill sits under it on load, and
  /// glides to a tab chosen while its page loads.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func kindTabsCarryTheSlidingPill(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/prompts/bibliographic")
        let list = page.locator(".tabs-solid .tabs-list").first
        try await expect(list).toHaveAttribute("data-sliding-pill", "ready")
        let active = list.locator("[role='tab'][aria-selected='true']")
        try await expect(active).toHaveAttribute("data-tab-name", "bibliographic")
        let thumb = list.locator(".sliding-pill-thumb")
        try await expect(thumb).toHaveAttribute("data-animate", "false")
        #expect(Self.sameBox(
          try #require(try await thumb.boundingBox()), try #require(try await active.boundingBox())),
          "the pill is not under the active tab")
        try await expect(active).toHaveCSS("background-color", "rgba(0, 0, 0, 0)")
        try await shoot(page, "tabs", layout)

        try await list.locator("[role='tab'][data-tab-name='lexicographic']").click()
        try await expect(page).toHaveURL("\(gnorium.baseURL)/mission-control/prompts/lexicographic")
        let next = page.locator(".tabs-solid .tabs-list").first
        try await expect(next).toHaveAttribute("data-sliding-pill", "ready")
        let chosen = next.locator("[role='tab'][aria-selected='true']")
        try await expect(chosen).toHaveAttribute("data-tab-name", "lexicographic")
        #expect(Self.sameBox(
          try #require(try await next.locator(".sliding-pill-thumb").boundingBox()),
          try #require(try await chosen.boundingBox())),
          "the pill is not under the tab chosen")
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }
}
