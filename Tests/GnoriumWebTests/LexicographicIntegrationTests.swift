import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Lexicographic calibration's Integration on the page (design-notes/lexico-pipeline.md D43, D47, D49): the
/// Watchtower's Calibration card's Integration opens its keys' page from its Lexicographic pending figure; the page
/// lists the keys waiting, each ticked alone or all at once, the form posting the ticked keys to Start, and the
/// passes; and a pass's page shows its key, its state and what it did. The key and the pass are seeded as their rows
/// (`lexicographic_integration_keys`, `lexicographic_integration_sessions`); the form is not submitted, so no pass is queued and no
/// model is called (the batch itself is the server suite's, `LexicographicIntegrationPagesTests`).
@Suite("Integration")
struct LexicographicIntegrationTests {
  @Test(arguments: [BrowserEngine.chrome])
  func theQueueIsTickedAndAPassIsRead(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let lemma = "webtestsintegration" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
    let pass = UUID()
    func remove() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        UPDATE lexicographic_integration_keys SET last_session_id = NULL WHERE lemma = '\(lemma)';
        DELETE FROM lexicographic_integration_sessions WHERE lemma = '\(lemma)';
        DELETE FROM lexicographic_integration_keys WHERE lemma = '\(lemma)';
        COMMIT;
        """)
    }
    do {
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO lexicographic_integration_keys (language_code, lemma, class, pending_units) VALUES ('eng', '\(lemma)', 'noun', 3);
        INSERT INTO lexicographic_integration_sessions
          (id, language_code, lemma, class, budget_tokens, provider, model, result, stopped, finished_at)
          VALUES ('\(pass.uuidString)', 'eng', '\(lemma)', 'verb', 1200, 'deepseek', 'deepseek-chat', 'passed',
            'queue_empty', now());
        COMMIT;
        """)
      try await withPage(engine, gnorium, cookies: [admin.cookie]) { page in
        // The Watchtower: no card of its own; the Calibration card's Integration opens the keys' page.
        let keysPath = "/mission-control/quatrains/lexicographic/integration"
        try await page.openHydrated("/")
        try await expect(page.locator(".lexicographic-integration-queue-view")).toHaveCount(0)
        let figure = page.locator(
          ".watchtower-process-view[data-integration='true'] .watchtower-process-figures a[href='\(keysPath)']")
        try await expect(figure, timeout: .seconds(15)).toHaveCount(1)
        try await expect(figure).toContainText("pending")
        try await page.expectNoErrors()

        // The keys' page: the key's row, ticked alone, then with all.
        try await page.openHydrated(keysPath)
        let card = page.locator(".lexicographic-integration-keys-view")
        try await expect(card, timeout: .seconds(15)).toHaveCount(1)
        let row = card.locator(".lexicographic-integration-keys-table tr").filter(hasText: lemma)
        try await expect(row).toHaveCount(1)
        try await expect(row).toContainText("English")
        try await expect(row).toContainText("Noun")
        let tick = card.locator("input[name='row-selection'][value='eng|noun|\(lemma)']")
        try await tick.check()
        try await expect(tick).toBeChecked()
        let posted = try await page.evaluate(
          "new URLSearchParams(new FormData(document.querySelector('.lexicographic-integration-keys-form'))).getAll('row-selection').join(',')"
        ).string
        #expect(posted?.split(separator: ",").contains(Substring("eng|noun|\(lemma)")) == true, "\(String(describing: posted))")
        try await card.locator(".lexicographic-integration-keys-form #select-all").check()
        let all = try await page.evaluate(
          "[...document.querySelectorAll('.lexicographic-integration-keys-form input[name=\"row-selection\"]')].every((i) => i.checked)"
        ).bool
        #expect(all == true, "Select all ticks every key")
        let form = card.locator(".lexicographic-integration-keys-form")
        try await expect(form).toHaveAttribute("action", keysPath)
        let start = form.locator("button[type='submit']")
        try await expect(start).toHaveText("Start")
        try await expect(start).toHaveAttribute("data-color", "blue")
        // Its passes, each opening its own page.
        let passed = card.locator(".lexicographic-integration-passes-table tr").filter(hasText: lemma)
        try await expect(passed).toHaveCount(1)
        try await expect(passed).toContainText("Integrated")
        try await page.expectNoErrors()

        // A pass's page: its state, its key, and what it did.
        try await page.openHydrated("\(keysPath)/\(pass.uuidString)")
        let view = page.locator(".lexicographic-integration-view")
        try await expect(view, timeout: .seconds(15)).toHaveCount(1)
        try await expect(view.locator(".computorium-core-title")).toHaveText("Integration Pass")
        try await expect(view.locator(".computorium-core-header-status-chip")).toContainText("Integrated")
        try await expect(view.locator(".lexicographic-integration-key")).toContainText(lemma)
        try await expect(view.locator(".lexicographic-integration-key")).toContainText("Queue empty")
        try await expect(view.locator(".lexicographic-integration-key")).toContainText("1,200 tokens")
        try await expect(view).toContainText("No quotes reviewed.")
        try await expect(view).toContainText("No sentiments submitted.")
        try await expect(view).toContainText("No removals submitted.")
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
