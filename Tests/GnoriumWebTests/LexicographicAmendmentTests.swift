import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A lexico-record's amendment (user, 2026-10-21): `<record path>/amendments/new`
/// is the record's page in edit mode—its sentiments in the outline (each
/// row's handle, its fields, and at its foot Merge into, a split's parts
/// and its "− Sentiment", which a dialog confirms and "+ Sentiment"
/// undoes, as a testament's), a new sentiment under the tree founded on a
/// quote—and Submit files a lexicographic palinode, whose page says what
/// it removes, offers Revise, and for an admin Permit. A refused Submit
/// draws the form again with everything posted and why, never the error
/// page. Phone and desktop, nothing scrolling sideways. A throwaway admin
/// owns a scratch word, removed after with the palinode it filed. Chrome
/// headless.
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
        let item = outline.locator(".outliner-item[data-outliner-id='s-1-1']")
        let dialog = page.locator(".sentiment-outliner-remove-dialog")
        try await expect(leaf).toHaveCount(1)
        try await expect(leaf.locator(".dropdown-view")).toHaveCount(1)
        try await expect(leaf.locator(".sense-editor-view")).toHaveCount(2)
        // Its removal is the house control, never a checkbox: the icon and
        // the noun, "− Sentiment", the words for assistive technology.
        try await expect(leaf.locator("input[type='checkbox']")).toHaveCount(0)
        let remove = leaf.locator(".sentiment-outliner-remove")
        let restore = leaf.locator(".sentiment-outliner-restore")
        try await expect(remove).toHaveText("Sentiment")
        try await expect(remove).toHaveAttribute("aria-label", "Remove Sentiment")
        try await expect(restore).toBeHidden()
        // One new sentiment, its fields always drawn.
        try await expect(form.locator("[name='new-sentiment-definition']")).toHaveCount(1)
        try await expect(form.locator("[name='new-sentiment-source-url']")).toHaveCount(1)
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()

        // Cancelled: nothing removed.
        try await remove.click()
        try await expect(dialog).toHaveAttribute("data-open", "true")
        try await dialog.locator(".dialog-default-button button").click()
        try await expect(dialog).toHaveAttribute("data-open", "false")
        try await expect(item).not.toHaveAttribute("data-outliner-removed", "true")

        // Removed in place, out of the tree it posts; "+ Sentiment" puts
        // it back.
        try await remove.click()
        try await dialog.locator(".dialog-primary-button button").click()
        try await expect(item).toHaveAttribute("data-outline-state", "removed")
        try await expect(leaf.locator("input[name$='-remove']")).toHaveValue("true")
        let shape = try await outline.locator("input[name='sentiment-shape']").inputValue()
        #expect(!shape.contains("\"s-1-1\""), "\(shape)")
        try await expect(restore).toBeVisible()
        try await expect(restore).toHaveText("Sentiment")
        try await expect(restore).toHaveAttribute("aria-label", "Restore Sentiment")
        try await expect(remove).toBeHidden()
        try await restore.click()
        try await expect(item).not.toHaveAttribute("data-outline-state", "removed")
        try await expect(leaf.locator("input[name$='-remove']")).toHaveValue("")
        try await expect(remove).toBeVisible()

        // The leaf removed, Submit: its palinode's page.
        try await remove.click()
        try await dialog.locator(".dialog-primary-button button").click()
        try await expect(item).toHaveAttribute("data-outline-state", "removed")
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

  /// A refused Submit—a new sentiment without the image its quote is on
  /// and its testament's Source URL—draws the form again (422), never the
  /// error page: why in one sentence above Submit, the new sentiment's
  /// definition and quote as typed, the removed sentiment still removed
  /// with "+ Sentiment" to restore it, and nothing filed. Corrected, it
  /// files.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aRefusedSubmitDrawsTheFormAgainWithEverythingPosted(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    let record = word.recordID.lowercased()
    func clean() async throws {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM locutions WHERE locutable_id IN
          (SELECT id FROM lexicographic_palinodes WHERE lexico_record_id = '\(record)');
        DELETE FROM lexicographic_palinodes WHERE lexico_record_id = '\(record)';
        COMMIT;
        """)
      word.remove()
      try await admin.remove()
    }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("\(word.path)/amendments/new")
        let form = page.locator("form.submit-lexicographic-amendment-form")
        let outline = form.locator(".sentiment-outliner-view")
        let leaf = outline.locator(".sentiment-outliner-controls[data-sentiment-id='s-1-1']")
        let item = outline.locator(".outliner-item[data-outliner-id='s-1-1']")
        let dialog = page.locator(".sentiment-outliner-remove-dialog")
        let definition = form.locator("textarea[name='new-sentiment-definition']")
        let quote = form.locator("textarea[name='new-sentiment-quote']")

        // The leaf removed, a new sentiment with its quote but no image
        // nor Source URL.
        try await leaf.locator(".sentiment-outliner-remove").click()
        try await dialog.locator(".dialog-primary-button button").click()
        try await expect(item).toHaveAttribute("data-outline-state", "removed")
        try await definition.fill("A slope beside water.")
        try await quote.fill("upon the bank, \"where the wild thyme\" grows")
        try await form.locator(".record-actions button[type='submit']").click()

        // The form again, at the address it posts to, saying why above
        // Submit.
        let refusal = page.locator(".submit-lexicographic-amendment-refusal")
        try await expect(refusal, timeout: .seconds(15)).toContainText(
          "Give the new sentiment's quote, the image it is on and its testament's Source URL.")
        try await expect(page).toHaveURL("the form, not the error page") { $0.path.hasSuffix("/amendments") }
        try await expect(page.locator("form.submit-lexicographic-amendment-form")).toHaveCount(1)
        let above = try await page.evaluate(
          """
          (() => {
            const alert = document.querySelector('.submit-lexicographic-amendment-refusal')
            const submit = document.querySelector('.record-actions button[type="submit"]')
            return alert.getBoundingClientRect().bottom <= submit.getBoundingClientRect().top
          })()
          """, as: Bool.self)
        #expect(above, "the refusal stands above Submit")
        // Everything as it was posted.
        try await expect(definition).toHaveValue("A slope beside water.")
        try await expect(quote).toHaveValue("upon the bank, \"where the wild thyme\" grows")
        try await expect(item).toHaveAttribute("data-outline-state", "removed")
        try await expect(leaf.locator("input[name$='-remove']")).toHaveValue("true")
        try await expect(leaf.locator(".sentiment-outliner-restore")).toBeVisible()
        let shape = try await outline.locator("input[name='sentiment-shape']").inputValue()
        #expect(!shape.contains("\"s-1-1\""), "\(shape)")
        let filed = try TestAdmin.query(
          "SELECT count(*) FROM lexicographic_palinodes WHERE lexico_record_id = '\(record)'")
        #expect(filed.trimmingCharacters(in: .whitespacesAndNewlines) == "0", "nothing refused is filed")
        try await page.expectNoErrors(ignoring: ["status of 422"])
        try await page.expectNoHorizontalOverflow()

        // Corrected—the new sentiment left out—it files.
        try await definition.fill("")
        try await quote.fill("")
        try await page.locator("form.submit-lexicographic-amendment-form .record-actions button[type='submit']").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the palinode's page") {
          $0.path.hasPrefix("/mission-control/palinodes/lexicographic/")
        }
        try await expect(page.locator(".lexicographic-palinode-work")).toContainText("Removed")
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
