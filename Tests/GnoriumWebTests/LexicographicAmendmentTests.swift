import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A lexico-record's amendment (user, 2026-10-21): `<record path>/amendments/new`
/// is the record's page in edit mode—its sentiments in the outline (each
/// row's handle and its fields; the tree's one row of steppers after it,
/// "‹ − Sentiment 1.1. ›", which a dialog confirms and the same button,
/// "+ Sentiment 1.1.", undoes, as a testament's, user 2026-11-03; no merge
/// and no split, user, 2026-10-22), a new sentiment a draft row in the
/// tree, placed by "‹ + Sentiment 1.2. ›" and founded on a quote (user,
/// 2026-11-02)—and Submit files a lexicographic palinode, frozen (submitted: no
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
        // the tree's one row of steppers after it.
        let form = page.locator("form.submit-lexicographic-amendment-form")
        try await expect(form).toHaveCount(1)
        try await expect(form.locator(".form-header-view")).toContainText("Submit Amendment")
        let outline = form.locator(".sentiment-outliner-view")
        try await expect(outline.locator("input[name='sentiment-shape']")).toHaveCount(1)
        let leaf = outline.locator(".sentiment-outliner-removal[data-sentiment-id='s-1-1']")
        let item = outline.locator(".outliner-item[data-outliner-id='s-1-1']")
        let dialog = page.locator(".sentiment-outliner-remove-dialog")
        try await expect(leaf).toHaveCount(1)
        // Its value is its heading's one box and its notes its Note box;
        // no `<sense>` editor (user, 2026-11-02). Its fields in its card's
        // body: a dropdown for each usage axis.
        let fields = item.locator(".sentiment-fields-view[data-sentiment-id='s-1-1']")
        try await expect(fields).toHaveCount(1)
        try await expect(item.locator(".sense-editor-view")).toHaveCount(0)
        let valueBox = item.locator(".record-node-heading textarea[name$='-value']").first
        try await expect(valueBox).toBeEnabled()
        try await expect(item.locator("textarea[name$='-note']").first).toBeAttached()
        for axis in ["grammar", "register", "domain", "region", "currency"] {
          try await expect(fields.locator(".dropdown-view:has([name$='-\(axis)'])")).toHaveCount(1)
        }
        // Its removal is the house control, never a checkbox: the tree's
        // "− Sentiment 1.1.", the icon and the noun, the words for
        // assistive technology; no sentiment has controls of its own.
        try await expect(leaf.locator("input[type='checkbox']")).toHaveCount(0)
        try await expect(outline.locator(".sentiment-outliner-controls")).toHaveCount(0)
        let steps = TreeStepper(page, tree: "sentiment-outline")
        #expect(try await steps.choose("remove", "Remove sentiment 1.1."))
        try await expect(steps.removeButton).toHaveText("Sentiment 1.1.")
        try await expect(steps.removeButton.locator("svg.minus-icon-view")).toHaveCount(1)
        // Nothing changed yet: every sentiment is open, no hint shown, and
        // none is the amendment's.
        let branch = outline.locator(".outliner-item[data-outliner-id='s-1']")
        try await expect(branch).toHaveAttribute("data-sentiment-frozen", "false")
        try await expect(item).toHaveAttribute("data-sentiment-frozen", "false")
        try await expect(outline.locator(".sentiment-outliner-hint[data-visible='true']")).toHaveCount(0)
        try await expect(outline.locator("input[name='sentiment-chosen']")).toHaveValue("")
        // One new sentiment, a draft row out of the tree until the tree's
        // "+ Sentiment" places it (user, 2026-11-03), its fields drawn with
        // it: its value in its heading, its Note, its Source box; no
        // "Under" dropdown, no section of its own.
        let draft = outline.locator(".outliner-item[data-outliner-id='new']")
        try await expect(draft).toHaveAttribute("data-outliner-removed", "true")
        try await expect(draft).toBeHidden()
        // "+ Sentiment" steps through every place: under the first, after
        // its sentiment ("1.2."), after it ("2.").
        let places = try await steps.choices("add")
        #expect(places.contains("Add sentiment 1.2.") && places.contains("Add sentiment 2."), "\(places)")
        try await expect(draft.locator(".record-node-heading [name='new-sentiment-value']")).toHaveCount(1)
        try await expect(draft.locator("[name='new-sentiment-note']")).toHaveCount(1)
        try await expect(draft.locator("[name='new-sentiment-quote-s1-source-url']")).toHaveCount(1)
        try await expect(form.locator("[name='new-sentiment-parent']")).toHaveCount(0)
        try await expect(form.locator(".submit-lexicographic-amendment-new")).toHaveCount(0)
        try await page.expectNoErrors()

        // The value edited in its box: the XML switch shows the `<sense>`
        // as it will be filed, read-only; undone, every sentiment is open.
        let original = try await valueBox.inputValue()
        try await valueBox.fill("A riverside, amended.")
        try await expect(item).toHaveAttribute("data-sentiment-chosen", "true")
        try await expect(draft).toHaveAttribute("data-sentiment-frozen", "true")
        try await form.locator(".apparatus-rule-xml-toggle").click()
        let xml = item.locator(".sentiment-value-xml .code-code").first
        try await expect(xml).toBeVisible()
        try await expect(xml).toContainText("<def>A riverside, amended.</def>")
        try await expect(xml).not.toHaveAttribute("contenteditable", "plaintext-only")
        try await expect(valueBox).toBeHidden()
        try await form.locator(".apparatus-rule-xml-toggle").click()
        try await expect(valueBox).toBeVisible()
        try await valueBox.fill(original)
        try await expect(draft).toHaveAttribute("data-sentiment-frozen", "false")
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()

        // Cancelled: nothing removed.
        try await steps.remove("Remove sentiment 1.1.")
        try await expect(dialog).toHaveAttribute("open")
        try await dialog.locator("button").filter(hasText: "Cancel").first.click()
        try await expect(dialog).not.toHaveAttribute("open")
        try await expect(item).not.toHaveAttribute("data-outliner-removed", "true")

        // Removed in place, out of the tree it posts; "+ Sentiment" puts
        // it back.
        try await steps.remove("Remove sentiment 1.1.")
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
        try await expect(draft).toHaveAttribute("data-sentiment-frozen", "true")
        try await expect(draft.locator(":scope > .outliner-row")).toHaveAttribute("inert", "")
        try await expect(steps.removeButton).toHaveText("Sentiment 1.1.")
        try await expect(steps.removeButton).toHaveAttribute("aria-label", "Restore sentiment 1.1.")
        try await expect(steps.removeButton.locator("svg.plus-icon-view")).toHaveCount(1)
        try await steps.remove("Restore sentiment 1.1.")
        try await expect(item).not.toHaveAttribute("data-outline-state", "removed")
        try await expect(leaf.locator("input[name$='-remove']")).toHaveValue("")
        try await expect(steps.removeButton).toHaveAttribute("aria-label", "Remove sentiment 1.1.")
        // Undone, every sentiment is open again, and the new one may be
        // placed again.
        try await expect(branch).toHaveAttribute("data-sentiment-frozen", "false")
        try await expect(draft).toHaveAttribute("data-sentiment-frozen", "false")
        #expect(try await steps.choose("add", "Add sentiment 1.2."))

        // The leaf removed, Submit: its overture's page.
        try await steps.remove("Remove sentiment 1.1.")
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
        // Revise, no Permit and no thread. The Pedigree is closed by
        // default (a reader came for the object): opened first.
        let pedigree = page.locator(".pedigree-accordion")
        try await pedigree.locator(".accordion-summary").first.click()
        try await pedigree.locator("a[href^='/mission-control/palinodes/lexicographic/']").first.click()
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
        let leaf = outline.locator(".sentiment-outliner-removal[data-sentiment-id='s-1-1']")
        let item = outline.locator(".outliner-item[data-outliner-id='s-1-1']")
        let dialog = page.locator(".sentiment-outliner-remove-dialog")
        let value = form.locator("textarea[name='new-sentiment-value']")
        let quote = form.locator("input[name='new-sentiment-quote-s1-quote']")

        // A new sentiment placed under the first by the tree's "+ Sentiment
        // 1.2." (user, 2026-11-03), with its quote but no source nor image:
        // it is the amendment's one sentiment, and the others freeze.
        let steps = TreeStepper(page, tree: "sentiment-outline")
        try await steps.add("Add sentiment 1.2.")
        try await expect(outline.locator(".outliner-item[data-outliner-id='new']")).toBeVisible()
        try await value.fill("A slope beside water.")
        // Its sentence as its reader's text pane fills it (user, 2026-11-02).
        _ = try await quote.evaluate(
          """
          (input) => { input.value = 'upon the bank, "where the wild thyme" grows';
            input.dispatchEvent(new Event('input', { bubbles: true })); return true; }
          """)
        try await expect(item).toHaveAttribute("data-sentiment-frozen", "true")
        try await expect(outline.locator(".sentiment-outliner-hint[data-hint='add']")).toHaveAttribute(
          "data-visible", "true")
        // None other may go while it is in.
        #expect(!(try await steps.choices("remove")).contains("Remove sentiment 1.1."))
        // Placed under the first sentiment, its last, as the outline posts it.
        try await expect(outline.locator(".outliner-item[data-outliner-id='s-1'] .outliner-item[data-outliner-id='new']"))
          .toHaveCount(1)
        let placed = try await outline.locator("input[name='sentiment-shape']").inputValue()
        #expect(placed.contains("\"new\":{\"parent\":\"s-1\""), "\(placed)")
        try await form.locator(".record-actions button[type='submit']").click()

        // The form again, at the address it posts to, saying why above
        // Submit.
        let refusal = page.locator(".submit-lexicographic-amendment-refusal")
        // Its quote's source refused (its wording is the Source box's).
        try await expect(refusal, timeout: .seconds(15)).toContainText("Give the ")
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
        // Its row where the outline placed it.
        try await expect(
          page.locator(".outliner-item[data-outliner-id='s-1'] .outliner-item[data-outliner-id='new']")
        ).toHaveCount(1)
        let filed = try TestAdmin.query(
          "SELECT count(*) FROM lexicographic_palinodes WHERE lexico_record_id = '\(record)'")
        #expect(filed.trimmingCharacters(in: .whitespacesAndNewlines) == "0", "nothing refused is filed")
        // The refusal answers 422, as the console and the request log say it.
        try await page.expectNoErrors(ignoring: ["status of 422", "HTTP 422"])
        try await page.expectNoHorizontalOverflow()

        // Corrected—the new sentiment taken out again by "− Sentiment 1.2.",
        // so every sentiment is open again, and a leaf removed instead—it
        // files.
        try await steps.remove("Remove sentiment 1.2.")
        try await expect(outline.locator(".outliner-item[data-outliner-id='new']")).toBeHidden()
        try await expect(item).toHaveAttribute("data-sentiment-frozen", "false")
        try await steps.remove("Remove sentiment 1.1.")
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

  /// A sentiment an open palinode holds (user, 2026-11-01): on the next
  /// amendment form it is frozen and stays where it is, its removal
  /// disabled with the palinode's UUID linked in its tooltip, as a held
  /// testament's radio. A second palinode on it, posted anyway, is refused
  /// (the form drawn again) naming and linking the open one.
  @Test(arguments: [BrowserEngine.chrome])
  func aSentimentAnOpenPalinodeHoldsLinksItsPalinode(engine: BrowserEngine) async throws {
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
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        // The leaf removed and submitted: its palinode holds it.
        try await page.openHydrated("\(word.path)/amendments/new")
        let form = page.locator("form.submit-lexicographic-amendment-form")
        let steps = TreeStepper(page, tree: "sentiment-outline")
        try await steps.remove("Remove sentiment 1.1.")
        try await page.locator(".sentiment-outliner-remove-dialog button").filter(hasText: "Remove").first.click()
        try await form.locator(".record-actions button[type='submit']").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the overture's page") {
          $0.path.hasPrefix("/mission-control/overtures/lexicographic/amendments/")
        }

        // Drawn again: the held sentiment is frozen, its handle still, and
        // never one "− Sentiment" steps to.
        try await page.openHydrated("\(word.path)/amendments/new")
        let item = form.locator(".outliner-item[data-outliner-id='s-1-1']")
        try await expect(item).toHaveAttribute("data-sentiment-held", "true")
        try await expect(item).toHaveAttribute("data-sentiment-frozen", "true")
        try await expect(item.locator(".outliner-handle").first).toBeDisabled()
        #expect(!(try await steps.choices("remove")).contains("Remove sentiment 1.1."))
        let palinode = try TestAdmin.query(
          "SELECT id FROM lexicographic_palinodes WHERE lexico_record_id = '\(record)' ORDER BY created_at DESC LIMIT 1"
        ).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // The others stay open.
        try await expect(form.locator(".outliner-item[data-outliner-id='s-1']")).toHaveAttribute(
          "data-sentiment-frozen", "false")
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()

        // Posted anyway: refused, the form drawn again naming the palinode.
        let answer = try await page.evaluate(
          """
          (async () => {
            const form = document.querySelector('form.submit-lexicographic-amendment-form');
            const value = document.querySelector(".outliner-item[data-outliner-id='s-1-1'] [name$='-value']");
            const data = new FormData(form);
            data.set(value.name.replace(/-value$/, '-remove'), 'true');
            const response = await fetch(form.action, { method: 'POST', body: new URLSearchParams(data) });
            return response.status + ' ' + await response.text();
          })()
          """, as: String.self)
        #expect(answer.hasPrefix("422 "), "\(answer.prefix(80))")
        #expect(answer.contains("is held by open palinode \(palinode)"), "the refusal names the palinode")
      }
    } catch {
      try await clean()
      throw error
    }
    try await clean()
  }
}
