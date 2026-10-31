import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An amendment inserts a level as an overture's fields do (user, 2026-10-03): a
/// node's "+ Testament" adds a new child at the next level after the ones it
/// has (an impression under an edition holding its copy: 1.2), and the copy
/// is moved into it by the outline's own moves. The new node's "−
/// Testament" takes it out again. Left empty it stops the amendment with
/// Submit Testament's words; filled, it names its row, and the reopened
/// object carries the tree with the impression over the copy, named for it,
/// its fields the palinode's (the object's first state, no revision), and
/// its Permit publishes that tree. An amendment is one node's act (user,
/// 2026-10-22). The scratch work's tree is made an edition › copy ›
/// digitization.
@Suite("Amendment insertion", .serialized)
struct AmendmentInsertionTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func anImpressionIsInsertedUnderAnEdition(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin, sourceURL: fixture.baseURL + "/manifest.json")
    let record = work.recordID.lowercased()
    func clean() {
      // Its Palinodes are submitted input, frozen: they stay.
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM inferred_citation_jobs WHERE record_id = '\(record)';
        DELETE FROM biblio_record_versions WHERE biblio_record_id = '\(record)' AND id <> '\(work.versionID.lowercased())';
        DELETE FROM revisions WHERE revisable_id IN
          (SELECT id FROM bibliographic_madrigals WHERE biblio_record_id = '\(record)' AND id <> '\(work.madrigalID.lowercased())');
        DELETE FROM bibliographic_madrigals WHERE biblio_record_id = '\(record)' AND id <> '\(work.madrigalID.lowercased())';
        COMMIT;
        """)
    }
    do {
      // A printed witness with a copy: an impression's publication is drawn
      // for it, and its copy hangs from its edition.
      let stood = try TestAdmin.query(
        "SELECT shape_json FROM biblio_record_versions WHERE id = '\(work.versionID.lowercased())';")
      let figurant = try #require(
        stood.firstMatch(of: /"edition-([0-9A-Fa-f-]+)"/).map { String($0.1) }, "\(stood)")
      _ = try TestAdmin.query(
        """
        UPDATE biblio_record_versions
          SET metadata_json = replace(replace(metadata_json, 'https://example.org/web-tests', '\(fixture.baseURL)/manifest.json'), '"category":"report"', '"category":"report","carrier":"printed","copyLabel":"Copy 1"'),
            -- A copy node of its own UUID over the manifest; every node
            -- it had keeps its own.
            shape_json = jsonb_set(
              shape_json::jsonb || jsonb_build_object('copy-\(figurant)', jsonb_build_object(
                'parent', 'edition-\(figurant)', 'position', 0, 'uuid', '\(UUID().uuidString)')),
              '{manifest-\(figurant),parent}', '"copy-\(figurant)"')::text
          WHERE id = '\(work.versionID.lowercased())';
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("\(work.path)/amendments/new")
        let edition = page.locator(".outliner-item[data-outliner-id^='edition-']:not([data-testament-draft])")
        let copy = page.locator(".outliner-item[data-outliner-id^='copy-']:not([data-testament-draft])")
        let impression = page.locator(".outliner-item[data-outliner-id='impression-new']")
        let add = edition.locator(":scope > .outliner-footer .testament-outliner-add-own").first
        let remove = impression.locator(":scope > .outliner-footer .testament-draft-remove-level").first
        // The witness the nodes are named for.
        let editionID = try #require(try await edition.first.getAttribute("data-outliner-id"))
        let witness = String(editionID.dropFirst("edition-".count))
        func shape() async throws -> String {
          try await page.locator("input[name='shape']").first.inputValue()
        }
        func number(_ item: Locator) -> Locator {
          item.locator(":scope > .outliner-row .record-row-number").first
        }

        // The edition's own "+ Testament", as it looks everywhere; a new
        // node out of the outline until it is asked for.
        try await expect(impression).toBeHidden()
        try await expect(page.locator("#testament-outliner .outliner-item[data-testament-draft='true']"))
          .toHaveCount(0)
        try await expect(add).toHaveText("Testament 1.2.")
        try await expect(add).toHaveAttribute("aria-label", "Add Testament 1.2.")

        // A new child at the next level, after the one it has: 1.2, the
        // copy still 1.1.
        try await add.click()
        try await expect(impression).toBeVisible()
        try await expect(number(impression)).toHaveText("1.2")
        try await expect(number(copy)).toHaveText("1.1")
        // The amendment's one testament: the others' fields frozen, no
        // other + offered.
        try await expect(edition.locator(":scope > .outliner-row .testament-outliner-node"))
          .toHaveAttribute("data-testament-frozen", "true")
        try await expect(add).toBeHidden()
        try await expect(page.locator(".testament-outliner-hint[data-hint='add']")).toBeVisible()

        // Taken out again by its own −.
        try await remove.click()
        try await expect(impression).toBeHidden()
        try await expect(add).toBeVisible()
        #expect(!(try await shape()).contains("impression-"))

        // In again, and the copy moved into it: picked up by its grip, moved
        // after it, put under it.
        try await add.click()
        try await expect(number(impression)).toHaveText("1.2")
        let grip = copy.locator(":scope > .outliner-row .outliner-handle").first
        try await grip.click()
        try await grip.press("ArrowDown")
        try await grip.press("ArrowRight")
        try await grip.press("Enter")
        try await expect(number(impression)).toHaveText("1.1")
        try await expect(number(copy)).toHaveText("1.1.1")
        try await expect(impression.locator(":scope > .outliner-list > .outliner-item[data-outliner-id^='copy-']"))
          .toHaveCount(1)
        let moved = try await shape()
        #expect(moved.contains("\"impression-new\":{\"parent\":\"edition-\(witness)\""), "\(moved)")
        #expect(moved.contains("\"copy-\(witness)\":{\"parent\":\"impression-new\""), "\(moved)")
        try await SubmissionTests.shoot(page, "amendment-impression-over-copy", from: page.locator("#testament-outliner"))

        // Submitted empty: it says what to fill in.
        try await page.locator(".record-actions button[type='submit']").click()
        try await expect(impression.locator(".testament-draft-message").first).toHaveText(
          "Fill in the impression or its place, agents or date, or remove the impression.")
        #expect(try await page.url().hasSuffix("/amendments/new"))

        // Filled: its row named by its statement, and submitted as the
        // impression inserted over the copy, named for it.
        try await impression.locator("[name='impression']").first.fill("Second impression")
        try await expect(impression.locator(":scope > .outliner-row .record-row-title").first)
          .toHaveText("Second impression")
        // Its one act: no other testament changed (user, 2026-10-22: one
        // node per object).
        try await page.expectNoHorizontalOverflow()
        try await page.locator(".record-actions button[type='submit']").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the reopened madrigal") {
          $0.path.hasPrefix("/mission-control/madrigals/bibliographic/")
        }
        let stored = try TestAdmin.query(
          """
          SELECT shape_json FROM bibliographic_madrigals
            WHERE biblio_record_id = '\(record)' AND id <> '\(work.madrigalID.lowercased())';
          """
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(stored.contains("\"impression-\(witness)\":{\"parent\":\"edition-\(witness)\""), "\(stored)")
        #expect(stored.contains("\"copy-\(witness)\":{\"parent\":\"impression-\(witness)\""), "\(stored)")
        #expect(stored.contains("\"edition-\(witness)\""))
        // Its fields are the palinode's, the object's first state: no
        // revision is filed for them (user, 2026-10-31).
        let filed = try TestAdmin.query(
          "SELECT metadata_json FROM bibliographic_palinodes WHERE biblio_record_id = '\(record)';")
        #expect(filed.contains("\"impression\":\"Second impression\""), "\(filed)")
        let revisions = try TestAdmin.query("SELECT count(*) FROM revisions WHERE revisable_id IN (SELECT id FROM bibliographic_madrigals WHERE biblio_record_id = '\(record)' AND id <> '\(work.madrigalID.lowercased())');").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(revisions == "0", "the fields are the object's first state")
        try await page.locator("button[form='madrigal-permit']").click()
        try await expect(page.locator(".mission-control-object-header-status-chip"), timeout: .seconds(15)).toHaveText("Permitted")
        let published = try TestAdmin.query("SELECT shape_json FROM biblio_record_versions WHERE biblio_record_id = '\(record)' ORDER BY created_at DESC LIMIT 1;").trimmingCharacters(in: .whitespacesAndNewlines)
        // One Permit publishes the reviewed tree: its every node in the
        // place the object holds it, each parent node now keeping its own
        // fields (seeded from its witness, the inserted impression's its
        // own: gnorium-server 4de37a73).
        func places(_ json: String) throws -> [String: NSDictionary] {
          let nodes = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: [String: Any]])
          return nodes.mapValues { node in node.filter { $0.key != "fields" } as NSDictionary }
        }
        #expect(try places(published) == places(stored), "\(published) vs \(stored)")
        #expect(published.contains("\"impression\":\"Second impression\""), "\(published)")
        let count = try TestAdmin.query("SELECT count(*) FROM biblio_record_versions WHERE biblio_record_id = '\(record)';").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(count == "2", "The amendment has one new published version")
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      clean()
      work.remove()
      try await admin.remove(after: error)
    }
    clean()
    work.remove()
    try await admin.remove()
  }
}
