import Foundation
import Testing
import WebTests
import WebTestsTesting

/// One Suggest is one revision (user, 2026-10-08): an object's Revise
/// page files whatever was changed—its fields, any number of markups
/// edited in its reader, the prompts of the process it would be committed
/// for—as one row, accepted whole; each diff is drawn live where it is made,
/// and the revision's page draws each in the record's tree. Suggest lands
/// on the object's own page at the suggestion's locution; the revision is
/// accepted or rejected there or on its own page, and each object's
/// Revisions page is read-only. Prompts are in force only once the
/// object is committed. A process's prompt page is read-only. All of it
/// under a throwaway contributor's account; Chrome, desktop.
@Suite("Revise pages", .serialized)
struct RevisePagesTests {
  /// The object's page at a suggestion's locution in its thread.
  static func atLocution(_ path: String) -> @Sendable (URL) -> Bool {
    { url in url.path.lowercased() == path.lowercased() && (url.fragment ?? "").hasPrefix("revision-") }
  }

  /// Revise opens on the resemblance the object's reader is showing (user,
  /// 2026-10-10): the Evidence roster's selected row, carried as
  /// `?resemblance=` into the Revise link as the reader turns; the Revise
  /// page's reader and editor open there, and its way back to the object
  /// (the breadcrumb) names the resemblance on screen too.
  @Test(arguments: [BrowserEngine.chrome])
  func reviseOpensOnTheResemblanceOnScreen(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor)
    let services = (1...3).map { "https://web-tests.invalid/iiif/p\($0)" }
    // The links name the object as the server writes its id.
    let objectURL = "/mission-control/madrigals/bibliographic/\(commit.madrigalID.uppercased())"
    do {
      let pages = (1...3).map {
        #"<pb n=\"\#($0)\" facs=\"https://web-tests.invalid/iiif/p\#($0)/full/1300,/0/default.jpg\"/><p>Line \#($0)</p>"#
      }.joined()
      _ = try TestAdmin.query(
        """
        UPDATE bibliographic_madrigals SET
          proposed_content_json = '{"teiXml":"<TEI><text><body>\(pages)</body></text></TEI>"}'
        WHERE id = '\(commit.madrigalID)'
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated(commit.madrigalPath)
        let rows = page.locator("#madrigal-resemblances .roster-row")
        try await expect(rows).toHaveCount(3)
        let revise = page.locator("a[data-value='revise']")
        try await expect(revise).toHaveAttribute("href", "\(objectURL)/revise")
        // Item 3 selected: the reader on resemblance 3, Revise opening there.
        try await rows.nth(2).click()
        try await expect(page).toHaveURL("the madrigal at resemblance 3") { $0.query == "resemblance=2" }
        try await expect(page.locator("#madrigal-resemblances .roster-row-selected"))
          .toHaveAttribute("data-computorium-session-id", "2")
        try await expect(revise).toHaveAttribute("href", "\(objectURL)/revise?resemblance=2")
        try await revise.click()
        try await expect(page).toHaveURL("the Revise page at resemblance 3") {
          $0.path.lowercased() == "\(objectURL)/revise".lowercased() && $0.query == "resemblance=2"
        }
        let viewer = page.locator(".revise-bibliographic-object .artifact-view")
        try await expect(viewer).toHaveAttribute("data-artifact-hydrated", "true")
        try await expect(viewer.locator("#artifact-page-input")).toHaveValue("3")
        try await expect(viewer.locator(".tei-page[data-active='true']")).toHaveAttribute("data-service-id", services[2])
        try await expect(viewer.locator(".tei-page[data-active='true'] .tei-page-edit textarea")).toHaveCount(1)
        // The way back names the resemblance on screen, and follows the pager.
        let back = page.locator(".breadcrumb-link[href='\(objectURL)?resemblance=2']")
        try await expect(back).toHaveCount(1)
        try await viewer.locator(".pagination-prev").first.click()
        try await expect(viewer.locator("#artifact-page-input")).toHaveValue("2")
        try await expect(page).toHaveURL("the Revise page at resemblance 2") { $0.query == "resemblance=1" }
        let backAtTwo = page.locator(".breadcrumb-link[href='\(objectURL)?resemblance=1']")
        try await expect(backAtTwo).toHaveCount(1)
        try await backAtTwo.click()
        try await expect(page).toHaveURL("the madrigal at resemblance 2") {
          $0.path.lowercased() == commit.madrigalPath.lowercased() && $0.query == "resemblance=1"
        }
        try await expect(page.locator("#madrigal-resemblances .roster-row-selected"))
          .toHaveAttribute("data-computorium-session-id", "1")
        // The object's pager turns the roster and the Revise link alike.
        let reader = page.locator(".madrigal-object .artifact-view")
        try await expect(reader).toHaveAttribute("data-artifact-hydrated", "true")
        try await reader.locator(".pagination-next").first.click()
        try await expect(page.locator("#madrigal-resemblances .roster-row-selected"))
          .toHaveAttribute("data-computorium-session-id", "2")
        try await expect(revise).toHaveAttribute("href", "\(objectURL)/revise?resemblance=2")
        try await reader.locator(".pagination-prev").first.click()
        try await reader.locator(".pagination-prev").first.click()
        try await expect(page.locator("#madrigal-resemblances .roster-row-selected"))
          .toHaveAttribute("data-computorium-session-id", "0")
        try await expect(revise).toHaveAttribute("href", "\(objectURL)/revise")
      }
    } catch {
      commit.remove()
      try await contributor.remove(after: error)
    }
    commit.remove()
    try await contributor.remove()
  }

  @Test(arguments: [BrowserEngine.chrome])
  func oneSuggestFilesFieldsMarkupsAndPromptsAsOneRevision(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let user = try contributor.column("id")
    // The witness's pages served on this machine: the ring is checked
    // with the resemblance shown too, which needs an image to show.
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let commit = try ScratchCommit(owner: contributor, sourceURL: fixture.baseURL + "/manifest.json")
    let slot = "bibliographic_explication"
    func remove() {
      _ = try? TestAdmin.query("DELETE FROM revisions WHERE requested_by_user_id = '\(user)'")
      commit.remove()
    }
    let inForce = try TestAdmin.query("SELECT vignette_id FROM active_prompt_vignettes WHERE slot = '\(slot)'")
    do {
      // Two resemblances; the digitization's required provider.
      _ = try TestAdmin.query(
        #"""
        UPDATE bibliographic_madrigals SET
          metadata_json = (metadata_json::jsonb || '{"title":"Web tests original title","provider":"folger_shakespeare_library"}'::jsonb)::text,
          proposed_content_json = '{"teiXml":"<TEI><teiHeader><date>1910</date></teiHeader><text><body><pb n=\"1\" facs=\"\#(fixture.baseURL)/page-1/full/1300,/0/default.jpg\"/><div><p>Old line</p></div><pb n=\"2\" facs=\"\#(fixture.baseURL)/page-2/full/1300,/0/default.jpg\"/><p>Kept line</p><pb n=\"3\" facs=\"\#(fixture.baseURL)/page-3/full/1300,/0/default.jpg\"/></body></text></TEI>"}'
        WHERE id = '\#(commit.madrigalID)'
        """#)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        // The process's page is read-only, its runs its associated ones.
        let processURL = "/mission-control/prompts/bibliographic/explication"
        try await page.openHydrated(processURL)
        try await expect(page.locator("a[href='\(processURL)/revise']")).toHaveCount(0)
        try await expect(page.locator(".associated-links-view a")).toHaveText("runs")

        try await page.openHydrated("\(commit.madrigalPath)/revise")
        try await expect(page.locator(".testament-tree-diff-view")).toHaveCount(1)
        try await expect(page.locator(".tei-page-edit textarea")).toHaveCount(3)
        // One Suggest, at the end: none per page, none for the prompts, no
        // Diff toggle and no scope.
        try await expect(page.locator("button[type='submit']").filter(hasText: "Suggest")).toHaveCount(1)
        try await expect(page.locator(".testament-suggest")).toHaveCount(0)
        try await expect(page.locator(".prompt-revision-fields-diff-toggle")).toHaveCount(0)
        try await expect(page.locator("input[name='scope']")).toHaveCount(0)
        try await expect(page.locator(".prompt-revision-fields-view .process-toggle-view")).toHaveCount(0)
        try await page.expectNoHorizontalOverflow()

        // Opening the formatted editor alone files no diff or revision.
        try await page.locator("button[type='submit']").filter(hasText: "Suggest").click()
        try await expect(page.locator(".alert-view").filter(hasText: "Nothing was changed.")).toBeVisible()
        let untouched = try TestAdmin.query("SELECT count(*) FROM revisions WHERE revisable_id = '\(commit.madrigalID)'")
        #expect(untouched.trimmingCharacters(in: .whitespacesAndNewlines) == "0")
        try await page.openHydrated("\(commit.madrigalPath)/revise")

        // The fields, a markup and the system prompt, each diff drawn
        // as it is made.
        try await page.locator("[data-revise-form] input[name='title']").first.fill("Web tests title")
        // The editor opens on the code as the Raw view lays it out, the
        // stored one-line markup one element per line.
        let initial = try await page.evaluate(
          "(() => document.querySelector('.tei-page-edit textarea').value)()", as: String.self)
        #expect(initial == "<div>\n  <p>Old line</p>\n</div>", "The editor's initial text: \(initial)")
        _ = try await page.evaluate(
          """
          (() => {
            const area = document.querySelector('.tei-page-edit textarea')
            area.value = area.value.replace('Old line', 'New line')
            area.dispatchEvent(new Event('input', { bubbles: true }))
            return true
          })()
          """, as: Bool.self)
        try await expect(page.locator(".testament-diff[data-edited='true']")).toHaveCount(1)
        // Both sides laid out alike, the source diff marks the one line
        // that changed, not the stored line against the whole layout.
        let code = page.locator(".testament-diff[data-edited='true'] .diff-view[data-diff-mode='code']")
        try await expect(code.locator(".diff-row[data-diff-line='removed']")).toHaveCount(1)
        try await expect(code.locator(".diff-row[data-diff-line='inserted']")).toHaveCount(1)
        try await expect(code.locator(".diff-row[data-diff-line='unchanged']")).toHaveCount(2)
        // Its own process's block: the Arbitration pair stands first.
        let prompts = page.locator(".prompt-revision-fields-view .prompt-revision-fields-process[data-process='\(slot)']")
        // The process in its accordion, each prompt in its own inside,
        // closed as on the object's page.
        try await expect(prompts.locator("#prompt-revision-process-\(slot)")).toHaveAttribute("data-expanded", "false")
        try await prompts.locator("#prompt-revision-process-\(slot) .accordion-summary").first.click()
        try await prompts.locator("#prompt-revision-system-accordion-\(slot) .accordion-summary").first.click()
        try await expect(prompts.locator("#prompt-revision-system-accordion-\(slot)"))
          .toHaveAttribute("data-open-finished", "true")
        // Appended where it is typed: the prompt runs past 60KB, which
        // Chrome's insertText (what `fill` sends) takes over 30s to type.
        _ = try await page.evaluate(
          """
          (() => {
            const area = document.querySelector("textarea[name='prompt-system-\(slot)']")
            area.value = area.value + '\\nWeb tests suggestion.'
            area.dispatchEvent(new Event('input', { bubbles: true }))
            return true
          })()
          """, as: Bool.self)
        let line = prompts.locator(".field-diff-diff").first
        try await expect(line).toBeVisible()
        try await expect(line).toContainText("Web tests suggestion.")
        try await page.locator(".revision-form button[type='submit']").click()
        // Back on the madrigal, at the suggestion's locution.
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("the madrigal at its locution", where: Self.atLocution(commit.madrigalPath))
        let stored = try TestAdmin.query(
          """
          SELECT count(*) || ' ' || bool_and(content_json IS NOT NULL)::text || ' '
            || max(json_array_length(pages_json::json)) || ' ' || max(prompt_slot)
          FROM revisions WHERE requested_by_user_id = '\(user)'
          """)
        #expect(stored == "1 true 1 \(slot)", "One row holding all three: \(stored)")
      }
      let id = try TestAdmin.query("SELECT id FROM revisions WHERE requested_by_user_id = '\(user)'").uppercased()
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        // The thread says who suggested it, its size and what it changed,
        // each linked, and offers an admin its verdicts.
        // The suggester's avatar on their event (the key alone: the
        // src is what the page owes it).
        _ = try TestAdmin.query("UPDATE users SET avatar_key = 'avatars/\(user)/webtest.webp' WHERE id = '\(user)'")
        try await page.openHydrated(commit.madrigalPath)
        _ = try TestAdmin.query("UPDATE users SET avatar_key = NULL WHERE id = '\(user)'")
        let event = page.locator("#revision-\(id)")
        try await expect(event.locator(".avatar-view img").first)
          .toHaveAttribute("src", "/avatars/\(user)?v=webtest")
        try await expect(event).toContainText("suggested revision")
        try await expect(event.locator(".locution-thread-event-added")).toBeVisible()
        try await expect(event.locator(".locution-thread-event-changed a").first).toBeVisible()
        try await expect(event.locator("form[action$='/accept'] button")).toHaveCount(1)
        try await expect(event.locator("form[action$='/reject'] button")).toHaveCount(1)
        try await Self.expectChangedLinksLand(page, revision: id, on: "\(commit.madrigalPath)/revisions/\(id)")

        // Its page draws each diff where it is made: the record's tree,
        // the markup under its resemblance, the prompts.
        try await page.openHydrated("\(commit.madrigalPath)/revisions/\(id)")
        try await expect(page.locator(".testament-tree-diff-view")).toHaveCount(1)
        // Under no heading of its own: the source diff, both sides laid out.
        try await expect(page.getByText("Markup of resemblance 1")).toHaveCount(0)
        let pageDiff = page.locator(".testament-diff[data-edited='true'] .diff-view[data-diff-mode='code']").first
        try await expect(pageDiff).toBeAttached()
        // The page's diff is code against code, under Raw alone (user,
        // 2026-10-10): hidden with the rendering, shown with the markup,
        // and no rendered diff at all.
        try await expect(page.locator(".testament-diff .diff-view[data-diff-mode='rendered']")).toHaveCount(0)
        try await expect(pageDiff).toBeHidden()
        try await page.locator(".artifact-raw-toggle button").first.click()
        try await expect(pageDiff).toBeVisible()
        try await page.locator(".artifact-raw-toggle button").first.click()
        try await expect(pageDiff).toBeHidden()
        // The changed page's markup pane alone wears the ring (user,
        // 2026-10-09): never the whole card, the resemblance pane or the pager's
        // number; the diff under it stands unboxed, as a changed field's
        // Diff line does.
        let unringed = try await page.evaluate(
          """
          (() => {
            const slot = document.querySelector(".testament-diff[data-edited='true']")
            if (!slot) return 'no diff'
            const boxed = [slot, ...slot.querySelectorAll('.resemblance-diff-view')].filter((el) => {
              const style = getComputedStyle(el)
              return style.borderTopStyle !== 'none' || style.outlineStyle !== 'none'
            })
            const viewer = document.querySelector('.artifact-view')
            const markup = viewer.querySelector('.artifact-markup')
            const pager = viewer.querySelector('.artifact-page-nav input')
            if (markup.dataset.diffState !== 'changed') return `markup ${markup.dataset.diffState}`
            if (viewer.dataset.diffState || (pager && pager.dataset.diffState)) return 'card or pager ringed'
            if (getComputedStyle(markup).outlineStyle === 'none') return 'markup unringed'
            return boxed.length === 0 ? 'ok' : `boxed ${boxed.length}`
          })()
          """, as: String.self)
        #expect(unringed == "ok", "The change ring is not on the markup pane alone: \(unringed)")
        // The ring on all four sides of the pane, border and outline in the
        // state's color, both inside the pane's own box (the outline just
        // inside the border), the pane itself without padding or inset,
        // flush with the viewer that clips it; the TEI view 1px inside it,
        // so the outline stays clear, the text's 16 inset its rendered
        // layer's (user, 2026-10-10). With the resemblance
        // put away and shown alike.
        let ring = """
          (() => {
            const probe = document.createElement('span'); document.body.append(probe)
            probe.style.borderColor = 'var(--border-color-orange)'
            const orange = getComputedStyle(probe).borderTopColor; probe.remove()
            const card = document.querySelector('.artifact-view')
            const pane = card.querySelector('.artifact-markup')
            const style = getComputedStyle(pane)
            for (const side of ['Top', 'Right', 'Bottom', 'Left']) {
              if (style['border' + side + 'Style'] !== 'solid') return side + ' border ' + style['border' + side + 'Style']
              if (style['border' + side + 'Color'] !== orange) return side + ' border ' + style['border' + side + 'Color']
              if (style['padding' + side] !== '0px') return side + ' padding ' + style['padding' + side]
            }
            if (style.outlineStyle !== 'solid' || style.outlineColor !== orange) return 'outline ' + style.outlineStyle + ' ' + style.outlineColor
            if (style.outlineWidth !== '1px' || style.outlineOffset !== '-2px') return 'outline ' + style.outlineWidth + ' at ' + style.outlineOffset
            const viewer = card.querySelector('.artifact-viewer-container')
            const a = viewer.getBoundingClientRect(), b = pane.getBoundingClientRect()
            const flush = (x, y) => Math.abs(x - y) < 1
            if (!flush(a.left + viewer.clientLeft, b.left) || !flush(a.top + viewer.clientTop, b.top) || !flush(a.bottom - viewer.clientTop, b.bottom)) return 'inset'
            if (card.dataset.canvasShown === 'false' && !flush(a.right - viewer.clientLeft, b.right)) return 'inset at the end'
            const view = pane.querySelector('.tei-view')
            const inner = getComputedStyle(view)
            if (inner.paddingLeft !== '1px' || inner.paddingTop !== '1px') return 'view inset ' + inner.padding
            const text = getComputedStyle(view.querySelector("[data-layer='rendering']"))
            if (text.paddingLeft !== '16px' || text.paddingTop !== '16px') return 'text inset ' + text.padding
            if (!flush(view.getBoundingClientRect().left, b.left + 1)) return 'view ' + (view.getBoundingClientRect().left - b.left)
            return 'ok ' + card.dataset.canvasShown
          })()
          """
        #expect(try await page.evaluate(ring, as: String.self) == "ok false", "Resemblance put away")
        try await page.locator(".artifact-canvas-toggle button").first.click()
        try await expect(page.locator(".artifact-view")).toHaveAttribute("data-canvas-shown", "true")
        #expect(try await page.evaluate(ring, as: String.self) == "ok true", "Resemblance shown")
        try await page.locator(".artifact-canvas-toggle button").first.click()
        try await expect(page.locator(".artifact-view")).toHaveAttribute("data-canvas-shown", "false")
        // The prompts as an object's read, the one changed open on its diff,
        // the other processes closed.
        try await expect(page.locator(".prompt-change-view .diff-view").first).toBeVisible()
        try await expect(page.locator("#prompt-change-process-\(slot)")).toHaveAttribute("data-expanded", "true")
        try await expect(page.locator("#prompt-change-process-bibliographic_arbitration")).toHaveAttribute("data-expanded", "false")
        try await expect(page.locator("#prompt-change-autocompaction-\(slot)")).toHaveAttribute("data-expanded", "false")
        try await expect(page.getByText("Web tests suggestion.").first).toBeAttached()
        try await page.expectNoHorizontalOverflow()
        // Its verdicts here too, posting to the thread's routes. No
        // Locution row in its Pedigree: a locution is an event in a thread,
        // not an object.
        try await expect(page.locator("form#revision-accept[action$='/revisions/\(id)/accept']")).toHaveCount(1)
        try await expect(page.locator(".pedigree-view").getByText("Locution", exact: true)).toHaveCount(0)

        // Accepted from the thread, back at its locution.
        try await page.openHydrated(commit.madrigalPath)
        try await expect(page.locator(".prompt-previews-slot"), timeout: .seconds(20))
          .toHaveAttribute("aria-busy", "false")
        // The madrigal's Evidence roster marks explication (user,
        // 2026-10-09): a first reading's pages green discs, markup added;
        // never a Computorium status.
        let roster = page.locator("#madrigal-resemblances")
        try await expect(roster.locator(".roster-status[data-mark='disc'][data-tone='green']").first).toBeAttached()
        try await expect(roster.locator(".roster-status[data-status]")).toHaveCount(0)
        try await page.locator("#revision-\(id) form[action$='/accept'] button").click()
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("the madrigal at its locution", where: Self.atLocution(commit.madrigalPath))
        try await expect(page.locator("#revision-\(id)-verdict-1")).toContainText("accepted revision")

        // The madrigal's Revisions list reads it, linking its own page.
        try await page.openHydrated("\(commit.madrigalPath)/revisions")
        try await expect(page.locator("a[href$='/revisions/\(id)']")).toHaveCount(1)
        try await expect(page.locator("form[action$='/accept'], form[action$='/reject']")).toHaveCount(0)
      }
      let document = try TestAdmin.query(
        "SELECT proposed_content_json::json ->> 'teiXml' FROM bibliographic_madrigals WHERE id = '\(commit.madrigalID)'")
      #expect(document.contains("New line") && document.contains("Kept line"), "Accepted, the markup is the madrigal's: \(document)")
      let title = try TestAdmin.query(
        "SELECT metadata_json::json ->> 'title' FROM bibliographic_madrigals WHERE id = '\(commit.madrigalID)'")
      #expect(title == "Web tests title", "and its fields: \(title)")
      let status = try TestAdmin.query(
        "SELECT status || ' ' || (prompt_vignette_id IS NULL)::text FROM revisions WHERE id = '\(id)'")
      #expect(status == "accepted true", "Accepted whole, its prompts not yet in force: \(status)")
      let still = try TestAdmin.query("SELECT vignette_id FROM active_prompt_vignettes WHERE slot = '\(slot)'")
      #expect(still == inForce, "Accepting puts no prompt in force")
    } catch {
      remove()
      try await admin.remove()
      try await contributor.remove(after: error)
    }
    remove()
    try await admin.remove()
    try await contributor.remove()
  }

  @Test(arguments: [BrowserEngine.chrome])
  func autocompactionPairIsNestedRevisableAndMergedOnTheObject(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let user = try contributor.column("id")
    let work = try ScratchCommit(owner: contributor)
    let parent = "bibliographic_arbitration"
    let slot = parent + "_autocompaction"
    let active = try TestAdmin.query("SELECT vignette_id FROM active_prompt_vignettes WHERE slot = '\(slot)'")
    func remove() {
      _ = try? TestAdmin.query("DELETE FROM revisions WHERE requested_by_user_id = '\(user)'")
      work.remove()
    }
    do {
      _ = try TestAdmin.query("""
        UPDATE bibliographic_madrigals SET metadata_json =
          (metadata_json::jsonb || '{"title":"Web tests autocompaction","provider":"folger_shakespeare_library"}'::jsonb)::text
        WHERE id = '\(work.madrigalID)'
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(work.madrigalPath)/revise")
        let auto = page.locator("#prompt-revision-autocompaction-\(parent)")
        try await expect(auto).toHaveAttribute("data-expanded", "false")
        try await expect(auto.locator(".accordion-details[data-expanded='false']")).toHaveCount(2)
        try await page.locator("#prompt-revision-process-\(parent) .accordion-summary").first.click()
        try await auto.locator(".accordion-summary").first.click()
        for (part, suffix) in [("system", "Web tests summarizer system."), ("task", "Web tests summarizer task.")] {
          try await auto.locator("#prompt-revision-\(part)-accordion-\(slot) .accordion-summary").click()
          try await expect(auto.locator("#prompt-revision-\(part)-accordion-\(slot)"))
            .toHaveAttribute("data-open-finished", "true")
          _ = try await page.evaluate(
            """
            (() => {
              const area = document.querySelector("textarea[name='prompt-\(part)-\(slot)']")
              area.value += '\\n\(suffix)'
              area.dispatchEvent(new Event('input', { bubbles: true }))
              return true
            })()
            """, as: Bool.self)
        }
        try await page.locator(".revision-form button[type='submit']").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the object at its revision", where: Self.atLocution(work.madrigalPath))
        let changed = page.locator(".locution-thread-event-changed")
        try await expect(changed).toContainText("Autocompaction System Prompt")
        try await expect(changed).toContainText("Autocompaction Task Prompt Template")
      }
      let id = try TestAdmin.query("SELECT id FROM revisions WHERE requested_by_user_id = '\(user)'").uppercased()
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated("\(work.madrigalPath)/revisions/\(id)")
        // Its page's Prompts as an object's: every process, its pairs
        // nested; the changed autocompaction pair open on its diffs, its
        // process with it, the rest closed (user, 2026-10-10).
        try await expect(page.locator(".prompt-change-heading")).toHaveText("Prompts")
        try await expect(page.locator("#prompt-change-process-\(parent)")).toHaveAttribute("data-expanded", "true")
        try await expect(page.locator("#prompt-change-autocompaction-\(parent)")).toHaveAttribute("data-expanded", "true")
        try await expect(page.locator("#prompt-change-system")).toHaveAttribute("data-expanded", "true")
        try await expect(page.locator("#prompt-change-\(parent)-system")).toHaveAttribute("data-expanded", "false")
        try await expect(page.locator("#prompt-change-process-bibliographic_explication")).toHaveAttribute("data-expanded", "false")
        try await expect(page.locator(".prompt-change-view .diff-view")).toHaveCount(2)
        try await page.locator("button[form='revision-accept']").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the object at its revision", where: Self.atLocution(work.madrigalPath))
        let auto = page.locator("#prompt-preview-autocompaction-arbitration")
        try await expect(auto, timeout: .seconds(20)).toHaveCount(1)
        try await expect(auto.locator(".prompt-text-source").nth(0)).toContainText("Web tests summarizer system.")
        try await expect(auto.locator(".prompt-text-source").nth(1)).toContainText("Web tests summarizer task.")
        try await page.openHydrated("\(work.madrigalPath)/revise")
        try await expect(page.locator("textarea[name='prompt-system-\(slot)']")).toContainText("Web tests summarizer system.")
        try await expect(page.locator("textarea[name='prompt-task-\(slot)']")).toContainText("Web tests summarizer task.")
      }
      let still = try TestAdmin.query("SELECT vignette_id FROM active_prompt_vignettes WHERE slot = '\(slot)'")
      #expect(still == active, "Acceptance merges the working copy; activation waits for Commit")
    } catch {
      remove()
      try await admin.remove()
      try await contributor.remove(after: error)
    }
    remove()
    try await admin.remove()
    try await contributor.remove()
  }

  /// A long text's diff box follows the caret (user, 2026-10-08): redrawn
  /// on every keystroke, it scrolls itself—never the page—so the row of the
  /// line being edited is in view. The Revise page has the record rule over
  /// its work, Verbose on it, as the object's page does. A fragment fetched
  /// into a page names its stylesheets in its `Link` header.
  @Test(arguments: [BrowserEngine.chrome])
  func passageDiffFollowsTheCaret(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor)
    let slot = "bibliographic_explication"
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(commit.madrigalPath)/revise")
        try await expect(page.locator(".apparatus-rule-view + .revise-bibliographic-object")).toHaveCount(1)
        try await expect(page.locator(".apparatus-rule-view .verbose-toggle-button-view, .apparatus-rule-view button").first)
          .toBeVisible()

        // Its own process's block: the Arbitration pair stands first.
        let prompts = page.locator(".prompt-revision-fields-view .prompt-revision-fields-process[data-process='\(slot)']")
        try await prompts.locator("#prompt-revision-process-\(slot) .accordion-summary").first.click()
        try await prompts.locator("#prompt-revision-system-accordion-\(slot) .accordion-summary").first.click()
        let result = try await page.evaluate(
          """
          (() => {
            const area = document.querySelector("textarea[name='prompt-system-\(slot)']")
            const lines = Array.from({ length: 60 }, (_, i) => 'Web tests line ' + (i + 1)).join('\\n')
            area.value = area.value + '\\n' + lines
            area.focus({ preventScroll: true })
            area.setSelectionRange(area.value.length, area.value.length)
            const pageY = window.scrollY
            area.dispatchEvent(new Event('input', { bubbles: true }))
            const box = area.closest('[data-field-diff-view]').querySelector('[data-diff-annotation] .diff-box')
            const rows = box.querySelectorAll('.diff-row')
            const last = rows[rows.length - 1].getBoundingClientRect()
            const frame = box.getBoundingClientRect()
            return [box.scrollTop > 0, last.top >= frame.top && last.bottom <= frame.bottom + 1,
              window.scrollY === pageY].join(' ')
          })()
          """, as: String.self)
        #expect(result == "true true true", "scrolled, the caret's row in view, the page still: \(result)")

        // A fragment—the record's prompts, fetched into an object's page—
        // names the sheets its render registered.
        let link = try await page.evaluate(
          """
          (async () => {
            const response = await fetch('\(commit.madrigalPath)', { headers: { Accept: 'text/html' } })
            const html = await response.text()
            const source = new DOMParser().parseFromString(html, 'text/html')
              .querySelector('.prompt-previews-view')?.dataset.sourceUrl
            if (!source) return 'no prompts section'
            const fragment = await fetch(source, { headers: { Accept: 'text/html' } })
            return fragment.headers.get('Link') ?? 'none'
          })()
          """, as: String.self)
        #expect(link.contains("rel=stylesheet"), "Link: \(link)")
      }
    } catch {
      commit.remove()
      try await contributor.remove(after: error)
    }
    commit.remove()
    try await contributor.remove()
  }

  /// A code editor's text replaced whole, as typed: selected, then the
  /// markup inserted over it; the hidden textarea follows.
  static func replaceCode(_ code: Locator, with markup: String, page: Page) async throws {
    _ = try await code.evaluate(
      "e => { e.focus(); const r = document.createRange(); r.selectNodeContents(e); getSelection().removeAllRanges(); getSelection().addRange(r); return true }")
    try await page.keyboard.insertText(markup)
  }

  /// A lexicographic madrigal's Revise page offers what a bibliographic
  /// one's does, in parallel (user, 2026-10-07): its record's identity and
  /// each sentiment's label and usage, in its Sentiments tree. A
  /// change is one revision of its fields, in the madrigal's thread, that
  /// an admin accepts there—written into the madrigal—and reverts.
  /// An epilogue's definition in the record's language is revised the same
  /// way, the session's confidence cleared once a person changed it.
  @Test(arguments: [BrowserEngine.chrome])
  func lexicographicFieldsAreRevisedAsBibliographicOnesAre(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let user = try contributor.column("id")
    let word = try ScratchWord(owner: contributor, submitted: true)
    let epilogue = UUID().uuidString.lowercased()
    func remove() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM revisions WHERE requested_by_user_id = '\(user)';
        DELETE FROM lexicographic_epilogues WHERE id = '\(epilogue)';
        COMMIT;
        """)
      word.remove()
    }
    func content() throws -> String {
      try TestAdmin.query(
        "SELECT proposed_content_json FROM lexicographic_madrigals WHERE id = '\(word.madrigalID.lowercased())'")
    }
    do {
      _ = try TestAdmin.query(
        """
        INSERT INTO lexicographic_epilogues (id, lexico_record_id, lexico_record_version_id, sentiment_id, tei,
            target, status, submitted_by_user_id, summary, definition_translation_json)
          VALUES ('\(epilogue)', '\(word.recordID.lowercased())', '\(word.versionID.lowercased())', 's-1-1',
            '<sense><def>A leaf sense.</def></sense>', 'definition', 'committed', (SELECT id FROM users WHERE username = 'gnorium'), 'Web tests.',
            '{"languageCode":"fra","tei":"<def xml:lang=\\"fr\\">Un sens feuille.</def>","confidence":"clear","reason":"Web tests."}');
        """)
      let madrigalPath = "/mission-control/madrigals/lexicographic/\(word.madrigalID)"
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(madrigalPath)/revise")
        // Every sentiment's fields, under its number.
        try await expect(page.locator("textarea[name='sentiment-0-label']")).toHaveValue("A branch sense.")
        try await expect(page.locator("textarea[name='sentiment-1-label']")).toHaveValue("A leaf sense.")
        // One field a usage axis, as Submit Sentiment draws them (user, 2026-10-09).
        for kind in ["grammar", "register", "domain", "region", "currency"] {
          try await expect(page.locator("input[name='sentiment-1-\(kind)']")).toBeAttached()
        }
        try await expect(page.locator("[data-item-list='sentiment-1-usage']")).toHaveCount(0)
        try await page.expectNoHorizontalOverflow()
        let leaf = page.locator("textarea[name='sentiment-1-label']")
        try await leaf.fill("A leaf sense, as a person reads it.")
        // Its diff is drawn as it is made, as a bibliographic field's is.
        try await expect(page.locator("[data-diff-annotation][data-visible='true']").first).toBeAttached()
        // Its definition is its TEI (user, 2026-10-10), edited as a page's
        // markup is: rendered by default, the XML under Raw.
        let editor = page.locator(".sense-editor-view:has(textarea[name='sentiment-1-definition'])")
        try await expect(editor.locator(".sense-editor-definition")).toHaveText("A leaf sense.")
        try await expect(editor.locator(".sense-editor-raw")).toBeHidden()
        try await editor.locator(".sense-editor-raw-toggle").click()
        try await expect(editor.locator(".sense-editor-raw .code-code")).toBeVisible()
        try await Self.replaceCode(editor.locator(".sense-editor-raw .code-code"), with: "<sense><def>A leaf sense, defined.</def></sense>", page: page)
        let posted = try await page.evaluate(
          "(() => document.querySelector(\"textarea[name='sentiment-1-definition']\").value)()", as: String.self)
        #expect(posted == "<sense><def>A leaf sense, defined.</def></sense>", "The form posts the XML typed: \(posted)")
        // And one of its usage fields: a Register.
        let register = page.locator(".dropdown-view:has(input[name='sentiment-1-register'])")
        try await register.locator(".dropdown-trigger").click()
        try await register.locator(".dropdown-option[data-value='poetic']").click()
        try await page.keyboard.press("Escape")
        try await expect(page.locator("input[name='sentiment-1-register']")).toHaveValue("poetic")
        try await page.locator(".revision-form button[type='submit']").click()
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("the madrigal at its locution", where: Self.atLocution(madrigalPath))
      }
      let id = try TestAdmin.query(
        "SELECT id FROM revisions WHERE requested_by_user_id = '\(user)' AND revisable_type = 'lexicographicMadrigal' AND content_json IS NOT NULL AND status = 'pending'"
      ).uppercased()
      #expect(!id.isEmpty, "A revision of the madrigal is filed")
      #expect(try content().contains("A leaf sense.\""), "The madrigal stands until it is accepted")

      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        let revisionPath = "\(madrigalPath)/revisions/\(id)"
        try await page.openHydrated(revisionPath)
        try await expect(page.getByText("Sentiment 1.1").first).toBeAttached()
        try await expect(page.locator(".diff-view").first).toBeAttached()
        try await expect(page.locator("form#revision-accept")).toHaveCount(1)
        try await expect(page.locator(".pedigree-view").getByText("Locution", exact: true)).toHaveCount(0)

        // Its thread, as a bibliographic madrigal's: what it changed,
        // linked, and its verdicts.
        try await page.openHydrated(madrigalPath)
        let event = page.locator("#revision-\(id)")
        // Its label and its one usage field, each its own item by
        // its form's label, each linked to its place on the page.
        let changed = event.locator(".locution-thread-event-changed")
        try await expect(changed).toHaveText("Changed Sentiment 1.1 Label, Sentiment 1.1 Definition, and Sentiment 1.1 Register")
        try await expect(changed.locator("a")).toHaveCount(3)
        // Each on the revision's own page, at its field there (user, 2026-10-09).
        try await expect(changed.locator("a[href='\(revisionPath)#sentiment-1-label']"))
          .toHaveText("Sentiment 1.1 Label")
        try await expect(changed.locator("a[href='\(revisionPath)#sentiment-1-definition']"))
          .toHaveText("Sentiment 1.1 Definition")
        try await expect(changed.locator("a[href='\(revisionPath)#sentiment-1-register']"))
          .toHaveText("Sentiment 1.1 Register")
        try await Self.expectChangedLinksLand(page, revision: id, on: revisionPath)
        try await page.openHydrated(madrigalPath)
        try await expect(page.locator(".prompt-previews-slot"), timeout: .seconds(20))
          .toHaveAttribute("aria-busy", "false")
        try await page.expectNoErrors()
        try await event.locator("form[action$='/accept'] button").click()
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("the madrigal at its locution", where: Self.atLocution(madrigalPath))
        #expect(try content().contains("A leaf sense, as a person reads it."), "Accepted, it is written into the madrigal")
        #expect(try content().contains("<def>A leaf sense, defined.</def>"), "Its definition with it, as TEI")
        try await expect(page.locator("#revision-\(id)-verdict-1")).toContainText("accepted revision")
        try await page.locator("#revision-\(id)-verdict-1 form[action$='/revert'] button").click()
        // Every verdict stays an act of the thread (user, 2026-10-10): the
        // acceptance, then its revert, which nothing can be done about.
        try await expect(page.locator("#revision-\(id)-verdict-2"), timeout: .seconds(15)).toContainText("reverted revision")
        try await expect(page.locator("#revision-\(id)-verdict-1")).toContainText("accepted revision")
        // The revert undid the verdict: the revision is pending again, its
        // Accept and Reject on the suggestion, nothing on either act.
        try await expect(page.locator(
          "#revision-\(id)-verdict-1 form[action$='/revert'], #revision-\(id)-verdict-2 form[action$='/revert'], "
            + "#revision-\(id)-verdict-2 form[action$='/accept']")).toHaveCount(0)
        try await expect(page.locator("#revision-\(id) form[action$='/accept']")).toHaveCount(1)
        #expect(try TestAdmin.query("SELECT status || ' ' || (evaluated_at IS NULL)::text FROM revisions WHERE id = '\(id)'") == "pending true")
        #expect(!(try content().contains("as a person reads it")), "Reverted, it comes back out")
        #expect(try content().contains("<def>A leaf sense.</def>"), "The TEI's definition with it")
      }

      // An epilogue's definition in the record's language, the same way.
      let epiloguePath = "/mission-control/epilogues/lexicographic/\(epilogue)"
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(epiloguePath)/revise")
        // Its `<def xml:lang>`, edited the same way.
        let editor = page.locator(".sense-editor-view:has(textarea[name='definition'])")
        try await expect(editor.locator(".sense-editor-translation")).toHaveText("Un sens feuille.")
        try await expect(editor.locator(".sense-editor-translation")).toHaveAttribute("lang", "fr")
        try await editor.locator(".sense-editor-raw-toggle").click()
        try await Self.replaceCode(editor.locator(".sense-editor-raw .code-code"), with: "<def xml:lang=\"fr\">Un sens feuille, corrigé.</def>", page: page)
        try await page.locator(".revision-form button[type='submit']").click()
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("the epilogue at its locution", where: Self.atLocution(epiloguePath))
      }
      let epilogueRevision = try TestAdmin.query(
        "SELECT id FROM revisions WHERE requested_by_user_id = '\(user)' AND revisable_type = 'lexicographicEpilogue' AND content_json IS NOT NULL"
      ).uppercased()
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated(epiloguePath)
        let event = page.locator("#revision-\(epilogueRevision)")
        try await expect(event.locator(".locution-thread-event-changed"))
          .toHaveText("Changed Sentiment 1.1 Definition")
        // Its revision's page, named as the server names it (ids upper case).
        let epilogueRevisionPath =
          "/mission-control/epilogues/lexicographic/\(epilogue.uppercased())/revisions/\(epilogueRevision)"
        try await expect(
          event.locator(".locution-thread-event-changed a[href='\(epilogueRevisionPath)#definition']")
        ).toHaveCount(1)
        try await Self.expectChangedLinksLand(page, revision: epilogueRevision, on: epilogueRevisionPath)
        try await page.openHydrated(epiloguePath)
        try await expect(page.locator(".prompt-previews-slot"), timeout: .seconds(20))
          .toHaveAttribute("aria-busy", "false")
        try await event.locator("form[action$='/accept'] button").click()
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("the epilogue at its locution", where: Self.atLocution(epiloguePath))
        let stored = try TestAdmin.query(
          "SELECT definition_translation_json FROM lexicographic_epilogues WHERE id = '\(epilogue)'")
        #expect(stored.contains("Un sens feuille, corrigé."), "stored: \(stored)")
        #expect(stored.contains("\"confidence\":\"\""), "A person's definition has no confidence: \(stored)")
        // The epilogue's page reads it, its confidence "—".
        try await page.openHydrated(epiloguePath)
        try await expect(page.getByText("Un sens feuille, corrigé.").first).toBeAttached()
        // "See associated revisions" opens the epilogue's own revisions
        // page: revisions are read per object (user, 2026-10-09).
        try await expect(
          page.locator("a[href^='/mission-control/epilogues/lexicographic/'][href$='/revisions']")
        ).toHaveCount(1)
        try await expect(page.locator("a[href*='/mission-control/revisions/']")).toHaveCount(0)

        // Its revisions page reads it, each row linking its own page.
        try await page.openHydrated("\(epiloguePath)/revisions")
        try await expect(page.getByText("Revisions suggested to this epilogue.")).toBeAttached()
        try await expect(page.locator("a[href$='/revisions/\(epilogueRevision)']").first).toBeAttached()
        try await expect(page.locator("form[action$='/accept'], form[action$='/reject']")).toHaveCount(0)
      }
    } catch {
      remove()
      try await admin.remove()
      try await contributor.remove(after: error)
    }
    remove()
    try await admin.remove()
    try await contributor.remove()
  }

  /// An accepted revision a later accepted one built on cannot be reverted
  /// alone: its Revert is disabled, in the thread and on its page, the one
  /// refusal sentence its tooltip—shown on hover, focus and a plain tap
  /// (user, 2026-10-10). The later one's Revert stays live.
  @Test(arguments: [BrowserEngine.chrome])
  func aRevertALaterChangeBuiltOnIsDisabledWithItsReason(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchCommit(owner: admin)
    let madrigalPath = work.madrigalPath
    let user = try admin.column("id")
    let a = UUID().uuidString.uppercased()
    let b = UUID().uuidString.uppercased()
    let refused = "A later accepted revision changed the same lines, so revert that one first."
    func remove() {
      _ = try? TestAdmin.query("DELETE FROM revisions WHERE id IN ('\(a)', '\(b)')")
      work.remove()
    }
    do {
      let slot = "bibliographic_explication"
      func sql(_ text: String) -> String { text.replacingOccurrences(of: "'", with: "''") }
      let system = try TestAdmin.query(
        "SELECT system_prompt FROM prompt_vignettes WHERE id = (SELECT vignette_id FROM active_prompt_vignettes WHERE slot = '\(slot)')")
      let task = try TestAdmin.query(
        "SELECT task_prompt FROM prompt_vignettes WHERE id = (SELECT vignette_id FROM active_prompt_vignettes WHERE slot = '\(slot)')")
      let afterA = system + "\nWeb tests A."
      let afterB = system + "\nWeb tests A, then B."
      for (id, previous, proposed, offset) in [(a, system, afterA, 2), (b, afterA, afterB, 1)] {
        _ = try TestAdmin.query("""
          INSERT INTO revisions (id, revisable_type, revisable_id, prompt_slot, previous_system_prompt, system_prompt,
            previous_task_prompt, task_prompt, status, requested_by_user_id, created_at)
          VALUES ('\(id)', 'bibliographicMadrigal', '\(work.madrigalID)', '\(slot)', '\(sql(previous))', '\(sql(proposed))',
            '\(sql(task))', '\(sql(task))', 'pending', '\(user)', now() - interval '\(offset) minute')
          """)
      }
      let trigger = "#revision-\(a)-verdict-1 form[action$='/revert'] .tooltip-view"
      // The bubble, portaled to the body's end once hydrated, shown.
      let bubble = ".tooltip-view[data-visible='true'] .tooltip-content"
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated(madrigalPath)
        for id in [a, b] {
          try await page.locator("#revision-\(id) form[action$='/accept'] button").click()
          try await expect(page, timeout: .seconds(15)).toHaveURL("the madrigal at its locution", where: Self.atLocution(madrigalPath))
          try await expect(page.locator("#revision-\(id)-verdict-1")).toContainText("accepted revision")
        }
        try await expect(page.locator("#revision-\(a)-verdict-1 form[action$='/revert'] button")).toBeDisabled()
        try await expect(page.locator("#revision-\(b)-verdict-1 form[action$='/revert'] button")).toBeEnabled()
        try await expect(page.locator(trigger)).toHaveAttribute("data-disabled-trigger", "true")
        // Hover shows the reason; focus does too.
        try await page.locator(trigger).hover()
        try await expect(page.locator(bubble).filter(hasText: refused)).toBeVisible()
        // Its own page: the header's Revert disabled, the reason its tooltip.
        try await page.openHydrated("\(madrigalPath)/revisions/\(a)")
        try await expect(page.locator("button[form='revision-revert']")).toBeDisabled()
        let header = ".mission-control-object-header-view .tooltip-view[data-disabled-trigger='true']"
        try await expect(page.locator(header)).toHaveCount(1)
        try await page.locator(header).focus()
        try await expect(page.locator(bubble).filter(hasText: refused)).toBeVisible()
        try await page.openHydrated("\(madrigalPath)/revisions/\(b)")
        try await expect(page.locator("button[form='revision-revert']")).toBeEnabled()
        try await page.expectNoErrors()
      }
      // At 375 on touch: a plain tap opens the reason and pins it; the next
      // tap closes it (user, 2026-10-10).
      try await withPage(engine, gnorium, viewport: Layout.phone.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(madrigalPath)
        try await expect(page.locator(trigger)).toHaveAttribute("data-disabled-trigger", "true")
        try await page.locator(trigger).tap()
        try await expect(page.locator(bubble).filter(hasText: refused)).toBeVisible()
        try await page.locator(trigger).tap()
        try await expect(page.locator(bubble).filter(hasText: refused)).toHaveCount(0)
        try await page.expectNoErrors()
      }
    } catch {
      remove()
      try await admin.remove(after: error)
    }
    remove()
    try await admin.remove()
  }

  /// Every item of a revision's "Changed" line (on the page open now) links
  /// to its revision's own page, where an element holds its anchor; a
  /// resemblance's turns the reader there instead (user, 2026-10-09).
  static func expectChangedLinksLand(_ page: Page, revision id: String, on revisionPath: String) async throws {
    let hrefs = try await page.evaluate(
      "JSON.stringify([...document.querySelectorAll('#revision-\(id) .locution-thread-event-changed a')].map(a => a.getAttribute('href')))"
    ).string ?? "[]"
    let links = try JSONDecoder().decode([String].self, from: Data(hrefs.utf8))
    #expect(!links.isEmpty, "a Changed line")
    for link in links {
      let parts = link.split(separator: "#", maxSplits: 1).map(String.init)
      #expect(parts.count == 2 && parts[0].lowercased() == revisionPath.lowercased(), "\(link) is on \(revisionPath)")
      guard parts.count == 2, !parts[1].hasPrefix("resemblance-") else { continue }
      try await page.openHydrated(parts[0])
      try await expect(page.locator("[id='\(parts[1])']")).toBeAttached()
    }
  }
}
