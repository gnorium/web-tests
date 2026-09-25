import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The Biblio-record field of Submit Testament: a searchable dropdown of
/// every record from the start. Once the work's language, title, author and
/// category are filled, the match is chosen, "New title" among the choices;
/// a record found by typing and picked fills those fields in from it. The
/// chosen record's chronicle tree follows with the new testament in it, the
/// only node that moves. Nothing is submitted. A throwaway admin owns a
/// scratch work — its author, evidence, overture, concerto, hallmark, record
/// and attributed version, made by SQL — removed after.
@Suite("Record choice", .serialized)
struct RecordChoiceTests {
  static let form = "/mission-control/submit/bibliographic/evidence-testament"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func choosingARecordAndPlacingTheTestament(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    do {
      try await run(engine: engine, viewport: layout.viewport(for: engine), admin: admin, work: work)
    } catch {
      work.remove()
      await admin.remove()
      throw error
    }
    work.remove()
    await admin.remove()
  }

  private func run(engine: BrowserEngine, viewport: Viewport, admin: TestAdmin, work: ScratchWork) async throws {
    try await withPage(engine, gnorium, viewport: viewport, cookies: [admin.cookie]) { page in
      try await page.openHydrated(Self.form)
      let field = page.locator(".record-choice-field-view")
      let form = page.locator(".submit-testament-form")
      let author = form.locator(
        "[data-item-list='work-author'] [data-item-section='true']:not([data-item-template] *) .text-input-input"
      ).first
      try await expect(field.locator("legend")).toContainText("Biblio-record")
      // A dropdown of every record from the start, none chosen: "—".
      let dropdown = field.locator(".dropdown-view")
      try await expect(dropdown.locator(".dropdown-selected-text")).toHaveText("—")
      try await expect(dropdown.locator(".dropdown-option[data-value='\(work.recordID)']")).toHaveCount(1)

      // The key fields: a dropdown tells its hidden input, as a pick does.
      _ = try await page.evaluate(
        """
        for (const [id, value] of [['work-language', 'eng'], ['work-category', 'report']]) {
          const input = document.getElementById(id);
          input.value = value;
          input.dispatchEvent(new Event('change'));
        }
        """)
      try await form.locator("input[name='title']").fill(work.title)
      try await author.fill(work.author)

      // The scratch work is the match, chosen, first; "New title" is the
      // other way.
      try await expect(dropdown.locator(".dropdown-selected-text")).toHaveText(work.title)
      try await expect(dropdown.locator(".dropdown-option").first).toHaveAttribute("data-value", work.recordID)
      try await expect(dropdown.locator(".dropdown-option[data-value='new']")).toHaveText("New title")
      let option = dropdown.locator(".dropdown-option[data-value='\(work.recordID)']")
      try await expect(option).toContainText("\(work.author) · Report")
      try await expect(option).toContainText(work.path)

      // Its tree: the edition it has, fixed, and the new testament after it.
      let tree = field.locator(".record-placement-view")
      try await expect(tree).toBeVisible()
      let fixed = tree.locator(
        ".outliner-item:not([data-outliner-id='edition-new']) > .outliner-row > .record-placement-node > .record-placement-row")
      try await expect(fixed.first.locator(".record-placement-label")).toContainText("First edition")
      try await expect(fixed.first.locator(".outliner-handle")).toBeDisabled()
      let new = tree.locator(".outliner-item[data-outliner-id='edition-new']")
      try await expect(new.locator(".record-placement-number").first).toHaveText("2")
      try await expect(field.locator("input[name='placement-version']")).toHaveValue(work.versionID)

      // Moved up, it takes the first place; the arrangement posts it.
      try await new.locator(".outliner-handle").first.click()
      try await page.locator(".outliner-toolbar [data-outliner-action='up']").click()
      try await page.locator(".outliner-toolbar [data-outliner-action='done']").click()
      try await expect(new.locator(".record-placement-number").first).toHaveText("1")
      let placement = try await field.locator("input[name='placement']").inputValue()
      #expect(placement.contains(#""edition-new":{"parent":"work","position":0}"#), "\(placement)")

      // "New title": no record, no tree, and nothing cleared.
      try await dropdown.locator(".dropdown-trigger").click()
      try await dropdown.locator(".dropdown-option[data-value='new']").click()
      try await expect(field.locator(".record-placement-view")).toHaveCount(0)
      try await expect(field.locator("input[name='biblio-record']")).toHaveValue("new")
      try await expect(form.locator("input[name='title']")).toHaveValue(work.title)
      try await expect(author).toHaveValue(work.author)

      // Afresh: found by typing, picked, and the key fields are its.
      try await page.openHydrated(Self.form)
      try await expect(dropdown.locator(".dropdown-option[data-value='\(work.recordID)']")).toHaveCount(1)
      try await dropdown.locator(".dropdown-trigger").click()
      try await dropdown.locator(".dropdown-search-input").fill(work.suffix)
      let results = dropdown.locator(".dropdown-options-list[data-dropdown-results='true']")
      try await expect(results).toBeVisible()
      try await expect(results.locator(".dropdown-option")).toHaveCount(2)
      let found = results.locator(".dropdown-option[data-value='\(work.recordID)']")
      try await expect(found).toContainText("\(work.author) · Report")
      try await found.click()

      try await expect(field.locator("input[name='biblio-record']")).toHaveValue(work.recordID)
      try await expect(form.locator("#work-language")).toHaveValue("eng")
      try await expect(form.locator("[data-dropdown-id='work-language'] .dropdown-selected-text")).toHaveText("English")
      try await expect(form.locator("#work-category")).toHaveValue("report")
      try await expect(form.locator("[data-dropdown-id='work-category'] .dropdown-selected-text")).toHaveText("Report")
      try await expect(form.locator("input[name='title']")).toHaveValue(work.title)
      try await expect(author).toHaveValue(work.author)
      try await expect(field.locator(".record-placement-view")).toBeVisible()
      try await expect(field.locator("input[name='placement-version']")).toHaveValue(work.versionID)
      // Filled in, not asked about: the choice stands.
      try await Task.sleep(for: .milliseconds(800))
      try await expect(field.locator("input[name='biblio-record']")).toHaveValue(work.recordID)
    }
  }
}

/// A work with one attributed version whose tree holds one edition and its
/// manifest, owned by the test's account. Every row by its own id, removed
/// in the order the foreign keys allow.
private struct ScratchWork {
  let title: String
  let author: String
  /// What makes its title and author unique: a search finds it by this.
  let suffix: String
  let recordID: String
  let versionID: String
  let path: String
  private let ids: [String: String]

  init(owner: TestAdmin) throws {
    let user = try owner.column("id")
    var ids: [String: String] = [:]
    for name in [
      "submission", "evidence", "overture", "concerto", "record", "hallmark", "version", "person", "authorship",
    ] {
      ids[name] = UUID().uuidString.lowercased()
    }
    let suffix = String(ids["record"]!.prefix(8))
    self.suffix = suffix
    title = "Web tests placement \(suffix)"
    let slug = "web-tests-placement-\(suffix)"
    author = "Web Tests Author \(suffix)"
    let authorSlug = "web-tests-author-\(suffix)"
    path = "/biblio-records/eng/\(slug)/\(authorSlug)/report"
    // As the server writes them: upper case.
    recordID = ids["record"]!.uppercased()
    versionID = ids["version"]!.uppercased()
    self.ids = ids
    let evidence = ids["evidence"]!.uppercased()
    let metadata = """
      {"sourceUrl":"https://example.org/web-tests","sourceKind":"iiif-manifest","title":"\(title)","authors":[],\
      "language":"eng","category":"report","edition":"First edition","year":1958,"genres":[],"isTranslation":false,\
      "translationChain":[],"activityStatements":[],"formerOwners":[],"citations":[]}
      """
    let shape = """
      {"edition-\(evidence)":{"parent":"work","position":0},"manifest-\(evidence)":{"parent":"edition-\(evidence)","position":0},"work":{"parent":null,"position":0}}
      """
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO submissions (id, user_id) VALUES ('\(ids["submission"]!)', '\(user)');
      INSERT INTO bibliographic_evidences (id, batch_id, reference_url, language, processing_status, title, category, edition, year)
        VALUES ('\(ids["evidence"]!)', '\(ids["submission"]!)', 'https://example.org/web-tests', 'eng', 'pending', '\(title)', 'report', 'First edition', 1958);
      INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_evidence_id, reference_url, language, processing_status)
        VALUES ('\(ids["overture"]!)', '\(ids["submission"]!)', '\(ids["evidence"]!)', 'https://example.org/web-tests', 'eng', 'pending');
      INSERT INTO bibliographic_concertos (id, bibliographic_overture_id, requested_by_user_id, processing_status)
        VALUES ('\(ids["concerto"]!)', '\(ids["overture"]!)', '\(user)', 'submitted');
      INSERT INTO biblio_records (id, corpus_id, title, title_slug, authors, category, language, genres, year, date_display)
        VALUES ('\(ids["record"]!)', (SELECT id FROM corpora ORDER BY created_at LIMIT 1), '\(title)', '\(slug)', '\(authorSlug)',
          'report', 'eng', '[]', 1958, 'AD 1958');
      INSERT INTO persons (id, display_name, slug) VALUES ('\(ids["person"]!)', '\(author)', '\(authorSlug)');
      INSERT INTO biblio_record_authors (id, biblio_record_id, person_id, position)
        VALUES ('\(ids["authorship"]!)', '\(ids["record"]!)', '\(ids["person"]!)', 0);
      INSERT INTO bibliographic_hallmarks (id, thread_id, bibliographic_overture_id, bibliographic_concerto_id, biblio_record_id, metadata_json, processing_status, permitted_by_user_id, permitted_at)
        VALUES ('\(ids["hallmark"]!)', '\(ids["hallmark"]!)', '\(ids["overture"]!)', '\(ids["concerto"]!)', '\(ids["record"]!)', '\(metadata)', 'permitted', '\(user)', now());
      INSERT INTO biblio_record_versions (id, biblio_record_id, bibliographic_hallmark_id, metadata_json, shape_json, treatment, created_at)
        VALUES ('\(ids["version"]!)', '\(ids["record"]!)', '\(ids["hallmark"]!)', '\(metadata)', '\(shape)', 1, now());
      COMMIT;
      """)
  }

  func remove() {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM biblio_record_versions WHERE id = '\(ids["version"]!)';
      DELETE FROM bibliographic_hallmarks WHERE id = '\(ids["hallmark"]!)';
      DELETE FROM bibliographic_concertos WHERE id = '\(ids["concerto"]!)';
      DELETE FROM url_histories WHERE entity_id = '\(ids["record"]!)';
      DELETE FROM biblio_record_authors WHERE id = '\(ids["authorship"]!)';
      DELETE FROM biblio_records WHERE id = '\(ids["record"]!)';
      DELETE FROM url_histories WHERE entity_id = '\(ids["person"]!)';
      DELETE FROM persons WHERE id = '\(ids["person"]!)';
      DELETE FROM bibliographic_overtures WHERE id = '\(ids["overture"]!)';
      DELETE FROM bibliographic_evidences WHERE id = '\(ids["evidence"]!)';
      DELETE FROM submissions WHERE id = '\(ids["submission"]!)';
      COMMIT;
      """)
  }
}
