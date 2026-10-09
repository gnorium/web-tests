import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A revision's origins against those it found (`OriginDiffView`, user
/// 2026-10-08), drawn as the testament tree diff draws a tree: on a
/// lexicographic overture's revision page, a step it moves framed orange
/// with its "Diff: 4 → 1", one it removes framed red where it stood, one it
/// adds in its plain frame with its fields green, one it edits open on the
/// form's own fields, each changed one framed orange with its "Diff:" line
/// under it, and no card tinted; its thread's "Origin" links to that diff. A scratch lexicographic folksong,
/// overture and revision of a throwaway admin, removed after. Headless
/// Chrome only (user: web-tests never in Safari).
///
/// `ORIGIN_DIFF_SCREENSHOTS`, a folder, keeps the page at each width
/// (`origins-diff-v2-375.png`, `origins-diff-v2-1400.png`).
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
      // Found: kept, removed, edited, moved. Proposed: moved (to the top),
      // kept, edited, added.
      let found = "[\(step("webtestskept", "lat")),\(step("webtestsremoved", "grc")),\(step("webtestsedited", "ine-pro", meaning: "bend")),\(step("webtestsmoved", "deu"))]"
      let proposed = "[\(step("webtestsmoved", "deu")),\(step("webtestskept", "lat")),\(step("webtestsedited", "ine-pro", meaning: "to bend", certainty: "probable")),\(step("webtestsadded", "fra"))]"
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
        try await expect(node("unchanged")).toHaveCount(2)
        try await expect(node("removed")).toHaveCount(1)
        try await expect(node("changed")).toHaveCount(1)
        try await expect(node("added")).toHaveCount(1)
        try await expect(node("removed")).toContainText("webtestsremoved")
        try await expect(node("added")).toContainText("webtestsadded")
        // The move, as the testament tree shows one: its frame and its
        // number's diff; the step it passed only renumbered.
        let moved = diff.locator(".origin-diff-node[data-tree-change='changed']")
        try await expect(moved).toHaveCount(1)
        try await expect(moved).toContainText("webtestsmoved")
        try await expect(moved.locator(".record-row-view .diff-view").first).toContainText("4→1")
        try await expect(diff.locator(".origin-diff-node[data-tree-change='removed']")).toHaveCount(1)
        // The edit is one step, open on the form's own fields: each changed
        // one framed, its "Diff:" line under it.
        let changed = node("changed")
        try await expect(changed).toContainText("webtestsedited")
        try await expect(changed.locator(".diff-wrap-changed")).toHaveCount(2)
        let lines = changed.locator(".diff-wrap-changed > .field-diff-diff")
        try await expect(lines.nth(0)).toContainText("Diff:")
        try await expect(lines.nth(0)).toContainText("Probable")
        try await expect(lines.nth(1)).toContainText("to bend")
        try await expect(changed.locator("input[name$='-meaning']")).toHaveCount(1)
        // Frames of the diff's own tokens, a border and an outline of one
        // color; no card tinted; the added step's fields green.
        let colors = try await diff.evaluate(
          """
          (root) => {
            // The card's frame: its outline item's border, round the whole
            // card (its own accordion draws none).
            const card = (frame) => root.querySelector(
              `.origin-diff-node[data-tree-change='${frame}']`).closest('.outliner-item');
            const probe = (name) => {
              const el = document.createElement('span');
              el.style.color = `var(${name})`;
              root.appendChild(el);
              const color = getComputedStyle(el).color;
              el.remove();
              return color;
            };
            const ring = (el, name) => {
              const style = getComputedStyle(el);
              return style.borderTopColor === probe(name) && style.outlineColor === probe(name)
                && style.outlineStyle === 'solid' && style.outlineWidth === style.borderTopWidth
                && style.boxShadow === 'none';
            };
            const untinted = [...root.querySelectorAll('.accordion-view')].every((el) => {
              const bg = getComputedStyle(el).backgroundColor;
              return bg !== probe('--background-color-green-subtle') && bg !== probe('--background-color-red-subtle');
            });
            const meaning = root.querySelector(
              ".origin-diff-node[data-origin-change='changed'] .diff-wrap-changed input[name$='-meaning']");
            const added = root.querySelector(
              ".origin-diff-node[data-origin-change='added'] .diff-wrap-added input[name$='-name']");
            return {
              moved: ring(card('changed'), '--border-color-orange'),
              removed: ring(card('removed'), '--border-color-red'),
              field: !!meaning && ring(meaning, '--border-color-orange'),
              added: !!added && ring(added, '--border-color-green'),
              untinted,
              filled: root.querySelector('.origin-step-old, .origin-step-new') === null,
            };
          }
          """)
        let report = colors.object ?? [:]
        for key in ["moved", "removed", "field", "added", "untinted", "filled"] {
          #expect(report[key]?.bool == true, "\(key) is not drawn as the testament tree draws it: \(colors)")
        }
        if let folder = ProcessInfo.processInfo.environment["ORIGIN_DIFF_SCREENSHOTS"] {
          // From the tree's top: moved, kept, removed, changed and added.
          _ = try await diff.evaluate("(el) => el.scrollIntoView({ block: 'start' })")
          try await tab.screenshot(
            to: URL(fileURLWithPath: folder).appendingPathComponent(
              "origins-diff-v2-\(layout == .phone ? 375 : 1400).png"))
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
