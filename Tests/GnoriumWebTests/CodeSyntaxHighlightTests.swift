import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Code is colored by its grammar's roles (user, 2026-10-12), one set of
/// CSS highlights across XML, Markdown and JSON: a madrigal's Raw TEI and a
/// locution's Raw, a session's prompts, reply and tool calls (their JSON,
/// and the markup a call sent). Each role's highlight holds the stretches
/// it names, painted over the text without writing into it.
/// CODE_SYNTAX_SHOTS=<dir> also saves each in the four schemes.
@Suite("Code syntax highlights", .serialized)
struct CodeSyntaxHighlightTests {
  /// Skeat's page 5, as read (design-notes/canvas-5-markup.xml), its own
  /// page break left out.
  static func skeat() throws -> String {
    let text = try String(
      contentsOfFile: "/Users/Madhavik/Downloads/Gnorium/design-notes/canvas-5-markup.xml", encoding: .utf8)
    return text.replacingOccurrences(of: #"<pb n="5"/>"#, with: "")
  }

  /// Every XML role but the page's own: a comment, a prefixed attribute, a
  /// value and text with references, CDATA and an instruction.
  static let snippet = """
    <!-- Every role, once. -->
    <p xml:id="p-roles" rend="R&amp;D">Skeat&#x2019;s &amp; <![CDATA[<raw> & text]]></p>
    """

  static let markdown = """
    # Skeat, page 5
    Read *closely*, **twice**, with `code` beside it; a snake_case name stays plain.
    - a [source](https://gnorium.com/sources/skeat) and ![page](/favicon.ico)
    1. first
    > quoted
    ---
    <!-- a note -->
    ```json
    {"page": 5, "ok": true}
    ```
    """

  /// Each highlight's stretches, by name.
  static let highlights = """
    (() => Object.fromEntries(['code-tag', 'code-name', 'code-attr', 'code-value', 'code-entity', 'code-prefix',
      'code-pi', 'code-cdata', 'code-comment'].map(n => [n, [...[...(CSS.highlights?.get(n) ?? [])].map((r => { const x = document.createRange(); x.setStart(r.startContainer, r.startOffset); x.setEnd(r.endContainer, r.endOffset); return x.toString() })), ...[...document.querySelectorAll('[data-code-kind=\"'+n+'\"]')].map(e => e.textContent)]])))()
    """

  static func stretches(_ page: Page) async throws -> [String: [String]] {
    let value = try await page.evaluate(highlights)
    guard case .object(let object) = value else { return [:] }
    return object.mapValues { $0.array?.compactMap(\.string) ?? [] }
  }

  /// Polls until `name` holds `text`.
  static func expectStretch(_ page: Page, _ name: String, _ text: String) async throws {
    for _ in 0..<40 {
      if try await stretches(page)[name]?.contains(text) == true { return }
      try await Task.sleep(for: .milliseconds(100))
    }
    let all = try await stretches(page)[name] ?? []
    Issue.record("\(name) holds no \(text): \(all.prefix(20))")
  }

  static func shots(_ page: Page, _ name: String) async throws {
    guard let directory = ProcessInfo.processInfo.environment["CODE_SYNTAX_SHOTS"] else { return }
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    for (scheme, contrast) in [("light", "less"), ("dark", "less"), ("light", "more"), ("dark", "more")] {
      _ = try await page.evaluate(
        "(() => { const r = document.documentElement; r.setAttribute('data-color-scheme', '\(scheme)'); r.setAttribute('data-contrast', '\(contrast)'); return 1 })()"
      )
      try await Task.sleep(for: .milliseconds(250))
      try await page.screenshot(
        to: URL(fileURLWithPath: directory).appendingPathComponent(
          "\(name)-\(scheme)\(contrast == "more" ? "-more" : "").png"))
    }
    _ = try await page.evaluate(
      "(() => { const r = document.documentElement; r.setAttribute('data-color-scheme', 'light'); r.setAttribute('data-contrast', 'less'); return 1 })()"
    )
  }

  static func sql(_ text: String) -> String { text.replacingOccurrences(of: "'", with: "''") }

  @Test(arguments: [BrowserEngine.chrome])
  func rawTEIAndALocutionsMarkdownAreColoredByRole(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor)
    let locution = UUID().uuidString.lowercased()
    func remove() {
      _ = try? TestAdmin.query("DELETE FROM locutions WHERE id = '\(locution)';")
      commit.remove()
    }
    do {
      let tei = """
        <TEI><text><body><pb n="1" facs="https://web-tests.invalid/iiif/p1/full/1300,/0/default.jpg"/>\(try Self.skeat())
        \(Self.snippet)</body></text></TEI>
        """
      let content = String(decoding: try JSONSerialization.data(withJSONObject: ["teiXml": tei]), as: UTF8.self)
      let user = try contributor.column("id")
      _ = try TestAdmin.query(
        """
        BEGIN;
        UPDATE bibliographic_madrigals SET proposed_content_json = '\(Self.sql(content))' WHERE id = '\(commit.madrigalID)';
        INSERT INTO locutions (id, locutable_type, locutable_id, author_id, content, created_at)
          VALUES ('\(locution)', 'bibliographic_madrigal', '\(commit.madrigalID)', '\(user)', '\(Self.sql(Self.markdown))', now());
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated(commit.madrigalPath)
        try await page.locator(".artifact-xml-toggle button").first.click()
        let code = page.locator(".tei-page-raw .code-code").first
        try await expect(code).toBeVisible()
        try await expect(code).toHaveAttribute("data-code-syntax", "xml")
        for (name, text) in [
          ("code-tag", "<"), ("code-tag", "/>"), ("code-name", "titlePage"), ("code-name", "w"),
          ("code-attr", "lemma"), ("code-prefix", "xml:"), ("code-attr", "id"), ("code-value", "\"bibl-3\""),
          ("code-entity", "&amp;"), ("code-entity", "&#x2019;"), ("code-comment", "<!-- Every role, once. -->"),
          ("code-cdata", "<![CDATA[<raw> & text]]>"),
        ] {
          try await Self.expectStretch(page, name, text)
        }
        // Painted over the text, never written into it.
        #expect(try await code.locator("[data-code-kind='code-name']").count() > 0, "Read-only XML is colored in its HTML without waiting for hydration")
        // Each role in its hue: the rule names the role's syntax token.
        #expect(
          try await page.evaluate(
            """
            (() => { const rules = [...document.styleSheets].flatMap(s => { try { return [...s.cssRules] } catch { return [] } })
              .map(r => r.cssText).join('\\n');
              return ['code-name) { color: var(--color-syntax-keywords)', 'code-attr) { color: var(--color-syntax-attributes)',
                'code-value) { color: var(--color-syntax-strings)', 'code-entity) { color: var(--color-syntax-characters)',
                'code-prefix) { color: var(--color-syntax-other-type-names)', 'code-pi) { color: var(--color-syntax-preprocessor-statements)',
                'code-cdata) { color: var(--color-syntax-other-constants)', 'code-comment) { color: var(--color-syntax-comments)']
                .every(t => rules.includes(t)) })()
            """, as: Bool.self))
        #expect(
          try await page.evaluate(
            """
            (() => { const s = getComputedStyle(document.documentElement), v = n => s.getPropertyValue(n).trim();
              return v('--color-syntax-keywords') === v('--glyph-magenta') && v('--color-syntax-attributes') === v('--glyph-cyan')
                && v('--color-syntax-strings') === v('--glyph-lime') && v('--color-syntax-characters') === v('--glyph-pink')
                && v('--color-syntax-other-type-names') === v('--glyph-indigo')
                && v('--color-syntax-preprocessor-statements') === v('--glyph-violet')
                && v('--color-syntax-other-constants') === v('--glyph-mint') && v('--color-syntax-comments') === v('--color-subtle') })()
            """, as: Bool.self), "Each role's token is its named hue")
        try await Self.shots(page, "raw-tei")
        // Its end: the snippet's comment, references and CDATA.
        _ = try await page.evaluate(
          "(() => { const p = document.querySelector('.artifact-markup'); p.scrollTop = p.scrollHeight; return 1 })()")
        try await Self.shots(page, "raw-tei-end")

        // A locution's Raw: its Markdown.
        let said = page.locator("#locution-\(locution.uppercased())")
        try await said.locator(".locution-markdown-toggle button").first.click()
        let raw = said.locator(".locution-body-raw")
        try await expect(raw).toBeVisible()
        try await expect(raw).toHaveAttribute("data-code-syntax", "markdown")
        for (name, text) in [
          ("code-name", "# Skeat, page 5"), ("code-pi", "*"), ("code-pi", "**"), ("code-cdata", "`code`"),
          ("code-prefix", "https://gnorium.com/sources/skeat"), ("code-prefix", "/favicon.ico"), ("code-entity", "-"),
          ("code-entity", "1."), ("code-entity", ">"), ("code-entity", "---"), ("code-comment", "<!-- a note -->"),
          ("code-cdata", "```json"), ("code-attr", "\"page\""), ("code-name", "true"),
        ] {
          try await Self.expectStretch(page, name, text)
        }
        _ = try await raw.evaluate("e => { e.scrollIntoView({block: 'center'}); return 1 }")
        try await Self.shots(page, "locution-markdown")
        try await page.expectNoErrors()
      }
    } catch {
      remove()
      try await contributor.remove(after: error)
    }
    remove()
    try await contributor.remove()
  }

  @Test(arguments: [BrowserEngine.chrome])
  func aSessionsPromptsReplyAndToolCallsAreColoredByRole(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphonID = UUID().uuidString.lowercased()
    let nocturneID = UUID().uuidString.lowercased()
    func remove() {
      _ = try? TestAdmin.query(
        SessionTrace.delete(table: "bibliographic_explication_nocturnes", where: "id='\(nocturneID)'")
          + "DELETE FROM bibliographic_explication_nocturnes WHERE id='\(nocturneID)'; DELETE FROM bibliographic_antiphons WHERE id='\(antiphonID)';")
      work.remove()
    }
    do {
      let written = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE TEI>\n" + Self.snippet
      let arguments = String(decoding: try JSONSerialization.data(withJSONObject: ["tei": written]), as: UTF8.self)
      let blocks: [[String: String]] = [
        ["type": "task_prompt_instance", "content": Self.markdown],
        ["type": "tool", "name": "read_page", "arguments": #"{"page": 5, "lines": [1, 2.5e1, -3]}"#,
         "result": #"{"ok": true, "tool": "read_page", "note": null, "count": 12}"#, "status": "ok", "call_id": "syntax_read"],
        ["type": "tool", "name": "write_tei", "arguments": arguments, "result": #"{"ok": true}"#, "status": "ok",
         "call_id": "syntax_write"],
        ["type": "text", "content": Self.markdown],
      ]
      let user = try admin.column("id")
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, resemblance_service_ids_json, processing_status)
          VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO bibliographic_explication_nocturnes (id, submission_id, process, resemblance, attempt, provider, model, result, nocturne_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
          VALUES ('\(nocturneID)', (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'),
            'explication', '1', 1, 'DeepSeek', 'deepseek-flash', 'passed', gen_random_uuid(), '\(antiphonID)', 1200, now());
        \(try SessionTrace.append(blocks, table: "bibliographic_explication_nocturnes", id: nocturneID))
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/antiphons/bibliographic/\(antiphonID)")
        let session = page.locator(".computorium-session-view")
        try await expect(session).toHaveCount(1)

        // A tool call's JSON.
        let read = page.locator("#computorium-session-tool-syntax_read")
        try await read.locator(".accordion-summary").first.click()
        try await read.locator(".computorium-session-tool-call-json-toggle button").first.click()
        let json = read.locator(".computorium-session-tool-call-json")
        try await expect(json).toBeVisible()
        try await expect(json).toHaveAttribute("data-code-syntax", "json")
        for (name, text) in [
          ("code-attr", "\"page\""), ("code-prefix", "5"), ("code-prefix", "2.5e1"), ("code-prefix", "-3"),
          ("code-attr", "\"tool\""), ("code-value", "\"read_page\""), ("code-name", "true"), ("code-name", "null"),
        ] {
          try await Self.expectStretch(page, name, text)
        }
        _ = try await json.evaluate("e => { e.scrollIntoView({block: 'center'}); return 1 }")
        try await Self.shots(page, "tool-call-json")

        // The markup a call sent: XML, its instruction and declaration too.
        let write = page.locator("#computorium-session-tool-syntax_write")
        try await write.locator(".accordion-summary").first.click()
        let sent = write.locator(".code-code[data-code-syntax='xml']").first
        try await expect(sent).toBeVisible()
        try await Self.expectStretch(page, "code-pi", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        try await Self.expectStretch(page, "code-pi", "<!DOCTYPE TEI>")
        _ = try await sent.evaluate("e => { e.scrollIntoView({block: 'center'}); return 1 }")
        try await Self.shots(page, "tool-call-xml")

        // The task prompt's Raw: Markdown, under the session's one Raw (its
        // switch in the controls row, 2026-10-16 and 2026-10-17).
        try await page.locator(".computorium-session-controls .computorium-session-markdown-toggle button").first.click()
        let prompt = page.locator(".computorium-session-task-fieldset .computorium-session-prompt-body")
        try await expect(prompt).toBeVisible()
        try await expect(prompt).toHaveAttribute("data-code-syntax", "markdown")
        try await Self.expectStretch(page, "code-name", "# Skeat, page 5")
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
