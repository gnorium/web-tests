import Foundation
import Testing
import WebTests
import WebTestsTesting

/// One suggestion is one modification of one scope (user, 2026-10-07): an
/// object's Modify page has a Suggest for its fields, one for each page in
/// its reader, and one for its Prompts—the prompts of the process it would
/// be committed for, suggested and discussed on the object, in force only
/// once the object is committed. A process's prompt page is read-only. All
/// of it under a throwaway contributor's account; Chrome, desktop.
@Suite("Modify pages", .serialized)
struct ModifyPagesTests {
  @Test(arguments: [BrowserEngine.chrome])
  func promptsAreSuggestedOnTheirObject(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let user = try contributor.column("id")
    let commit = try ScratchCommit(owner: contributor)
    let slot = "bibliographic_explication"
    func remove() {
      _ = try? TestAdmin.query("DELETE FROM modifications WHERE requested_by_user_id = '\(user)'")
      commit.remove()
    }
    let inForce = try TestAdmin.query("SELECT revision_id FROM active_prompt_revisions WHERE slot = '\(slot)'")
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        // The process's page is read-only, its runs its associated ones.
        let processURL = "/mission-control/prompts/bibliographic/explication"
        try await page.openHydrated(processURL)
        try await expect(page.locator("a[href='\(processURL)/modify']")).toHaveCount(0)
        try await expect(page.locator(".associated-links-view a")).toHaveText("runs")

        try await page.openHydrated("\(commit.madrigalPath)/modify")
        let prompts = page.locator(".prompt-modification-fields-view")
        try await expect(prompts).toHaveCount(1)
        try await expect(prompts.locator("input[name='scope']")).toHaveValue("prompt")
        // Diff is off until pressed: outlined, no diff under a changed box.
        let diff = prompts.locator(".prompt-modification-fields-diff-toggle")
        try await expect(diff).toHaveAttribute("aria-pressed", "false")
        let system = prompts.locator("textarea[name='prompt-system-\(slot)']")
        try await system.fill((try await system.inputValue()) + "\nWeb tests suggestion.")
        let line = prompts.locator(".field-diff-diff").first
        try await expect(line).toBeHidden()
        try await diff.locator("button").click()
        try await expect(diff).toHaveAttribute("aria-pressed", "true")
        try await expect(line).toBeVisible()
        try await expect(line).toContainText("Web tests suggestion.")
        try await diff.locator("button").click()
        try await expect(line).toBeHidden()
        try await page.expectNoHorizontalOverflow()

        try await prompts.locator("button[type='submit']").click()
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("/mission-control/modifications/bibliographic?object=madrigal")
        let stored = try TestAdmin.query(
          """
          SELECT target || ' ' || prompt_slot || ' ' || status || ' ' || modifiable_type || ' '
            || (content_json IS NULL)::text || ' ' || (semblance_markup IS NULL)::text
          FROM modifications WHERE requested_by_user_id = '\(user)'
          """)
        #expect(stored == "prompt \(slot) pending bibliographicMadrigal true true", "stored: \(stored)")
      }
      let id = try TestAdmin.query("SELECT id FROM modifications WHERE requested_by_user_id = '\(user)'")
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        // Its page reads the prompts' change; accepted, it waits for the
        // madrigal's commit.
        try await page.openHydrated("\(commit.madrigalPath)/modifications/\(id)")
        try await expect(page.getByText("Explication Prompts").first).toBeAttached()
        try await expect(page.getByText("Web tests suggestion.").first).toBeAttached()
        _ = try await page.evaluate(
          "(() => { document.getElementById('modification-accept').submit(); return true })()", as: Bool.self)
        try await expect(page, timeout: .seconds(15)).toHaveURL("the madrigal's page") {
          $0.path.lowercased() == commit.madrigalPath.lowercased()
        }
      }
      let status = try TestAdmin.query(
        "SELECT status || ' ' || (prompt_template_id IS NULL)::text FROM modifications WHERE id = '\(id)'")
      #expect(status == "accepted true", "Accepted, not yet in force: \(status)")
      let still = try TestAdmin.query("SELECT revision_id FROM active_prompt_revisions WHERE slot = '\(slot)'")
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

  /// A bibliographic madrigal's Modify page is its record as its own page
  /// draws it, open to correction: the work's fields, the Testaments tree
  /// and its reader—no whole document. The fields' Suggest files the fields
  /// alone; an edited page's own Suggest, that page alone. Accepted, each is
  /// written into the madrigal.
  @Test(arguments: [BrowserEngine.chrome])
  func aBibliographicMadrigalsSuggestionsAreOneScopeEach(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let user = try contributor.column("id")
    let commit = try ScratchCommit(owner: contributor)
    func remove() {
      _ = try? TestAdmin.query("DELETE FROM modifications WHERE requested_by_user_id = '\(user)'")
      commit.remove()
    }
    do {
      // One page; the digitization's required provider.
      _ = try TestAdmin.query(
        #"""
        UPDATE bibliographic_madrigals SET
          metadata_json = (metadata_json::jsonb || '{"provider":"folger_shakespeare_library"}'::jsonb)::text,
          proposed_content_json = '{"teiXml":"<TEI><teiHeader><date>1910</date></teiHeader><text><body><pb n=\"1\" facs=\"https://web-tests.invalid/iiif/p1/full/1300,/0/default.jpg\"/><p>Old line</p></body></text></TEI>"}'
        WHERE id = '\#(commit.madrigalID)'
        """#)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(commit.madrigalPath)/modify")
        try await expect(page.locator(".testament-tree-diff-view")).toHaveCount(1)
        try await expect(page.locator("textarea[name='document']")).toHaveCount(0)
        try await expect(page.getByText("current_tei.xml")).toHaveCount(0)
        try await expect(page.locator(".tei-page-edit textarea")).toHaveCount(1)
        try await expect(page.locator("input[name='testament-levels']")).toBeAttached()
        // A page's Suggest shows once the page is edited.
        let pageSuggest = page.locator(".testament-suggest").first
        try await expect(pageSuggest).toBeHidden()
        try await page.expectNoHorizontalOverflow()

        // The fields alone, with the fields' Suggest.
        try await page.locator("[data-modify-form] input[name='title']").first.fill("Web tests title")
        try await page.locator(".modification-form button[type='submit']").click()
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("/mission-control/modifications/bibliographic?object=madrigal")

        // One page alone, with its own Suggest.
        try await page.openHydrated("\(commit.madrigalPath)/modify")
        _ = try await page.evaluate(
          """
          (() => {
            const area = document.querySelector('.tei-page-edit textarea')
            area.value = area.value.replace('Old line', 'New line')
            area.dispatchEvent(new Event('input', { bubbles: true }))
            return true
          })()
          """, as: Bool.self)
        try await expect(pageSuggest).toBeVisible()
        try await pageSuggest.locator("button[type='submit']").click()
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("/mission-control/modifications/bibliographic?object=madrigal")
        let stored = try TestAdmin.query(
          """
          SELECT string_agg(target || ' ' || (content_json IS NOT NULL)::text || ' '
            || (semblance_markup IS NOT NULL)::text, ',' ORDER BY target)
          FROM modifications WHERE requested_by_user_id = '\(user)'
          """)
        #expect(stored == "form true false,semblance false true", "One scope each: \(stored)")
      }
      let pageID = try TestAdmin.query(
        "SELECT id FROM modifications WHERE requested_by_user_id = '\(user)' AND target = 'semblance'")
      let formID = try TestAdmin.query(
        "SELECT id FROM modifications WHERE requested_by_user_id = '\(user)' AND target = 'form'")
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        for id in [pageID, formID] {
          try await page.openHydrated("\(commit.madrigalPath)/modifications/\(id)")
          _ = try await page.evaluate(
            "(() => { document.getElementById('modification-accept').submit(); return true })()", as: Bool.self)
          try await expect(page, timeout: .seconds(15)).toHaveURL("the madrigal's page") {
            $0.path.lowercased() == commit.madrigalPath.lowercased()
          }
        }
      }
      let document = try TestAdmin.query(
        "SELECT proposed_content_json::json ->> 'teiXml' FROM bibliographic_madrigals WHERE id = '\(commit.madrigalID)'")
      #expect(document.contains("New line"), "Accepted, the page is the madrigal's: \(document)")
      let title = try TestAdmin.query(
        "SELECT metadata_json::json ->> 'title' FROM bibliographic_madrigals WHERE id = '\(commit.madrigalID)'")
      #expect(title == "Web tests title", "and its fields: \(title)")
    } catch {
      remove()
      try await admin.remove()
      try await contributor.remove(after: error)
    }
    remove()
    try await admin.remove()
    try await contributor.remove()
  }

  /// A lexicographic madrigal's Modify page offers what a bibliographic
  /// one's does, in parallel (user, 2026-10-07): its record's identity and
  /// each sentiment's definition and labels, in its Sentiments tree. A
  /// change is one `form` modification an admin accepts—written into the
  /// madrigal—and reverts.
  /// An epilogue's definition in the record's language is modified the same
  /// way, the session's confidence cleared once a person changed it.
  @Test(arguments: [BrowserEngine.chrome])
  func lexicographicFieldsAreModifiedAsBibliographicOnesAre(engine: BrowserEngine) async throws {
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
        DELETE FROM modifications WHERE requested_by_user_id = '\(user)';
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
        INSERT INTO lexicographic_epilogues (id, lexico_record_id, lexico_record_version_id, sentiment_id, definition,
            target, status, submitted_by_user_id, summary, definition_translation_json)
          VALUES ('\(epilogue)', '\(word.recordID.lowercased())', '\(word.versionID.lowercased())', 's-1-1',
            'A leaf sense.', 'definition', 'proposed', (SELECT id FROM users WHERE username = 'gnorium'), 'Web tests.',
            '{"language_code":"fra","definition":"Un sens feuille.","labels":[],"confidence":"clear","reason":"Web tests."}');
        """)
      let madrigalPath = "/mission-control/madrigals/lexicographic/\(word.madrigalID)"
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(madrigalPath)/modify")
        // Every sentiment's fields, under its number.
        try await expect(page.locator("textarea[name='sentiment-0-definition']")).toHaveValue("A branch sense.")
        try await expect(page.locator("textarea[name='sentiment-1-definition']")).toHaveValue("A leaf sense.")
        try await expect(page.locator("input[name='sentiment-1-labels-json']")).toBeAttached()
        try await page.expectNoHorizontalOverflow()
        let leaf = page.locator("textarea[name='sentiment-1-definition']")
        try await leaf.fill("A leaf sense, as a person reads it.")
        // Its diff is drawn as it is made, as a bibliographic field's is.
        try await expect(page.locator("[data-diff-annotation][data-visible='true']").first).toBeAttached()
        try await page.locator(".modification-form button[type='submit']").click()
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("/mission-control/modifications/lexicographic?object=madrigal")
      }
      let id = try TestAdmin.query(
        "SELECT id FROM modifications WHERE requested_by_user_id = '\(user)' AND modifiable_type = 'lexicographicMadrigal' AND target = 'form' AND status = 'pending'")
      #expect(!id.isEmpty, "A modification of the madrigal is filed")
      #expect(try content().contains("A leaf sense.\""), "The madrigal stands until it is accepted")

      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        let modificationPath = "\(madrigalPath)/modifications/\(id.uppercased())"
        try await page.openHydrated(modificationPath)
        try await expect(page.getByText("Sentiment 1.1").first).toBeAttached()
        try await expect(page.locator(".diff-view").first).toBeAttached()
        _ = try await page.evaluate("(() => { document.getElementById('modification-accept').submit(); return true })()", as: Bool.self)
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("/mission-control/modifications/lexicographic?object=madrigal")
        #expect(try content().contains("A leaf sense, as a person reads it."), "Accepted, it is written into the madrigal")
        try await page.openHydrated(modificationPath)
        _ = try await page.evaluate("(() => { document.getElementById('modification-revert').submit(); return true })()", as: Bool.self)
        try await expect(page, timeout: .seconds(15)).toHaveURL(modificationPath)
        #expect(!(try content().contains("as a person reads it")), "Reverted, it comes back out")
        #expect(try content().contains("<def>A leaf sense.</def>"), "The TEI's definition with it")
      }

      // An epilogue's definition in the record's language, the same way.
      let epiloguePath = "/mission-control/epilogues/lexicographic/\(epilogue)"
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(epiloguePath)/modify")
        let definition = page.locator("textarea[name='definition']")
        try await expect(definition).toHaveValue("Un sens feuille.")
        try await definition.fill("Un sens feuille, corrigé.")
        try await page.locator(".modification-form button[type='submit']").click()
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("/mission-control/modifications/lexicographic?object=epilogue")
      }
      let epilogueModification = try TestAdmin.query(
        "SELECT id FROM modifications WHERE requested_by_user_id = '\(user)' AND modifiable_type = 'lexicographicEpilogue' AND target = 'form'")
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated("\(epiloguePath)/modifications/\(epilogueModification)")
        _ = try await page.evaluate("(() => { document.getElementById('modification-accept').submit(); return true })()", as: Bool.self)
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("/mission-control/modifications/lexicographic?object=epilogue")
        let stored = try TestAdmin.query(
          "SELECT definition_translation_json FROM lexicographic_epilogues WHERE id = '\(epilogue)'")
        #expect(stored.contains("Un sens feuille, corrigé."), "stored: \(stored)")
        #expect(stored.contains("\"confidence\":\"\""), "A person's definition has no confidence: \(stored)")
        // The epilogue's page reads it, its confidence "—".
        try await page.openHydrated(epiloguePath)
        try await expect(page.getByText("Un sens feuille, corrigé.").first).toBeAttached()
        try await expect(page.locator("a[href*='/mission-control/modifications/lexicographic?target=']")).toHaveCount(1)
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
}
