import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A revision's origins against those it found (`OriginDiffView`, user
/// 2026-10-08): on a lexicographic overture's revision page, a step it adds
/// tinted green, one it removes tinted red where it stood, one it edits
/// open on its changed values, old → new, and one it leaves plain; its
/// thread's "Origin" links to that diff. A scratch lexicographic folksong,
/// overture and revision of a throwaway admin, removed after. Headless
/// Chrome only (user: web-tests never in Safari).
///
/// `ORIGIN_DIFF_SCREENSHOTS`, a folder, keeps the page at each width
/// (`origins-diff-375.png`, `origins-diff-1400.png`).
@Suite("Origin diff on a revision page", .serialized)
struct OriginDiffTests {
  @Test(arguments: Layout.allCases)
  func aRevisionShowsItsOriginsAgainstThoseItFound(layout: Layout) async throws {
    guard gnorium.engines.contains(.chrome) else { try Test.cancel("Chrome is not among the engines.") }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let submission = UUID().uuidString.lowercased()
    let folksong = UUID().uuidString.lowercased()
    let overture = UUID().uuidString.lowercased()
    let revision = UUID().uuidString.lowercased()
    func remove() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM locutions WHERE locutable_type = 'lexicographic_overture' AND locutable_id = '\(overture)';
        DELETE FROM revisions WHERE revisable_id = '\(overture)';
        DELETE FROM lexicographic_overtures WHERE id = '\(overture)';
        UPDATE lexicographic_folksongs SET deleted_at = now(), deleted_by = '\(admin.username)'
          WHERE id = '\(folksong)' AND deleted_at IS NULL;
        COMMIT;
        """)
    }
    func step(_ form: String, _ language: String, meaning: String? = nil, certainty: String? = nil) -> String {
      let meaningPart = meaning.map { #","meaning":"\#($0)""# } ?? ""
      let certaintyPart = certainty.map { #","certainty":"\#($0)""# } ?? ""
      return #"{"relations":["borrowed_from"]\#(certaintyPart),"typed":{"form":"\#(form)","type":"noun","language":"\#(language)","voices":[]\#(meaningPart)},"origins":[]}"#
    }
    do {
      let user = try admin.column("id")
      let form = #"{"title":"webtestsorigindiff","languageCode":"eng","class":"noun","spellings":[],"inflections":[],"origin":{"etymons":[],"citations":[],"derivation":""}}"#
      // Found: kept, removed, edited. Proposed: kept, edited, added.
      let found = "[\(step("webtestskept", "lat")),\(step("webtestsremoved", "grc")),\(step("webtestsedited", "ine-pro", meaning: "bend"))]"
      let proposed = "[\(step("webtestskept", "lat")),\(step("webtestsedited", "ine-pro", meaning: "to bend", certainty: "probable")),\(step("webtestsadded", "fra"))]"
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO submissions (id, user_id) VALUES ('\(submission)', '\(user)');
        INSERT INTO lexicographic_folksongs (id, batch_id, language, order_in_batch, processing_status,
          title_form_json, anchors_json, created_at)
          VALUES ('\(folksong)', '\(submission)', 'eng', 0, 'pending', '\(form)', '[]', now());
        INSERT INTO lexicographic_overtures (id, lexicographic_folksong_id, title_form_json, anchors_json, origins_json,
          created_at)
          VALUES ('\(overture)', '\(folksong)', '\(form)', '[]', '\(found)', now());
        INSERT INTO revisions (id, revisable_type, revisable_id, previous_content_json, content_json, status,
          requested_by_user_id, created_at)
          VALUES ('\(revision)', 'lexicographicOverture', '\(overture)',
            '{"titleForm":\(form),"origins":\(found)}', '{"titleForm":\(form),"origins":\(proposed)}', 'pending',
            '\(user)', now());
        COMMIT;
        """)
      let page = "/mission-control/overtures/lexicographic/\(overture)"
      try await withPage(.chrome, gnorium, viewport: layout.viewport(for: .chrome), cookies: [admin.cookie]) { tab in
        try await tab.openHydrated("\(page)/revisions/\(revision)")
        try await tab.expectNoErrors()
        try await tab.expectNoHorizontalOverflow()
        let diff = tab.locator(".origin-diff-view")
        try await expect(diff).toHaveCount(1)
        func node(_ change: String) -> Locator { diff.locator(".origin-diff-node[data-origin-change='\(change)']") }
        try await expect(node("unchanged")).toHaveCount(1)
        try await expect(node("removed")).toHaveCount(1)
        try await expect(node("changed")).toHaveCount(1)
        try await expect(node("added")).toHaveCount(1)
        try await expect(node("removed")).toContainText("webtestsremoved")
        try await expect(node("added")).toContainText("webtestsadded")
        // The edit is one step, its changed values old → new; its unchanged
        // ones as they read.
        let changed = node("changed")
        try await expect(changed).toContainText("webtestsedited")
        try await expect(changed.locator(".origin-step-old")).toHaveTexts(["bend", "Certain"])
        try await expect(changed.locator(".origin-step-new")).toHaveTexts(["to bend", "Probable"])
        // Tinted and filled with the diff's own tokens.
        let colors = try await diff.evaluate(
          """
          (root) => {
            const card = (change) => getComputedStyle(root.querySelector(
              `.origin-diff-node[data-origin-change='${change}'] > .record-row-view > .accordion-view`)).backgroundColor;
            const probe = (name) => {
              const el = document.createElement('span');
              el.style.backgroundColor = `var(${name})`;
              root.appendChild(el);
              const color = getComputedStyle(el).backgroundColor;
              el.remove();
              return color;
            };
            return {
              added: card('added') === probe('--background-color-green-subtle'),
              removed: card('removed') === probe('--background-color-red-subtle'),
              old: getComputedStyle(root.querySelector('.origin-step-old')).backgroundColor === probe('--background-color-red'),
              new: getComputedStyle(root.querySelector('.origin-step-new')).backgroundColor === probe('--background-color-green'),
            };
          }
          """)
        let report = colors.object ?? [:]
        for key in ["added", "removed", "old", "new"] {
          #expect(report[key]?.bool == true, "\(key) is not drawn with the diff's token: \(colors)")
        }
        if let folder = ProcessInfo.processInfo.environment["ORIGIN_DIFF_SCREENSHOTS"] {
          // From the removed step down: removed, changed and added in view.
          _ = try await node("removed").evaluate("(el) => el.scrollIntoView({ block: 'start' })")
          try await tab.screenshot(
            to: URL(fileURLWithPath: folder).appendingPathComponent(
              "origins-diff-\(layout == .phone ? 375 : 1400).png"))
        }

        // The thread names Origin among what changed, linked to that diff.
        try await tab.openHydrated(page)
        let link = tab.locator(".locution-thread-event-changed a").filter(hasText: "Origin")
        try await expect(link).toHaveCount(1)
        let href = try await link.evaluate("(el) => el.getAttribute('href')")
        #expect(
          (href.string ?? "").lowercased() == "\(page)/revisions/\(revision)#apparatus-origin-tree",
          "the thread's Origin does not link to the revision's diff: \(href)")
      }
    } catch {
      remove()
      try await admin.remove(after: error)
    }
    remove()
    try await admin.remove()
  }
}
