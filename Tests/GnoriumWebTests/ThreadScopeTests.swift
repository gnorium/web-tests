import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An object's thread is its own (user, 2026-10-10): the act that created
/// it, each commit of it, and the locutions written on it—never an earlier
/// version's acts or locutions, though they share an argument; its pedigree
/// shows those. The count counts what it shows.
@Suite("Locution thread scope", .serialized)
struct ThreadScopeTests {
  @Test(arguments: [BrowserEngine.chrome])
  func aMadrigalsThreadShowsOnlyItsOwnActsAndLocutions(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let scratch: ScratchCommit
    do { scratch = try ScratchCommit(owner: contributor) }
    catch { try await contributor.remove(after: error) }
    let antiphonID = UUID().uuidString.lowercased()
    let laterID = UUID().uuidString.lowercased()
    let earlierLocutionID = UUID().uuidString.lowercased()
    let laterLocutionID = UUID().uuidString.lowercased()
    func removeLater() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM locutions WHERE id IN ('\(earlierLocutionID)', '\(laterLocutionID)');
        DELETE FROM bibliographic_madrigals WHERE id = '\(laterID)';
        DELETE FROM bibliographic_antiphons WHERE id = '\(antiphonID)';
        COMMIT;
        """)
    }
    do {
      let user = try contributor.column("id")
      // The scratch madrigal committed into an antiphon, submitted as a
      // later version in its argument.
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, image_service_ids_json, processing_status, created_at, updated_at)
          VALUES ('\(antiphonID)', '\(scratch.madrigalID)', '\(user)', '[]', 'submitted', now(), now());
        INSERT INTO bibliographic_madrigals (id, thread_id, bibliographic_antiphon_id, proposed_content_json, metadata_json, processing_status, created_at, updated_at)
          VALUES ('\(laterID)', '\(scratch.madrigalID)', '\(antiphonID)', '{"teiXml":""}', '{"language":"eng","sourceUrl":"\(ScratchCommit.sourceURL)","sourceKind":"iiif-manifest"}', 'pending', now(), now());
        INSERT INTO locutions (id, locutable_type, locutable_id, author_id, content, created_at)
          VALUES ('\(earlierLocutionID)', 'bibliographic_madrigal', '\(scratch.madrigalID.lowercased())', '\(user)', 'On the earlier reading.', now()),
                 ('\(laterLocutionID)', 'bibliographic_madrigal', '\(laterID)', '\(user)', 'On the later reading.', now());
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        // The later version: its creation and its own locution alone.
        try await page.openHydrated("/mission-control/madrigals/bibliographic/\(laterID)")
        let events = page.locator(".thread-event")
        try await expect(events).toHaveCount(1)
        try await expect(page.locator("#creation-\(laterID.uppercased())")).toHaveCount(1)
        try await expect(page.locator("#locution-\(laterLocutionID.uppercased())")).toHaveCount(1)
        try await expect(page.locator("#locution-\(earlierLocutionID.uppercased())")).toHaveCount(0)
        // Its one locution: the events beside it are not counted.
        try await expect(page.locator(".thread-count")).toHaveText("1")

        // The earlier one: its creation and its commit, never the later's.
        try await page.openHydrated(scratch.madrigalPath)
        try await expect(events).toHaveCount(2)
        try await expect(page.locator("#creation-\(scratch.madrigalID.uppercased())")).toHaveCount(1)
        try await expect(page.locator("#creation-\(antiphonID.uppercased())")).toHaveCount(1)
        try await expect(page.locator("#creation-\(laterID.uppercased())")).toHaveCount(0)
        try await expect(page.locator("#locution-\(earlierLocutionID.uppercased())")).toHaveCount(1)
        try await expect(page.locator("#locution-\(laterLocutionID.uppercased())")).toHaveCount(0)
        try await expect(page.locator(".thread-count")).toHaveText("1")
        try await page.expectNoErrors()
      }
    } catch {
      removeLater()
      scratch.remove()
      try await contributor.remove(after: error)
    }
    removeLater()
    scratch.remove()
    try await contributor.remove()
  }

  /// A reply quotes what it answers (user, 2026-10-11): Reply on a
  /// locution sets the composer, which shows the quote; posted, the reply
  /// sits in time order with a quote card above its words, linked to the
  /// quoted locution. The card keeps the words as they were when quoted (an
  /// edit leaves it); nullified, the original's quote reads "[nullified]";
  /// hidden, the card is left out for whoever is not shown the original.
  @Test(arguments: [BrowserEngine.chrome])
  func aReplyQuotesTheLocutionItAnswers(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let scratch: ScratchCommit
    do { scratch = try ScratchCommit(owner: contributor) }
    catch { try await contributor.remove(after: error) }
    // The quoted locution is another's, so its hiding hides it from the
    // reader.
    let other: TestAdmin
    do { other = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false) }
    catch { scratch.remove(); try await contributor.remove(after: error) }
    let quotedID = UUID().uuidString.lowercased()
    func removeLocutions() {
      _ = try? TestAdmin.query("DELETE FROM locutions WHERE locutable_id = '\(scratch.madrigalID.lowercased())'")
    }
    do {
      let user = try other.column("id")
      _ = try TestAdmin.query(
        """
        INSERT INTO locutions (id, locutable_type, locutable_id, author_id, content, created_at)
          VALUES ('\(quotedID)', 'bibliographic_madrigal', '\(scratch.madrigalID.lowercased())', '\(user)', 'The **first** page is misread.', now() - interval '1 minute')
        """)
      let quoted = "#locution-\(quotedID.uppercased())"
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated(scratch.madrigalPath)
        // Nothing above the thread moves once drawn (user, 2026-10-11): the
        // prompts' loading boxes stand as tall as the previews that replace
        // them, and no shift has moved the thread.
        try await expect(page.locator(".prompt-previews-slot").first, timeout: .seconds(30)).toHaveAttribute("aria-busy", "false")
        let reserved = try await page.evaluate("""
          fetch(location.href).then(r => r.text()).then(html => {
            const doc = new DOMParser().parseFromString(html, 'text/html');
            const n = doc.querySelectorAll('.prompt-previews-loading').length;
            return JSON.stringify({n, loaded: Math.round(document.querySelector('.prompt-previews-slot').getBoundingClientRect().height)});
          })
          """).string ?? ""
        struct Reserved: Decodable { let n: Int; let loaded: Int }
        let heights = try JSONDecoder().decode(Reserved.self, from: Data(reserved.utf8))
        #expect(heights.n > 0 && heights.loaded == heights.n * 56 + (heights.n - 1) * 16, "Reserved as loaded: \(reserved)")
        let shifted = try await page.evaluate("""
          new Promise(done => { let sum = 0; new PerformanceObserver(list => { for (const e of list.getEntries())
            if (e.sources.some(x => x.node && x.node.closest && x.node.closest('.disputorium-core-locutions'))) sum += e.value; })
            .observe({type: 'layout-shift', buffered: true}); setTimeout(() => done(sum), 500); })
          """).double ?? -1
        #expect(shifted == 0, "No layout shift in the thread: \(shifted)")
        let replyButton = page.locator("\(quoted) .locution-reply-button")
        try await expect(replyButton).toBeVisible()
        try await expect(replyButton).toHaveAttribute("href", "?reply=\(quotedID.uppercased())#thread-form")
        try await replyButton.click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the page answering it", where: {
          $0.absoluteString.contains("reply=\(quotedID.uppercased())")
        })
        let replying = page.locator(".thread-replying")
        try await expect(replying.locator(".locution-quote-author")).toHaveText(other.username)
        try await expect(replying.locator(".locution-quote-text")).toHaveText("The first page is misread.")
        try await page.locator("#thread-locution-body").fill("Agreed; it reads 1611.")
        try await page.locator(".thread-submit").click()
        for _ in 0..<60 {
          let count = try TestAdmin.query(
            "SELECT count(*) FROM locutions WHERE parent_id = '\(quotedID)'")
          if count.trimmingCharacters(in: .whitespacesAndNewlines) == "1" { break }
          try await Task.sleep(for: .milliseconds(250))
        }
        let replyID = try TestAdmin.query("SELECT id FROM locutions WHERE parent_id = '\(quotedID)'")
          .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        try await page.openHydrated(scratch.madrigalPath)
        let reply = page.locator("#locution-\(replyID)")
        let card = reply.locator(".locution-quote-view a")
        try await expect(card).toHaveAttribute("href", "#locution-\(quotedID.uppercased())")
        try await expect(card.locator(".locution-quote-text")).toHaveText("The first page is misread.")
        try await expect(reply.locator(".locution-body")).toContainText("Agreed; it reads 1611.")
        // In time order: the reply after what it answers.
        let order = try await page.evaluate(
          "[...document.querySelectorAll('.thread-entry')].map(e => e.id).join(' ')"
        ).string ?? ""
        let answered = order.range(of: "locution-\(quotedID.uppercased())")?.lowerBound
        let answering = order.range(of: "locution-\(replyID)")?.lowerBound
        #expect(answered != nil && answering != nil && answered! < answering!, "In time order: \(order)")
        // Edited: the quote keeps what it quoted.
        _ = try TestAdmin.query("UPDATE locutions SET content = 'The first page is right.' WHERE id = '\(quotedID)'")
        try await page.openHydrated(scratch.madrigalPath)
        try await expect(card.locator(".locution-quote-text")).toHaveText("The first page is misread.")
        // Discarded: the reader, not shown the original's words, is not
        // shown its quote's either (user, 2026-10-21).
        _ = try TestAdmin.query("UPDATE locutions SET discarded_at = now(), discarded_by = 'admin' WHERE id = '\(quotedID)'")
        try await page.openHydrated(scratch.madrigalPath)
        try await expect(card.locator(".locution-quote-text")).toHaveText("[discarded]")
        // Nullified: "[nullified]".
        _ = try TestAdmin.query("UPDATE locutions SET discarded_at = NULL, discarded_by = NULL, nullified_at = now(), content = '' WHERE id = '\(quotedID)'")
        try await page.openHydrated(scratch.madrigalPath)
        try await expect(card.locator(".locution-quote-text")).toHaveText("[nullified]")
        try await page.expectNoErrors()
      }
    } catch {
      removeLocutions()
      scratch.remove()
      try? await other.remove()
      try await contributor.remove(after: error)
    }
    removeLocutions()
    scratch.remove()
    try await other.remove()
    try await contributor.remove()
  }
}
