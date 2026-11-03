import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A lexico-record's Pronunciation is a list, as Wiktionary's (user,
/// 2026-11-03): each row a card with its legend "Pronunciation", an Accent
/// dropdown and an IPA field (phonemic between slashes or phonetic between
/// square brackets, typed with the value), "+ Pronunciation" under the
/// list and "− Pronunciation" in each row while there is more than one, as
/// Voice rows are. Submit Sentiment offers one empty row; on the amendment
/// the rows post as the list's JSON, and the overture it files draws them
/// as read rows against what the record had. A throwaway admin owns a
/// scratch word, removed after with what it filed. Chrome headless.
@Suite("Pronunciation rows", .serialized)
struct PronunciationRowsTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func pronunciationsAreRowsAddedRemovedAndFiled(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    func clean() async throws {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM locutions WHERE locutable_id IN
          (SELECT id FROM lexicographic_record_overtures WHERE lexico_record_id = '\(word.recordID)');
        DELETE FROM lexicographic_record_overtures WHERE lexico_record_id = '\(word.recordID)';
        DELETE FROM lexicographic_palinodes WHERE lexico_record_id = '\(word.recordID)';
        COMMIT;
        """)
      word.remove()
      try await admin.remove()
    }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        // Submit Sentiment: one empty row, its fields their placeholders.
        try await page.openHydrated(SubmissionTests.sentimentForm)
        let offered = page.locator(".submit-sentiment-form [data-item-list='pronunciation']")
        let offeredRows = offered.locator(":scope > [data-item-section='true']")
        try await expect(offeredRows).toHaveCount(1)
        try await expect(offeredRows.first.locator(".form-item-legend")).toHaveText("Pronunciation")
        try await expect(offeredRows.first.locator(".dropdown-selected-text")).toHaveText("Accent")
        try await expect(offeredRows.first.locator("input[placeholder='IPA']")).toBeEnabled()
        try await expect(offered.locator("button[aria-label='Add Pronunciation']")).toBeVisible()
        try await page.expectNoErrors()

        // The amendment: rows typed, added and taken away.
        try await page.openHydrated("\(word.path)/amendments/new")
        let form = page.locator("form.submit-lexicographic-amendment-form")
        let list = form.locator("[data-item-list='pronunciation']")
        let rows = list.locator(":scope > [data-item-section='true']")
        let add = list.locator("button[aria-label='Add Pronunciation']")
        // In the record's Metadata, closed until opened.
        if !(try await add.isVisible()) {
          try await form.locator("#record-metadata .accordion-summary").first.click()
        }
        try await expect(add).toBeVisible()
        try await expect(rows).toHaveCount(1)
        try await expect(rows.first.locator("button[aria-label='Remove Pronunciation']")).toBeHidden()
        // Its Accent picked from the list, once the list stands open (it
        // scrolls its search field into view as it opens).
        let accent = rows.nth(0).locator(".dropdown-view")
        let rp = accent.locator(".dropdown-option[data-value='received_pronunciation']")
        for _ in 0..<3 {
          let shown = try await accent.locator(".dropdown-selected-text").textContent()
          if shown.trimmingCharacters(in: .whitespacesAndNewlines) == "Received Pronunciation" { break }
          if !(try await rp.isVisible()) { try await accent.locator(".dropdown-trigger").click() }
          try await expect(rp).toBeVisible()
          try await rp.click()
        }
        try await expect(accent.locator(".dropdown-selected-text")).toHaveText("Received Pronunciation")
        try await rows.nth(0).locator("input[name='pronunciation-item1-text-input']").fill("/ˈæŋkə/")
        try await add.click()
        try await expect(rows).toHaveCount(2)
        try await expect(rows.nth(1).locator(".form-item-legend")).toHaveText("Pronunciation")
        try await expect(rows.nth(0).locator("button[aria-label='Remove Pronunciation']")).toBeVisible()
        try await expect(rows.nth(1).locator("button[aria-label='Remove Pronunciation']")).toBeVisible()
        // Phonetic, no accent named.
        try await rows.nth(1).locator("input[name='pronunciation-item2-text-input']").fill("[ˈæŋkə]")
        try await add.click()
        try await expect(rows).toHaveCount(3)
        try await rows.nth(2).locator("button[aria-label='Remove Pronunciation']").click()
        try await expect(rows).toHaveCount(2)
        // The list's JSON, as it posts.
        let posted = try await list.locator("input[name='pronunciation-json']").inputValue()
        let filed = try JSONDecoder().decode([[String: String]].self, from: Data(posted.utf8))
        #expect(filed == [["role": "received_pronunciation", "value": "/ˈæŋkə/"], ["value": "[ˈæŋkə]"]], "\(posted)")
        try await page.expectNoHorizontalOverflow()

        // Submitted, its overture draws them as read rows, each added.
        try await form.locator(".record-actions button[type='submit']").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the overture's page") {
          $0.path.hasPrefix("/mission-control/overtures/lexicographic/amendments/")
        }
        let read = page.locator("[data-item-list='pronunciation']").first
        let readRows = read.locator(":scope > [data-item-section='true']")
        try await expect(readRows).toHaveCount(2)
        try await expect(readRows.nth(0).locator(".dropdown-selected-text")).toHaveText("Received Pronunciation")
        try await expect(readRows.nth(0).locator("input[name='pronunciation-item1-text-input']")).toHaveValue("/ˈæŋkə/")
        try await expect(readRows.nth(0).locator("input[name='pronunciation-item1-text-input']")).toBeDisabled()
        try await expect(readRows.nth(1).locator("input[name='pronunciation-item2-text-input']")).toHaveValue("[ˈæŋkə]")
        try await expect(read.locator(".diff-wrap-added").first).toBeAttached()
        try await expect(read.locator("button[aria-label='Remove Pronunciation']")).toHaveCount(0)
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      try await clean()
      throw error
    }
    try await clean()
  }
}
