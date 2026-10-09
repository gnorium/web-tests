import Foundation
import Testing
import WebTests
import WebTestsTesting

/// One Suggest is one revision (user, 2026-10-08): an object's Revise
/// page files whatever was changed—its fields, any number of ordinances
/// edited in its reader, the prompts of the process it would be committed
/// for—as one row, accepted whole; each diff is drawn live where it is made,
/// and the revision's page draws each in the record's tree. Suggest lands
/// on the object's own page at the suggestion's locution; the revision is
/// accepted or rejected there or on its own page, and the Revisions lists
/// are read-only. Prompts are in force only once the
/// object is committed. A process's prompt page is read-only. All of it
/// under a throwaway contributor's account; Chrome, desktop.
@Suite("Revise pages", .serialized)
struct RevisePagesTests {
  /// The object's page at a suggestion's locution in its thread.
  static func atLocution(_ path: String) -> @Sendable (URL) -> Bool {
    { url in url.path.lowercased() == path.lowercased() && (url.fragment ?? "").hasPrefix("revision-") }
  }

  @Test(arguments: [BrowserEngine.chrome])
  func oneSuggestFilesFieldsOrdinancesAndPromptsAsOneRevision(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let user = try contributor.column("id")
    let commit = try ScratchCommit(owner: contributor)
    let slot = "bibliographic_explication"
    func remove() {
      _ = try? TestAdmin.query("DELETE FROM revisions WHERE requested_by_user_id = '\(user)'")
      commit.remove()
    }
    let inForce = try TestAdmin.query("SELECT vignette_id FROM active_prompt_vignettes WHERE slot = '\(slot)'")
    do {
      // Two semblances; the digitization's required provider.
      _ = try TestAdmin.query(
        #"""
        UPDATE bibliographic_madrigals SET
          metadata_json = (metadata_json::jsonb || '{"provider":"folger_shakespeare_library"}'::jsonb)::text,
          proposed_content_json = '{"teiXml":"<TEI><teiHeader><date>1910</date></teiHeader><text><body><pb n=\"1\" facs=\"https://web-tests.invalid/iiif/p1/full/1300,/0/default.jpg\"/><div><p>Old line</p></div><pb n=\"2\" facs=\"https://web-tests.invalid/iiif/p2/full/1300,/0/default.jpg\"/><p>Kept line</p></body></text></TEI>"}'
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
        try await expect(page.locator(".tei-page-edit textarea")).toHaveCount(2)
        // One Suggest, at the end: none per page, none for the prompts, no
        // Diff toggle and no scope.
        try await expect(page.locator("button[type='submit']").filter(hasText: "Suggest")).toHaveCount(1)
        try await expect(page.locator(".testament-suggest")).toHaveCount(0)
        try await expect(page.locator(".prompt-revision-fields-diff-toggle")).toHaveCount(0)
        try await expect(page.locator("input[name='scope']")).toHaveCount(0)
        // A process toggle, where there is one, is in the header.
        try await expect(page.locator(".prompt-revision-fields-view .process-toggle-view")).toHaveCount(0)
        try await page.expectNoHorizontalOverflow()

        // The fields, an ordinance and the system prompt, each diff drawn
        // as it is made.
        try await page.locator("[data-revise-form] input[name='title']").first.fill("Web tests title")
        // The editor opens on the code as the Raw view lays it out, the
        // stored one-line ordinance one element per line.
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
        let prompts = page.locator(".prompt-revision-fields-view")
        // Each prompt in its accordion, closed as on the object's page.
        try await prompts.locator("#prompt-revision-system-accordion-\(slot) .accordion-summary").first.click()
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
        try await page.openHydrated(commit.madrigalPath)
        let event = page.locator("#revision-\(id)")
        try await expect(event).toContainText("suggested revision")
        try await expect(event.locator(".locution-thread-event-added")).toBeVisible()
        try await expect(event.locator(".locution-thread-event-changed a").first).toBeVisible()
        try await expect(event.locator("form[action$='/accept'] button")).toHaveCount(1)
        try await expect(event.locator("form[action$='/reject'] button")).toHaveCount(1)
        try await Self.expectChangedLinksLand(page, revision: id, on: "\(commit.madrigalPath)/revisions/\(id)")

        // Its page draws each diff where it is made: the record's tree,
        // the ordinance under its semblance, the prompts.
        try await page.openHydrated("\(commit.madrigalPath)/revisions/\(id)")
        try await expect(page.locator(".testament-tree-diff-view")).toHaveCount(1)
        // Under no heading of its own: the source diff, both sides laid out.
        try await expect(page.getByText("Ordinance of semblance 1")).toHaveCount(0)
        try await expect(
          page.locator(".testament-diff[data-edited='true'] .diff-view[data-diff-mode='code']").first
        ).toBeAttached()
        // The changed page's frame alone wears the ring; the diff under it
        // stands unboxed, as a changed field's Diff line does.
        let unringed = try await page.evaluate(
          """
          (() => {
            const slot = document.querySelector(".testament-diff[data-edited='true']")
            if (!slot) return 'no diff'
            const boxed = [slot, ...slot.querySelectorAll('.semblance-diff-view')].filter((el) => {
              const style = getComputedStyle(el)
              return style.borderTopStyle !== 'none' || style.outlineStyle !== 'none'
            })
            const viewer = document.querySelector('.artifact-view')
            return boxed.length === 0 && viewer.dataset.diffState === 'changed' ? 'ok' : `boxed ${boxed.length}`
          })()
          """, as: String.self)
        #expect(unringed == "ok", "The diff under the changed page is not unboxed: \(unringed)")
        // The prompts as an object's read, the one changed open on its diff.
        try await expect(page.locator(".prompt-change-view .diff-view").first).toBeVisible()
        try await expect(page.getByText("Web tests suggestion.").first).toBeAttached()
        try await page.expectNoHorizontalOverflow()
        // Its verdicts here too, posting to the thread's routes. No
        // Locution row in its Pedigree: a locution is an event in a thread,
        // not an object.
        try await expect(page.locator("form#revision-accept[action$='/revisions/\(id)/accept']")).toHaveCount(1)
        try await expect(page.locator(".pedigree-view").getByText("Locution", exact: true)).toHaveCount(0)

        // Accepted from the thread, back at its locution.
        try await page.openHydrated(commit.madrigalPath)
        try await page.locator("#revision-\(id) form[action$='/accept'] button").click()
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("the madrigal at its locution", where: Self.atLocution(commit.madrigalPath))
        try await expect(page.locator("#revision-\(id)-verdict")).toContainText("accepted revision")

        // The madrigal's Revisions list reads it, linking its own page.
        try await page.openHydrated("\(commit.madrigalPath)/revisions")
        try await expect(page.locator("a[href$='/revisions/\(id)']")).toHaveCount(1)
        try await expect(page.locator("form[action$='/accept'], form[action$='/reject']")).toHaveCount(0)
      }
      let document = try TestAdmin.query(
        "SELECT proposed_content_json::json ->> 'teiXml' FROM bibliographic_madrigals WHERE id = '\(commit.madrigalID)'")
      #expect(document.contains("New line") && document.contains("Kept line"), "Accepted, the ordinance is the madrigal's: \(document)")
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

        let prompts = page.locator(".prompt-revision-fields-view")
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
              .querySelector('.prompt-instances-view')?.dataset.sourceUrl
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

  /// A lexicographic madrigal's Revise page offers what a bibliographic
  /// one's does, in parallel (user, 2026-10-07): its record's identity and
  /// each sentiment's description and labels, in its Sentiments tree. A
  /// change is one revision of its fields, in the madrigal's thread, that
  /// an admin accepts there—written into the madrigal—and reverts.
  /// An epilogue's description in the record's language is revised the same
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
        INSERT INTO lexicographic_epilogues (id, lexico_record_id, lexico_record_version_id, sentiment_id, description,
            target, status, submitted_by_user_id, summary, description_translation_json)
          VALUES ('\(epilogue)', '\(word.recordID.lowercased())', '\(word.versionID.lowercased())', 's-1-1',
            'A leaf sense.', 'description', 'proposed', (SELECT id FROM users WHERE username = 'gnorium'), 'Web tests.',
            '{"language_code":"fra","description":"Un sens feuille.","labels":[],"confidence":"clear","reason":"Web tests."}');
        """)
      let madrigalPath = "/mission-control/madrigals/lexicographic/\(word.madrigalID)"
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(madrigalPath)/revise")
        // Every sentiment's fields, under its number.
        try await expect(page.locator("textarea[name='sentiment-0-description']")).toHaveValue("A branch sense.")
        try await expect(page.locator("textarea[name='sentiment-1-description']")).toHaveValue("A leaf sense.")
        // One field a label kind, as Submit Sentiment draws them (user, 2026-10-09).
        for kind in ["grammar", "register", "domain", "region", "currency"] {
          try await expect(page.locator("input[name='sentiment-1-\(kind)']")).toBeAttached()
        }
        try await expect(page.locator("[data-item-list='sentiment-1-labels']")).toHaveCount(0)
        try await page.expectNoHorizontalOverflow()
        let leaf = page.locator("textarea[name='sentiment-1-description']")
        try await leaf.fill("A leaf sense, as a person reads it.")
        // Its diff is drawn as it is made, as a bibliographic field's is.
        try await expect(page.locator("[data-diff-annotation][data-visible='true']").first).toBeAttached()
        // And one of its metadata fields: a Register label.
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
        // Its description and its one metadata field, each its own item by
        // its form's label, each linked to its place on the page.
        let changed = event.locator(".locution-thread-event-changed")
        try await expect(changed).toHaveText("Changed Sentiment 1.1 Description and Sentiment 1.1 Register")
        try await expect(changed.locator("a")).toHaveCount(2)
        // Each on the revision's own page, at its field there (user, 2026-10-09).
        try await expect(changed.locator("a[href='\(revisionPath)#sentiment-1-description']"))
          .toHaveText("Sentiment 1.1 Description")
        try await expect(changed.locator("a[href='\(revisionPath)#sentiment-1-register']"))
          .toHaveText("Sentiment 1.1 Register")
        try await Self.expectChangedLinksLand(page, revision: id, on: revisionPath)
        try await page.openHydrated(madrigalPath)
        try await event.locator("form[action$='/accept'] button").click()
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("the madrigal at its locution", where: Self.atLocution(madrigalPath))
        #expect(try content().contains("A leaf sense, as a person reads it."), "Accepted, it is written into the madrigal")
        try await page.locator("#revision-\(id)-verdict form[action$='/revert'] button").click()
        try await expect(page.locator("#revision-\(id)-verdict"), timeout: .seconds(15)).toHaveCount(0)
        #expect(!(try content().contains("as a person reads it")), "Reverted, it comes back out")
        #expect(try content().contains("<def>A leaf sense.</def>"), "The TEI's description with it")
      }

      // An epilogue's description in the record's language, the same way.
      let epiloguePath = "/mission-control/epilogues/lexicographic/\(epilogue)"
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(epiloguePath)/revise")
        let description = page.locator("textarea[name='description']")
        try await expect(description).toHaveValue("Un sens feuille.")
        try await description.fill("Un sens feuille, corrigé.")
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
          .toHaveText("Changed Sentiment 1.1 Description")
        // Its revision's page, named as the server names it (ids upper case).
        let epilogueRevisionPath =
          "/mission-control/epilogues/lexicographic/\(epilogue.uppercased())/revisions/\(epilogueRevision)"
        try await expect(
          event.locator(".locution-thread-event-changed a[href='\(epilogueRevisionPath)#description']")
        ).toHaveCount(1)
        try await Self.expectChangedLinksLand(page, revision: epilogueRevision, on: epilogueRevisionPath)
        try await page.openHydrated(epiloguePath)
        try await event.locator("form[action$='/accept'] button").click()
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("the epilogue at its locution", where: Self.atLocution(epiloguePath))
        let stored = try TestAdmin.query(
          "SELECT description_translation_json FROM lexicographic_epilogues WHERE id = '\(epilogue)'")
        #expect(stored.contains("Un sens feuille, corrigé."), "stored: \(stored)")
        #expect(stored.contains("\"confidence\":\"\""), "A person's description has no confidence: \(stored)")
        // The epilogue's page reads it, its confidence "—".
        try await page.openHydrated(epiloguePath)
        try await expect(page.getByText("Un sens feuille, corrigé.").first).toBeAttached()
        try await expect(page.locator("a[href*='/mission-control/revisions/lexicographic?objectID=']")).toHaveCount(1)

        // The Revisions list reads it, each row linking its own page.
        try await page.openHydrated("/mission-control/revisions/lexicographic?objectID=\(epilogue)")
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

  /// Every item of a revision's "Changed" line (on the page open now) links
  /// to its revision's own page, where an element holds its anchor; a
  /// semblance's turns the reader there instead (user, 2026-10-09).
  static func expectChangedLinksLand(_ page: Page, revision id: String, on revisionPath: String) async throws {
    let hrefs = try await page.evaluate(
      "JSON.stringify([...document.querySelectorAll('#revision-\(id) .locution-thread-event-changed a')].map(a => a.getAttribute('href')))"
    ).string ?? "[]"
    let links = try JSONDecoder().decode([String].self, from: Data(hrefs.utf8))
    #expect(!links.isEmpty, "a Changed line")
    for link in links {
      let parts = link.split(separator: "#", maxSplits: 1).map(String.init)
      #expect(parts.count == 2 && parts[0].lowercased() == revisionPath.lowercased(), "\(link) is on \(revisionPath)")
      guard parts.count == 2, !parts[1].hasPrefix("semblance-") else { continue }
      try await page.openHydrated(parts[0])
      try await expect(page.locator("[id='\(parts[1])']")).toBeAttached()
    }
  }
}
