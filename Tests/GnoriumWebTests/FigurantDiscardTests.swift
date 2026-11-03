import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A figurant is a frozen form with no Discard of its own (user,
/// 2026-10-21): an admin's Discard of its overture takes it along and marks
/// it Discarded, the figurants register drops it unless the State filter asks
/// for the discarded, and Recover of the overture brings both back. A scratch lexicographic figurant
/// and overture of a throwaway admin, removed after.
@Suite("Figurant discard")
struct FigurantDiscardTests {
  @Test(arguments: gnorium.engines)
  func anOverturesDiscardAndRecoverCarryItsFigurant(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let submission = UUID().uuidString
    let figurant = UUID().uuidString
    let overture = UUID().uuidString
    func remove() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM lexicographic_overtures WHERE id = '\(overture)';
        UPDATE lexicographic_figurants SET discarded_at = now(), discarded_by = '\(admin.username)'
          WHERE id = '\(figurant)' AND discarded_at IS NULL;
        COMMIT;
        """)
    }
    do {
      let user = try admin.column("id")
      // A whole title form, as Submit Sentiment writes one (ScratchWord):
      // the figurant page reads it.
      let form = #"{"title":"webtestsdiscard","languageCode":"eng","class":"noun","origin":{"etymons":[],"citations":[],"derivation":""}}"#
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO submissions (id, user_id) VALUES ('\(submission)', '\(user)');
        INSERT INTO lexicographic_figurants (id, batch_id, language, order_in_batch, processing_status,
          title_form_json, anchors_json, created_at)
          VALUES ('\(figurant)', '\(submission)', 'eng', 0, 'pending', '\(form)', '[]', now());
        INSERT INTO lexicographic_overtures (id, lexicographic_figurant_id, title_form_json, anchors_json, created_at)
          VALUES ('\(overture)', '\(figurant)', '\(form)', '[]', now());
        COMMIT;
        """)
      let page = "/mission-control/figurants/lexicographic/\(figurant)"
      let register = "/mission-control/figurants/lexicographic"
      try await withPage(engine, gnorium, cookies: [admin.cookie]) { tab in
        let status = tab.locator(".mission-control-object-header-status-chip")
        try await tab.openHydrated(page)
        try await expect(status).toContainText("Submitted")
        try await expect(tab.locator("button[form='object-recover']")).toHaveCount(0)
        try await expect(tab.locator("button[form='object-discard']")).toHaveCount(0)
        // The overture's page: Discard asks first, saying what goes with it.
        try await tab.openHydrated("/mission-control/overtures/lexicographic/\(overture)")
        try await tab.locator("button[form='overture-discard']").click()
        let confirm = tab.locator(".mission-control-object-header-confirm")
        try await expect(confirm).toContainText("This also discards the submission it came from.")
        try await confirm.locator(".dialog-primary-button").click()
        try await expect(tab, timeout: .seconds(15)).toHaveURL("/mission-control/overtures/lexicographic")
        try await tab.openHydrated(page)
        try await expect(status).toContainText("Discarded")
        try await expect(tab.locator("button[form='object-recover']")).toHaveCount(0)
        try await expect(tab.locator(".pedigree-view")).toContainText("Discarded")
        #expect(try TestAdmin.query("SELECT discarded_by FROM lexicographic_overtures WHERE id = '\(overture)';")
          == admin.username)

        // Gone from the register; there with the State filter.
        try await tab.openHydrated(register)
        try await expect(tab.locator("a[href='\(page)']")).toHaveCount(0)
        try await tab.openHydrated(register + "?status=discarded")
        try await expect(tab.locator("a[href='\(page)']").first).toBeVisible()

        try await tab.openHydrated("/mission-control/overtures/lexicographic/\(overture)")
        // Its page again once the Recover is through (it checks the node is
        // held by no other), before the next page is asked for.
        try await expect(status, timeout: .seconds(15)).toContainText("Pending")
        try await tab.locator("button[form='overture-recover']").click()
        try await tab.openHydrated(page)
        try await expect(status).toContainText("Submitted")
        #expect(try TestAdmin.query("SELECT coalesce(discarded_by, '') FROM lexicographic_overtures WHERE id = '\(overture)';")
          == "")
      }
    } catch {
      remove()
      try await admin.remove(after: error)
    }
    remove()
    try await admin.remove()

  /// Its submitter discards their own overture (user, 2026-11-03), nobody
  /// else: a plain account that submitted the figurant sees Discard, gray
  /// in the header's row; it asks first, in the header's dialog with Cancel
  /// and a blue Discard (an admin's Recover undoes it, so it is no red act);
  /// Cancel posts nothing. Confirmed, the overture is kept, Discarded, gone
  /// from its list, and its thread says who discarded it. Another plain
  /// account is offered no Discard; the submitter, no Recover.
  @Test(arguments: gnorium.engines)
  func aSubmitterDiscardsTheirOwnOvertureAfterConfirming(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let submitter = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let stranger: TestAdmin
    do {
      stranger = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    } catch {
      try await submitter.remove(after: error)
    }
    let submission = UUID().uuidString
    let figurant = UUID().uuidString
    let overture = UUID().uuidString
    func remove() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM lexicographic_overtures WHERE id = '\(overture)';
        UPDATE lexicographic_figurants SET discarded_at = now(), discarded_by = '\(submitter.username)'
          WHERE id = '\(figurant)' AND discarded_at IS NULL;
        COMMIT;
        """)
    }
    func removeAccounts() async throws {
      try await stranger.remove()
      try await submitter.remove()
    }
    do {
      let user = try submitter.column("id")
      let form = #"{"title":"webtestsowndiscard","languageCode":"eng","class":"noun","origin":{"etymons":[],"citations":[],"derivation":""}}"#
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO submissions (id, user_id) VALUES ('\(submission)', '\(user)');
        INSERT INTO lexicographic_figurants (id, batch_id, language, order_in_batch, processing_status,
          title_form_json, anchors_json, created_at)
          VALUES ('\(figurant)', '\(submission)', 'eng', 0, 'pending', '\(form)', '[]', now());
        INSERT INTO lexicographic_overtures (id, lexicographic_figurant_id, title_form_json, anchors_json, created_at)
          VALUES ('\(overture)', '\(figurant)', '\(form)', '[]', now());
        COMMIT;
        """)
      let page = "/mission-control/overtures/lexicographic/\(overture)"
      let discard = "button[form='overture-discard']"
      try await withPage(engine, gnorium, cookies: [stranger.cookie]) { tab in
        try await tab.openHydrated(page)
        try await expect(tab.locator(".mission-control-object-header-status-chip")).toContainText("Pending")
        try await expect(tab.locator(discard)).toHaveCount(0)
      }
      try await withPage(engine, gnorium, cookies: [submitter.cookie]) { tab in
        let status = tab.locator(".mission-control-object-header-status-chip")
        try await tab.openHydrated(page)
        try await expect(tab.locator(discard)).toHaveAttribute("data-color", "gray")
        // Asked first; Cancel posts nothing.
        let confirm = tab.locator(".mission-control-object-header-confirm")
        try await expect(confirm, timeout: .seconds(20)).toHaveAttribute("data-confirm-bound", "true")
        try await tab.locator(discard).click()
        try await expect(confirm.locator(".dialog-view")).toBeVisible()
        try await expect(confirm).toContainText("This also discards the submission it came from.")
        try await expect(confirm.locator(".dialog-primary-button .button-view")).toHaveAttribute("data-color", "blue")
        try await confirm.locator(".dialog-default-button .button-view").click()
        try await expect(confirm.locator(".dialog-view")).toBeHidden()
        #expect(try TestAdmin.query("SELECT coalesce(discarded_by, '') FROM lexicographic_overtures WHERE id = '\(overture)';")
          == "")
        // Confirmed: to its list, where it is shown no more.
        try await tab.locator(discard).click()
        try await confirm.locator(".dialog-primary-button .button-view").click()
        try await expect(tab, timeout: .seconds(15)).toHaveURL("/mission-control/overtures/lexicographic")
        // Matched in any case: a count of none must not pass on a spelling.
        try await expect(tab.locator("a[href='\(page)' i]")).toHaveCount(0)
        #expect(try TestAdmin.query("SELECT discarded_by FROM lexicographic_overtures WHERE id = '\(overture)';")
          == submitter.username)
        try await tab.openHydrated(page)
        try await expect(status).toContainText("Discarded")
        try await expect(tab.locator(discard)).toHaveCount(0)
        try await expect(tab.locator("button[form='overture-recover']")).toHaveCount(0)
        try await expect(tab.locator(".thread-view")).toContainText("discarded overture")
      }
    } catch {
      remove()
      do { try await stranger.remove() } catch {}
      try await submitter.remove(after: error)
    }
    remove()
    try await removeAccounts()
  }

  /// An amendment's submitter discards the madrigal it reopened, before its
  /// first Commit or Permit (user, 2026-11-03): Discard asks first, saying
  /// the node it holds goes free, then the madrigal is kept, Discarded, gone
  /// from its list, and the node it held may be amended again at once. A
  /// plain account's scratch work (`ScratchWork`): its digitization removed
  /// as the amendment's one subject.
  @Test(arguments: gnorium.engines)
  func anAmendmentsSubmitterDiscardsItsMadrigalAndItsHoldGoes(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let submitter = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let work = try ScratchWork(owner: submitter)
    let record = work.recordID
    func clean() {
      // Its Palinode is submitted input, frozen: it stays.
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM revisions WHERE revisable_id IN
          (SELECT id FROM bibliographic_madrigals WHERE biblio_record_id = '\(record)' AND id <> '\(work.madrigalID)');
        DELETE FROM bibliographic_madrigals WHERE biblio_record_id = '\(record)' AND id <> '\(work.madrigalID)';
        COMMIT;
        """)
    }
    do {
      try await withPage(engine, gnorium, cookies: [submitter.cookie]) { page in
        try await page.openHydrated("\(work.path)/amendments/new")
        let manifest = page.locator(".outliner-item[data-outliner-id^='manifest-']:not([data-testament-draft])")
        let heldMarker = manifest.locator(":scope > .outliner-row .record-node-marker").first
        try await expect(heldMarker).toBeAttached()
        try await expect(heldMarker).not.toHaveAttribute("data-outliner-held", "true")
        _ = try await manifest.evaluate(
          """
          (item) => {
            const d = item.querySelector(':scope > .outliner-row details');
            if (!d.open) d.querySelector(':scope > summary').click();
            return d.open;
          }
          """)
        let removal = page.locator(".testament-outliner-remove-dialog")
        try await TreeStepper(page, tree: "testament-outliner").remove("Remove testament 1.1.")
        try await removal.locator("button").filter(hasText: "Remove").first.click()
        try await expect(manifest).toHaveAttribute("data-outline-state", "removed")
        try await page.locator(".record-actions button[type='submit']").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the reopened madrigal") {
          $0.path.hasPrefix("/mission-control/madrigals/bibliographic/")
        }
        let madrigal = try TestAdmin.query(
          "SELECT upper(id::text) FROM bibliographic_madrigals WHERE biblio_record_id = '\(record)' AND id <> '\(work.madrigalID)';"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        // Held while it is open.
        try await page.openHydrated("\(work.path)/amendments/new")
        try await page.locator(".testament-outliner-hint").first.evaluate("(hint) => document.body.click()")
        try await expect(heldMarker).toHaveAttribute("data-outliner-held", "true")
        try await page.openHydrated("/mission-control/madrigals/bibliographic/\(madrigal)")

        // Gray in the header's row; asked first, the blue Discard of the
        // header's dialog saying what it takes along.
        let discard = page.locator("button[form='madrigal-discard']")
        try await expect(discard).toHaveAttribute("data-color", "gray")
        let confirm = page.locator(".mission-control-object-header-confirm")
        try await expect(confirm, timeout: .seconds(20)).toHaveAttribute("data-confirm-bound", "true")
        try await discard.click()
        try await expect(confirm.locator(".dialog-view")).toBeVisible()
        try await expect(confirm).toContainText("This also releases the testament it holds.")
        try await expect(confirm.locator(".dialog-primary-button .button-view")).toHaveAttribute("data-color", "blue")
        try await confirm.locator(".dialog-primary-button .button-view").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("/mission-control/madrigals/bibliographic")
        try await expect(page.locator("a[href*='\(madrigal)' i]")).toHaveCount(0)
        #expect(try TestAdmin.query(
          "SELECT processing_status || ' ' || discarded_by FROM bibliographic_madrigals WHERE id = '\(madrigal)';"
        ) == "discarded \(submitter.username)")

        // Kept, Discarded, its thread saying so; no Discard again and no
        // Recover for its submitter.
        try await page.openHydrated("/mission-control/madrigals/bibliographic/\(madrigal)")
        try await expect(page.locator(".mission-control-object-header-status-chip")).toContainText("Discarded")
        try await expect(discard).toHaveCount(0)
        try await expect(page.locator("button[form='madrigal-recover']")).toHaveCount(0)
        try await expect(page.locator(".thread-view")).toContainText("discarded madrigal")

        // Its hold released at once: the digitization is free to amend.
        try await page.openHydrated("\(work.path)/amendments/new")
        try await page.locator(".testament-outliner-hint").first.evaluate("(hint) => document.body.click()")
        try await expect(heldMarker).toBeAttached()
        try await expect(heldMarker).not.toHaveAttribute("data-outliner-held", "true")
        try await expect(manifest).toBeAttached()
        try await expect(manifest).not.toHaveAttribute("data-outliner-hold")
        try await page.expectNoErrors()
      }
    } catch {
      clean()
      work.remove()
      try await submitter.remove(after: error)
    }
    clean()
    work.remove()
    try await submitter.remove()
  }
  }
}
