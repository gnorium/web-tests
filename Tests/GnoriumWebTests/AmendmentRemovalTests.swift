import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An amendment edits or removes, never adds (user, 2026-09-28): any
/// testament of the Submit Amendment form's tree can be removed, every
/// testament under it with it, once the dialog confirms it; a removed one is
/// framed red, leaves the tree the amendment posts, and can be restored.
/// Submitted, the reopened object carries the tree without it, and its page
/// draws it where it stood, removed. The scratch work's tree is an edition
/// and its digitization.
@Suite("Amendment removal", .serialized)
struct AmendmentRemovalTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aTestamentIsRemovedWithEverythingUnderIt(engine: BrowserEngine, layout: Layout) async throws {
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
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("\(work.path)/amendments/new")
        let edition = page.locator(".outliner-item[data-outliner-id^='edition-']")
        let manifest = page.locator(".outliner-item[data-outliner-id^='manifest-']")
        let dialog = page.locator(".testament-outliner-remove-dialog")
        func own(_ item: Locator, _ selector: String) -> Locator {
          item.locator(":scope > .outliner-row > .outliner-node > .testament-outliner-node > .record-row-view \(selector)").first
        }
        /// Opens every accordion round a node's removal controls.
        func reveal(_ item: Locator) async throws {
          _ = try await own(item, ".testament-outliner-removal").evaluate(
            """
            (el) => {
              const chain = [];
              for (let d = el.closest('details'); d; d = d.parentElement.closest('details')) chain.unshift(d);
              for (const d of chain) if (!d.open) d.querySelector(':scope > summary').click();
              return chain.length;
            }
            """)
          // Its row settled open before its controls are aimed at: they
          // move while it grows.
          try await expect(
            item.locator(":scope > .outliner-row > .outliner-node > .testament-outliner-node > .record-row-view > .accordion-view > .accordion-details")
              .first
          ).toHaveAttribute("data-open-finished", "true")
        }
        func shape() async throws -> String {
          try await page.locator("input[name='shape']").first.inputValue()
        }

        // Cancelled: nothing removed.
        try await reveal(manifest)
        try await own(manifest, ".testament-outliner-remove").click()
        try await expect(dialog).toHaveAttribute("data-open", "true")
        try await dialog.locator(".dialog-default-button button").click()
        try await expect(dialog).toHaveAttribute("data-open", "false")
        try await expect(manifest).not.toHaveAttribute("data-outliner-removed", "true")

        // Removed, then restored.
        try await own(manifest, ".testament-outliner-remove").click()
        try await dialog.locator(".dialog-primary-button button").click()
        try await expect(manifest).toHaveAttribute("data-outline-state", "removed")
        #expect(!(try await shape()).contains("manifest-"))
        try await own(manifest, ".testament-outliner-restore").click()
        try await expect(manifest).not.toHaveAttribute("data-outline-state", "removed")
        #expect((try await shape()).contains("manifest-"))

        // The edition removed, its digitization with it.
        try await reveal(edition)
        try await own(edition, ".testament-outliner-remove").click()
        try await dialog.locator(".dialog-primary-button button").click()
        try await expect(edition).toHaveAttribute("data-outline-state", "removed")
        let posted = try await shape()
        #expect(!posted.contains("edition-") && !posted.contains("manifest-"), "\(posted)")
        try await expect(own(edition, ".testament-outliner-restore")).toBeVisible()
        try await expect(own(edition, ".testament-outliner-remove")).toBeHidden()

        try await page.locator("#amendment-rationale").fill("Web tests: this testament is not the work's.")
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
        #expect(stored.contains("\"work\"") && !stored.contains("edition-") && !stored.contains("manifest-"), "\(stored)")
        // Its page draws the removed testaments where they stood.
        try await expect(page.locator(".testament-tree-diff-node[data-tree-change='removed']")).toHaveCount(2)
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
