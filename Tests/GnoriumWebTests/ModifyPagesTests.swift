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
            'A leaf sense.', 'translations', 'proposed', (SELECT id FROM users WHERE username = 'gnorium'), 'Web tests.');
        """)
      let objects: [(path: String, slot: String, title: String, fields: Bool)] = [
        (commit.notationPath, "bibliographic_explication", "Prompts: Explication", true),
        ("/mission-control/notations/lexicographic/\(word.notationID)", "lexicographic_explication",
         "Prompts: Explication", true),
        ("/mission-control/epilogues/lexicographic/\(epilogue)", "equivalents", "Prompts: Translation", false),
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
}
