import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A lexico-record's amendment (user, 2026-10-21): `<record path>/amendments/new`
/// is the record's page in edit mode—its sentiments in the outline (each
/// row's handle, its fields, and at its foot its "− Sentiment", which a
/// dialog confirms and "+ Sentiment" undoes, as a testament's; no merge and
/// no split, user, 2026-10-22), a new sentiment under the tree founded on a
/// quote—and Submit files a lexicographic palinode, frozen (submitted: no
/// Revise, no Permit, no thread), and creates its overture (user,
/// 2026-10-22), whose page says what it removes, offers Revise, and for an
/// admin Permit. An amendment is about ONE sentiment (user, 2026-10-22), as
/// a biblio-record's is about one testament: the first change makes that
/// sentiment the amendment's and the others freeze, grey and inert, with
/// their handles disabled and a hint saying why; undone, they open again. A refused Submit
/// draws the form again with everything posted and why, never the error
/// page. Phone and desktop, nothing scrolling sideways. A throwaway admin
/// owns a scratch word, removed after with the overture it created (its
/// palinode, frozen, stays). Chrome
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
          (SELECT id FROM lexicographic_record_overtures WHERE lexico_record_id = '\(word.recordID.lowercased())');
        DELETE FROM lexicographic_record_overtures WHERE lexico_record_id = '\(word.recordID.lowercased())';
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
        // Its fields in its card's body: its value, as its TEI is edited,
        // and a dropdown for each usage axis.
        let fields = item.locator(".sentiment-fields-view[data-sentiment-id='s-1-1']")
        try await expect(fields).toHaveCount(1)
        try await expect(fields.locator(".sense-editor-view")).toHaveCount(1)
        for axis in ["grammar", "register", "domain", "region", "currency"] {
          try await expect(fields.locator(".dropdown-view:has([name$='-\(axis)'])")).toHaveCount(1)
        }
        // Its removal is the house control, never a checkbox: the icon and
        // the noun, "− Sentiment", the words for assistive technology.
        try await expect(leaf.locator("input[type='checkbox']")).toHaveCount(0)
        let remove = leaf.locator(".sentiment-outliner-remove")
        let restore = leaf.locator(".sentiment-outliner-restore")
        try await expect(remove).toHaveText("Sentiment 1.1.")
        try await expect(remove).toHaveAttribute("aria-label", "Remove Sentiment 1.1.")
        try await expect(restore).toBeHidden()
        // Nothing changed yet: every sentiment is open, no hint shown, and
        // none is the amendment's.
        let branch = outline.locator(".outliner-item[data-outliner-id='s-1']")
        try await expect(branch).toHaveAttribute("data-sentiment-frozen", "false")
        try await expect(item).toHaveAttribute("data-sentiment-frozen", "false")
        try await expect(outline.locator(".sentiment-outliner-hint[data-visible='true']")).toHaveCount(0)
        try await expect(outline.locator("input[name='sentiment-chosen']")).toHaveValue("")
        // One new sentiment, its fields always drawn.
        try await expect(form.locator("[name='new-sentiment-value']")).toHaveCount(1)
        try await expect(form.locator("[name='new-sentiment-source-url']")).toHaveCount(1)
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()

        // Cancelled: nothing removed.
        try await remove.click()
        try await expect(dialog).toHaveAttribute("open")
        try await dialog.locator("button").filter(hasText: "Cancel").first.click()
        try await expect(dialog).not.toHaveAttribute("open")
        try await expect(item).not.toHaveAttribute("data-outliner-removed", "true")

        // Removed in place, out of the tree it posts; "+ Sentiment" puts
        // it back.
        try await remove.click()
        try await dialog.locator("button").filter(hasText: "Remove").first.click()
        try await expect(item).toHaveAttribute("data-outline-state", "removed")
        try await expect(leaf.locator("input[name$='-remove']")).toHaveValue("true")
        let shape = try await outline.locator("input[name='sentiment-shape']").inputValue()
        #expect(!shape.contains("\"s-1-1\""), "\(shape)")
        // The removed sentiment is the amendment's one: it is chosen, the
        // others freeze (their fields, removal and handle
        // stop, the new sentiment's fields too) and the hint says why.
        try await expect(item).toHaveAttribute("data-sentiment-chosen", "true")
        try await expect(outline.locator("input[name='sentiment-chosen']")).toHaveValue("s-1-1")
        try await expect(branch).toHaveAttribute("data-sentiment-frozen", "true")
        try await expect(branch.locator(".outliner-handle").first).toBeDisabled()
        try await expect(outline.locator(".sentiment-outliner-hint[data-hint='edit']")).toHaveAttribute(
          "data-visible", "true")
        try await expect(form.locator(".submit-lexicographic-amendment-new")).toHaveAttribute("inert", "")
        try await expect(restore).toBeVisible()
        try await expect(restore).toHaveText("Sentiment 1.1.")
        try await expect(restore).toHaveAttribute("aria-label", "Restore Sentiment 1.1.")
        try await expect(remove).toBeHidden()
        try await restore.click()
        try await expect(item).not.toHaveAttribute("data-outline-state", "removed")
        try await expect(leaf.locator("input[name$='-remove']")).toHaveValue("")
        try await expect(remove).toBeVisible()
        // Undone, every sentiment is open again.
        try await expect(branch).toHaveAttribute("data-sentiment-frozen", "false")
        try await expect(form.locator(".submit-lexicographic-amendment-new")).not.toHaveAttribute("inert", "")

        // The leaf removed, Submit: its overture's page.
        try await remove.click()
        try await dialog.locator("button").filter(hasText: "Remove").first.click()
        try await expect(item).toHaveAttribute("data-outline-state", "removed")
        try await form.locator(".record-actions button[type='submit']").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the overture's page") {
          $0.path.hasPrefix("/mission-control/overtures/lexicographic/amendments/")
        }
        try await expect(page.locator("h1").first).toContainText("Lexicographic Overture")
        try await expect(page.locator(".lexicographic-record-overture-work")).toContainText("Removed")
        // Anyone signed in revises it; an admin permits it.
        try await expect(page.locator("a").filter(hasText: "Revise").first).toBeVisible()
        try await expect(page.locator("button").filter(hasText: "Permit").first).toBeVisible()
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()

        // The palinode its Pedigree names is frozen: submitted, with no
        // Revise, no Permit and no thread.
        try await page.locator("a[href^='/mission-control/palinodes/lexicographic/']").first.click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the palinode's page") {
          $0.path.hasPrefix("/mission-control/palinodes/lexicographic/")
        }
        try await expect(page.locator("h1").first).toContainText("Lexicographic Palinode")
        try await expect(page.locator(".submitted-notice")).toContainText("This palinode has been submitted creating overture")
        try await expect(page.locator("a").filter(hasText: "Revise")).toHaveCount(0)
        try await expect(page.locator("button").filter(hasText: "Permit")).toHaveCount(0)
        try await page.expectNoErrors()
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
  /// value and quote as typed, the removed sentiment still removed
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
          (SELECT id FROM lexicographic_record_overtures WHERE lexico_record_id = '\(record)');
        DELETE FROM lexicographic_record_overtures WHERE lexico_record_id = '\(record)';
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
        let value = form.locator("textarea[name='new-sentiment-value']")
        let quote = form.locator("textarea[name='new-sentiment-quote']")

        // A new sentiment with its quote but no image nor Source URL: it is
        // the amendment's one sentiment, and the others freeze.
        try await value.fill("A slope beside water.")
        try await quote.fill("upon the bank, \"where the wild thyme\" grows")
        try await expect(item).toHaveAttribute("data-sentiment-frozen", "true")
        try await expect(outline.locator(".sentiment-outliner-hint[data-hint='add']")).toHaveAttribute(
          "data-visible", "true")
        try await expect(leaf.locator(".sentiment-outliner-actions")).toHaveAttribute("inert", "")
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
        try await expect(value).toHaveValue("A slope beside water.")
        try await expect(quote).toHaveValue("upon the bank, \"where the wild thyme\" grows")
        try await expect(leaf.locator("input[name$='-remove']")).toHaveValue("")
        try await expect(item).toHaveAttribute("data-sentiment-frozen", "true")
        let filed = try TestAdmin.query(
          "SELECT count(*) FROM lexicographic_palinodes WHERE lexico_record_id = '\(record)'")
        #expect(filed.trimmingCharacters(in: .whitespacesAndNewlines) == "0", "nothing refused is filed")
        try await page.expectNoErrors(ignoring: ["status of 422"])
        try await page.expectNoHorizontalOverflow()

        // Corrected—the new sentiment left out, so every sentiment is open
        // again, and a leaf removed instead—it files.
        try await value.fill("")
        try await quote.fill("")
        try await expect(item).toHaveAttribute("data-sentiment-frozen", "false")
        try await leaf.locator(".sentiment-outliner-remove").click()
        try await dialog.locator("button").filter(hasText: "Remove").first.click()
        try await expect(item).toHaveAttribute("data-outline-state", "removed")
        try await page.locator("form.submit-lexicographic-amendment-form .record-actions button[type='submit']").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the overture's page") {
          $0.path.hasPrefix("/mission-control/overtures/lexicographic/amendments/")
        }
        try await expect(page.locator(".lexicographic-record-overture-work")).toContainText("Removed")
      }
    } catch {
      try await clean()
      throw error
    }
    try await clean()
  }

  /// Signed out, the amendment page asks for a sign-in, as the
  /// biblio-record's does.
  /// The form is open to a reader who is signed out (user, 2026-10-22): they
  /// fill it in, its Submit posts nothing and says signing in is needed with
  /// a link that opens in a new tab, what they typed is kept in
  /// `localStorage`, and once they sign in in another tab the page lets
  /// Submit through when they return to it, no reload. `/auth/status` says
  /// only whether the session is signed in.
  @Test(arguments: [BrowserEngine.chrome])
  func theAmendmentFormIsOpenToASignedOutReaderWhoSignsInElsewhere(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    defer { word.remove() }
    try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine)) { page in
      let result = try await page.goto("\(word.path)/amendments/new")
      #expect(result.status == 200, "signed out: \(String(describing: result.status))")
      try await page.openHydrated("\(word.path)/amendments/new")
      try await expect(page.locator("form.submit-lexicographic-amendment-form")).toHaveCount(1)
      let status = try await page.evaluate(
        "fetch('/auth/status').then(async (r) => r.headers.get('cache-control') + ' ' + (await r.text()))")
      #expect(status.string == "no-store {\"signedIn\":false}", "status: \(String(describing: status.string))")
      // Typed in, kept.
      _ = try await page.evaluate(
        """
        (() => {
          const field = document.querySelector("main input[name][type='text'], main textarea[name]");
          field.value = 'kept';
          field.dispatchEvent(new Event('input', { bubbles: true }));
        })()
        """)
      try await Task.sleep(for: .milliseconds(800))
      let kept = try await page.evaluate("localStorage.getItem('gnorium:draft:' + location.pathname)")
      #expect(kept.string?.contains("kept") == true, "the draft is kept")
      // Submit posts nothing: the alert says so, with a link to a new tab.
      let gate = page.locator(".action-gate-view .action-gate-alert[data-gate-sign-in='true']")
      try await expect(gate).toBeHidden()
      try await page.locator(".action-gate-view button[type='submit']").click()
      try await expect(gate).toBeVisible()
      try await expect(gate.locator("a")).toHaveAttribute("target", "_blank")
      try await expect(gate.locator("a")).toHaveAttribute("rel", "noopener")
      let href = try await gate.locator("a").getAttribute("href")
      #expect(href?.hasPrefix("/auth/sign-in?next=") == true, "sign-in comes back here: \(String(describing: href))")
      #expect(URL(string: try await page.url())?.path == "\(word.path)/amendments/new")
      // Signed in in another tab: back on this one, the notice goes.
      try await page.setCookie(name: admin.cookie.name, value: admin.cookie.value)
      _ = try await page.evaluate("window.dispatchEvent(new Event('focus'))")
      try await expect(gate).toHaveCount(0)
    }
    try await admin.remove()
  }
}
