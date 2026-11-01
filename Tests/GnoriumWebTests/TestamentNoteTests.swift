import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A node's Note (user, 2026-11-01): every node of the testament tree has
/// one, the work's root among them, as a sentiment has its `<note>`s, for
/// what no other field holds (a copy's provenance, binding, condition,
/// facsimile or supplied leaves). It stands above the node's Metadata as a
/// label-and-field pair, a "Note" label over a text area whose placeholder
/// is "Note", frozen on the record page, open on Submit Testament; the
/// Metadata does not repeat it. A throwaway admin owns a scratch work,
/// removed after.
@Suite("Testament note", .serialized)
struct TestamentNoteTests {
  static let note = "Binding signed by Macdonald. Last leaf in facsimile from the British Library copy. Inlaid; trimmed at head."
  static let workNote = "Known as the bad quarto."

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aNodesNoteStandsAboveItsMetadata(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    do {
      _ = try TestAdmin.query(
        """
        UPDATE biblio_record_versions
          SET metadata_json = (metadata_json::jsonb
            || '{"editionNote":"\(Self.note)","workNote":"\(Self.workNote)"}'::jsonb)::text
          WHERE id = '\(work.versionID.lowercased())';
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(work.path)
        // A testament's: frozen, labeled, above its row's Metadata.
        let note = page.locator(".record-row-view textarea[name='edition_note']")
        try await expect(note).toHaveCount(1)
        try await expect(note).toHaveValue(Self.note)
        try await expect(note).toBeDisabled()
        try await expect(note).toHaveAttribute("placeholder", "Note")
        let field = page.locator(".record-row-view .note-field-view").first
        try await expect(field.locator(".label-view").first).toContainText("Note")
        let row = page.locator(".record-row-view:has(textarea[name='edition_note'])").first
        let metadata = row.locator(".metadata-accordion-view").first
        try await metadata.locator(".accordion-summary").first.click()
        // Its row's Metadata, opened, does not repeat it.
        try await expect(metadata.locator("textarea[name='edition_note']")).toHaveCount(0)
        let box = try #require(try await field.boundingBox())
        let fields = try #require(try await metadata.boundingBox())
        #expect(box.y + box.height <= fields.y)
        // The root's: the work's Note above the record's Metadata.
        let root = page.locator("textarea[name='work_note']")
        try await expect(root).toHaveValue(Self.workNote)
        let rootBox = try #require(try await root.boundingBox())
        let rootMetadata = try #require(try await page.locator("#metadata .metadata-accordion-view").first.boundingBox())
        #expect(rootBox.y + rootBox.height <= rootMetadata.y)
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()

        // Submit Testament asks for each node's Note, the work's too, open.
        try await page.openHydrated(CarrierTests.form)
        try await expect(page.locator(".submit-testament-form textarea[name='digitization_note']")).toHaveCount(1)
        try await expect(page.locator(".submit-testament-form textarea[name='digitization_note']")).toBeEnabled()
        try await expect(page.locator(".submit-testament-form textarea[name='work_note']")).toHaveCount(1)
        try await page.expectNoErrors()
      }
    } catch {
      work.remove()
      try await admin.remove(after: error)
    }
    work.remove()
    try await admin.remove()
  }
}
