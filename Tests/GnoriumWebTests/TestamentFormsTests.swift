import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Forms are never typed (user, 2026-10-03): a testament's are derived
/// from the citations of it in the corpus, shown read-only on the record
/// page and frozen in an amendment. Submit Testament has no Form rows, at
/// any level, nor the work. Nothing is submitted.
@Suite("Testament forms")
struct TestamentFormsTests {
  static let form = "/mission-control/submit/bibliographic/evidence-testament"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func noFormIsTyped(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(Self.form)
        let form = page.locator(".submit-testament-form")
        let carrier = form.locator(".dropdown-view:has(#testament-carrier)")
        try await carrier.locator(".dropdown-trigger").click()
        try await carrier.locator(".dropdown-option[data-value='printed']").click()
        try await expect(form.locator("[data-item-list='title-form'], .title-form-json")).toHaveCount(0)
        try await expect(form.locator("button[aria-label='Add Form']")).toHaveCount(0)
        // A new testament has no citations yet: no Forms list either.
        try await expect(form.locator(".derived-forms-view")).toHaveCount(0)
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }

  /// A record page shows each node's Forms read-only, after its description
  /// fields: the work's from the citations linked to the record alone, the
  /// edition's from those a person linked to it, each with its dates and
  /// its testaments; a work naming itself counts. Chrome headless.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aRecordPageShowsItsDerivedForms(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let version = work.versionID.lowercased()
    let record = work.recordID.lowercased()
    let edition = try TestAdmin.query(
      "SELECT key FROM biblio_record_versions, jsonb_object_keys(shape_json::jsonb) AS key WHERE id = '\(version)' AND key LIKE 'edition-%';"
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    let extraction = UUID().uuidString.lowercased()
    let citations = [UUID().uuidString.lowercased(), UUID().uuidString.lowercased()]
    func cite(_ id: String, _ surface: String, word: Int, node: String?) -> String {
      """
      INSERT INTO citations (id, biblio_record_version_id, biblio_record_id, testament_id, permitted_at, canvas_id, page,
        start_line, start_word, start_surface, end_line, end_word, end_surface, element, kind, surface, parts_json,
        language_code, status, decided_by, cited_biblio_record_id, cited_node_id, resolved_at,
        created_at, entry_head)
        VALUES ('\(id)', '\(version)', '\(record)', '\(version)', now(), 'c', 1, 1, \(word), 'w', 1, \(word), 'w',
          'bibl', 'work', '\(surface)', '{}', 'eng', 'resolved', 'person', '\(record)', \(node.map { "'\($0)'" } ?? "NULL"),
          now(), now(), false);
      """
    }
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO citation_extractions (id, biblio_record_version_id, testament_id, permitted_at, citations_version, count, extracted_at)
        VALUES ('\(extraction)', '\(version)', '\(version)', now(), 'web-tests', 2, now());
      \(cite(citations[0], "The Placement Report", word: 1, node: nil))
      \(cite(citations[1], "Placement Rep.", word: 2, node: edition))
      COMMIT;
      """)
    func cleanUp() async throws {
      _ = try? TestAdmin.query(
        """
        DELETE FROM citations WHERE id IN ('\(citations[0])', '\(citations[1])');
        DELETE FROM citation_extractions WHERE id = '\(extraction)';
        """)
      work.remove()
      try await admin.remove()
    }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(work.path)
        // The work's, right after its title.
        let order = try await page.locator("#record-metadata").evaluate(
          """
          (root) => {
            const title = root.querySelector('#work-title'), forms = root.querySelector('.derived-forms-view');
            if (!title || !forms) return 'missing';
            return title.compareDocumentPosition(forms) & Node.DOCUMENT_POSITION_FOLLOWING ? 'ok' : 'forms before title';
          }
          """
        ).string
        #expect(order == "ok", "\(order ?? "")")
        let texts = try await page.evaluate(
          "JSON.stringify([...document.querySelectorAll('.derived-forms-view')].map((v) => v.textContent.replace(/\\s+/g, ' ').trim()))"
        ).string ?? "[]"
        #expect(texts.contains("The Placement Report, AD 1958, 1 testament"), "\(texts)")
        #expect(texts.contains("Placement Rep., AD 1958, 1 testament"), "\(texts)")
        // Read-only: no field, no item control.
        try await expect(page.locator(".derived-forms-view input")).toHaveCount(0)
        try await expect(page.locator("button[aria-label='Add Form']")).toHaveCount(0)
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      try await cleanUp()
      throw error
    }
    try await cleanUp()
  }
}
