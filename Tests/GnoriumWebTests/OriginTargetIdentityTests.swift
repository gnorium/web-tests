import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Origin target identity on revision pages", .serialized)
struct OriginTargetIdentityTests {
  @Test(arguments: [false, true])
  func retargetedNodesAreVisibleEvenWhenTheirLabelsMatch(unnamed: Bool) async throws {
    guard gnorium.engines.contains(.chrome) else { try Test.cancel("Chrome is not among the engines.") }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let source = try ScratchWord(owner: admin)
    let submission = UUID().uuidString.lowercased()
    let folksong = UUID().uuidString.lowercased()
    let overture = UUID().uuidString.lowercased()
    let revision = UUID().uuidString.lowercased()
    let step = UUID().uuidString
    let label = unnamed ? "" : "A shared source label."
    func remove() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM revisions WHERE revisable_id = '\(overture)';
        DELETE FROM lexicographic_overtures WHERE id = '\(overture)';
        UPDATE lexicographic_folksongs SET deleted_at = now(), deleted_by = '\(admin.username)'
          WHERE id = '\(folksong)' AND deleted_at IS NULL;
        COMMIT;
        """)
      source.remove()
    }
    func origin(_ node: String?) -> String {
      let target = node.map { #","node":"\#($0)""# } ?? ""
      return #"[{"id":"\#(step)","relations":["borrowed_from"],"record":"\#(source.recordID)"\#(target),"origins":[]}]"#
    }
    do {
      let user = try admin.column("id")
      let form = #"{"title":"webteststargetdiff","languageCode":"eng","class":"noun","spellings":[],"inflections":[],"origin":{"etymons":[],"citations":[],"derivation":""}}"#
      let before = origin(unnamed ? nil : "s-1")
      let after = origin("s-1-1")
      _ = try TestAdmin.query(
        """
        BEGIN;
        UPDATE lexico_record_versions SET record_json = jsonb_set(jsonb_set(jsonb_set(jsonb_set(record_json::jsonb,
          '{senses,0,label}', '"\(label)"'), '{senses,1,label}', '"\(label)"'),
          '{senses,0,tei}', '"<sense><def>\(label)</def></sense>"'),
          '{senses,1,tei}', '"<sense><def>\(label)</def></sense>"')::text
          WHERE id = '\(source.versionID.lowercased())';
        INSERT INTO submissions (id, user_id) VALUES ('\(submission)', '\(user)');
        INSERT INTO lexicographic_folksongs (id, batch_id, language, order_in_batch, processing_status,
          title_form_json, anchors_json, created_at)
          VALUES ('\(folksong)', '\(submission)', 'eng', 0, 'pending', '\(form)', '[]', now());
        INSERT INTO lexicographic_overtures (id, lexicographic_folksong_id, title_form_json, anchors_json, origins_json, created_at)
          VALUES ('\(overture)', '\(folksong)', '\(form)', '[]', '\(before)', now());
        INSERT INTO revisions (id, revisable_type, revisable_id, previous_content_json, content_json, status,
          requested_by_user_id, created_at)
          VALUES ('\(revision)', 'lexicographicOverture', '\(overture)',
            '{"titleForm":\(form),"origins":\(before)}', '{"titleForm":\(form),"origins":\(after)}', 'pending', '\(user)', now());
        COMMIT;
        """)
      try await withPage(.chrome, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/overtures/lexicographic/\(overture)/revisions/\(revision)")
        let changed = page.locator(".origin-diff-node[data-origin-change='changed']")
        try await expect(changed).toHaveCount(1)
        let field = changed.locator(".origin-record-field-view .field-diff-view").last
        try await expect(field.locator("input[name$='-node']")).toHaveValue("s-1-1")
        try await expect(field.locator(".dropdown-trigger")).toContainText("1.1 \(unnamed ? "—" : label)")
        let diff = field.locator(".field-diff-diff")
        try await expect(diff).toContainText("Diff:")
        if unnamed {
          try await expect(changed.locator(".origin-record-field-view .diff-wrap-added")).toHaveCount(1)
          try await expect(diff).toContainText("1.1 —")
        } else {
          try await expect(changed.locator(".origin-record-field-view .diff-wrap-changed")).toHaveCount(1)
          try await expect(diff).toContainText("1 A shared source label.")
          try await expect(diff).toContainText("1.1 A shared source label.")
        }
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      remove()
      try await admin.remove(after: error)
    }
    remove()
    try await admin.remove()
  }
}
