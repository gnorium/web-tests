import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A lexico-record's amendment (user, 2026-10-21): `<record path>/amendments/new`
/// is the record's page in edit mode—its sentiments in the outline (each
/// row's handle, its fields, and at its foot Remove, Merge into and a
/// split's parts), a new sentiment under the tree founded on a quote—and
/// Submit files a lexicographic palinode, whose page says what it removes,
/// offers Revise, and for an admin Permit. Phone and desktop, nothing
/// scrolling sideways. A throwaway admin owns a scratch word, removed after
/// with the palinode it filed. Chrome headless.
@Suite("Lexicographic amendment", .serialized)
struct LexicographicAmendmentTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func anAmendmentIsFiledFromTheRecordsPageInEditMode(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    func clean() async throws {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM locutions WHERE locutable_id IN
          (SELECT id FROM lexicographic_palinodes WHERE lexico_record_id = '\(word.recordID.lowercased())');
        DELETE FROM lexicographic_palinodes WHERE lexico_record_id = '\(word.recordID.lowercased())';
        COMMIT;
        """)
      word.remove()
      try await admin.remove()
    }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("\(word.path)/amendments/new")
        // The record's page in edit mode: its sentiments in the outline,
        // each with its controls at its foot.
        let form = page.locator("form.submit-lexicographic-amendment-form")
        try await expect(form).toHaveCount(1)
        try await expect(form.locator(".form-header-view")).toContainText("Submit Amendment")
        let outline = form.locator(".sentiment-outliner-view")
        try await expect(outline.locator("input[name='sentiment-shape']")).toHaveCount(1)
        let leaf = outline.locator(".sentiment-outliner-controls[data-sentiment-id='s-1-1']")
        try await expect(leaf).toHaveCount(1)
        try await expect(leaf.locator("input[type='checkbox'][name$='-remove']")).toHaveCount(1)
        try await expect(leaf.locator(".dropdown-view")).toHaveCount(1)
        try await expect(leaf.locator(".sense-editor-view")).toHaveCount(2)
        // One new sentiment, its fields always drawn.
        try await expect(form.locator("[name='new-sentiment-definition']")).toHaveCount(1)
        try await expect(form.locator("[name='new-sentiment-source-url']")).toHaveCount(1)
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()

        // The leaf removed, Submit: its palinode's page.
        _ = try await leaf.locator("input[type='checkbox'][name$='-remove']").evaluate(
          "(box) => { box.checked = true; return true; }")
        try await form.locator(".record-actions button[type='submit']").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the palinode's page") {
          $0.path.hasPrefix("/mission-control/palinodes/lexicographic/")
        }
        try await expect(page.locator("h1").first).toContainText("Lexicographic Palinode")
        try await expect(page.locator(".lexicographic-palinode-work")).toContainText("Removed")
        // Anyone signed in revises it; an admin permits it.
        try await expect(page.locator("a").filter(hasText: "Revise").first).toBeVisible()
        try await expect(page.locator("button").filter(hasText: "Permit").first).toBeVisible()
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      try await clean()
      throw error
    }
    try await clean()
  }

  /// Signed out, the amendment page asks for a sign-in, as the
  /// biblio-record's does.
  @Test(arguments: [BrowserEngine.chrome])
  func theAmendmentPageIsASignedInReaders(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    defer { word.remove() }
    try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine)) { page in
      let result = try await page.goto("\(word.path)/amendments/new")
      #expect(result.status == 401, "signed out: \(String(describing: result.status))")
    }
    try await admin.remove()
  }
}
