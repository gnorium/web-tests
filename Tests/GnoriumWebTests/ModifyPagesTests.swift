import Foundation
import Testing
import WebTests
import WebTestsTesting

/// One Suggest is one modification (user, 2026-10-08): an object's Modify
/// page files whatever was changed—its fields, any number of ordinances
/// edited in its reader, the prompts of the process it would be committed
/// for—as one row, accepted whole; each diff is drawn live where it is made,
/// and the modification's page draws each in the record's tree. Prompts are
/// in force only once the object is committed. A process's prompt page is
/// read-only. All of it under a throwaway contributor's account; Chrome,
/// desktop.
@Suite("Modify pages", .serialized)
struct ModifyPagesTests {
  @Test(arguments: [BrowserEngine.chrome])
  func oneSuggestFilesFieldsOrdinancesAndPromptsAsOneModification(engine: BrowserEngine) async throws {
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
      // Two semblances; the digitization's required provider.
      _ = try TestAdmin.query(
        #"""
        UPDATE bibliographic_madrigals SET
          metadata_json = (metadata_json::jsonb || '{"provider":"folger_shakespeare_library"}'::jsonb)::text,
          proposed_content_json = '{"teiXml":"<TEI><teiHeader><date>1910</date></teiHeader><text><body><pb n=\"1\" facs=\"https://web-tests.invalid/iiif/p1/full/1300,/0/default.jpg\"/><p>Old line</p><pb n=\"2\" facs=\"https://web-tests.invalid/iiif/p2/full/1300,/0/default.jpg\"/><p>Kept line</p></body></text></TEI>"}'
        WHERE id = '\#(commit.madrigalID)'
        """#)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        // The process's page is read-only, its runs its associated ones.
        let processURL = "/mission-control/prompts/bibliographic/explication"
        try await page.openHydrated(processURL)
        try await expect(page.locator("a[href='\(processURL)/modify']")).toHaveCount(0)
        try await expect(page.locator(".associated-links-view a")).toHaveText("runs")

        try await page.openHydrated("\(commit.madrigalPath)/modify")
        try await expect(page.locator(".testament-tree-diff-view")).toHaveCount(1)
        try await expect(page.locator(".tei-page-edit textarea")).toHaveCount(2)
        // One Suggest, at the end: none per page, none for the prompts, no
        // Diff toggle and no scope.
        try await expect(page.locator("button[type='submit']").filter(hasText: "Suggest")).toHaveCount(1)
        try await expect(page.locator(".testament-suggest")).toHaveCount(0)
        try await expect(page.locator(".prompt-modification-fields-diff-toggle")).toHaveCount(0)
        try await expect(page.locator("input[name='scope']")).toHaveCount(0)
        // A process toggle, where there is one, is in the header.
        try await expect(page.locator(".prompt-modification-fields-view .process-toggle-view")).toHaveCount(0)
        try await page.expectNoHorizontalOverflow()

        // The fields, an ordinance and the system prompt, each diff drawn
        // as it is made.
        try await page.locator("[data-modify-form] input[name='title']").first.fill("Web tests title")
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
        let prompts = page.locator(".prompt-modification-fields-view")
        let system = prompts.locator("textarea[name='prompt-system-\(slot)']")
        try await system.fill((try await system.inputValue()) + "\nWeb tests suggestion.")
        let line = prompts.locator(".field-diff-diff").first
        try await expect(line).toBeVisible()
        try await expect(line).toContainText("Web tests suggestion.")
        try await page.locator(".modification-form button[type='submit']").click()
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("/mission-control/modifications/bibliographic?object=madrigal")
        let stored = try TestAdmin.query(
          """
          SELECT count(*) || ' ' || bool_and(content_json IS NOT NULL)::text || ' '
            || max(json_array_length(pages_json::json)) || ' ' || max(prompt_slot)
          FROM modifications WHERE requested_by_user_id = '\(user)'
          """)
        #expect(stored == "1 true 1 \(slot)", "One row holding all three: \(stored)")
      }
      let id = try TestAdmin.query("SELECT id FROM modifications WHERE requested_by_user_id = '\(user)'")
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        // The thread says who suggested it and its size, and links it.
        try await page.openHydrated(commit.madrigalPath)
        let event = page.locator("#modification-\(id)")
        try await expect(event).toContainText("suggested modification")
        try await expect(event.locator(".intervention-thread-event-added")).toBeVisible()

        // Its page draws each diff where it is made: the record's tree,
        // the ordinance under its semblance, the prompts.
        try await page.openHydrated("\(commit.madrigalPath)/modifications/\(id)")
        try await expect(page.locator(".testament-tree-diff-view")).toHaveCount(1)
        try await expect(page.getByText("Ordinance of semblance 1").first).toBeVisible()
        try await expect(page.locator(".testament-diff[data-edited='true'] .tooltip-view").first).toBeAttached()
        // The prompts as an object's read, the one changed open on its diff.
        try await expect(page.locator(".prompt-change-view .diff-view").first).toBeVisible()
        try await expect(page.getByText("Web tests suggestion.").first).toBeAttached()
        try await page.expectNoHorizontalOverflow()
        _ = try await page.evaluate(
          "(() => { document.getElementById('modification-accept').submit(); return true })()", as: Bool.self)
        try await expect(page, timeout: .seconds(15)).toHaveURL("the madrigal's page") {
          $0.path.lowercased() == commit.madrigalPath.lowercased()
        }
      }
      let document = try TestAdmin.query(
        "SELECT proposed_content_json::json ->> 'teiXml' FROM bibliographic_madrigals WHERE id = '\(commit.madrigalID)'")
      #expect(document.contains("New line") && document.contains("Kept line"), "Accepted, the ordinance is the madrigal's: \(document)")
      let title = try TestAdmin.query(
        "SELECT metadata_json::json ->> 'title' FROM bibliographic_madrigals WHERE id = '\(commit.madrigalID)'")
      #expect(title == "Web tests title", "and its fields: \(title)")
      let status = try TestAdmin.query(
        "SELECT status || ' ' || (prompt_template_id IS NULL)::text FROM modifications WHERE id = '\(id)'")
      #expect(status == "accepted true", "Accepted whole, its prompts not yet in force: \(status)")
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

  /// A lexicographic madrigal's Modify page offers what a bibliographic
  /// one's does, in parallel (user, 2026-10-07): its record's identity and
  /// each sentiment's definition and labels, in its Sentiments tree. A
  /// change is one modification of its fields an admin accepts—written into the
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
        "SELECT id FROM modifications WHERE requested_by_user_id = '\(user)' AND modifiable_type = 'lexicographicMadrigal' AND content_json IS NOT NULL AND status = 'pending'")
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
        "SELECT id FROM modifications WHERE requested_by_user_id = '\(user)' AND modifiable_type = 'lexicographicEpilogue' AND content_json IS NOT NULL")
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
