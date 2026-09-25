import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The Biblio-record field of Submit Testament: once the work's language,
/// title and category are filled, the records it may belong to are offered,
/// the match chosen, "New title" among the choices; the chosen record's
/// chronicle tree follows with the new testament in it, the only node that
/// moves. Nothing is submitted. A throwaway admin owns a scratch work — its
/// evidence, overture, concerto, hallmark, record and attributed version,
/// made by SQL — removed after.
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
      try await expect(field.locator("legend")).toContainText("Biblio-record")
      try await expect(field.locator(".record-choice-note"))
        .toContainText("Fill in the language, title, authors and category")

      // The key fields: a dropdown tells its hidden input, as a pick does.
      _ = try await page.evaluate(
        """
        for (const [id, value] of [['work-language', 'eng'], ['work-category', 'report']]) {
          const input = document.getElementById(id);
          input.value = value;
          input.dispatchEvent(new Event('change'));
        }
        """)
      try await page.locator(".submit-testament-form input[name='title']").fill(work.title)

      // The scratch work is the match, chosen; "New title" is the other way.
      let select = field.locator(".select-view")
      try await expect(select).toHaveCount(1)
      try await expect(select.locator(".select-label")).toHaveText(work.title)
      try await expect(select.locator(".menu-item-view[data-value='new'] .menu-item-label")).toHaveText("New title")
      try await expect(select.locator(".menu-item-view[data-value='\(work.recordID)']")).toContainText(work.path)

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

      // "New title": no record, no tree.
      try await select.locator(".select-handle").click()
      try await select.locator(".menu-item-view[data-value='new']").click()
      try await expect(field.locator(".record-placement-view")).toHaveCount(0)
      try await expect(field.locator("input[name='biblio-record']")).toHaveValue("new")
    }
  }
}

/// A work with one attributed version whose tree holds one edition and its
/// manifest, owned by the test's account. Every row by its own id, removed
/// in the order the foreign keys allow.
private struct ScratchWork {
  let title: String
  let recordID: String
  let versionID: String
  let path: String
  private let ids: [String: String]

  init(owner: TestAdmin) throws {
    let user = try owner.column("id")
    var ids: [String: String] = [:]
    for name in ["submission", "evidence", "overture", "concerto", "record", "hallmark", "version"] {
      ids[name] = UUID().uuidString.lowercased()
    }
    let suffix = String(ids["record"]!.prefix(8))
    title = "Web tests placement \(suffix)"
    let slug = "web-tests-placement-\(suffix)"
    path = "/biblio-records/eng/\(slug)/—/report"
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
      INSERT INTO bibliographic_evidences (id, batch_id, source_url, language, processing_status, title, category, edition, year)
        VALUES ('\(ids["evidence"]!)', '\(ids["submission"]!)', 'https://example.org/web-tests', 'eng', 'pending', '\(title)', 'report', 'First edition', 1958);
      INSERT INTO bibliographic_overtures (id, batch_id, bibliographic_evidence_id, source_url, language, processing_status)
        VALUES ('\(ids["overture"]!)', '\(ids["submission"]!)', '\(ids["evidence"]!)', 'https://example.org/web-tests', 'eng', 'pending');
      INSERT INTO bibliographic_concertos (id, bibliographic_overture_id, requested_by_user_id, processing_status)
        VALUES ('\(ids["concerto"]!)', '\(ids["overture"]!)', '\(user)', 'submitted');
      INSERT INTO biblio_records (id, corpus_id, title, title_slug, authors, category, language, genres, year, date_display)
        VALUES ('\(ids["record"]!)', (SELECT id FROM corpora ORDER BY created_at LIMIT 1), '\(title)', '\(slug)', '—',
          'report', 'eng', '[]', 1958, 'AD 1958');
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
      DELETE FROM biblio_records WHERE id = '\(ids["record"]!)';
      DELETE FROM bibliographic_overtures WHERE id = '\(ids["overture"]!)';
      DELETE FROM bibliographic_evidences WHERE id = '\(ids["evidence"]!)';
      DELETE FROM submissions WHERE id = '\(ids["submission"]!)';
      COMMIT;
      """)
  }
}
