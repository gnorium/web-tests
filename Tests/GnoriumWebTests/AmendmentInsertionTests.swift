import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An amendment inserts a level as attribution does (user, 2026-10-03): a
/// node's "+ Impression" puts a new impression under it, over the node under
/// it, shown and empty with its fields; its "− Testament" takes it out
/// again. Left empty it stops the amendment with Submit Testament's words;
/// filled, it names its row, and the reopened object carries the tree with
/// it and files its fields. The scratch work's tree is an edition and its
/// digitization.
@Suite("Amendment insertion", .serialized)
struct AmendmentInsertionTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func anImpressionIsInsertedUnderAnEdition(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let record = work.recordID.lowercased()
    func clean() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM modifications WHERE modifiable_id IN
          (SELECT id FROM bibliographic_hallmarks WHERE biblio_record_id = '\(record)' AND id <> '\(work.hallmarkID.lowercased())');
        DELETE FROM bibliographic_hallmarks WHERE biblio_record_id = '\(record)' AND id <> '\(work.hallmarkID.lowercased())';
        DELETE FROM bibliographic_rebuttals WHERE biblio_record_id = '\(record)';
        COMMIT;
        """)
    }
    do {
      // A printed witness: an impression's publication is drawn for it.
      _ = try TestAdmin.query(
        """
        UPDATE biblio_record_versions
          SET metadata_json = replace(metadata_json, '"category":"report"', '"category":"report","carrier":"printed"')
          WHERE id = '\(work.versionID.lowercased())';
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("\(work.path)/amendments/new")
        let edition = page.locator(".outliner-item[data-outliner-id^='edition-']:not([data-testament-draft])")
        let manifest = page.locator(".outliner-item[data-outliner-id^='manifest-']:not([data-testament-draft])")
        let impression = page.locator(".outliner-item[data-testament-inserted='true'][data-outliner-id^='impression-']")
        let insert = edition.locator(":scope > .outliner-footer .testament-outliner-insert").first
        let uninsert = impression.locator(":scope > .outliner-footer .testament-outliner-uninsert").first
        // The witness the nodes are named for.
        let editionID = try #require(try await edition.first.getAttribute("data-outliner-id"))
        let witness = String(editionID.dropFirst("edition-".count))
        func shape() async throws -> String {
          try await page.locator("input[name='shape']").first.inputValue()
        }

        // Out of the tree until it is asked for: the edition's own control,
        // the icon and the noun.
        try await expect(impression).toBeHidden()
        try await expect(insert).toHaveText("Impression")
        try await expect(insert).toHaveAttribute("aria-label", "Add Impression")
        #expect(!(try await shape()).contains("impression-"))

        // In: under the edition, over the digitization, which hangs from it.
        try await insert.click()
        try await expect(impression).toBeVisible()
        try await expect(impression).toHaveAttribute("data-outliner-removed", "false")
        try await expect(impression.locator(":scope > .outliner-list > .outliner-item[data-outliner-id^='manifest-']"))
          .toHaveCount(1)
        let inserted = try await shape()
        #expect(inserted.contains("\"impression-\(witness)\":{\"parent\":\"edition-\(witness)\""), "\(inserted)")
        #expect(inserted.contains("\"manifest-\(witness)\":{\"parent\":\"impression-\(witness)\""), "\(inserted)")
        // The amendment's one testament: the others frozen, no other level
        // or testament offered.
        try await expect(edition.locator(":scope > .outliner-row .testament-outliner-node"))
          .toHaveAttribute("data-testament-frozen", "true")
        try await expect(insert).toBeHidden()
        try await expect(page.locator(".testament-outliner-hint[data-hint='insert']")).toBeVisible()

        // Out again: the digitization back under the edition.
        try await uninsert.click()
        try await expect(impression).toBeHidden()
        try await expect(edition.locator(":scope > .outliner-list > .outliner-item[data-outliner-id^='manifest-']"))
          .toHaveCount(1)
        try await expect(manifest).not.toHaveAttribute("data-outline-state", "moved")
        #expect(!(try await shape()).contains("impression-"))

        // In, and submitted empty: it says what to fill in.
        try await insert.click()
        try await page.locator("#amendment-rationale").fill("Web tests: this edition had a later impression.")
        try await page.locator(".record-actions button[type='submit']").click()
        try await expect(impression.locator(".testament-draft-message")).toHaveText(
          "Fill in Impression or its place, agents or date, or remove the impression.")
        #expect(try await page.url().hasSuffix("/amendments/new"))

        // Filled: its row named by its statement, and submitted.
        try await impression.locator("[name='impression']").first.fill("Second impression")
        try await expect(impression.locator(":scope > .outliner-row .record-row-title").first)
          .toHaveText("Second impression")
        try await page.locator(".record-actions button[type='submit']").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the reopened hallmark") {
          $0.path.hasPrefix("/mission-control/hallmarks/bibliographic/")
        }
        let stored = try TestAdmin.query(
          """
          SELECT shape_json FROM bibliographic_hallmarks
            WHERE biblio_record_id = '\(record)' AND id <> '\(work.hallmarkID.lowercased())';
          """
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(stored.contains("\"impression-\(witness)\":{\"parent\":\"edition-\(witness)\""), "\(stored)")
        let filed = try TestAdmin.query(
          """
          SELECT content_json FROM modifications WHERE modifiable_id IN
            (SELECT id FROM bibliographic_hallmarks WHERE biblio_record_id = '\(record)' AND id <> '\(work.hallmarkID.lowercased())');
          """)
        #expect(filed.contains("\"impression\":\"Second impression\""), "\(filed)")
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
