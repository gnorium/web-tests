import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Prompts are modified apart from objects (user, 2026-10-07): a process's
/// prompt page offers Modify to anyone signed in, its Modify page the system
/// prompt and the task prompt template, and a submit is exactly one `prompt`
/// modification of the process, tied to no object, listed on its kind's
/// Modifications. An object's Modify page carries no prompts. All of it
/// under a throwaway contributor's account; Chrome, desktop.
@Suite("Modify pages", .serialized)
struct ModifyPagesTests {
  @Test(arguments: [BrowserEngine.chrome])
  func promptsAreSuggestedFromTheirProcesssPage(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let user = try contributor.column("id")
    let commit = try ScratchCommit(owner: contributor)
    let word = try ScratchWord(owner: contributor, submitted: true)
    func remove() {
      _ = try? TestAdmin.query("DELETE FROM modifications WHERE requested_by_user_id = '\(user)'")
      commit.remove()
      word.remove()
    }
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        // An object's Modify page is the object alone.
        for path in [commit.madrigalPath, "/mission-control/madrigals/lexicographic/\(word.madrigalID)"] {
          try await page.openHydrated("\(path)/modify")
          try await expect(page.locator("[data-modify-form]")).toHaveCount(1)
          try await expect(page.locator("[name='promptSystem']")).toHaveCount(0)
        }
        for (kind, process, slot) in [
          ("bibliographic", "explication", "bibliographic_explication"),
          ("lexicographic", "translation", "lexicographic_translation"),
        ] {
          let processURL = "/mission-control/prompts/\(kind)/\(process)"
          try await page.openHydrated(processURL)
          try await expect(page.getByText("See associated").first).toBeAttached()
          let modify = page.locator("a[href='\(processURL)/modify']")
          try await expect(modify).toHaveCount(1)
          try await expect(modify).toHaveText("Modify")
          try await page.openHydrated("\(processURL)/modify")
          try await expect(page.getByText("Modify Prompts").first).toBeAttached()
          let system = page.locator("textarea[name='promptSystem']")
          try await system.fill((try await system.inputValue()) + "\nWeb tests suggestion.")
          try await page.locator(".modify-prompts-form button[type='submit']").click()
          try await expect(page, timeout: .seconds(15))
            .toHaveURL("/mission-control/modifications/\(kind)?object=prompt&slot=\(slot)")
          let stored = try TestAdmin.query(
            """
            SELECT target || ' ' || prompt_slot || ' ' || status || ' ' || (modifiable_type IS NULL)::text
              || ' ' || (modifiable_id IS NULL)::text
            FROM modifications WHERE requested_by_user_id = '\(user)' AND prompt_slot = '\(slot)'
            """)
          #expect(stored == "prompt \(slot) pending true true", "stored: \(stored)")
          // Its own page, under its process: the prompts before and after.
          let id = try TestAdmin.query(
            "SELECT id FROM modifications WHERE requested_by_user_id = '\(user)' AND prompt_slot = '\(slot)'")
          try await page.openHydrated("\(processURL)/modifications/\(id)")
          try await expect(page.getByText("Web tests suggestion.").first).toBeAttached()
        }
        let count = try TestAdmin.query("SELECT count(*) FROM modifications WHERE requested_by_user_id = '\(user)'")
        #expect(count == "2", "One submit, one modification: \(count)")
      }
    } catch {
      remove()
      try await contributor.remove(after: error)
    }
    remove()
    try await contributor.remove()
  }

  /// A bibliographic madrigal's Modify page is its record as its own page
  /// draws it, open to correction: the work's fields, the Testaments tree,
  /// its reader and its whole document, `current_tei.xml`. One submit is one
  /// modification of the madrigal holding everything it changed; pages and
  /// the document together are refused; accepted, the fields and the
  /// document are written into the madrigal.
  @Test(arguments: [BrowserEngine.chrome])
  func aBibliographicMadrigalsSuggestionIsOneModification(engine: BrowserEngine) async throws {
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
      // One page, and a header a person fixes without rerunning it; the
      // digitization's required provider.
      _ = try TestAdmin.query(
        #"""
        UPDATE bibliographic_madrigals SET
          metadata_json = (metadata_json::jsonb || '{"provider":"folger_shakespeare_library"}'::jsonb)::text,
          proposed_content_json = '{"teiXml":"<TEI><teiHeader><date>exact 1910</date></teiHeader><text><body><pb n=\"1\" facs=\"https://web-tests.invalid/iiif/p1/full/1300,/0/default.jpg\"/><p>Old line</p></body></text></TEI>"}'
        WHERE id = '\#(commit.madrigalID)'
        """#)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(commit.madrigalPath)/modify")
        try await expect(page.locator(".testament-tree-diff-view")).toHaveCount(1)
        try await expect(page.locator(".tei-document-view textarea[name='document']")).toHaveCount(1)
        try await expect(page.locator(".tei-page-edit textarea")).toHaveCount(1)
        try await expect(page.locator("input[name='testament-levels']")).toBeAttached()
        try await page.expectNoHorizontalOverflow()

        // The work's title and the document's header, in one suggestion.
        try await page.locator("[data-modify-form] input[name='title']").first.fill("Web tests title")
        _ = try await page.evaluate(
          """
          (() => {
            const area = document.querySelector('textarea[name="document"]')
            area.value = area.value.replace('exact 1910', '1910')
            area.dispatchEvent(new Event('input', { bubbles: true }))
            return true
          })()
          """, as: Bool.self)
        try await page.locator(".modification-form button[type='submit']").click()
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("/mission-control/modifications/bibliographic?object=madrigal")
        let stored = try TestAdmin.query(
          """
          SELECT target || ' ' || (content_json IS NOT NULL)::text || ' ' || (document IS NOT NULL)::text
            || ' ' || (pages_json IS NULL)::text
          FROM modifications WHERE requested_by_user_id = '\(user)'
          """)
        #expect(stored == "object true true true", "One modification, fields and document: \(stored)")

        // A page and the document together are refused, plainly.
        try await page.openHydrated("\(commit.madrigalPath)/modify")
        try await page.locator("[data-modify-form] input[name='title']").first.fill("Web tests title")
        _ = try await page.evaluate(
          """
          (() => {
            const document_ = document.querySelector('textarea[name="document"]')
            document_.value = document_.value.replace('exact 1910', '1911')
            const page = document.querySelector('.tei-page-edit textarea')
            page.value = page.value.replace('Old line', 'New line')
            return true
          })()
          """, as: Bool.self)
        try await page.locator(".modification-form button[type='submit']").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("back to the page, with the reason") {
          $0.query?.contains("error=") == true
        }
        try await expect(page.getByText("Edit the document or its pages, not both, in one suggestion.").first)
          .toBeAttached()
        let count = try TestAdmin.query("SELECT count(*) FROM modifications WHERE requested_by_user_id = '\(user)'")
        #expect(count == "1", "Nothing refused is filed: \(count)")
      }
      let id = try TestAdmin.query("SELECT id FROM modifications WHERE requested_by_user_id = '\(user)'")
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated("\(commit.madrigalPath)/modifications/\(id)")
        try await expect(page.getByText("current_tei.xml").first).toBeAttached()
        _ = try await page.evaluate(
          "(() => { document.getElementById('modification-accept').submit(); return true })()", as: Bool.self)
        try await expect(page, timeout: .seconds(15)).toHaveURL("the madrigal's page") {
          $0.path.lowercased() == commit.madrigalPath.lowercased()
        }
      }
      let document = try TestAdmin.query(
        "SELECT proposed_content_json::json ->> 'teiXml' FROM bibliographic_madrigals WHERE id = '\(commit.madrigalID)'")
      #expect(document.contains("<date>1910</date>"), "Accepted, the document is the madrigal's: \(document)")
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
  /// change is one `object` modification an admin accepts—written into the
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
        "SELECT id FROM modifications WHERE requested_by_user_id = '\(user)' AND modifiable_type = 'lexicographicMadrigal' AND target = 'object' AND status = 'pending'")
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
        "SELECT id FROM modifications WHERE requested_by_user_id = '\(user)' AND modifiable_type = 'lexicographicEpilogue' AND target = 'object'")
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
