import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An origin's evidence (design-notes/origin-evidence.md, user 2026-11-01):
/// on an overture's Revise page an origin's "+ Source" asks for a Source box,
/// filled with its testament's Source URL, the image the quote is on and
/// its sentence, and what it attests; Suggest reads it into an anchor in
/// that permitted testament (the quotes service), and the thread's line
/// names it "Origin 2 › Source 1", and the revision's page
/// draws the quote under its origin. A madrigal carrying that origin:
/// Permit refuses it while its quote names no permitted testament's page;
/// with the quote in place it publishes it, and the record's page draws
/// the quote under its origin.
///
/// Needs the quotes service the server under test reads
/// (`GNORIUM_QUOTES_URL`, default http://127.0.0.1:8006): the scratch
/// testament's version is indexed there, as a Permit indexes one, and the
/// test is cancelled when none answers. A throwaway admin owns the scratch
/// testament, the overture revised and the madrigal permitted, removed
/// after.
@Suite("Origin evidence", .serialized)
struct OriginEvidenceTests {
  static var quotesURL: String {
    ProcessInfo.processInfo.environment["GNORIUM_QUOTES_URL"].flatMap { $0.isEmpty ? nil : $0 }
      ?? "http://127.0.0.1:8006"
  }

  static let words = "Whole quartos of scratch evidence"

  /// One page, its words in one sentence.
  static func tei(image: String) -> String {
    #"<TEI><text><body><pb n="1" facs="\#(image)/full/1300,/0/default.jpg"/><p><s>\#(words) stand on this page.</s></p></body></text></TEI>"#
  }

  /// Posts JSON to the quotes service; nil when it does not answer.
  static func post(_ path: String, _ body: [String: Any]) async -> (Int, Data)? {
    guard let url = URL(string: quotesURL + path),
      let data = try? JSONSerialization.data(withJSONObject: body)
    else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = data
    request.timeoutInterval = 10
    guard let (answer, response) = try? await URLSession.shared.data(for: request),
      let http = response as? HTTPURLResponse
    else { return nil }
    return (http.statusCode, answer)
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aQuoteIsAddedToAnOriginAndPermitted(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let suffix = String(UUID().uuidString.prefix(8)).lowercased()
    let image = "https://web-tests.invalid/iiif/origin-evidence-\(suffix)-p1"
    let source = "https://web-tests.invalid/origin-evidence-\(suffix).json"
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    var testament: ScratchTestament?
    var reading: ScratchReading?
    var revisedOverture: ScratchOverture?
    func clean() {
      if let revisedOverture {
        _ = try? TestAdmin.query(
          """
          BEGIN;
          DELETE FROM locutions WHERE locutable_id = '\(revisedOverture.overtureID)';
          DELETE FROM revisions WHERE revisable_id = '\(revisedOverture.overtureID)';
          COMMIT;
          """)
        revisedOverture.remove()
      }
      if let reading {
        let record = reading.work.recordID.lowercased()
        _ = try? TestAdmin.query(
          """
          BEGIN;
          DELETE FROM locutions WHERE locutable_id = '\(reading.madrigalID)';
          DELETE FROM revisions WHERE revisable_id = '\(reading.madrigalID)';
          DELETE FROM inferred_citation_jobs WHERE record_id = '\(record)';
          DELETE FROM biblio_record_origin_quote_roles WHERE quote_id IN (SELECT id FROM biblio_record_origin_quotes
            WHERE origin_id IN (SELECT id FROM biblio_record_origins WHERE biblio_record_id = '\(record)'));
          DELETE FROM biblio_record_origin_quotes WHERE origin_id IN
            (SELECT id FROM biblio_record_origins WHERE biblio_record_id = '\(record)');
          DELETE FROM biblio_record_origin_relations WHERE origin_id IN
            (SELECT id FROM biblio_record_origins WHERE biblio_record_id = '\(record)');
          DELETE FROM biblio_record_origins WHERE biblio_record_id = '\(record)';
          DELETE FROM biblio_record_versions WHERE biblio_record_id = '\(record)'
            AND id <> '\(reading.work.versionID.lowercased())';
          COMMIT;
          """)
        reading.remove()
      }
      if let testament {
        _ = try? TestAdmin.query(
          """
          DELETE FROM survey_images WHERE witness_id = (SELECT bibliographic_figurant_id FROM bibliographic_overtures
            WHERE id = '\(testament.reading.work.overtureID)');
          """)
      }
      testament?.remove()
    }
    do {
      // The testament quoted: permitted, its version indexed.
      let quoted = try ScratchTestament(owner: admin, tei: Self.tei(image: image), sourceURL: source)
      testament = quoted
      let indexed = await Self.post(
        "/index",
        [
          "biblio_record_id": quoted.reading.work.recordID.lowercased(), "version_id": quoted.versionID,
          "testament_id": UUID().uuidString.lowercased(), "language_code": "eng",
          "permitted_at": ISO8601DateFormatter().string(from: Date()), "permitter_id": try admin.column("id"),
          "images": [["image_id": image, "tei_xml": Self.tei(image: image)]],
        ])
      guard let indexed else {
        clean()
        try await admin.remove()
        try Test.cancel("No quotes service answers at \(Self.quotesURL) (GNORIUM_QUOTES_URL).")
      }
      #expect(indexed.0 == 200, "\(String(decoding: indexed.1, as: UTF8.self))")
      // Its image 1, as its survey numbers it, read in its permitted
      // version: what a quote's image number is found on.
      let witness = try TestAdmin.query(
        "SELECT bibliographic_figurant_id FROM bibliographic_overtures WHERE id = '\(quoted.reading.work.overtureID)';"
      ).trimmingCharacters(in: .whitespacesAndNewlines)
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO survey_images (id, witness_id, ordinal, label, image_url)
          VALUES (gen_random_uuid(), '\(witness)', 1, '1', '\(image)/full/1300,/0/default.jpg');
        UPDATE biblio_record_versions SET page_readings_json = '{"\(image)": "web-tests"}' WHERE id = '\(quoted.versionID)';
        COMMIT;
        """)

      // The overture revised: two typed origins, the second to be quoted.
      let scratch = try ScratchOverture(owner: admin, sealed: false)
      revisedOverture = scratch
      func step(_ title: String) -> String {
        #"{"id":"\#(UUID().uuidString)","relations":["based_on"],"typed":{"title":"\#(title)","voices":[]},"origins":[]}"#
      }
      _ = try TestAdmin.query(
        """
        UPDATE bibliographic_overtures
          SET origins_json = '[\(step("Web tests source one")),\(step("Web tests source two"))]',
            provider = 'British Library'
          WHERE id = '\(scratch.overtureID)';
        """)
      let overture = scratch.path
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("\(overture)/revise")
        let rows = page.locator("[data-revise-form] .origin-field-view [data-origin-row='true']")
        try await expect(rows).toHaveCount(2)
        let second = rows.nth(1)
        // Its Outgoing citations (user, 2026-11-03): "+ Citation" stamps a
        // card, its claim the step itself, its Source the form's.
        let add = second.locator(".outgoing-citations-actions .outgoing-citations-add")
        try await expect(add).toHaveText("Citation")
        try await expect(add).toHaveAttribute("aria-label", "Add citation")
        try await add.click()
        let citation = second.locator(".outgoing-citations-list > .outgoing-citation")
        let card = citation.locator(".evidence-source-view")
        try await expect(card).toHaveCount(1)
        // Its record field in place (it is asked for as the box comes),
        // so nothing moves under the next press.
        try await expect(card.locator(".quote-passage-record .origin-record-field-view"), timeout: .seconds(15))
          .toHaveCount(1)
        // Removed by its own "− Citation", added again.
        try await citation.locator(".quote-passage-actions .quote-passage-citation-remove").click()
        try await expect(card).toHaveCount(0)
        try await add.click()
        try await expect(card).toHaveCount(1)
        try await expect(card.locator(".quote-passage-record .origin-record-field-view"), timeout: .seconds(15))
          .toHaveCount(1)
        try await expect(rows.nth(0).locator(".outgoing-citation")).toHaveCount(0)
        // Its Source: its URL in its accordion, the quote typed in its Quote
        // card's text pane.
        try await expect(card.locator(".source-accordion-view .accordion-title").first).toHaveText("Source")
        try await card.locator("input[name$='-source-url']").fill(source)
        let pane = card.locator(".quote-passage-quote .quote-passage-text .tei-page-text").first
        try await expect(pane, timeout: .seconds(20)).toBeAttached()
        try await pane.fill(Self.words)
        // Its form picked as any quote's (user, 2026-11-03): a selection
        // and "+ Form", carried word for word onto the anchor it is read
        // into.
        try await page.addForm(in: card, from: ".quote-typed-word[data-typed-word='2']")
        try await expect(card.locator(".quote-typed-word[data-highlight='title']")).toHaveText("quartos")
        try await page.expectNoHorizontalOverflow()
        if let folder = ProcessInfo.processInfo.environment["NOTE_SCREENSHOTS"] {
          _ = try await card.evaluate("(el) => el.scrollIntoView({ block: 'center' })")
          try await page.screenshot(
            to: URL(fileURLWithPath: folder).appendingPathComponent("origin-quote-revise-\(layout).png"))
        }
        try await page.locator("button[type='submit']").filter(hasText: "Suggest").click()
        try await expect(page, timeout: .seconds(20)).toHaveURL("the overture at its locution") { url in
          url.path.lowercased() == overture.lowercased() && (url.fragment ?? "").hasPrefix("revision-")
        }
        let revision = try TestAdmin.query(
          "SELECT id FROM revisions WHERE revisable_id = '\(scratch.overtureID)' ORDER BY created_at DESC LIMIT 1;"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!revision.isEmpty, "no revision was filed")
        // Read into an anchor in the permitted testament, never kept typed.
        let content = try TestAdmin.query("SELECT content_json FROM revisions WHERE id = '\(revision)';")
        #expect(content.lowercased().contains(quoted.versionID), "the quote is not anchored: \(content)")
        #expect(!content.contains(Self.words), "the typed words were kept: \(content)")
        #expect(content.contains("\"forms\""), "its form carried onto its anchor: \(content)")

        // The thread's line: "Origin 2 › Citation 1".
        let line = page.locator(".thread-event-changed").last
        try await expect(line).toBeVisible()
        let text = try await line.evaluate("(el) => el.textContent.replace(/\\s+/g, ' ')")
        let said = text.string ?? ""
        #expect(
          said.contains("Origin 2") && said.contains("Citation 1") && !said.contains("Origin 1"),
          "the Changed line does not name Origin 2 › Citation 1: \(said)")
        if let folder = ProcessInfo.processInfo.environment["NOTE_SCREENSHOTS"] {
          _ = try await line.evaluate("(el) => el.scrollIntoView({ block: 'center' })")
          try await page.screenshot(
            to: URL(fileURLWithPath: folder).appendingPathComponent("origin-quote-thread-\(layout).png"))
        }

        // The revision's page draws the quote under its origin.
        try await page.openHydrated("\(overture)/revisions/\(revision)")
        try await expect(page.locator(".outgoing-citations-view .attestation-view").first).toBeAttached()
        try await page.expectNoHorizontalOverflow()

        // A madrigal whose origin is the one revised.
        let origins = try TestAdmin.query(
          "SELECT content_json::json -> 'origins' FROM revisions WHERE id = '\(revision)';"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(origins.lowercased().contains(quoted.versionID), "\(origins)")
        let revised = try ScratchReading(owner: admin, tei: Self.tei(image: image + "-revised"))
        reading = revised
        let settled = origins.replacingOccurrences(of: "'", with: "''")
        _ = try TestAdmin.query(
          "UPDATE bibliographic_madrigals SET origins_json = '\(settled)' WHERE id = '\(revised.madrigalID)';")
        let madrigal = revised.path

        // Permit refuses a quote no permitted testament holds.
        let stranger = UUID().uuidString.lowercased()
        _ = try TestAdmin.query(
          """
          UPDATE bibliographic_madrigals SET origins_json = replace(replace(origins_json, '\(quoted.versionID)', '\(stranger)'),
            '\(quoted.versionID.uppercased())', '\(stranger)')
            WHERE id = '\(revised.madrigalID)';
          """)
        try await page.openHydrated(madrigal)
        try await page.locator("button[form='madrigal-permit']").click()
        try await expect(page.locator("body"), timeout: .seconds(15)).toContainText("names no permitted testament")
        let refused = try TestAdmin.query(
          "SELECT count(*) FROM biblio_record_versions WHERE biblio_record_id = '\(revised.work.recordID.lowercased())';"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(refused == "1", "the refused Permit published a version")

        // In place, it permits; the record's page lists it under its origin.
        _ = try TestAdmin.query(
          "UPDATE bibliographic_madrigals SET origins_json = '\(settled)' WHERE id = '\(revised.madrigalID)';"
        )
        try await page.openHydrated(madrigal)
        try await page.locator("button[form='madrigal-permit']").click()
        try await expect(page.locator(".mission-control-object-header-status-chip"), timeout: .seconds(15))
          .toHaveText("Permitted")
        try await page.openHydrated(revised.work.path)
        let evidence = page.locator(".origin-view .outgoing-citations-view")
        try await expect(evidence.locator(".attestation-view")).toHaveCount(1)
        // Under the second origin, the first has none.
        let order = try await page.evaluate(
          """
          (() => {
            const quote = document.querySelector('.origin-view .outgoing-citations-view .attestation-view');
            const step = quote && quote.closest('.origin-step-view, .outliner-item, [data-origin-id]');
            return step ? step.textContent.includes('Web tests source two') && !step.textContent.includes('Web tests source one') : false;
          })()
          """)
        #expect(order == .bool(true), "the quote is not under its origin")
        if let folder = ProcessInfo.processInfo.environment["NOTE_SCREENSHOTS"] {
          _ = try await evidence.first.evaluate("(el) => el.scrollIntoView({ block: 'center' })")
          try await page.screenshot(
            to: URL(fileURLWithPath: folder).appendingPathComponent("origin-quote-record-\(layout).png"))
        }
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      clean()
      try await admin.remove(after: error)
    }
    clean()
    try await admin.remove()
  }
}
