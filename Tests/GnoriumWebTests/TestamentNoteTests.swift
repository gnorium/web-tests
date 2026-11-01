import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A node's Note (user, 2026-11-01): every node of the testament tree has
/// one, the work's root among them, as a sentiment has its `<note>`s, for
/// what no other field holds (a copy's provenance, binding, condition,
/// facsimile or supplied leaves). It stands above the node's Metadata as a
/// label-and-field pair, a "Note" label over a text area whose placeholder
/// is "Note", frozen on the record page, open on Submit Testament; the
/// Metadata does not repeat it. A throwaway admin owns a scratch work,
/// removed after.
@Suite("Testament note", .serialized)
struct TestamentNoteTests {
  static let note = "Binding signed by Macdonald. Last leaf in facsimile from the British Library copy. Inlaid; trimmed at head."
  static let workNote = "Known as the bad quarto."

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aNodesNoteStandsAboveItsMetadata(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    do {
      _ = try TestAdmin.query(
        """
        UPDATE biblio_record_versions
          SET metadata_json = (metadata_json::jsonb
            || '{"editionNote":"\(Self.note)","workNote":"\(Self.workNote)"}'::jsonb)::text
          WHERE id = '\(work.versionID.lowercased())';
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(work.path)
        // A testament's: frozen, labeled, above its row's Metadata.
        let note = page.locator(".record-row-view textarea[name='edition_note']")
        try await expect(note).toHaveCount(1)
        try await expect(note).toHaveValue(Self.note)
        try await expect(note).toBeDisabled()
        try await expect(note).toHaveAttribute("placeholder", "Note")
        let field = page.locator(".record-row-view .note-field-view").first
        try await expect(field.locator(".label-view").first).toContainText("Note")
        let row = page.locator(".record-row-view:has(textarea[name='edition_note'])").first
        let metadata = row.locator(".metadata-accordion-view").first
        try await metadata.locator(".accordion-summary").first.click()
        // Its row's Metadata, opened, does not repeat it.
        try await expect(metadata.locator("textarea[name='edition_note']")).toHaveCount(0)
        let box = try #require(try await field.boundingBox())
        let fields = try #require(try await metadata.boundingBox())
        #expect(box.y + box.height <= fields.y)
        // The root's: the work's Note above the record's Metadata.
        let root = page.locator("textarea[name='work_note']")
        try await expect(root).toHaveValue(Self.workNote)
        let rootBox = try #require(try await root.boundingBox())
        let rootMetadata = try #require(try await page.locator("#metadata .metadata-accordion-view").first.boundingBox())
        #expect(rootBox.y + rootBox.height <= rootMetadata.y)
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()

        // Submit Testament asks for each node's Note, the work's too, open.
        try await page.openHydrated(CarrierTests.form)
        try await expect(page.locator(".submit-testament-form textarea[name='digitization_note']")).toHaveCount(1)
        try await expect(page.locator(".submit-testament-form textarea[name='digitization_note']")).toBeEnabled()
        try await expect(page.locator(".submit-testament-form textarea[name='work_note']")).toHaveCount(1)
        try await page.expectNoErrors()
      }
    } catch {
      work.remove()
      try await admin.remove(after: error)
    }
    work.remove()
    try await admin.remove()
  }

  /// A screenshot for a person to look at, when `NOTE_SCREENSHOTS` names a
  /// folder.
  static func shoot(_ page: Page, _ name: String) async throws {
    guard let folder = ProcessInfo.processInfo.environment["NOTE_SCREENSHOTS"] else { return }
    try await page.screenshot(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
  }

  /// The notes travel (user, 2026-11-01): written on Submit Testament, the
  /// work's and a level's, they are filed on the figurant and its overture,
  /// frozen on the overture's page; revised there, the revision's page
  /// diffs them and its line in the thread names "Note" among what
  /// changed, linked to the work's note. A throwaway admin's submission,
  /// its overture deleted and its figurant discarded after.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func notesAreFiledAndRevised(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let suffix = String(UUID().uuidString.prefix(8)).lowercased()
    let path = "/web-tests-notes-\(suffix)"
    let fixtures = try await FixtureServer.manifests(at: [path])
    defer { fixtures.stop() }
    let source = fixtures.baseURL + path
    func clean() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM locutions WHERE locutable_type = 'bibliographic_overture' AND locutable_id IN
          (SELECT id FROM bibliographic_overtures WHERE source_url = '\(source)');
        DELETE FROM revisions WHERE revisable_id IN (SELECT id FROM bibliographic_overtures WHERE source_url = '\(source)');
        DELETE FROM bibliographic_overtures WHERE source_url = '\(source)';
        UPDATE bibliographic_figurants SET discarded_at = now(), discarded_by = '\(admin.username)'
          WHERE source_url = '\(source)' AND discarded_at IS NULL;
        COMMIT;
        """)
    }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        // Submit Testament: the work's Note and the digitization's, each
        // open above its node's Metadata.
        try await page.openHydrated(CarrierTests.form)
        let form = page.locator(".submit-testament-form")
        let tree = form.locator(".submit-testament-tree")
        func node(_ level: String) -> Locator { tree.locator(".outliner-item[data-outliner-id='\(level)-new']") }
        _ = try await page.evaluate(
          """
          (() => {
            for (const [id, value] of [['work-language', 'eng'], ['work-type', 'report']]) {
              const input = document.getElementById(id);
              input.value = value;
              input.dispatchEvent(new Event('change'));
            }
          })()
          """)
        try await form.locator("#metadata input[name='title']").fill("Web tests notes \(suffix)")
        try await form.locator(
          "#metadata [data-item-list='work-voice'] [data-item-section='true']:not([data-item-template] *) .text-input-input"
        ).first.fill("Web Tests Author \(suffix)")
        let carrier = tree.locator(".dropdown-view:has(#testament-carrier)")
        try await carrier.locator(".dropdown-trigger").click()
        try await carrier.locator(".dropdown-option[data-value='printed']").filter(visible: true).first.click()
        for level in ["impression", "issue", "copy"] {
          try await node(level).locator(":scope > .outliner-footer .testament-draft-remove-level").click()
          try await expect(node(level)).toHaveAttribute("data-outliner-removed", "true")
        }
        let manifest = node("manifest").locator(":scope > .outliner-row")
        try await manifest.locator(".combobox-view:has(input[name='provider-dropdown']) .text-input-input")
          .fill("British Library")
        try await manifest.locator("input[name='source-url']").fill(source)
        let rights = manifest.locator(".dropdown-view:has(input[name='rights_statement'])")
        try await rights.locator(".dropdown-trigger").click()
        try await rights.locator(".dropdown-option[data-value='nkc']").filter(visible: true).first.click()
        let workNote = form.locator("textarea[name='work_note']")
        try await expect(workNote).toBeEnabled()
        try await workNote.fill(Self.workNote)
        let digitizationNote = manifest.locator("textarea[name='digitization_note']")
        try await expect(digitizationNote).toBeEnabled()
        try await expect(digitizationNote).toHaveAttribute("placeholder", "Note")
        try await digitizationNote.fill(Self.note)
        // Above its node's Metadata.
        let noteBox = try #require(try await digitizationNote.boundingBox())
        let metadataBox = try #require(
          try await manifest.locator(".metadata-accordion-view").first.boundingBox())
        #expect(noteBox.y + noteBox.height <= metadataBox.y)
        try await expect(form.locator(".record-choice-field-view .record-choice-field-slot"), timeout: .seconds(20))
          .toHaveAttribute("aria-busy", "false")
        try await expect(form.locator(".submit-testament-reader .artifact-view"), timeout: .seconds(20)).toBeVisible()
        try await Self.shoot(page, "notes-submit-\(layout)")
        _ = try await page.evaluate(
          "Promise.all(document.getAnimations().filter(a => a.effect?.getTiming().iterations !== Infinity).map(a => a.finished.catch(() => null))).then(() => 1)",
          as: Int.self)
        try await form.locator(".record-actions button[type='submit']").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the Mission Control page") {
          $0.path == "/mission-control"
        }
        // Filed on the figurant and its overture.
        let filed = try TestAdmin.query(
          """
          SELECT coalesce(f.work_note, '') || '|' || coalesce(f.digitization_note, '') || '|'
            || coalesce(o.work_note, '') || '|' || coalesce(o.digitization_note, '') || '|' || o.id
            FROM bibliographic_figurants f JOIN bibliographic_overtures o ON o.bibliographic_figurant_id = f.id
            WHERE f.source_url = '\(source)';
          """
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = filed.components(separatedBy: "|")
        #expect(parts.count == 5, "\(filed)")
        #expect(Array(parts.prefix(4)) == [Self.workNote, Self.note, Self.workNote, Self.note], "\(filed)")
        let overture = "/mission-control/overtures/bibliographic/\(parts.last ?? "")"

        // The overture's page: each note frozen in its field.
        try await page.openHydrated(overture)
        try await expect(page.locator("textarea[name='work_note']")).toHaveValue(Self.workNote)
        try await expect(page.locator("textarea[name='work_note']")).toBeDisabled()
        try await expect(page.locator("textarea[name='digitization_note']")).toHaveValue(Self.note)
        try await expect(page.locator("textarea[name='digitization_note']")).toBeDisabled()
        try await Self.shoot(page, "notes-overture-\(layout)")
        try await page.expectNoErrors(ignoring: ["/web-tests-notes-"])

        // Revise: both open, both changed, one Suggest.
        try await page.openHydrated("\(overture)/revise")
        let revise = page.locator("[data-revise-form]")
        let reviseWork = page.locator("textarea[name='work_note']")
        let reviseDigitization = page.locator("textarea[name='digitization_note']")
        try await expect(reviseWork).toBeEnabled()
        try await expect(reviseWork).toHaveValue(Self.workNote)
        try await expect(reviseDigitization).toBeEnabled()
        try await reviseWork.fill(Self.workNote + " Revised.")
        try await reviseDigitization.fill(Self.note + " Revised.")
        try await Self.shoot(page, "notes-revise-\(layout)")
        try await expect(revise).toHaveCount(1)
        try await page.locator("button[type='submit']").filter(hasText: "Suggest").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the overture at its locution") { url in
          url.path.lowercased() == overture.lowercased() && (url.fragment ?? "").hasPrefix("revision-")
        }
        let revision = try TestAdmin.query(
          "SELECT id FROM revisions WHERE revisable_id = '\(parts.last ?? "")' ORDER BY created_at DESC LIMIT 1;"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!revision.isEmpty, "no revision was filed")

        // The thread's line names Note, linked to the work's note in the
        // revision's diff.
        let changed = page.locator(".thread-event-changed a").filter(hasText: "Note")
        try await expect(changed.first).toBeVisible()
        let hrefs = try await page.evaluate(
          "[...document.querySelectorAll('.thread-event-changed a')].map((el) => el.textContent.trim() + ' ' + el.getAttribute('href'))")
        print("web-tests: Changed \(hrefs)")
        try await Self.shoot(page, "notes-thread-\(layout)")

        // The revision's page: each note frozen, its diff against what it
        // stood at.
        try await page.openHydrated("\(overture)/revisions/\(revision)")
        let diffWork = page.locator("textarea[name='work_note']")
        try await expect(diffWork).toHaveValue(Self.workNote + " Revised.")
        try await expect(diffWork).toBeDisabled()
        try await expect(page.locator(".diff-wrap-changed:has(textarea[name='work_note'])")).toHaveCount(1)
        try await expect(page.locator(".diff-wrap-changed:has(textarea[name='digitization_note'])")).toHaveCount(1)
        for name in ["work_note", "digitization_note"] {
          let ring = try await page.locator(".diff-wrap-changed textarea[name='\(name)']").evaluate(
            "(el) => { const s = getComputedStyle(el); return s.outlineStyle === 'solid' && s.outlineColor === s.borderTopColor; }")
          #expect(ring.bool == true, "the changed \(name) is not ringed")
        }
        // Each Note the thread names lands on its field in the diff.
        for anchor in ["work-note", "testament-digitization-note"] {
          try await expect(page.locator("[id$='\(anchor)']").first).toBeAttached()
        }
        try await Self.shoot(page, "notes-revision-\(layout)")
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors(ignoring: ["/web-tests-notes-"])
      }
    } catch {
      clean()
      try await admin.remove(after: error)
    }
    clean()
    try await admin.remove()
  }

  /// An amendment's Note: the work's, open on the record's amendment,
  /// filed on its palinode and carried into the reopened madrigal, frozen
  /// there and diffed against the record's (none). A throwaway admin's
  /// scratch work; its palinode is submitted input and stays.
  @Test(arguments: [BrowserEngine.chrome], [Layout.desktop])
  func anAmendmentFilesItsNote(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let fixture = try await FixtureServer.threePageManifest()
    defer { fixture.stop() }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin, sourceURL: fixture.baseURL + "/manifest.json")
    let record = work.recordID.lowercased()
    func clean() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM inferred_citation_jobs WHERE record_id = '\(record)';
        DELETE FROM locutions WHERE locutable_id IN
          (SELECT id FROM bibliographic_madrigals WHERE biblio_record_id = '\(record)' AND id <> '\(work.madrigalID.lowercased())');
        DELETE FROM revisions WHERE revisable_id IN
          (SELECT id FROM bibliographic_madrigals WHERE biblio_record_id = '\(record)' AND id <> '\(work.madrigalID.lowercased())');
        DELETE FROM bibliographic_madrigals WHERE biblio_record_id = '\(record)' AND id <> '\(work.madrigalID.lowercased())';
        COMMIT;
        """)
    }
    do {
      _ = try TestAdmin.query(
        """
        UPDATE biblio_record_versions
          SET metadata_json = replace(metadata_json, 'https://example.org/web-tests', '\(fixture.baseURL)/manifest.json')
          WHERE id = '\(work.versionID.lowercased())';
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("\(work.path)/amendments/new")
        let note = page.locator("textarea[name='work_note']")
        try await expect(note).toBeEnabled()
        try await expect(note).toHaveValue("")
        try await note.fill(Self.workNote)
        // The work edited: its one digitization is the amendment's.
        try await expect(page.locator(".testament-choice-view input[name='testament']").first).toBeChecked()
        try await Self.shoot(page, "notes-amendment-\(layout)")
        try await page.locator(".record-actions button[type='submit']").first.click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the reopened madrigal") {
          $0.path.hasPrefix("/mission-control/madrigals/bibliographic/")
        }
        let filed = try TestAdmin.query(
          "SELECT metadata_json FROM bibliographic_palinodes WHERE biblio_record_id = '\(record)';")
        #expect(filed.contains("\"workNote\":\"\(Self.workNote)\""), "\(filed)")
        // The madrigal: the note frozen, an addition to the record's.
        let frozen = page.locator("textarea[name='work_note']")
        try await expect(frozen).toHaveValue(Self.workNote)
        try await expect(frozen).toBeDisabled()
        try await expect(page.locator(".diff-wrap-added:has(textarea[name='work_note'])")).toHaveCount(1)
        try await Self.shoot(page, "notes-amendment-madrigal-\(layout)")
        try await page.expectNoErrors(ignoring: ["/page-"])
      }
    } catch {
      clean()
      work.remove()
      try await admin.remove(after: error)
    }
    clean()
    work.remove()
    try await admin.remove()
  }

  /// A lexico-record's root Note (user, 2026-11-01): open on Submit
  /// Sentiment; an overture's, frozen on its page; revised on its overture's Revise
  /// page, the revision diffs it and the thread's line names "Note". A
  /// throwaway admin's scratch overture, removed after.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aWordsRootNoteIsFiledAndRevised(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let title = "webtestsnote\(String(UUID().uuidString.prefix(8)).lowercased().filter(\.isLetter))"
    let rootNote = "Recorded first in the scratch tests."
    let figurants = "(SELECT id FROM lexicographic_figurants WHERE title_form_json::json ->> 'title' = '\(title)')"
    let overtures = "(SELECT id FROM lexicographic_overtures WHERE lexicographic_figurant_id IN \(figurants))"
    func clean() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM locutions WHERE locutable_type = 'lexicographic_overture' AND locutable_id IN \(overtures);
        DELETE FROM revisions WHERE revisable_id IN \(overtures);
        DELETE FROM lexicographic_overtures WHERE id IN \(overtures);
        UPDATE lexicographic_figurants SET discarded_at = now(), discarded_by = '\(admin.username)'
          WHERE id IN \(figurants) AND discarded_at IS NULL;
        COMMIT;
        """)
    }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        // Submit Sentiment asks for the root's Note, open.
        try await page.openHydrated(SubmissionTests.sentimentForm)
        let note = page.locator(".submit-sentiment-form textarea[name='note']")
        try await expect(note).toBeEnabled()
        try await expect(note).toHaveAttribute("placeholder", "Note")
        // An overture whose title form carries one: frozen on its page.
        let user = try admin.column("id")
        let form = #"{"title":"\#(title)","languageCode":"eng","class":"noun","note":"\#(rootNote)","spellings":[],"inflections":[],"origin":{"etymons":[],"citations":[],"derivation":""}}"#
        let submission = UUID().uuidString.lowercased()
        let figurant = UUID().uuidString.lowercased()
        let id = UUID().uuidString.lowercased()
        _ = try TestAdmin.query(
          """
          BEGIN;
          INSERT INTO submissions (id, user_id) VALUES ('\(submission)', '\(user)');
          INSERT INTO lexicographic_figurants (id, batch_id, language, order_in_batch, processing_status,
            title_form_json, anchors_json, created_at)
            VALUES ('\(figurant)', '\(submission)', 'eng', 0, 'pending', '\(form)', '[]', now());
          INSERT INTO lexicographic_overtures (id, lexicographic_figurant_id, title_form_json, anchors_json, created_at)
            VALUES ('\(id)', '\(figurant)', '\(form)', '[]', now());
          COMMIT;
          """)
        let overture = "/mission-control/overtures/lexicographic/\(id)"
        try await page.openHydrated(overture)
        try await expect(page.locator("textarea[name='note']")).toHaveValue(rootNote)
        try await expect(page.locator("textarea[name='note']")).toBeDisabled()

        try await page.openHydrated("\(overture)/revise")
        let revise = page.locator("[data-revise-form] textarea[name='note']")
        try await expect(revise).toBeEnabled()
        try await revise.fill(rootNote + " Revised.")
        try await page.locator("button[type='submit']").filter(hasText: "Suggest").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the overture at its locution") { url in
          url.path.lowercased() == overture.lowercased() && (url.fragment ?? "").hasPrefix("revision-")
        }
        let link = page.locator(".thread-event-changed a").filter(hasText: "Note")
        try await expect(link).toHaveCount(1)
        let href = try await link.evaluate("(el) => el.getAttribute('href')")
        let target = try #require(href.string)
        try await page.openHydrated(target)
        let diffed = page.locator("textarea[name='note']")
        try await expect(diffed).toHaveValue(rootNote + " Revised.")
        try await expect(diffed).toBeDisabled()
        try await expect(page.locator(".diff-wrap-changed:has(textarea[name='note'])")).toHaveCount(1)
        let anchor = String(target.split(separator: "#").last ?? "")
        try await expect(page.locator("[id='\(anchor)']")).toBeAttached()
        let ring = try await page.locator(".diff-wrap-changed textarea[name='note']").evaluate(
          "(el) => { const s = getComputedStyle(el); return s.outlineStyle === 'solid' && s.outlineColor === s.borderTopColor; }")
        #expect(ring.bool == true, "the changed note is not ringed")
        try await Self.shoot(page, "notes-lexico-revision-\(layout)")
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      clean()
      try await admin.remove(after: error)
    }
    clean()
    try await admin.remove()
  }
}
