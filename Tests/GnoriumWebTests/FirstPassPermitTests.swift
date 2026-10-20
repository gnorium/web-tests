import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A first pass's sentiment reaches a record only by an admin's Permit of
/// the overture gnorium submitted (user, 2026-10-20). Its overture page
/// offers the admin Permit beside Commit, a person's overture none; the
/// Permit makes the record, postulated, whose sidebar says so with the
/// dotted ring and the word, the same on a phone. The fountain's Pedigree names the antiphon
/// and the page session that submitted it, linked, its submission
/// gnorium's. Chrome headless.
@Suite("First-pass permit", .serialized)
struct FirstPassPermitTests {
  @Test(arguments: [BrowserEngine.chrome])
  func anAdminPermitsGnoriumsOvertureIntoAPostulatedRecord(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let pass = try ScratchFirstPass(owner: admin)
    func cleanUp() async throws {
      pass.remove()
      try await admin.remove()
    }
    do {
      let page = "/mission-control/overtures/lexicographic/\(pass.overtureID)"
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { tab in
        try await tab.openHydrated(page)
        // Revise, Commit, Permit, Delete, in that order.
        let actions = try await tab.evaluate(
          "[...document.querySelectorAll('.disputorium-core-actions .button-view')].map(b => b.textContent.trim()).join(' ')",
          as: String.self)
        #expect(actions == "Revise Commit Permit Delete", "\(actions)")
        try await expect(tab.locator("form#overture-permit[action='\(page)/permit' i]")).toHaveCount(1)

        try await tab.locator("button[form='overture-permit']").click()
        try await expect(tab, timeout: .seconds(15)).toHaveURL("/lexico-records/eng/\(pass.title)/noun")
        #expect(try TestAdmin.query(
          "SELECT permitted_at IS NOT NULL FROM lexicographic_overtures WHERE id = '\(pass.overtureID)';") == "t")
        #expect(try TestAdmin.query(
          "SELECT lexico_record_id IS NOT NULL FROM sentiments WHERE uuid = '\(pass.sentimentID)';") == "t")
      }
      // The record's level in its sidebar, as text at a phone's width too:
      // postulated, nothing done yet: the dotted ring beside the word.
      for viewport in [Viewport.desktop, .phone] {
        try await withPage(engine, gnorium, viewport: viewport) { tab in
          try await tab.openHydrated("/lexico-records/eng/\(pass.title)/noun")
          // A phone reaches the sidebar through its menu.
          if viewport.width < 768 {
            try await tab.locator("[aria-label='Open menu']").filter(visible: true).first.click()
          }
          let level = tab.locator(".record-level-view").filter(visible: true).first
          try await expect(level).toBeVisible()
          try await expect(level.locator(".record-level-level")).toHaveText("Postulated")
          try await expect(level.locator(".record-level-level .icon-view .dotted-ring-view")).toHaveCount(1)
          try await expect(level.locator(".record-level-partial")).toHaveCount(0)
          try await expect(tab.locator(".record-sidebar-status")).toHaveCount(0)
          try await tab.expectNoHorizontalOverflow()
        }
      }
    } catch {
      do { try await cleanUp() } catch let removal {
        throw WebTestError("\(error)\n…and cleaning up failed too: \(removal)")
      }
      throw error
    }
    try await cleanUp()
  }

  /// A person's overture holds no sentiment of its own: no Permit.
  @Test(arguments: [BrowserEngine.chrome])
  func aPersonsOvertureHasNoPermit(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    func cleanUp() async throws {
      try await admin.remove()
    }
    do {
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { tab in
        // A person's Submit Sentiment, a working copy.
        let user = try admin.column("id")
        let submission = UUID().uuidString.lowercased()
        let fountain = UUID().uuidString.lowercased()
        let overture = UUID().uuidString.lowercased()
        let form = #"{"title":"webtestsperson\#(overture.prefix(8))","languageCode":"eng","class":"noun","spellings":[],"inflections":[],"origin":{"etymons":[],"citations":[],"derivation":""}}"#
        _ = try TestAdmin.query(
          """
          BEGIN;
          INSERT INTO submissions (id, user_id) VALUES ('\(submission)', '\(user)');
          INSERT INTO lexicographic_fountains (id, batch_id, language, order_in_batch, processing_status,
            title_form_json, anchors_json, created_at)
            VALUES ('\(fountain)', '\(submission)', 'eng', 0, 'pending', '\(form)', '[]', now());
          INSERT INTO lexicographic_overtures (id, lexicographic_fountain_id, title_form_json, anchors_json, created_at)
            VALUES ('\(overture)', '\(fountain)', '\(form)', '[]', now());
          COMMIT;
          """)
        defer {
          _ = try? TestAdmin.query(
            """
            BEGIN;
            DELETE FROM lexicographic_overtures WHERE id = '\(overture)';
            UPDATE lexicographic_fountains SET deleted_at = now(), deleted_by = '\(admin.username)'
              WHERE id = '\(fountain)' AND deleted_at IS NULL;
            COMMIT;
            """)
        }
        try await tab.openHydrated("/mission-control/overtures/lexicographic/\(overture)")
        try await expect(tab.locator("button[form='overture-delete']")).toHaveCount(1)
        try await expect(tab.locator("button[form='overture-permit']")).toHaveCount(0)
      }
    } catch {
      do { try await cleanUp() } catch let removal {
        throw WebTestError("\(error)\n…and cleaning up failed too: \(removal)")
      }
      throw error
    }
    try await cleanUp()
  }

  /// The fountain's Pedigree: the antiphon (linked), its page (linked to
  /// the antiphon open on it) and its session, under the fountain, whose
  /// submission is gnorium's.
  @Test(
    .disabled("gnorium-server does not yet pass LexicographicFountainView(firstPass:): the antiphon, page and nocturne"),
    arguments: [BrowserEngine.chrome])
  func theFountainsPedigreeNamesTheAntiphonAndItsPage(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let pass = try ScratchFirstPass(owner: admin)
    func cleanUp() async throws {
      pass.remove()
      try await admin.remove()
    }
    do {
      try await withPage(engine, gnorium, viewport: .phone, cookies: [admin.cookie]) { tab in
        try await tab.openHydrated("/mission-control/fountains/lexicographic/\(pass.fountainID)")
        let pedigree = tab.locator(".pedigree-view")
        try await pedigree.locator(".accordion-summary").first.click()
        let antiphon = "/mission-control/antiphons/bibliographic/\(pass.antiphonID)"
        try await expect(pedigree.locator("a[href='\(antiphon)']")).toHaveText(pass.antiphonID)
        try await expect(pedigree.locator("a[href='\(antiphon)?resemblance=1']")).toHaveText("1")
        try await expect(pedigree).toContainText(pass.nocturneID)
        let groups = try await tab.evaluate(
          "[...document.querySelectorAll('.pedigree-group')].map(g => g.querySelector('.datum-label').textContent.trim()).join(' ')",
          as: String.self)
        #expect(groups == "Fountain ID Antiphon ID", "Newest first: \(groups)")
        try await expect(pedigree.locator(".pedigree-group").first).toContainText("By gnorium")
        try await tab.expectNoHorizontalOverflow()
      }
    } catch {
      do { try await cleanUp() } catch let removal {
        throw WebTestError("\(error)\n…and cleaning up failed too: \(removal)")
      }
      throw error
    }
    try await cleanUp()
  }
}
