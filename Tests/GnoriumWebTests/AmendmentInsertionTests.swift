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
/// and files its fields. The scratch work's tree is made an edition › copy
/// › digitization.
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
      // Its amendment Instances are submitted input, frozen: they stay.
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM inferred_citation_jobs WHERE record_id = '\(record)';
        DELETE FROM biblio_record_versions WHERE biblio_record_id = '\(record)' AND id <> '\(work.versionID.lowercased())';
        DELETE FROM modifications WHERE modifiable_id IN
          (SELECT id FROM bibliographic_notations WHERE biblio_record_id = '\(record)' AND id <> '\(work.notationID.lowercased())');
        DELETE FROM bibliographic_notations WHERE biblio_record_id = '\(record)' AND id <> '\(work.notationID.lowercased())';
        COMMIT;
        """)
    }
    do {
      // A printed witness with a copy: an impression's publication is drawn
      // for it, and its copy hangs from its edition.
      let stood = try TestAdmin.query(
        "SELECT shape_json FROM biblio_record_versions WHERE id = '\(work.versionID.lowercased())';")
      let instance = try #require(
        stood.firstMatch(of: /"edition-([0-9A-Fa-f-]+)"/).map { String($0.1) }, "\(stood)")
      _ = try TestAdmin.query(
        """
        UPDATE biblio_record_versions
          SET metadata_json = replace(replace(metadata_json, 'https://example.org/web-tests', '\(fixture.baseURL)/manifest.json'), '"category":"report"', '"category":"report","carrier":"printed","copyLabel":"Copy 1"'),
            shape_json = '{"copy-\(instance)":{"parent":"edition-\(instance)","position":0},"edition-\(instance)":{"parent":"work","position":0},"manifest-\(instance)":{"parent":"copy-\(instance)","position":0},"work":{"parent":null,"position":0}}'
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
        try await expect(add).toHaveText("Testament")
        try await expect(add).toHaveAttribute("aria-label", "Add Testament")

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
        try await page.locator("#amendment-rationale").fill("Web tests: this copy is of a later impression.")
        try await page.locator(".record-actions button[type='submit']").click()
        try await expect(impression.locator(".testament-draft-message").first).toHaveText(
          "Fill in Impression or its place, agents or date, or remove the impression.")
        #expect(try await page.url().hasSuffix("/amendments/new"))

        // Filled: its row named by its statement, and submitted as the
        // impression inserted over the copy, named for it.
        try await impression.locator("[name='impression']").first.fill("Second impression")
        try await expect(impression.locator(":scope > .outliner-row .record-row-title").first)
          .toHaveText("Second impression")
        // A second ancestor and a move/deletion belong to this same review.
        let issue = page.locator(".outliner-item[data-outliner-id='issue-new']")
        try await impression.locator(":scope > .outliner-footer .testament-draft-add-level").first.click()
        try await expect(issue).toBeVisible()
        try await issue.locator("[name='issue']").first.fill("Library issue")
        try await grip.click()
        try await grip.press("ArrowDown")
        try await grip.press("ArrowRight")
        try await grip.press("Enter")
        try await expect(issue.locator(":scope > .outliner-list > .outliner-item[data-outliner-id^='copy-']")).toHaveCount(1)
        let impressionGrip = impression.locator(":scope > .outliner-row .outliner-handle").first
        try await impressionGrip.click()
        try await impressionGrip.press("ArrowLeft")
        try await impressionGrip.press("Enter")
        let editionRemoval = edition.locator(":scope > .outliner-footer .testament-outliner-remove").first
        try await expect(editionRemoval).toBeVisible()
        #expect(try await editionRemoval.getAttribute("inert") == nil)
        try await editionRemoval.click()
        try await page.locator(".testament-outliner-remove-dialog button").filter(hasText: "Remove").first.click()
        let atomic = try await shape()
        #expect(!atomic.contains("\"edition-\(witness)\""), "\(atomic)")
        #expect(atomic.contains("\"manifest-\(witness)\""), "The existing leaf keeps its identity")
        #expect(atomic.contains("\"issue-new\""))
        try await page.expectNoHorizontalOverflow()
        try await page.locator(".record-actions button[type='submit']").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the reopened notation") {
          $0.path.hasPrefix("/mission-control/notations/bibliographic/")
        }
        let stored = try TestAdmin.query(
          """
          SELECT shape_json FROM bibliographic_notations
            WHERE biblio_record_id = '\(record)' AND id <> '\(work.notationID.lowercased())';
          """
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(stored.contains("\"impression-\(witness)\":{\"parent\":\"work\""), "\(stored)")
        #expect(stored.contains("\"issue-\(witness)\":{\"parent\":\"impression-\(witness)\""), "\(stored)")
        #expect(stored.contains("\"copy-\(witness)\":{\"parent\":\"issue-\(witness)\""), "\(stored)")
        #expect(!stored.contains("\"edition-\(witness)\""))
        let filed = try TestAdmin.query(
          """
          SELECT content_json FROM modifications WHERE modifiable_id IN
            (SELECT id FROM bibliographic_notations WHERE biblio_record_id = '\(record)' AND id <> '\(work.notationID.lowercased())');
          """)
        #expect(filed.contains("\"impression\":\"Second impression\""), "\(filed)")
        #expect(filed.contains("\"issue\":\"Library issue\""), "\(filed)")
        let modification = try TestAdmin.query("SELECT upper(id::text) FROM modifications WHERE modifiable_id IN (SELECT id FROM bibliographic_notations WHERE biblio_record_id = '\(record)' AND id <> '\(work.notationID.lowercased())');").trimmingCharacters(in: .whitespacesAndNewlines)
        try await page.locator(".intervention-thread-view form[action$='/modifications/\(modification)/accept'] button").first.click()
        try await page.waitForLoadState()
        try await page.locator("button[form='notation-permit']").click()
        try await expect(page.locator(".mission-control-object-header-status-chip"), timeout: .seconds(15)).toHaveText("Permitted")
        let published = try TestAdmin.query("SELECT shape_json FROM biblio_record_versions WHERE biblio_record_id = '\(record)' ORDER BY created_at DESC LIMIT 1;").trimmingCharacters(in: .whitespacesAndNewlines)
        let publishedShape = try JSONSerialization.jsonObject(with: Data(published.utf8)) as? NSDictionary
        let reviewedShape = try JSONSerialization.jsonObject(with: Data(stored.utf8)) as? NSDictionary
        #expect(publishedShape == reviewedShape, "One Permit publishes the complete reviewed tree")
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
