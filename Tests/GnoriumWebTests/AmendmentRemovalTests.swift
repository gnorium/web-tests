import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An amendment edits or removes, never adds (user, 2026-09-28): any
/// testament of the Submit Amendment form's tree can be removed, every
/// testament under it with it, once the dialog confirms it, by the tree's
/// "‹ − Testament 1.1. ›" stepped to it (user, 2026-11-03); a removed one
/// is framed red, leaves the tree the amendment posts, and can be restored
/// by the same button, "+ Testament 1.1.".
/// Submitted (an amendment is about one digitization), the reopened object
/// carries the tree without it, and its page draws it where it stood,
/// removed; while that object is open, another amendment can neither move
/// nor remove the digitization, nor remove a testament above it. The
/// scratch work's tree is an edition and its digitization.
@Suite("Amendment removal", .serialized)
struct AmendmentRemovalTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aTestamentIsRemovedWithEverythingUnderIt(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let record = work.recordID.lowercased()
    func clean() {
      // Its Palinodes are submitted input, frozen: they stay.
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM revisions WHERE revisable_id IN
          (SELECT id FROM bibliographic_madrigals WHERE biblio_record_id = '\(record)' AND id <> '\(work.madrigalID.lowercased())');
        DELETE FROM bibliographic_madrigals WHERE biblio_record_id = '\(record)' AND id <> '\(work.madrigalID.lowercased())';
        COMMIT;
        """)
    }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("\(work.path)/amendments/new")
        let edition = page.locator(".outliner-item[data-outliner-id^='edition-']:not([data-testament-draft])")
        let manifest = page.locator(".outliner-item[data-outliner-id^='manifest-']:not([data-testament-draft])")
        let dialog = page.locator(".testament-outliner-remove-dialog")
        // The tree's one row of steppers removes and restores (user,
        // 2026-11-03); no node has controls of its own.
        let stepper = TreeStepper(page, tree: "testament-outliner")
        /// Opens a node's row, and settles it, before its controls are aimed
        /// at: they move while it grows.
        func reveal(_ item: Locator) async throws {
          _ = try await item.evaluate(
            """
            (item) => {
              const d = item.querySelector(':scope > .outliner-row details');
              if (!d.open) d.querySelector(':scope > summary').click();
              return d.open;
            }
            """)
          try await expect(
            item.locator(":scope > .outliner-row > .outliner-node > .testament-outliner-node > .record-node-view > .accordion-view > .accordion-details")
              .first
          ).toHaveAttribute("data-open-finished", "true")
        }
        func shape() async throws -> String {
          try await page.locator("input[name='shape']").first.inputValue()
        }

        // Cancelled: nothing removed. "− Testament 1.1." chosen, the last
        // node at first; none in a node.
        try await reveal(manifest)
        try await expect(stepper.removeButton).toHaveText("Testament 1.1.")
        try await expect(stepper.removeButton).toHaveAttribute("aria-label", "Remove testament 1.1.")
        try await expect(page.locator(".outliner-item .testament-outliner-remove")).toHaveCount(0)
        try await stepper.remove("Remove testament 1.1.")
        try await expect(dialog).toHaveAttribute("open")
        try await dialog.locator("button").filter(hasText: "Cancel").first.click()
        try await expect(dialog).not.toHaveAttribute("open")
        try await expect(manifest).not.toHaveAttribute("data-outliner-removed", "true")

        // Removed, then restored.
        try await stepper.remove("Remove testament 1.1.")
        try await dialog.locator("button").filter(hasText: "Remove").first.click()
        try await expect(manifest).toHaveAttribute("data-outline-state", "removed")
        #expect(!(try await shape()).contains("manifest-"))
        // Its node ringed as a field is: the ring the outline item draws
        // round the whole node and every node under it (its `::after`), a
        // border and an outline of one red, never a box-shadow and never a
        // line through the node, right of its marker (user, 2026-11-03).
        let ring = try await manifest.evaluate(
          """
          (item) => {
            const s = getComputedStyle(item, '::after')
            const row = getComputedStyle(item.querySelector(':scope > .outliner-row .accordion-view'))
            const marker = item.querySelector(':scope > .outliner-row .outliner-marker').getBoundingClientRect()
            const left = item.getBoundingClientRect().left + parseFloat(s.left) - 1
            const ok = s.borderTopColor === s.outlineColor && s.outlineStyle === 'solid'
              && s.outlineWidth === s.borderTopWidth && s.borderTopWidth === '1px' && s.boxShadow === 'none'
              && row.outlineStyle === 'none' && row.boxShadow === 'none' && left > marker.right
            return ok ? 'ok' : [s.borderTopColor, s.outlineColor, s.outlineStyle, s.outlineWidth, s.borderTopWidth,
              s.boxShadow, row.outlineStyle, row.boxShadow, left, marker.right].join(' | ')
          }
          """)
        #expect(ring.string == "ok", "The removed testament's node is not ringed as a field: \(ring)")
        // The stepper on to the node next to it, here the one before (user,
        // 2026-11-03); stepped back, it restores it.
        try await expect(stepper.removeButton).toHaveAttribute("aria-label", "Remove testament 1.")
        try await stepper.remove("Restore testament 1.1.")
        try await expect(manifest).not.toHaveAttribute("data-outline-state", "removed")
        #expect((try await shape()).contains("manifest-"))

        // The edition removed, its digitization with it.
        try await reveal(edition)
        try await stepper.remove("Remove testament 1.")
        try await expect(dialog).toHaveAttribute("open")
        try await dialog.locator("button").filter(hasText: "Remove").first.click()
        try await expect(edition).toHaveAttribute("data-outline-state", "removed")
        let posted = try await shape()
        #expect(!posted.contains("edition-") && !posted.contains("manifest-"), "\(posted)")
        // The icon and the noun: "+ Testament 1." restores it, the words
        // for assistive technology.
        try await expect(stepper.removeButton).toHaveText("Testament 1.")
        try await expect(stepper.removeButton).toHaveAttribute("aria-label", "Restore testament 1.")
        try await expect(stepper.removeButton.locator("svg.plus-icon-view")).toHaveCount(1)

        // An amendment is about one digitization: the edition restored, the
        // digitization removed is what it submits.
        try await stepper.remove("Restore testament 1.")
        try await expect(edition).not.toHaveAttribute("data-outline-state", "removed")
        try await stepper.remove("Remove testament 1.1.")
        try await expect(dialog).toHaveAttribute("open")
        try await dialog.locator("button").filter(hasText: "Remove").first.click()
        try await expect(manifest).toHaveAttribute("data-outline-state", "removed")

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
        #expect(stored.contains("\"work\"") && stored.contains("edition-") && !stored.contains("manifest-"), "\(stored)")
        // Its page draws the removed testament where it stood.
        try await expect(page.locator(".testament-tree-diff-node[data-tree-change='removed']")).toHaveCount(1)
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()

        // While that object is open its digitization keeps its place in
        // another amendment: its handle disabled, and neither it nor the
        // edition above it removable—the stepper drawn so, not hidden.
        try await page.openHydrated("\(work.path)/amendments/new")
        // Drawn so, and kept so by the outline's every pass (a click runs one).
        try await page.locator(".testament-outliner-hint").first.evaluate("(hint) => document.body.click()")
        try await expect(manifest.locator(":scope > .outliner-row .outliner-handle").first).toHaveAttribute(
          "data-outliner-immovable", "true")
        try await expect(edition.locator(":scope > .outliner-row .outliner-handle").first).toHaveAttribute(
          "data-outliner-immovable", "false")
        // Neither is one "− Testament" steps to: none to remove, the
        // button there, disabled.
        try await expect(stepper.removeButton).toBeVisible()
        try await expect(stepper.removeButton).toBeDisabled()
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
