import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Verbose opens every accordion below its switch in document order, never
/// the Pedigree above it (user, 2026-10-09), which stays the reader's to
/// open: on a Disputorium object's page, whose scope is the work under the
/// rule, and on a Computorium page, whose scope holds the Pedigree too.
@Suite("Disputorium verbose record scope", .serialized)
struct DisputoriumVerboseTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func overtureRuleOpensOnlyRecordWorkAndRestoresDefaultMetadata(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/mission-control/overtures/lexicographic/C0FFEE00-0000-4000-8000-000000000130")
      let toggle = page.locator(".lexicographic-overture-view .disputorium-core-content > .apparatus-rule-view .verbose-toggle-button-control")
      try await expect(toggle).toHaveAttribute("aria-pressed", "false")
      // A small button's label is 16px, like the pager and legend beside it.
      #expect(try await page.evaluate("""
        (()=>{const b=document.querySelector('.lexicographic-overture-view .disputorium-core-content > .apparatus-rule-view .verbose-toggle-button-control .button-view');
          const l=b.querySelector('.toggle-button-label');
          return b.getAttribute('data-size')+' '+getComputedStyle(l).fontSize;})()
        """, as: String.self) == "small 16px")
      try await expect(page.locator("#apparatus-metadata")).toHaveAttribute("data-expanded", "true")
      #expect(try await page.evaluate("""
        (()=>{const work=document.querySelector('.lexicographic-overture-view .disputorium-core-work');const rule=work.previousElementSibling;
          const metadata=work.querySelector('.record-metadata-change > .metadata-accordion-view > .accordion-view');
          const fields=[...work.querySelectorAll('#apparatus-metadata [data-metadata-added=true]')];
          const probe=document.createElement('span');document.body.append(probe);probe.style.borderColor='var(--border-color-base)';const neutral=getComputedStyle(probe).borderTopColor;
          probe.style.borderColor='var(--border-color-green)';const green=getComputedStyle(probe).borderTopColor;probe.remove();
          return rule.classList.contains('apparatus-rule-view') && metadata && getComputedStyle(metadata).borderTopColor===neutral
            && fields.length>0 && fields.every(e=>getComputedStyle(e).borderTopColor===green)
            && !work.querySelector('.prompt-previews-view');})()
        """, as: Bool.self))
      try await toggle.click()
      try await expect(toggle).toHaveAttribute("aria-pressed", "true")
      try await expect(page.locator(".lexicographic-overture-view .disputorium-core-work .accordion-details[data-expanded=false]")).toHaveCount(0)
      // Never the Pedigree above the switch (user, 2026-10-09): it stays
      // the reader's to open.
      try await expect(page.locator(".pedigree-accordion > .accordion-details")).toHaveAttribute("data-expanded", "false")
      try await toggle.click()
      try await expect(toggle).toHaveAttribute("aria-pressed", "false")
      try await expect(page.locator("#apparatus-metadata")).toHaveAttribute("data-expanded", "true")
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func computoriumVerboseLeavesThePedigreeAboveItClosed(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphonID = UUID().uuidString.lowercased()
    let runID = UUID().uuidString.lowercased()
    func remove() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM bibliographic_explication_runs WHERE id = '\(runID)';
        DELETE FROM bibliographic_antiphons WHERE id = '\(antiphonID)';
        COMMIT;
        """)
      work.remove()
    }
    do {
      let user = try admin.column("id")
      // One session with a thinking block and a compaction: its card's
      // accordions stand under the switch.
      let blocks: [[String: String]] = [
        ["type": "thinking", "content": "Reading the page."],
        [
          "type": "compaction", "mode": "auto", "micro": "0", "chars_before": "100", "chars_after": "60",
          "prompt": "Summarize.", "summary": "Kept the page.",
        ],
        ["type": "text", "content": "The page saved."],
      ]
      let output = String(decoding: try JSONSerialization.data(withJSONObject: blocks), as: UTF8.self)
        .replacingOccurrences(of: "'", with: "''")
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, canvas_service_ids_json, processing_status)
          VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO bibliographic_explication_runs (id, submission_id, process, canvas, attempt, provider, model, output, result, run_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
          VALUES ('\(runID)',
            (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'),
            'explication', '1', 1, 'DeepSeek', 'deepseek-flash', '\(output)', 'passed', gen_random_uuid(),
            '\(antiphonID)', 1200, now());
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/antiphons/bibliographic/\(antiphonID)")
        let scope = page.locator(".computorium-core-view")
        let pedigree = scope.locator(".pedigree-accordion > .accordion-details")
        try await expect(pedigree).toHaveAttribute("data-expanded", "false")
        let toggle = scope.locator(".verbose-toggle-button-control")
        // The Pedigree stands above the switch in its scope.
        let above = try await page.evaluate(
          """
          (() => { const p = document.querySelector('.computorium-core-view .pedigree-accordion');
            const t = document.querySelector('.computorium-core-view .verbose-toggle-button-view');
            return !!(p.compareDocumentPosition(t) & Node.DOCUMENT_POSITION_FOLLOWING) })()
          """)
        #expect(above == .bool(true), "the Pedigree is not above the switch")
        try await toggle.click()
        try await expect(toggle).toHaveAttribute("aria-pressed", "true")
        // Every accordion under the switch open; the Pedigree still closed.
        let below = try await page.evaluate(
          """
          (() => { const t = document.querySelector('.computorium-core-view .verbose-toggle-button-view');
            return [...document.querySelectorAll('.computorium-core-view .accordion-view')]
              .filter((a) => t.compareDocumentPosition(a) & Node.DOCUMENT_POSITION_FOLLOWING)
              .map((a) => a.querySelector(':scope > .accordion-details').getAttribute('data-expanded')) })()
          """)
        let states = below.array ?? []
        #expect(!states.isEmpty && states.allSatisfy { $0 == .string("true") }, "below the switch: \(below)")
        try await expect(pedigree).toHaveAttribute("data-expanded", "false")
        try await toggle.click()
        try await expect(toggle).toHaveAttribute("aria-pressed", "false")
        try await expect(pedigree).toHaveAttribute("data-expanded", "false")
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
