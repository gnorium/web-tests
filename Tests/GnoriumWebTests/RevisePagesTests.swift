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
        // The process's page is read-only, its nocturnes its associated ones.
        let processURL = "/mission-control/prompts/bibliographic/explication"
        try await page.openHydrated(processURL)
        try await expect(page.locator("a[href='\(processURL)/revise']")).toHaveCount(0)
        try await expect(page.locator(".associated-links-view a")).toHaveText("nocturnes")

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
        // The editor opens on the stored text as it is (a document is
        // stored formatted; this one was written before, on one line),
        // headed as every view of a page is (user, 2026-10-14): this
        // document declares no renditions, so no header.
        let initial = try await page.evaluate(
          "(() => document.querySelector('.tei-page-edit textarea').value)()", as: String.self)
        #expect(
          initial == "<TEI xmlns=\"http://www.tei-c.org/ns/1.0\">\n<text><body>\n<div><p>Old line</p></div>\n</body></text>\n</TEI>",
          "The editor's initial text: \(initial)")
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
        // Headed both sides: the page's lines and the document's four.
        try await expect(code.locator(".diff-row[data-diff-line='unchanged']")).toHaveCount(6)
        if let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"] {
          _ = try await page.evaluate(
            "(() => { document.querySelector(\".testament-diff[data-edited='true'] .diff-view\").scrollIntoView({block: 'center'}); return 1 })()",
            as: Int.self)
          try await page.screenshot(to: URL(fileURLWithPath: directory).appendingPathComponent("code-diff.png"))
        }
        // Its own process's block: the Arbitration pair stands first.
        let prompts = page.locator(".prompt-revision-fields-view .prompt-revision-fields-process[data-process='\(slot)']")
        // The process in its accordion, each prompt in its own inside,
        // closed as on the object's page.
        try await expect(prompts.locator("#prompt-revision-process-\(slot)")).toHaveAttribute("data-expanded", "false")
        try await prompts.locator("#prompt-revision-process-\(slot) .accordion-summary").first.click()
        try await prompts.locator("#prompt-revision-system-accordion-\(slot) .accordion-summary").first.click()
        try await expect(prompts.locator("#prompt-revision-system-accordion-\(slot)"))
          .toHaveAttribute("data-open-finished", "true")
        // Shown as on the object's page (user, 2026-10-11): rendered, Raw
        // and the vignette linked; edited in raw mode only.
        let system = prompts.locator("#prompt-revision-system-accordion-\(slot) .prompt-text-view")
        try await expect(system).toHaveAttribute("data-raw", "false")
        try await expect(system.locator(".prompt-text-rendered")).toBeVisible()
        try await expect(system.locator("textarea")).toBeHidden()
        try await expect(system.locator(".prompt-text-vignette")).toHaveCount(1)
        try await system.locator(".prompt-text-markdown-toggle button").click()
        try await expect(system.locator("textarea")).toBeVisible()
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
        // Back to the rendering: it reads what the box now holds.
        try await system.locator(".prompt-text-markdown-toggle button").click()
        try await expect(system.locator(".prompt-text-rendered")).toContainText("Web tests suggestion.")
        try await page.locator(".revision-form button[type='submit']").click()
        // Back on the madrigal, at the suggestion's locution.
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("the madrigal at its locution", where: Self.atLocution(commit.madrigalPath))
        let stored = try TestAdmin.query(
          """
          SELECT count(*) || ' ' || bool_and(content_json IS NOT NULL)::text || ' '
            || max(json_array_length(pages_json::json)) || ' ' || max(prompt_changes_json::json -> 0 ->> 'slot')
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
        try await page.locator(".artifact-xml-toggle button").first.click()
        try await expect(pageDiff).toBeVisible()
        try await page.locator(".artifact-xml-toggle button").first.click()
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
            const frame = markup.closest('.artifact-markup-frame')
            if (!frame || getComputedStyle(frame, '::after').outlineStyle === 'none') return 'markup unringed'
            return boxed.length === 0 ? 'ok' : `boxed ${boxed.length}`
          })()
          """, as: String.self)
        #expect(unringed == "ok", "The change ring is not on the markup pane alone: \(unringed)")
        // The ring on all four sides of the pane, border and outline in the
        // state's color (a modification orange), the pane wearing the
        // border, its frame's overlay both, the outline just inside the
        // border, drawn over the scrollport so scrolled code cannot cover
        // it; the pane itself without padding or inset, flush with the
        // viewer that clips it; the TEI view 1px inside it, so the outline
        // stays clear, the text's 16 inset its rendered layer's (user,
        // 2026-10-10). With the resemblance put away and shown alike.
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
            const overlay = getComputedStyle(pane.closest('.artifact-markup-frame'), '::after')
            if (overlay.borderTopStyle !== 'solid' || overlay.borderTopColor !== orange) return 'overlay border ' + overlay.borderTopStyle + ' ' + overlay.borderTopColor
            if (overlay.outlineStyle !== 'solid' || overlay.outlineColor !== orange) return 'outline ' + overlay.outlineStyle + ' ' + overlay.outlineColor
            if (overlay.outlineWidth !== '1px' || overlay.outlineOffset !== '-2px') return 'outline ' + overlay.outlineWidth + ' at ' + overlay.outlineOffset
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
        // The prompts as an object's read, the one changed open in Raw, its
        // diff under the box as a field's is; the other processes closed.
        let changedPrompt = page.locator(".prompt-change-view .prompt-text-comparison:has(.prompt-text-diff)").first
        try await expect(changedPrompt.locator(".prompt-text-view")).toHaveAttribute("data-raw", "true")
        try await expect(changedPrompt.locator(".prompt-text-diff .diff-view")).toBeVisible()
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
        try await expect(page.locator("#revision-\(id)-verdict-1")).toContainText("as accepted")

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
        "SELECT status || ' ' || (prompt_changes_json::json -> 0 ->> 'vignetteID' IS NULL)::text FROM revisions WHERE id = '\(id)'")
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
        // Each part by its path, its steps apart by the breadcrumb's chevron,
        // the list joined as English joins it (user, 2026-10-14).
        let paths = try await changed.evaluate(
          "e => [...e.querySelectorAll('.locution-thread-path')].map(p => [...p.children].filter(c => !c.classList.contains('breadcrumb-separator-view')).map(c => c.textContent).join(' › ')).join(' | ')")
        #expect(
          paths.string == "Arbitration › Autocompaction › System Prompt | Arbitration › Autocompaction › Task Prompt Template",
          "\(paths)")
        let joined = try await changed.evaluate(
          "e => [...e.childNodes].filter(n => n.nodeType === 3).map(n => n.textContent).join('|')")
        #expect(joined.string == "Changed | and |.", "\(joined)")
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
        try await expect(page.locator("#prompt-change-\(parent)_autocompaction-system")).toHaveAttribute("data-expanded", "true")
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
        try await expect(prompts.locator("#prompt-revision-system-accordion-\(slot)"))
          .toHaveAttribute("data-open-finished", "true")
        try await prompts.locator("#prompt-revision-system-accordion-\(slot) .prompt-text-markdown-toggle button").first.click()
        try await expect(page.locator("textarea[name='prompt-system-\(slot)']")).toBeVisible()
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

        // Scrolled back to its top and clicked into (to select or read),
        // the diff stays where the reader put it: the editor's losing focus
        // redraws nothing, scrolls nothing, and moves no focus (user,
        // 2026-10-11).
        let box = page.locator("[data-field-diff-view]:has(textarea[name='prompt-system-\(slot)']) [data-diff-annotation] .diff-box")
        _ = try await box.evaluate(
          "el => { el.scrollTop = 0; el.querySelector('.diff-row').scrollIntoView({ block: 'center' }); el.scrollTop = 0; return true }")
        let before = try await page.evaluate("JSON.stringify([window.scrollY])", as: String.self)
        try await box.locator(".diff-row").first.click()
        let after = try await page.evaluate(
          """
          (() => { const box = document.querySelector("[data-field-diff-view]:has(textarea[name='prompt-system-\(slot)']) [data-diff-annotation] .diff-box")
            return JSON.stringify({ top: box.scrollTop, y: window.scrollY, active: document.activeElement?.tagName ?? '' }) })()
          """, as: String.self)
        #expect(after.contains("\"top\":0"), "the diff stayed at its top: \(after)")
        #expect(after.contains("\"y\":\(before.dropFirst().dropLast())"), "the page did not move: \(before) → \(after)")
        #expect(!after.contains("TEXTAREA"), "focus stayed off the editor: \(after)")

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
          VALUES ('\(epilogue)', '\(word.recordID.lowercased())', '\(word.versionID.lowercased())', '\(word.leaf)',
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
        try await editor.locator(".sense-editor-xml-toggle").click()
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
        try await expect(changed).toHaveText("Changed Sentiment 1.1 Label, Sentiment 1.1 Definition, and Sentiment 1.1 Register.")
        try await expect(changed.locator("a")).toHaveCount(3)
        // Each on the revision's own page, at its field there (user, 2026-10-09).
        try await expect(changed.locator("a[href='\(revisionPath)?source=code#sentiment-1-label']"))
          .toHaveText("Sentiment 1.1 Label")
        try await expect(changed.locator("a[href='\(revisionPath)?source=code#sentiment-1-definition']"))
          .toHaveText("Sentiment 1.1 Definition")
        try await expect(changed.locator("a[href='\(revisionPath)?source=code#sentiment-1-register']"))
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
        try await expect(page.locator("#revision-\(id)-verdict-1")).toContainText("as accepted")
        try await page.locator("#revision-\(id)-verdict-1 form[action$='/revert'] button").click()
        // Every verdict stays an act of the thread (user, 2026-10-10): the
        // acceptance, then its revert, which nothing can be done about.
        try await expect(page.locator("#revision-\(id)-verdict-2"), timeout: .seconds(15)).toContainText("as reverted")
        try await expect(page.locator("#revision-\(id)-verdict-1")).toContainText("as accepted")
        // One verb, the outcome colored; the act a later one acted on says so
        // under it, a link to that act (user, 2026-10-11).
        try await expect(page.locator("#revision-\(id)-verdict-1 .locution-thread-event-outcome[data-tone='green']")).toHaveText("accepted")
        let note = page.locator("#revision-\(id)-verdict-1 .locution-thread-event-note")
        try await expect(note).toContainText("Evaluated as reverted by")
        try await expect(note).toHaveAttribute("href", "#revision-\(id)-verdict-2")
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
        try await editor.locator(".sense-editor-xml-toggle").click()
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
          .toHaveText("Changed Sentiment 1.1 Definition.")
        // Its revision's page, named as the server names it (ids upper case).
        let epilogueRevisionPath =
          "/mission-control/epilogues/lexicographic/\(epilogue.uppercased())/revisions/\(epilogueRevision)"
        try await expect(
          event.locator(".locution-thread-event-changed a[href='\(epilogueRevisionPath)?source=code#definition']")
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
  /// alone: its Revert stays enabled, and pressing it shows the one
  /// refusal sentence in a warning above it, as a form shows an action it
  /// refuses—in place on the client, and by the server's answer (the page
  /// at the warning) without it (user, 2026-10-11). The later one's Revert
  /// is given.
  @Test(arguments: [BrowserEngine.chrome])
  func aRevertALaterChangeBuiltOnSaysWhyWhenPressed(engine: BrowserEngine) async throws {
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
          INSERT INTO revisions (id, revisable_type, revisable_id, prompt_changes_json, status, requested_by_user_id, created_at)
          VALUES ('\(id)', 'bibliographicMadrigal', '\(work.madrigalID)', json_build_array(json_build_object('slot', '\(slot)', 'previous', json_build_object('system', '\(sql(previous))', 'task', '\(sql(task))'),
              'proposed', json_build_object('system', '\(sql(proposed))', 'task', '\(sql(task))')))::text, 'pending', '\(user)', now() - interval '\(offset) minute')
          """)
      }
      let revert = "#revision-\(a)-verdict-1 form[action$='/revert']"
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated(madrigalPath)
        for id in [a, b] {
          try await page.locator("#revision-\(id) form[action$='/accept'] button").click()
          // Accepted, the server answers with the page at the revision
          // (`#revision-<id>`): waited for, then its verdict read there.
          try await expect(page).toHaveURL("at #revision-\(id)") {
            $0.fragment?.lowercased() == "revision-\(id)".lowercased()
          }
          try await page.waitForLoadState()
          try await expect(page.locator("#revision-\(id)-verdict-1")).toContainText("as accepted")
        }
        // Enabled, its warning hidden until pressed; pressed, shown, the
        // form not sent.
        let button = page.locator("\(revert) button")
        try await expect(button).toBeEnabled()
        try await expect(page.locator("\(revert) .refusal-view")).toBeHidden()
        try await button.click()
        try await expect(page.locator("\(revert) .refusal-view")).toBeVisible()
        try await expect(page.locator("\(revert) .refusal-view")).toContainText(refused)
        let status = try TestAdmin.query("SELECT status FROM revisions WHERE id = '\(a)'")
        #expect(status.trimmingCharacters(in: .whitespacesAndNewlines) == "accepted")
        // Its own page: the header's Revert enabled, the same warning when
        // pressed.
        try await page.openHydrated("\(madrigalPath)/revisions/\(a)")
        try await expect(page.locator("button[form='revision-revert']")).toBeEnabled()
        try await page.locator("button[form='revision-revert']").click()
        try await expect(page.locator(".refusal-view").filter(hasText: refused)).toBeVisible()
        try await page.expectNoErrors()
      }
      // Without the client (the form sent as a browser sends it, no
      // script in the way): the server answers with the page at the warning.
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated(madrigalPath)
        _ = try await page.evaluate("(() => { HTMLFormElement.prototype.submit.call(document.querySelector(\"\(revert)\")); return 1 })()", as: Int.self)
        try await expect(page.locator("\(revert) .refusal-view"), timeout: .seconds(15)).toBeVisible()
        try await expect(page.locator("\(revert) .refusal-view")).toContainText(refused)
        let at = try await page.url()
        #expect(at.hasSuffix("#refused-\(a)-revert"), "At the warning: \(at)")
      }
    } catch {
      remove()
      try await admin.remove(after: error)
    }
    remove()
    try await admin.remove()
  }

  /// A shared prompt revision (user, 2026-10-11, design-notes/
  /// shared-revisions.md): filed on another open object, it is in that
  /// object's thread as gnorium's forwarding of it, and its page says where
  /// it was suggested and forwarded. One that clashes with a change accepted since it was suggested
  /// shows the clash before acceptance—its Old diff and New diff—and its
  /// Accept, pressed, says why. The list compares one revision with the
  /// object as created, or two with each other.
  @Test(arguments: [BrowserEngine.chrome])
  func aSharedRevisionIsFiledAndAClashShowsBeforeAcceptance(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchCommit(owner: admin)
    let madrigalPath = work.madrigalPath
    let overtureID = String(work.overturePath.split(separator: "/").last ?? "")
    let user = try admin.column("id")
    let a = UUID().uuidString.uppercased()
    let b = UUID().uuidString.uppercased()
    let c = UUID().uuidString.uppercased()
    let refused =
      "This change clashes with one accepted or committed since it was suggested: see its Old diff and New diff, and suggest it again."
    func remove() {
      _ = try? TestAdmin.query("DELETE FROM revisions WHERE id IN ('\(a)', '\(b)', '\(c)')")
      work.remove()
    }
    do {
      let slot = "bibliographic_explication"
      func sql(_ text: String) -> String { text.replacingOccurrences(of: "'", with: "''") }
      let system = try TestAdmin.query(
        "SELECT system_prompt FROM prompt_vignettes WHERE id = (SELECT vignette_id FROM active_prompt_vignettes WHERE slot = '\(slot)')")
      let task = try TestAdmin.query(
        "SELECT task_prompt FROM prompt_vignettes WHERE id = (SELECT vignette_id FROM active_prompt_vignettes WHERE slot = '\(slot)')")
      let arbitration = "bibliographic_arbitration"
      let arbitrationSystem = try TestAdmin.query(
        "SELECT system_prompt FROM prompt_vignettes WHERE id = (SELECT vignette_id FROM active_prompt_vignettes WHERE slot = '\(arbitration)')")
      let arbitrationTask = try TestAdmin.query(
        "SELECT task_prompt FROM prompt_vignettes WHERE id = (SELECT vignette_id FROM active_prompt_vignettes WHERE slot = '\(arbitration)')")
      // A, accepted, adds a line to Explication's system prompt; C, pending
      // and suggested before A was accepted, adds another at the same place:
      // they clash. B changes Arbitration's.
      for (id, slot, system, task, proposed, offset, status) in [
        (a, slot, system, task, system + "\nWeb tests A.", 2, "accepted"),
        (b, arbitration, arbitrationSystem, arbitrationTask, arbitrationSystem + "\nWeb tests B.", 1, "pending"),
        (c, slot, system, task, system + "\nWeb tests C.", 3, "pending"),
      ] {
        let evaluated = status == "accepted" ? "'\(user)', now()" : "NULL, NULL"
        _ = try TestAdmin.query("""
          INSERT INTO revisions (id, revisable_type, revisable_id, prompt_changes_json, status, requested_by_user_id, evaluated_by_user_id, evaluated_at, created_at)
          VALUES ('\(id)', 'bibliographicMadrigal', '\(work.madrigalID)', json_build_array(json_build_object('slot', '\(slot)', 'previous', json_build_object('system', '\(sql(system))', 'task', '\(sql(task))'),
              'proposed', json_build_object('system', '\(sql(proposed))', 'task', '\(sql(task))')))::text, '\(status)', '\(user)', \(evaluated), now() - interval '\(offset) minute')
          """)
      }
      // C filed on the overture as well, as suggesting it files it.
      _ = try TestAdmin.query("""
        INSERT INTO revision_filings (revision_id, revisable_type, revisable_id)
        VALUES ('\(c)', 'bibliographicOverture', '\(overtureID)')
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        // In the overture's thread: gnorium forwarded it from the madrigal.
        try await page.openHydrated(work.overturePath)
        let filed = page.locator("#revision-\(c)")
        try await expect(filed).toContainText("gnorium forwarded revision")
        try await expect(filed).toContainText("from madrigal")
        try await expect(filed.locator("a[href$='\(work.madrigalID)' i]").first).toBeAttached()
        // In the madrigal's thread, after its suggestion: forwarded to the
        // overture.
        try await page.openHydrated(madrigalPath)
        let forwarded = page.locator("#revision-\(c)-forwarded")
        try await expect(forwarded).toContainText("gnorium forwarded revision")
        try await expect(forwarded).toContainText("to overture")
        try await expect(forwarded.locator("a[href$='\(overtureID)' i]").first).toBeAttached()
        // Its page: where it is filed, the clash, and Accept refused.
        try await page.openHydrated("\(madrigalPath)/revisions/\(c)")
        try await expect(page.locator(".revision-filing-view")).toContainText("Suggested on madrigal")
        try await expect(page.locator(".revision-filing-view")).toContainText("forwarded by gnorium to overture")
        let clash = page.locator(".prompt-clash-view")
        try await expect(clash.locator(".prompt-clash-label").filter(hasText: "Old diff")).toHaveCount(1)
        try await expect(clash.locator(".prompt-clash-label").filter(hasText: "New diff")).toHaveCount(1)
        try await expect(clash.locator(".locution-thread-path")).toContainText("Explication")
        try await expect(clash).toContainText("Web tests C.")
        try await expect(clash).toContainText("Web tests A.")
        try await page.locator("button[form='revision-accept']").click()
        try await expect(page.locator(".refusal-view").filter(hasText: refused)).toBeVisible()
        let status = try TestAdmin.query("SELECT status FROM revisions WHERE id = '\(c)'")
        #expect(status.trimmingCharacters(in: .whitespacesAndNewlines) == "pending")

        try await page.openHydrated("\(madrigalPath)/revisions")
        // One ticked: compared with the object as created.
        let compare = page.locator(".revisions-compare button")
        try await expect(compare).toBeDisabled()
        try await page.locator("input[name='row-selection'][value='\(a)']").check()
        try await expect(compare).toBeEnabled()
        try await compare.click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the compare page", where: { $0.absoluteString.contains("/revisions/compare?to=\(a)") })
        try await expect(page.locator("h1, .page-heading").first).toContainText("Revisions Compared")
        try await expect(page.locator(".pedigree-view")).toContainText("As created")
        try await expect(page.locator("button[form='revision-revert'], button[form='revision-accept']")).toHaveCount(0)
        // Two ticked: compared with each other, the older first.
        try await page.openHydrated("\(madrigalPath)/revisions")
        try await page.locator("input[name='row-selection'][value='\(a)']").check()
        try await page.locator("input[name='row-selection'][value='\(b)']").check()
        try await page.locator(".revisions-compare button").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the compare page", where: { $0.absoluteString.contains("/revisions/compare?from=") })
        try await expect(page.locator(".pedigree-view")).toContainText(a)
        try await expect(page.locator(".pedigree-view")).toContainText(b)
        // Every process either touched, each with its diff under its box.
        let compared = page.locator(".prompt-change-view .prompt-text-comparison:has(.prompt-text-diff)")
        try await expect(compared).toHaveCount(2)
        try await expect(compared.nth(0)).toContainText("Web tests")
        // A part's anchor, arrived at from elsewhere: the accordions on the
        // way open and it is scrolled to; and on a change of fragment.
        let target = "prompt-revision-system-accordion-\(slot)"
        try await page.openHydrated("\(madrigalPath)/revise#\(target)")
        try await expect(page.locator("#\(target)"), timeout: .seconds(10)).toHaveAttribute("data-expanded", "true")
        try await expect(page.locator("#prompt-revision-process-\(slot)")).toHaveAttribute("data-expanded", "true")
        let shown = try await page.evaluate(
          "(() => { const r = document.getElementById('\(target)').getBoundingClientRect(); return r.top < innerHeight && r.bottom > 0; })()",
          as: Bool.self)
        #expect(shown, "Scrolled to the part")
        let task = "prompt-revision-task-accordion-\(arbitration)"
        _ = try await page.evaluate("(() => { location.hash = '\(task)'; return 1 })()", as: Int.self)
        try await expect(page.locator("#\(task)"), timeout: .seconds(10)).toHaveAttribute("data-expanded", "true")
        try await expect(page.locator("#prompt-revision-process-\(arbitration)")).toHaveAttribute("data-expanded", "true")
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
  /// to its revision's own page in source mode, where an element holds its
  /// anchor; a resemblance's turns the reader there instead (user,
  /// 2026-10-09).
  static func expectChangedLinksLand(_ page: Page, revision id: String, on revisionPath: String) async throws {
    let hrefs = try await page.evaluate(
      "JSON.stringify([...document.querySelectorAll('#revision-\(id) .locution-thread-event-changed a')].map(a => a.getAttribute('href')))"
    ).string ?? "[]"
    let links = try JSONDecoder().decode([String].self, from: Data(hrefs.utf8))
    #expect(!links.isEmpty, "a Changed line")
    for link in links {
      let parts = link.split(separator: "#", maxSplits: 1).map(String.init)
      #expect(
        parts.count == 2 && parts[0].lowercased() == "\(revisionPath)?source=code".lowercased(),
        "\(link) is on \(revisionPath) in source mode")
      guard parts.count == 2, !parts[1].hasPrefix("resemblance-") else { continue }
      try await page.openHydrated(parts[0])
      try await expect(page.locator("[id='\(parts[1])']")).toBeAttached()
    }
  }

  /// One Suggest changes the prompts of several processes at once (user,
  /// 2026-10-14): Explication's system prompt and Arbitration's task
  /// template in one revision. Refused first—an autocompaction template
  /// that drops its variable—the page comes back (422) with every value as
  /// it was typed, byte for byte, why right above Suggest, and the field
  /// marked; corrected, the one revision holds both slots.
  @Test(arguments: [BrowserEngine.chrome])
  func oneSuggestChangesSeveralProcessesPromptsAndARefusalKeepsEveryValue(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let user = try contributor.column("id")
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let work = try ScratchCommit(owner: contributor, sourceURL: fixture.baseURL + "/manifest.json")
    let explication = "bibliographic_explication"
    let arbitration = "bibliographic_arbitration"
    let auto = arbitration + "_autocompaction"
    func remove() {
      _ = try? TestAdmin.query("DELETE FROM revisions WHERE requested_by_user_id = '\(user)'")
      work.remove()
    }
    do {
      _ = try TestAdmin.query(
        #"""
        UPDATE bibliographic_madrigals SET
          metadata_json = (metadata_json::jsonb || '{"title":"Web tests many prompts","provider":"folger_shakespeare_library"}'::jsonb)::text,
          proposed_content_json = '{"teiXml":"<TEI><teiHeader><date>1910</date></teiHeader><text><body><pb n=\"1\" facs=\"\#(fixture.baseURL)/page-1/full/1300,/0/default.jpg\"/><div><p>Old line</p></div><pb n=\"2\" facs=\"\#(fixture.baseURL)/page-2/full/1300,/0/default.jpg\"/><p>Kept line</p><pb n=\"3\" facs=\"\#(fixture.baseURL)/page-3/full/1300,/0/default.jpg\"/></body></text></TEI>"}'
        WHERE id = '\#(work.madrigalID)'
        """#)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(work.madrigalPath)/revise")
        // Each edit as a person makes it: the value set, its input sent.
        // The values carry what a round trip could lose: CRLF, a leading
        // line break, markup, quotes, and a 90 KB prompt.
        let edited = try await page.evaluate(
          """
          (() => {
            const set = (selector, value) => {
              const area = document.querySelector(selector)
              area.value = value
              area.dispatchEvent(new Event('input', { bubbles: true }))
              return area.value
            }
            const long = 'A line of a long prompt, with <tags> & "quotes".\\n'.repeat(1900)
            const system = document.querySelector("textarea[name='prompt-system-\(explication)']").value
            const task = document.querySelector("textarea[name='prompt-task-\(arbitration)']").value
            return JSON.stringify({
              explication: set("textarea[name='prompt-system-\(explication)']", '\\n' + system + '\\n' + long),
              arbitration: set("textarea[name='prompt-task-\(arbitration)']", task + '\\r\\nCite the canvas, "always".'),
              auto: set("textarea[name='prompt-task-\(auto)']", 'Summarize the turns.'),
              title: set("[data-revise-form] input[name='title']", '  Web tests <title> & more  '),
              markup: set('.tei-page-edit textarea', '<div><p>New line &amp; more</p></div>'),
            })
          })()
          """, as: String.self)
        #expect(edited.utf8.count > 90_000)
        try await page.locator(".revision-form button[type='submit']").click()

        // The page again, at its own address, saying why above Suggest.
        let form = page.locator(".revision-form-view")
        let alert = form.locator(".alert-view").filter(hasText: "Keep the required task variable {transcript}.")
        try await expect(alert, timeout: .seconds(15)).toBeVisible()
        try await expect(page).toHaveURL("the Revise page, not a redirect") { $0.path.hasSuffix("/revise") && $0.query == nil }
        let order = try await page.evaluate(
          """
          (() => {
            const view = document.querySelector('.revision-form-view')
            const alert = [...view.querySelectorAll('.alert-view')].find(a => a.textContent.includes('{transcript}'))
            const button = view.querySelector("button[type='submit']")
            return Boolean(alert.compareDocumentPosition(button) & Node.DOCUMENT_POSITION_FOLLOWING)
              && !document.querySelector('.pedigree-view ~ .alert-view')
          })()
          """, as: Bool.self)
        #expect(order, "The reason stands before Suggest, not under the Pedigree")
        // The field it is of, marked where it stands.
        try await expect(page.locator("#prompt-revision-task-accordion-\(auto) .field-validation-message-view"))
          .toContainText("{transcript}")
        // Every value as it was typed.
        let restored = try await page.evaluate(
          """
          (() => new Promise(done => setTimeout(() => done(JSON.stringify({
            explication: document.querySelector("textarea[name='prompt-system-\(explication)']").value,
            arbitration: document.querySelector("textarea[name='prompt-task-\(arbitration)']").value,
            auto: document.querySelector("textarea[name='prompt-task-\(auto)']").value,
            title: document.querySelector("[data-revise-form] input[name='title']").value,
            markup: document.querySelector('.tei-page-edit textarea').value,
          })), 500)))()
          """, as: String.self)
        #expect(restored == edited, "Every value kept byte for byte")
        let nothing = try TestAdmin.query("SELECT count(*) FROM revisions WHERE requested_by_user_id = '\(user)'")
        #expect(nothing.trimmingCharacters(in: .whitespacesAndNewlines) == "0", "Nothing refused is filed")

        // Corrected, the autocompaction left as it was: one revision.
        _ = try await page.evaluate(
          """
          (() => {
            const area = document.querySelector("textarea[name='prompt-task-\(auto)']")
            area.value = area.defaultValue
            area.dispatchEvent(new Event('input', { bubbles: true }))
            return true
          })()
          """, as: Bool.self)
        try await page.locator(".revision-form button[type='submit']").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the madrigal at its locution", where: Self.atLocution(work.madrigalPath))
        let stored = try TestAdmin.query(
          """
          SELECT count(*) || ' ' || string_agg(c ->> 'slot', ',' ORDER BY c ->> 'slot')
          FROM revisions, json_array_elements(prompt_changes_json::json) AS c
          WHERE requested_by_user_id = '\(user)'
          """)
        #expect(stored == "2 \(arbitration),\(explication)", "One revision, both slots: \(stored)")
        let rows = try TestAdmin.query("SELECT count(*) FROM revisions WHERE requested_by_user_id = '\(user)'")
        #expect(rows.trimmingCharacters(in: .whitespacesAndNewlines) == "1")
        // Its "Changed" line names both.
        let changed = page.locator(".locution-thread-event-changed").last
        try await expect(changed).toContainText("Explication")
        try await expect(changed).toContainText("Arbitration")
      }
    } catch {
      remove()
      try await contributor.remove(after: error)
    }
    remove()
    try await contributor.remove()
  }
}
