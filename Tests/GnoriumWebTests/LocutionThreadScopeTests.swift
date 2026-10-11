import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An object's thread is its own (user, 2026-10-10): the act that created
/// it, each commit of it, and the locutions written on it—never an earlier
/// version's acts or locutions, though they share an argument; its pedigree
/// shows those. The count counts what it shows.
@Suite("Locution thread scope", .serialized)
struct LocutionThreadScopeTests {
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
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, resemblance_service_ids_json, processing_status, created_at, updated_at)
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
        let events = page.locator(".locution-thread-event")
        try await expect(events).toHaveCount(1)
        try await expect(page.locator("#creation-\(laterID.uppercased())")).toHaveCount(1)
        try await expect(page.locator("#locution-\(laterLocutionID.uppercased())")).toHaveCount(1)
        try await expect(page.locator("#locution-\(earlierLocutionID.uppercased())")).toHaveCount(0)
        // Its one locution: the events beside it are not counted.
        try await expect(page.locator(".locution-thread-count")).toHaveText("1")

        // The earlier one: its creation and its commit, never the later's.
        try await page.openHydrated(scratch.madrigalPath)
        try await expect(events).toHaveCount(2)
        try await expect(page.locator("#creation-\(scratch.madrigalID.uppercased())")).toHaveCount(1)
        try await expect(page.locator("#creation-\(antiphonID.uppercased())")).toHaveCount(1)
        try await expect(page.locator("#creation-\(laterID.uppercased())")).toHaveCount(0)
        try await expect(page.locator("#locution-\(earlierLocutionID.uppercased())")).toHaveCount(1)
        try await expect(page.locator("#locution-\(laterLocutionID.uppercased())")).toHaveCount(0)
        try await expect(page.locator(".locution-thread-count")).toHaveText("1")
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
  /// edit leaves it); deleted, the original's quote reads "[deleted]";
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
        let replyButton = page.locator("\(quoted) .locution-reply-button")
        try await expect(replyButton).toBeVisible()
        try await expect(replyButton).toHaveAttribute("href", "?reply=\(quotedID.uppercased())#locution-thread-form")
        // Followed as the link it is: a click by position races the
        // thread's late layout (avatars, faded lines) on a busy machine.
        _ = try await page.evaluate(
          "(() => { document.querySelector('\(quoted) .locution-reply-button').click(); return 1 })()", as: Int.self)
        try await expect(page, timeout: .seconds(15)).toHaveURL("the page answering it", where: {
          $0.absoluteString.contains("reply=\(quotedID.uppercased())")
        })
        let replying = page.locator(".locution-thread-replying")
        try await expect(replying.locator(".locution-quote-author")).toHaveText(other.username)
        try await expect(replying.locator(".locution-quote-text")).toHaveText("The first page is misread.")
        try await page.locator("#locution-thread-locution-body").fill("Agreed; it reads 1611.")
        try await page.locator(".locution-thread-submit").click()
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
          "[...document.querySelectorAll('.locution-thread-entry')].map(e => e.id).join(' ')"
        ).string ?? ""
        let answered = order.range(of: "locution-\(quotedID.uppercased())")?.lowerBound
        let answering = order.range(of: "locution-\(replyID)")?.lowerBound
        #expect(answered != nil && answering != nil && answered! < answering!, "In time order: \(order)")
        // Edited: the quote keeps what it quoted.
        _ = try TestAdmin.query("UPDATE locutions SET content = 'The first page is right.' WHERE id = '\(quotedID)'")
        try await page.openHydrated(scratch.madrigalPath)
        try await expect(card.locator(".locution-quote-text")).toHaveText("The first page is misread.")
        // Hidden: the reader, not shown the original, is not shown its quote.
        _ = try TestAdmin.query("UPDATE locutions SET hidden_at = now() WHERE id = '\(quotedID)'")
        try await page.openHydrated(scratch.madrigalPath)
        try await expect(reply.locator(".locution-quote-view")).toHaveCount(0)
        // Deleted: "[deleted]".
        _ = try TestAdmin.query("UPDATE locutions SET hidden_at = NULL, deleted_at = now() WHERE id = '\(quotedID)'")
        try await page.openHydrated(scratch.madrigalPath)
        try await expect(card.locator(".locution-quote-text")).toHaveText("[deleted]")
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
