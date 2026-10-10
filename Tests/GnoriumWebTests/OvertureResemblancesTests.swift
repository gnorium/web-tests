import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An overture's Resemblances roster, its testament's pager and its prompt
/// preview stay on one resemblance (user, 2026-10-07): the pager moves the
/// roster's current row, a row moves the reader, and the preview always
/// shows the page on screen. An admin ticks the resemblances its commit sends
/// to explication; a tick never moves the reader. Every object has one
/// process, decided by its state (user, 2026-10-10): no process toggle
/// anywhere. The solid kind tabs carry the sliding pill.
/// Nothing is committed here.
@Suite("Overture resemblances", .serialized)
struct OvertureResemblancesTests {
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
  func rosterPagerAndPreviewShareTheResemblance(engine: BrowserEngine, layout: Layout) async throws {
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
        // The manifest is fetched after hydration: slow while the full run
        // loads the server, so waited for in full.
        try await expect(viewer.locator("#artifact-page-total"), timeout: .seconds(20)).toHaveText("3")
        // No markup yet: the page images alone, always shown, with no
        // switch to put them away and no Raw or Find (user, 2026-10-09).
        try await expect(viewer.locator(".artifact-object")).toBeVisible()
        try await expect(viewer.locator(".artifact-canvas-toggle, .artifact-raw-toggle, .testament-find-button"))
          .toHaveCount(0)
        let roster = page.locator(".overture-resemblances").first
        let rows = roster.locator(".roster-row")
        try await expect(rows).toHaveCount(3)
        try await expect(rows.nth(0)).toHaveAttribute("class", "roster-row roster-row-check roster-row-selected")
        // Each row is ticked for the commit, with the image service it names.
        try await expect(roster.locator("input[name='resemblance[]'][value='\(fixture.baseURL)/page-2']")).toHaveCount(1)
        // An overture's pages have no markup yet: each a blue ring, pending
        // explication (user, 2026-10-09)—never a Computorium status.
        try await expect(roster.locator(".roster-status[data-mark='ring'][data-tone='blue']")).toHaveCount(3)
        try await expect(roster.locator(".roster-status[data-status]")).toHaveCount(0)

        // The preview is the page on screen's, never a notice.
        let task = page.locator("[data-process='Explication'] .prompt-preview-task .prompt-text-source").first
        try await expect(page.locator(".prompt-previews-slot"), timeout: .seconds(20))
          .toHaveAttribute("aria-busy", "false")
        try await expect(page.locator("[data-process='Explication'] .prompt-preview-task-notice")).toHaveCount(0)
        try await expect(page.locator(".prompt-previews-content .accordion-view")).toHaveCount(12)
        try await expect(task).toContainText("Title page")

        // The pager moves the roster and the address.
        try await viewer.locator(".pagination-next").first.click()
        try await expect(viewer.locator("#artifact-page-input")).toHaveValue("2")
        try await expect(rows.nth(1)).toHaveAttribute("class", "roster-row roster-row-check roster-row-selected")
        try await expect(rows.nth(0)).toHaveAttribute("class", "roster-row roster-row-check")
        #expect(try await page.url().hasSuffix("?resemblance=1"))

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

        // One process: no toggle anywhere.
        try await expect(page.locator(".process-toggle-view")).toHaveCount(0)
        try await expect(page.locator(".prompt-previews-heading")).toHaveText("Prompts")
        // One accordion a process, its prompts nested inside (user,
        // 2026-10-10), closed until opened.
        try await expect(page.locator("#prompt-preview-process .accordion-title").first).toHaveText("Explication")
        try await expect(page.locator("#prompt-preview-process")).toHaveAttribute("data-expanded", "false")
        try await expect(page.locator("#prompt-preview-process .accordion-title").nth(1)).toHaveText("System Prompt")
        try await expect(page.locator("#prompt-preview-process .accordion-title").nth(3)).toHaveText("Autocompaction")
        try await shoot(page, "roster", layout)
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()

        // A madrigal, whatever its state, has one process too (user,
        // 2026-10-10): no toggle; its actions in their order, a full-width
        // row each on a phone.
        _ = try TestAdmin.query("""
          UPDATE bibliographic_madrigals SET metadata_json =
            (metadata_json::jsonb || '{"language":"ita"}'::jsonb)::text WHERE id = '\(scratch.madrigalID)'
          """)
        try await page.openHydrated(scratch.madrigalPath)
        try await expect(page.locator(".process-toggle-view")).toHaveCount(0)
        try await expect(page.locator(".prompt-previews-slot"), timeout: .seconds(20))
          .toHaveAttribute("aria-busy", "false")
        // Its page not read yet: explication, though the witness is Italian.
        try await expect(page.locator(".prompt-previews-content")).toHaveAttribute("data-process", "bibliographic_explication")
        let actions = page.locator(".mission-control-object-header-grouped-actions")
        let row = try #require(try await actions.boundingBox())
        let revise = try #require(try await actions.locator(".button-group-button[data-value='revise']").boundingBox())
        let commit = try #require(try await actions.locator(".commit-trigger").boundingBox())
        let permit = try #require(try await actions.locator(".button-group-button[data-value='madrigal-permit']").boundingBox())
        if layout == .phone {
          for (name, box) in [("Revise", revise), ("Commit", commit), ("Permit", permit)] {
            #expect(abs(box.width - row.width) < 2, "\(name) does not span its row")
          }
          #expect(revise.maxY <= commit.y && commit.maxY <= permit.y, "out of order")
        } else {
          #expect(revise.maxX <= commit.x && commit.maxX <= permit.x, "out of order")
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
        // A solid tab is a large control, as a quiet one is (user,
        // 2026-10-10): 48.
        let tabHeight = try #require(try await active.boundingBox()).height
        #expect(abs(tabHeight - 48) < 0.5, "a solid tab is \(tabHeight)px tall, not 48")
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

  /// A prompt's legend links the accepted revision merged into it at the
  /// prompt it is (user, 2026-10-09): the revision page's system or task
  /// accordion. Opened by the task prompt's link, a system-prompt-only
  /// revision's page opens the task's accordion—unchanged, so closed on
  /// its own—and scrolls it into view; the system prompt's stands open on
  /// its diff as before.
  @Test(arguments: [BrowserEngine.chrome])
  func aPromptLegendLinkLandsOnItsPromptOfTheRevision(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let user = try contributor.column("id")
    let scratch: ScratchCommit
    do { scratch = try ScratchCommit(owner: admin, sourceURL: fixture.baseURL + "/manifest.json") }
    catch { try await admin.remove(after: error) }
    func remove() {
      _ = try? TestAdmin.query("DELETE FROM revisions WHERE requested_by_user_id = '\(user)'")
      scratch.remove()
    }
    do {
      // The form's required fields the fixture leaves empty—the carrier,
      // the digitization's provider—set as the overture's own.
      _ = try TestAdmin.query(
        "UPDATE bibliographic_overtures SET carrier = 'printed', provider = 'folger_shakespeare_library' WHERE id = '\(scratch.overturePath.split(separator: "/").last ?? "")'")
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        // A contributor's suggestion of the system prompt alone.
        try await page.openHydrated("\(scratch.overturePath)/revise")
        // The form's required fields, filled so the browser lets it go.
        try await page.locator("[data-revise-form] input[name='title']").first.fill("Web tests legend title")
        let prompts = page.locator(".prompt-revision-fields-process[data-process='bibliographic_explication']")
        try await prompts.locator("#prompt-revision-process-bibliographic_explication .accordion-summary").first.click()
        try await prompts.locator("#prompt-revision-system-accordion-bibliographic_explication .accordion-summary").first
          .click()
        try await expect(prompts.locator("#prompt-revision-system-accordion-bibliographic_explication"))
          .toHaveAttribute("data-open-finished", "true")
        _ = try await page.evaluate(
          """
          (() => {
            const area = document.querySelector("textarea[name='prompt-system-bibliographic_explication']")
            area.value = area.value + '\\nWeb tests legend suggestion.'
            area.dispatchEvent(new Event('input', { bubbles: true }))
            return true
          })()
          """, as: Bool.self)
        try await expect(prompts.locator(".field-diff-diff").first).toContainText("Web tests legend suggestion.")
        try await page.locator(".revision-form button[type='submit']").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL(
          "the overture at its locution",
          where: { url in url.path.lowercased() == scratch.overturePath.lowercased() })
      }
      let id = try TestAdmin.query("SELECT id FROM revisions WHERE requested_by_user_id = '\(user)'").uppercased()
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        // Accepted from the thread.
        try await page.openHydrated(scratch.overturePath)
        try await expect(page.locator(".prompt-previews-slot"), timeout: .seconds(20))
          .toHaveAttribute("aria-busy", "false")
        let accept = page.locator("#revision-\(id) form[action$='/accept'] button")
        try await expect(accept).toBeVisible()
        try await accept.click()
        try await expect(page, timeout: .seconds(15)).toHaveURL(
          "the overture at its locution",
          where: { url in url.path.lowercased() == scratch.overturePath.lowercased() && (url.fragment ?? "").hasPrefix("revision-") })
        try await expect(page.locator("#revision-\(id)-verdict-1")).toContainText("accepted revision")

        // Merged in, each prompt's legend links the revision's page at the
        // prompt it is.
        try await page.openHydrated(scratch.overturePath)
        try await expect(page.locator(".prompt-previews-slot"), timeout: .seconds(20))
          .toHaveAttribute("aria-busy", "false")
        try await expect(page.locator(".prompt-preview-system a[href$='/revisions/\(id)#prompt-change-system']"))
          .toHaveCount(1)
        try await expect(page.locator("[data-process='Explication'] .prompt-preview-task a[href$='/revisions/\(id)#prompt-change-task']").first)
          .toBeAttached()

        // The task prompt's link: its accordion opened and in view, the
        // system prompt's open on its diff as before.
        try await page.openHydrated("\(scratch.overturePath)/revisions/\(id)#prompt-change-task")
        try await expect(page.locator("#prompt-change-system")).toHaveAttribute("data-expanded", "true")
        try await expect(page.locator("#prompt-change-task")).toHaveAttribute("data-expanded", "true")
        try await expect(page.locator("#prompt-change-task")).toHaveAttribute("data-open-finished", "true")
        let inView = try await page.evaluate(
          """
          (() => {
            const box = document.getElementById('prompt-change-task').getBoundingClientRect()
            return box.top >= 0 && box.top < window.innerHeight
          })()
          """, as: Bool.self)
        #expect(inView, "The task prompt's accordion is scrolled into view")
      }
    } catch {
      remove()
      try await contributor.remove()
      try await admin.remove(after: error)
    }
    remove()
    try await contributor.remove()
    try await admin.remove()
  }
}
