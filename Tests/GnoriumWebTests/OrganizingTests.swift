import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The organizing pass on the page (design-notes/lexico-pipeline.md D43, D47): the Watchtower's Organizing card lists
/// an admin the keys waiting, each ticked alone or all at once, the form posting the ticked keys to Start; and a
/// pass's page shows its key, its state and what it did. The key and the pass are seeded as their rows
/// (`organizing_keys`, `lexicographic_organizing_sessions`); the form is not submitted, so no pass is queued and no
/// model is called (the batch itself is the server suite's, `OrganizingPagesTests`).
@Suite("Organizing")
struct OrganizingTests {
  @Test(arguments: [BrowserEngine.chrome])
  func theQueueIsTickedAndAPassIsRead(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let lemma = "webtestsorganizing" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
    let pass = UUID()
    func remove() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        UPDATE organizing_keys SET last_session_id = NULL WHERE lemma = '\(lemma)';
        DELETE FROM lexicographic_organizing_sessions WHERE lemma = '\(lemma)';
        DELETE FROM organizing_keys WHERE lemma = '\(lemma)';
        COMMIT;
        """)
    }
    do {
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO organizing_keys (language_code, lemma, class, pending_units) VALUES ('eng', '\(lemma)', 'noun', 3);
        INSERT INTO lexicographic_organizing_sessions
          (id, language_code, lemma, class, budget_tokens, provider, model, result, stopped, finished_at)
          VALUES ('\(pass.uuidString)', 'eng', '\(lemma)', 'verb', 1200, 'deepseek', 'deepseek-chat', 'passed',
            'queue_empty', now());
        COMMIT;
        """)
      try await withPage(engine, gnorium, cookies: [admin.cookie]) { page in
        // The Watchtower's queue: the key's row, ticked alone, then with all.
        try await page.openHydrated("/")
        let card = page.locator(".organizing-queue-view")
        try await expect(card, timeout: .seconds(15)).toHaveCount(1)
        let row = card.locator("tr").filter(hasText: lemma)
        try await expect(row).toHaveCount(1)
        try await expect(row).toContainText("English")
        try await expect(row).toContainText("Noun")
        let tick = card.locator("input[name='row-selection'][value='eng|noun|\(lemma)']")
        try await tick.check()
        try await expect(tick).toBeChecked()
        let posted = try await page.evaluate(
          "new URLSearchParams(new FormData(document.querySelector('.organizing-queue-form'))).getAll('row-selection').join(',')"
        ).string
        #expect(posted?.split(separator: ",").contains(Substring("eng|noun|\(lemma)")) == true, "\(String(describing: posted))")
        try await card.locator("#select-all").check()
        let all = try await page.evaluate(
          "[...document.querySelectorAll('.organizing-queue-form input[name=\"row-selection\"]')].every((i) => i.checked)"
        ).bool
        #expect(all == true, "Select all ticks every key")
        let start = card.locator(".organizing-queue-form button[type='submit']")
        try await expect(start).toHaveText("Start")
        try await expect(start).toHaveAttribute("data-color", "blue")
        try await expect(card.locator("a[href='/mission-control/organizing/merges']")).toHaveCount(1)
        try await page.expectNoErrors()

        // A pass's page: its state, its key, and what it did.
        try await page.openHydrated("/mission-control/organizing/\(pass.uuidString)")
        let view = page.locator(".lexicographic-organizing-view")
        try await expect(view, timeout: .seconds(15)).toHaveCount(1)
        try await expect(view.locator(".computorium-core-title")).toHaveText("Organizing Pass")
        try await expect(view.locator(".computorium-core-header-status-chip")).toContainText("Organized")
        try await expect(view.locator(".lexicographic-organizing-key")).toContainText(lemma)
        try await expect(view.locator(".lexicographic-organizing-key")).toContainText("Queue empty")
        try await expect(view.locator(".lexicographic-organizing-key")).toContainText("1,200 tokens")
        try await expect(view).toContainText("No quotes reviewed.")
        try await expect(view).toContainText("No sentiments submitted.")
        try await expect(view).toContainText("No merges proposed.")
        try await page.expectNoErrors()
      }
    } catch {
      remove()
      try await admin.remove(after: error)
    }
    remove()
    try await admin.remove()
  }
}
