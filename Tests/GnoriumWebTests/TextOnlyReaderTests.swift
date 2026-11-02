import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A quote in a record with no source (a provisional quote, user
/// 2026-11-01) is read in the text-only reader, on its submission's page as
/// any quote is: its sentence the text, named by its page as printed (its
/// `<biblScope unit="page">`), and only what text alone needs—XML (the body
/// of the TEI its reader builds in memory, never a header: user, 2026-11-02)
/// and Reflow at the footer's start, fullscreen at its end, Find at the
/// header's end; no Header, Detach, Overlay, Image switch or pager.
@Suite("Text-only reader")
struct TextOnlyReaderTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aProvisionalQuoteReadsAsTextAlone(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let submission = UUID().uuidString.lowercased()
    let figurant = UUID().uuidString.lowercased()
    func remove() {
      _ = try? TestAdmin.query(
        """
        UPDATE lexicographic_figurants SET discarded_at = now(), discarded_by = '\(admin.username)'
          WHERE id = '\(figurant)' AND discarded_at IS NULL;
        """)
    }
    do {
      let user = try admin.column("id")
      // A submitted sentiment whose quote is provisional: in a record with
      // no source, located by its page as printed.
      let form = #"{"title":"webtestsprovisional","languageCode":"eng","class":"noun","origin":{"etymons":[],"citations":[],"derivation":""}}"#
      let sentiment =
        #"{"usage":{"domain":[],"region":[],"grammar":[],"register":[]},"value":"<sense><def>A web tests word</def></sense>","#
        + #""quotes":[{"text":"Hamlet, revenge.","pending":{"record":"\#(UUID().uuidString)","images":[],"pages":["sig. B2r"],"text":"Hamlet, revenge."}}]}"#
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO submissions (id, user_id) VALUES ('\(submission)', '\(user)');
        INSERT INTO lexicographic_figurants (id, batch_id, language, order_in_batch, processing_status,
          title_form_json, anchors_json, sentiment_json, created_at)
          VALUES ('\(figurant)', '\(submission)', 'eng', 0, 'pending', '\(form)', '[]', '\(sentiment)', now());
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/figurants/lexicographic/\(figurant)")
        let quote = page.locator(".attestation-view").first
        try await expect(quote, timeout: .seconds(15)).toBeAttached()
        _ = try await quote.evaluate("(el) => { el.scrollIntoView({ block: 'center' }); return true }")
        let viewer = quote.locator(".artifact-view")
        try await expect(viewer, timeout: .seconds(15)).toHaveCount(1)
        // The sentence is the text.
        try await expect(viewer.locator(".artifact-markup .tei-page-text").first).toHaveText("Hamlet, revenge.")
        // Named by its page as printed.
        try await expect(viewer.locator(".artifact-canvas-label"), timeout: .seconds(10)).toHaveText("sig. B2r")
        // XML, Reflow and fullscreen in the footer, Find in the header;
        // nothing else.
        let footer = viewer.locator(".artifact-footer")
        try await expect(footer.locator(".artifact-xml-toggle")).toHaveCount(1)
        try await expect(footer.locator(".artifact-reflow-toggle")).toHaveCount(1)
        try await expect(footer.locator(".artifact-fullscreen-button")).toHaveCount(1)
        for absent in [
          ".artifact-header-toggle", ".artifact-detach-toggle", ".artifact-overlay-toggle",
          ".artifact-page-nav", ".artifact-canvas-toggle", ".artifact-english-toggle",
        ] {
          try await expect(viewer.locator(absent)).toHaveCount(0)
        }
        let actions = try await viewer.locator(".artifact-header-actions").evaluate(
          "(a) => [...a.querySelectorAll('button')].filter((b) => b.getClientRects().length).length"
        ).int
        #expect(actions == 1, "Find alone at the header's end: \(String(describing: actions))")
        // A text pane: its lines as printed, one line each, never wrapped
        // until Reflow; zoomed by the wheel as any text pane is.
        let markup = viewer.locator(".artifact-markup")
        try await expect(markup.locator(".tei-line")).toHaveCount(1)
        let unwrapped = try await markup.locator(".tei-line").first.evaluate("(l) => getComputedStyle(l).whiteSpace").string ?? ""
        #expect(unwrapped.hasPrefix("nowrap") || unwrapped.hasPrefix("pre"), "a line as printed: \(unwrapped)")
        let zoom = """
          (m) => { const l = m.querySelector('.tei-line'); const z = [...m.querySelectorAll('[style*=zoom], [style*=transform]')].map((e) => e.className.split(' ')[0] + '=' + (e.style.zoom || '') + (e.style.transform || '')).join(';');
            return Math.round(l.getBoundingClientRect().width) + ' ' + z; }
          """
        let before = try await markup.evaluate(zoom).string ?? ""
        _ = try await markup.evaluate(
          """
          (m) => { const b = m.getBoundingClientRect();
            m.dispatchEvent(new WheelEvent('wheel', { deltaY: -400, ctrlKey: true, clientX: b.x + 20, clientY: b.y + 20, bubbles: true, cancelable: true }));
            return true; }
          """)
        try await Task.sleep(for: .milliseconds(600))
        let after = try await markup.evaluate(zoom).string ?? ""
        #expect(before != after, "the wheel zooms the text: \(before) → \(after)")
        try await footer.locator(".artifact-reflow-toggle button").click()
        try await expect(viewer).toHaveAttribute("data-reflow", "true")
        let wrapped = try await markup.locator(".tei-line").first.evaluate("(l) => getComputedStyle(l).whiteSpace").string ?? ""
        #expect(!wrapped.hasPrefix("nowrap"), "reflowed, it wraps: \(wrapped)")
        // XML: the sentence's page as the TEI in memory holds it, its body
        // alone, no header.
        try await footer.locator(".artifact-xml-toggle button").click()
        let code = markup.locator(".tei-page-raw .code-code").first
        try await expect(code, timeout: .seconds(5)).toBeVisible()
        try await expect(code).toContainText("<text><body>")
        try await expect(code).toContainText("<p>Hamlet, revenge.</p>")
        try await expect(code).toContainText("</body></text>")
        try await expect(code).not.toContainText("teiHeader")
        try await expect(markup.locator(".tei-page-text").first).toBeHidden()
        try await page.expectNoHorizontalOverflow()
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
