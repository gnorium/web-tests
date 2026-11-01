import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A testament's Note (user, 2026-11-01): every level below the work has
/// one, as a sentiment has its `<note>`s, for what no other field holds (a
/// copy's provenance, binding, condition, facsimile or supplied leaves). On
/// the record page it is plain prose under the node's header, above its
/// Metadata, once: the Metadata does not repeat it. Submit Testament asks for
/// it at each level, last. A throwaway admin owns a scratch work, removed
/// after.
@Suite("Testament note", .serialized)
struct TestamentNoteTests {
  static let note = "Binding signed by Macdonald. Last leaf in facsimile from the British Library copy. Inlaid; trimmed at head."

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aTestamentsNoteStandsAboveItsMetadata(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    do {
      _ = try TestAdmin.query(
        """
        UPDATE biblio_record_versions
          SET metadata_json = (metadata_json::jsonb || '{"editionNote":"\(Self.note)"}'::jsonb)::text
          WHERE id = '\(work.versionID.lowercased())';
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(work.path)
        let note = page.locator(".record-row-view .node-notes-text")
        try await expect(note).toHaveCount(1)
        try await expect(note).toHaveText(Self.note)
        // Its row's Metadata, opened, does not repeat it.
        let row = page.locator(".record-row-view:has(.node-notes-text)").first
        let metadata = row.locator(".metadata-accordion-view").first
        try await metadata.locator(".accordion-summary").first.click()
        try await expect(metadata.locator("textarea[name='edition_note']")).toHaveCount(0)
        let prose = try #require(try await note.boundingBox())
        let fields = try #require(try await metadata.boundingBox())
        #expect(prose.y + prose.height <= fields.y)
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()

        // Submit Testament asks for each level's Note.
        try await page.openHydrated(CarrierTests.form)
        try await expect(page.locator(".submit-testament-form textarea[name='digitization_note']")).toHaveCount(1)
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
