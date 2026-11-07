import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A Note is one paragraph (user, 2026-11-05: "should limit note value to a
/// single line like a continuous string without newline … and show a single
/// line diff with edge fade"): its box wraps, but a line break pasted becomes
/// a space and Enter inserts nothing; its diff, live on Revise and saved on
/// the revision's page, is a field's one line, edge-faded, never a passage's
/// box; and the server refuses a Note posted with a line break, in one
/// sentence. A throwaway admin's scratch lexicographic overture, removed
/// after.
@Suite("Note paragraph", .serialized)
struct NoteParagraphTests {
  static let note = "Recorded first in the scratch tests."
  /// Long enough that its diff runs past its line at every layout.
  static let added =
    "Revised at length, so that its one line runs on past the edge of its field on a phone and on a desktop alike, and further still."
  static let refusal = "A note is one paragraph, with no line breaks."

  /// A diff's values on one line, never wrapped, faded where they run past
  /// it (`data-overflowing`), opened on a tap (`expand`).
  static func expectOneFadedLine(_ diff: Locator) async throws {
    let content = diff.locator(":scope > .diff-content")
    try await expect(content).toHaveAttribute("data-edge-fade-view", "expand")
    try await expect(content, timeout: .seconds(5)).toHaveAttribute("data-overflowing", "true")
    let line = try await content.evaluate(
      """
      (el) => { const s = getComputedStyle(el);
        const masked = (s.maskImage && s.maskImage !== 'none') || (s.webkitMaskImage && s.webkitMaskImage !== 'none');
        return s.whiteSpace === 'nowrap' && s.overflowX !== 'visible' && masked
          && el.getBoundingClientRect().height <= parseFloat(s.lineHeight) + 1; }
      """)
    #expect(line.bool == true, "the Note's diff is not one edge-faded line")
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aNoteIsOneParagraphAndItsDiffOneLine(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let title = "webtestsparagraph\(String(UUID().uuidString.prefix(8)).lowercased().filter(\.isLetter))"
    let figurants = "(SELECT id FROM lexicographic_figurants WHERE title_form_json::json ->> 'title' = '\(title)')"
    let overtures = "(SELECT id FROM lexicographic_overtures WHERE lexicographic_figurant_id IN \(figurants))"
    func clean() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM locutions WHERE locutable_type = 'lexicographic_overture' AND locutable_id IN \(overtures);
        DELETE FROM revisions WHERE revisable_id IN \(overtures);
        DELETE FROM lexicographic_overtures WHERE id IN \(overtures);
        UPDATE lexicographic_figurants SET discarded_at = now(), discarded_by = '\(admin.username)'
          WHERE id IN \(figurants) AND discarded_at IS NULL;
        COMMIT;
        """)
    }
    do {
      let user = try admin.column("id")
      let form = #"{"title":"\#(title)","languageCode":"eng","class":"noun","note":"\#(Self.note)","origin":{"etymons":[],"citations":[],"derivation":""}}"#
      let submission = UUID().uuidString
      let figurant = UUID().uuidString
      let id = UUID().uuidString
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO submissions (id, user_id) VALUES ('\(submission)', '\(user)');
        INSERT INTO lexicographic_figurants (id, batch_id, language, order_in_batch, processing_status,
          title_form_json, anchors_json, created_at)
          VALUES ('\(figurant)', '\(submission)', 'eng', 0, 'pending', '\(form)', '[]', now());
        INSERT INTO lexicographic_overtures (id, lexicographic_figurant_id, title_form_json, anchors_json, created_at)
          VALUES ('\(id)', '\(figurant)', '\(form)', '[]', now());
        COMMIT;
        """)
      let overture = "/mission-control/overtures/lexicographic/\(id)"
      let one = Self.note + " " + Self.added
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("\(overture)/revise")
        let note = page.locator("[data-revise-form] textarea[name='note']")
        try await expect(note).toBeEnabled()
        // A line break pasted is a space; Enter and Shift+Enter insert
        // nothing; the box still wraps.
        try await note.fill(Self.note + "\n" + Self.added)
        try await expect(note).toHaveValue(one)
        try await note.press("End")
        try await note.press("Enter")
        try await note.press("Shift+Enter")
        try await expect(note).toHaveValue(one)
        let wraps = try await note.evaluate("(el) => getComputedStyle(el).whiteSpace !== 'nowrap'")
        #expect(wraps.bool == true, "the Note's box does not wrap")
        // Its live diff: a field's one line, never a box.
        let live = page.locator(".field-diff-view:has(textarea[name='note']) > .field-diff-diff > .diff-view")
        try await expect(live).toHaveAttribute("data-shape", "line")
        try await expect(live).toHaveAttribute("data-diff-mode", "text")
        try await expect(page.locator(".note-field-view .diff-box")).toHaveCount(0)
        try await Self.expectOneFadedLine(live)
        try await page.expectNoErrors()

        // Suggested: the revision's page draws it saved, the same one line.
        try await page.locator("button[type='submit']").filter(hasText: "Suggest").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the overture at its locution") { url in
          url.path == overture && (url.fragment ?? "").hasPrefix("revision-")
        }
        let link = page.locator(".thread-event-changed a").filter(hasText: "Note")
        try await expect(link).toHaveCount(1)
        let target = try #require(try await link.evaluate("(el) => el.getAttribute('href')").string)
        try await page.openHydrated(target)
        try await expect(page.locator("textarea[name='note']")).toHaveValue(one)
        let saved = page.locator(".field-diff-view.diff-wrap-changed:has(textarea[name='note']) > .field-diff-diff > .diff-view")
        try await expect(saved).toHaveAttribute("data-shape", "line")
        try await expect(saved).toHaveAttribute("data-diff-mode", "text")
        try await expect(page.locator(".note-field-view .diff-box")).toHaveCount(0)
        try await Self.expectOneFadedLine(saved)
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()

        // Posted around the page with a line break: refused in one
        // sentence, the form drawn again.
        try await page.openHydrated("\(overture)/revise")
        try await expect(page.locator("[data-revise-form] textarea[name='note']")).toBeEnabled()
        let answer = try await page.evaluate(
          """
          (async () => {
            const form = document.querySelector('.revision-form-view form.revision-form');
            // Every control of the page joins the form as the page settles.
            const note = document.querySelector("[data-revise-form] textarea[name='note']");
            for (let i = 0; i < 50 && note.form !== form; i++) await new Promise((r) => setTimeout(r, 100));
            const data = new FormData(form);
            data.set('note', 'One line.\\nAnother line.');
            const response = await fetch(form.action, { method: 'POST', body: new URLSearchParams(data) });
            return response.status + ' ' + await response.text();
          })()
          """, as: String.self)
        #expect(answer.hasPrefix("422 "), "\(answer.prefix(80))")
        #expect(answer.contains(Self.refusal), "the refusal's sentence")
      }
    } catch {
      clean()
      try await admin.remove(after: error)
    }
    clean()
    try await admin.remove()
  }
}
