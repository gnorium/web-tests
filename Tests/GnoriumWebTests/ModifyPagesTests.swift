import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Notations and epilogues, both kinds, are modified as overtures are
/// (user, 2026-10-07): while one awaits its verdict, its page offers Modify
/// to anyone signed in, and its Modify page carries the Prompts of the
/// process its next run takes—Explication on a notation, Translation on an
/// epilogue, of its own kind. A prompt change suggested there is a `prompt`
/// modification of the object, listed on the kind's Modifications. All of
/// it under a throwaway contributor's account; Chrome, desktop.
@Suite("Modify pages", .serialized)
struct ModifyPagesTests {
  @Test(arguments: [BrowserEngine.chrome])
  func notationsAndEpiloguesOfBothKindsOfferTheirProcesssPrompts(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let user = try contributor.column("id")
    let commit = try ScratchCommit(owner: contributor)
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
      commit.remove()
      word.remove()
    }
    do {
      _ = try TestAdmin.query(
        """
        INSERT INTO lexicographic_epilogues (id, lexico_record_id, lexico_record_version_id, sentiment_id, definition,
            target, status, submitted_by_user_id, summary)
          VALUES ('\(epilogue)', '\(word.recordID.lowercased())', '\(word.versionID.lowercased())', 's-1-1',
            'A leaf sense.', 'definition', 'proposed', (SELECT id FROM users WHERE username = 'gnorium'), 'Web tests.');
        """)
      let objects: [(path: String, slot: String, title: String, fields: Bool)] = [
        (commit.notationPath, "bibliographic_explication", "Prompts: Explication", true),
        ("/mission-control/notations/lexicographic/\(word.notationID)", "lexicographic_explication",
         "Prompts: Explication", true),
        ("/mission-control/epilogues/lexicographic/\(epilogue)", "lexicographic_translation", "Prompts: Translation", false),
      ]
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        for object in objects {
          try await page.openHydrated(object.path)
          let modify = page.locator("a[href$='/modify']")
          try await expect(modify).toHaveCount(1)
          try await expect(modify).toHaveText("Modify")
          try await page.openHydrated("\(object.path)/modify")
          try await expect(page.locator("form[data-modify-form] input[name='promptSlot']"))
            .toHaveAttribute("value", object.slot)
          try await expect(page.getByText(object.title)).toBeAttached()
          try await expect(page.locator("input[name='title']")).toHaveCount(object.fields ? 1 : 0)
          try await page.expectNoHorizontalOverflow()
        }

        // A prompt change suggested from each lexicographic object's page.
        for (object, kind) in [("notation", objects[1]), ("epilogue", objects[2])] {
          try await page.openHydrated("\(kind.path)/modify")
          _ = try await page.evaluate(
            """
            (() => {
              const system = document.querySelector('form[data-modify-form] textarea[name="promptSystem"]')
              system.value = system.value + '\\nWeb tests suggestion.'
              document.querySelector('form[data-modify-form]').submit()
              return true
            })()
            """, as: Bool.self)
          try await expect(page, timeout: .seconds(15))
            .toHaveURL("/mission-control/modifications/lexicographic?object=\(object)")
          try await expect(page.locator("a[href*='/\(object)s/lexicographic/'][href*='/modifications/']").first)
            .toBeAttached()
          let stored = try TestAdmin.query(
            "SELECT modifiable_type || ' ' || target || ' ' || status FROM modifications WHERE requested_by_user_id = '\(user)' AND modifiable_type = 'lexicographic\(object.capitalized)'")
          #expect(stored == "lexicographic\(object.capitalized) prompt pending", "stored: \(stored)")
        }
        // The suggestion's own page: the prompts before and after.
        let id = try TestAdmin.query(
          "SELECT id FROM modifications WHERE requested_by_user_id = '\(user)' AND modifiable_type = 'lexicographicEpilogue'")
        try await page.openHydrated("/mission-control/epilogues/lexicographic/\(epilogue)/modifications/\(id)")
        try await expect(page.getByText("Web tests suggestion.").first).toBeAttached()
      }
    } catch {
      remove()
      try await contributor.remove(after: error)
    }
    remove()
    try await contributor.remove()
  }

  /// A lexicographic notation's Modify page offers what a bibliographic
  /// one's does, in parallel (user, 2026-10-07): its record's identity and
  /// each sentiment's definition and labels. A change is a `form`
  /// modification an admin accepts—written into the notation—and reverts.
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
        "SELECT proposed_content_json FROM lexicographic_notations WHERE id = '\(word.notationID.lowercased())'")
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
      let notationPath = "/mission-control/notations/lexicographic/\(word.notationID)"
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(notationPath)/modify")
        // Every sentiment's fields, under its number.
        try await expect(page.locator("textarea[name='sentiment-0-definition']")).toHaveValue("A branch sense.")
        try await expect(page.locator("textarea[name='sentiment-1-definition']")).toHaveValue("A leaf sense.")
        try await expect(page.locator("input[name='sentiment-1-labels-json']")).toBeAttached()
        try await page.expectNoHorizontalOverflow()
        let leaf = page.locator("textarea[name='sentiment-1-definition']")
        try await leaf.fill("A leaf sense, as a person reads it.")
        // Its diff is drawn as it is made, as a bibliographic field's is.
        try await expect(page.locator("[data-diff-annotation][data-visible='true']").first).toBeAttached()
        try await page.locator("form[data-modify-form] button[type='submit']").click()
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("/mission-control/modifications/lexicographic?object=notation")
      }
      let id = try TestAdmin.query(
        "SELECT id FROM modifications WHERE requested_by_user_id = '\(user)' AND modifiable_type = 'lexicographicNotation' AND target = 'form' AND status = 'pending'")
      #expect(!id.isEmpty, "A form modification of the notation is filed")
      #expect(try content().contains("A leaf sense.\""), "The notation stands until it is accepted")

      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        let modificationPath = "\(notationPath)/modifications/\(id.uppercased())"
        try await page.openHydrated(modificationPath)
        try await expect(page.getByText("Sentiment 1.1").first).toBeAttached()
        try await expect(page.locator(".diff-view").first).toBeAttached()
        _ = try await page.evaluate("(() => { document.getElementById('modification-accept').submit(); return true })()", as: Bool.self)
        try await expect(page, timeout: .seconds(15))
          .toHaveURL("/mission-control/modifications/lexicographic?object=notation")
        #expect(try content().contains("A leaf sense, as a person reads it."), "Accepted, it is written into the notation")
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
        try await page.locator("form[data-modify-form] button[type='submit']").click()
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
