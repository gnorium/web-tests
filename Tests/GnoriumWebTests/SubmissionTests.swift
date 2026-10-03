import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Submit Testament and Submit Sentiment are the record page in edit mode
/// (user, 2026-09-28): the record field at the head ("New record" until one
/// is chosen), the record's fields, then the chronicle tree with the new
/// nodes, open, their fields in their Metadata, each row named by its own
/// fields as they are typed ("—" until then; no level name). A new
/// testament is drawn as the nodes it will become (user, 2026-10-01): a
/// printed one edition › copy › digitization, the copy removable with its
/// "− Testament" (the digitization then under the edition) and put back
/// with the edition's "+ Testament", each node's controls its last row; a
/// manuscript copy › digitization. A copy node left empty
/// blocks submit ("Fill in Copy, Holding institution or Classification identifier, or remove the copy."). Submit Testament makes
/// records: a chosen biblio-record is one the testament already has, its
/// Submit waits, disabled, and the record's "Submit Amendment" carries what
/// was typed into that record's amendment, the new nodes added to its tree:
/// under an edition a copy and its digitization, the edition's carrier
/// taken, its own edition node out and unposted; nothing goes under a
/// digitization. A chosen lexico-record's fields are frozen and its tree is
/// its own, the new sentiment placed in it. A manuscript's citations are its
/// copy's. A work's page offers its amendment; a word's, its submission
/// with the record chosen; signed out, each says so in an alert. Each case
/// is submitted, and its evidence and overture read back from the database.
/// A throwaway admin owns the scratch records and every row submitted,
/// removed after.
@Suite("Submission", .serialized)
struct SubmissionTests {
  static let testamentForm = "/mission-control/submit/bibliographic/evidence-testament"
  static let sentimentForm = "/mission-control/submit/lexicographic/evidence-sentiment"

  /// A screenshot for a person to look at, on a desktop page: the page made
  /// tall enough to hold the tree from `top`, then put back.
  static func shoot(_ page: Page, _ name: String, from top: Locator) async throws {
    guard try await top.evaluate("(el) => window.innerWidth >= 1000").bool == true else { return }
    try await page.setViewport(width: 1400, height: 2400)
    // The nodes' Metadata shut for the picture, so the tree reads as rows.
    _ = try await top.evaluate(
      """
      (el) => {
        el.querySelectorAll('.record-row-metadata').forEach((m) => {
          const d = m.closest('details');
          if (d && d.open) { d.open = false; d.dataset.shotClosed = 'true'; }
        });
        el.scrollIntoView({block: 'start'});
        return true;
      }
      """)
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("web-tests-artifacts/\(name)-\(UUID().uuidString.prefix(4)).png")
    try await page.screenshot(to: url)
    print("web-tests: screenshot \(url.path)")
    _ = try await top.evaluate(
      """
      (el) => {
        el.querySelectorAll('details[data-shot-closed]').forEach((d) => { d.open = true; delete d.dataset.shotClosed; });
        return true;
      }
      """)
    try await page.setViewport(.desktop)
  }

  // MARK: - Submit Testament

  @Test(arguments: gnorium.engines, Layout.allCases)
  func aTestamentIsItsNewNodesInItsRecordsTree(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let suffix = String(UUID().uuidString.prefix(8)).lowercased()
    // Each testament's source a manifest the server can read.
    let path = "/web-tests-submission-\(suffix)"
    let fixtures = try await FixtureServer.manifests(at: ["\(path)/new", "\(path)/placed"])
    defer { fixtures.stop() }
    let source = fixtures.baseURL + path
    func clean() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM bibliographic_overtures WHERE bibliographic_evidence_id IN
          (SELECT id FROM bibliographic_evidences WHERE source_url LIKE '\(source)%');
        DELETE FROM submissions WHERE id IN
          (SELECT batch_id FROM bibliographic_evidences WHERE source_url LIKE '\(source)%');
        DELETE FROM bibliographic_evidences WHERE source_url LIKE '\(source)%';
        COMMIT;
        """)
    }
    do {
      // The scratch work's testament is printed, as a permit writes it.
      _ = try TestAdmin.query(
        """
        UPDATE biblio_record_versions
          SET metadata_json = replace(metadata_json, '"edition":"First edition"', '"edition":"First edition","carrier":"printed"')
          WHERE id = '\(work.versionID.lowercased())';
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await newTestament(page, suffix: suffix, source: source)
        try await placedTestament(page, work: work, source: source)
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
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

  /// Sets a dropdown by its hidden input, as a pick does.
  private func set(_ page: Page, _ values: [(String, String)]) async throws {
    let pairs = values.map { "['\($0.0)', '\($0.1)']" }.joined(separator: ", ")
    _ = try await page.evaluate(
      """
      (() => {
        for (const [id, value] of [\(pairs)]) {
          const input = document.getElementById(id);
          input.value = value;
          input.dispatchEvent(new Event('change'));
        }
      })()
      """)
  }

  private func choose(_ dropdown: Locator, _ value: String) async throws {
    try await dropdown.locator(".dropdown-trigger").click()
    try await dropdown.locator(".dropdown-option[data-value='\(value)']").filter(visible: true).first.click()
  }

  /// A new testament's node, and its own row's parts.
  private func node(_ scope: Locator, _ level: String) -> Locator {
    scope.locator(".outliner-item[data-outliner-id='\(level)-new']")
  }

  private func row(_ scope: Locator, _ level: String) -> Locator {
    node(scope, level).locator(":scope > .outliner-row")
  }

  /// A new testament's node's own controls: its last row, after the nodes
  /// under it (user, 2026-10-01).
  private func controls(_ scope: Locator, _ level: String) -> Locator {
    node(scope, level).locator(":scope > .outliner-footer")
  }

  /// A new record: its fields to fill in, its tree the new testament's
  /// nodes, each named as its fields are typed; the copy removed and put
  /// back, left empty refused; submitted without it, an evidence and its
  /// overture with no record chosen and no copy.
  private func newTestament(_ page: Page, suffix: String, source: String) async throws {
    try await page.openHydrated(Self.testamentForm)
    let form = page.locator(".submit-testament-form")
    try await expect(page).toHaveTitle("Submit Testament | Mission Control | Gnorium")
    // The record page's column: the header, its rule, the record field
    // "New record", the fields, then the tree.
    try await expect(form.locator(".record-view .record-identity .form-header-view")).toHaveCount(1)
    let field = form.locator(".record-choice-field-view")
    try await expect(field.locator(".dropdown-selected-text")).toHaveText("New record")
    let apparatus = form.locator("#metadata")
    try await expect(apparatus.locator("input[name='title']")).toBeEnabled()
    let tree = form.locator(".submit-testament-tree")
    // Every level starts in (user, 2026-10-03): edition › impression ›
    // issue › copy › digitization, numbered as the record page numbers.
    for (level, number) in [
      ("edition", "1"), ("impression", "1.1"), ("issue", "1.1.1"), ("copy", "1.1.1.1"), ("manifest", "1.1.1.1.1"),
    ] {
      try await expect(node(tree, level)).toHaveAttribute("data-outliner-removed", "false")
      try await expect(row(tree, level).locator(".record-row-number").first).toHaveText(number)
      try await expect(row(tree, level).locator(".record-row-title").first).toHaveText("—")
    }
    // No card and no level named: its fields in its open Metadata.
    try await expect(form.locator(".framed-accordion-view")).toHaveCount(0)
    try await expect(row(tree, "edition").locator(".metadata-accordion-view .accordion-details").first)
      .toHaveAttribute("data-expanded", "true")

    // The work.
    let name = "Web tests submission \(suffix)"
    try await set(page, [("work-language", "eng"), ("work-type", "report")])
    try await apparatus.locator("input[name='title']").fill(name)
    try await apparatus.locator(
      "[data-item-list='work-voice'] [data-item-section='true']:not([data-item-template] *) .text-input-input"
    ).first.fill("Web Tests Author \(suffix)")

    // A manuscript: no edition, impression or issue node; its copy the top,
    // the carrier and its making there, not removable; its citations its
    // copy's.
    let carrier = tree.locator(".dropdown-view:has(#testament-carrier)")
    let citations = "fieldset:has([data-item-list='reference-citation'])"
    try await choose(carrier, "manuscript")
    try await expect(node(tree, "edition")).toHaveAttribute("data-outliner-removed", "true")
    try await expect(node(tree, "impression")).toHaveAttribute("data-outliner-removed", "true")
    try await expect(node(tree, "issue")).toHaveAttribute("data-outliner-removed", "true")
    try await expect(row(tree, "copy").locator(".record-row-number").first).toHaveText("1")
    try await expect(row(tree, "copy").locator("#testament-carrier")).toHaveCount(1)
    try await expect(controls(tree, "copy").locator(".testament-draft-remove-level")).toBeHidden()
    try await expect(
      row(tree, "copy").locator(".testament-metadata-view-citations[data-citations-slot='production'] \(citations)")
    ).toBeVisible()
    // Printed: its edition back, the carrier and publication there; the
    // copy's making gone; the edition named as it is typed.
    try await choose(carrier, "printed")
    try await expect(node(tree, "edition")).toHaveAttribute("data-outliner-removed", "false")
    let edition = row(tree, "edition")
    try await expect(edition.locator("#testament-carrier")).toHaveCount(1)
    try await expect(
      edition.locator(
        ".activity-statement-view[data-as-namespace='publication'] [data-citations-slot='publication'] \(citations)")
    ).toBeVisible()
    try await expect(row(tree, "copy").locator(".activity-statement-view[data-as-namespace='production']"))
      .toBeHidden()
    try await edition.locator("input[name='edition']").fill("Second edition")
    try await expect(edition.locator(".record-row-title").first).toHaveText("Second edition")
    let manifest = row(tree, "manifest")
    try await manifest.locator(".combobox-view:has(input[name='provider-dropdown']) .text-input-input")
      .fill("British Library")
    try await manifest.locator("input[name='source-url']").fill("\(source)/new")

    // Printed again, the impression and issue the manuscript took come back
    // in their places; each is taken out by its own −, the nodes under it
    // standing where it stood. The copy left empty: refused on it, nothing
    // sent.
    try await expect(row(tree, "copy").locator(".record-row-number").first).toHaveText("1.1.1.1")
    try await controls(tree, "impression").locator(".testament-draft-remove-level").click()
    try await expect(node(tree, "impression")).toHaveAttribute("data-outliner-removed", "true")
    try await expect(row(tree, "issue").locator(".record-row-number").first).toHaveText("1.1")
    try await controls(tree, "issue").locator(".testament-draft-remove-level").click()
    try await expect(node(tree, "issue")).toHaveAttribute("data-outliner-removed", "true")
    try await expect(row(tree, "copy").locator(".record-row-number").first).toHaveText("1.1")
    let submit = form.locator(".record-actions button[type='submit']")
    try await submit.click()
    try await expect(row(tree, "copy").locator(".testament-draft-message"))
      .toHaveText("Fill in Copy, Holding institution or Classification identifier, or remove the copy.")
    try await expect(page).toHaveURL("the form") { $0.path == Self.testamentForm }
    // Removed: the digitization stands where the copy stood.
    try await controls(tree, "copy").locator(".testament-draft-remove-level").click()
    try await expect(node(tree, "copy")).toHaveAttribute("data-outliner-removed", "true")
    try await expect(manifest.locator(".record-row-number").first).toHaveText("1.1")

    // The edition's "+ Testament" adds a new child at the next level, after
    // the one it has: 1.2, never pushing 1.1 down (user, 2026-10-03). Every
    // node is a testament: the icon and the noun, the words for assistive
    // technology.
    let add = controls(tree, "edition").locator(".testament-draft-add-level")
    try await expect(add).toHaveText("Testament")
    try await expect(add).toHaveAttribute("aria-label", "Add Testament")
    try await expect(row(tree, "edition").locator(".testament-draft-add-level")).toHaveCount(0)
    try await add.click()
    try await expect(node(tree, "impression")).toHaveAttribute("data-outliner-removed", "false")
    try await expect(row(tree, "impression").locator(".record-row-number").first).toHaveText("1.2")
    try await expect(manifest.locator(".record-row-number").first).toHaveText("1.1")
    try await Self.shoot(page, "submit-testament-added-1.2", from: tree)
    // Empty: refused. Filled but with nothing under it: one testament, one
    // digitization, the one leaf.
    try await submit.click()
    try await expect(row(tree, "impression").locator(".testament-draft-message"))
      .toHaveText("Fill in Impression or its place, agents or date, or remove the impression.")
    try await row(tree, "impression").locator("input[name='impression']").fill("Second impression")
    try await expect(row(tree, "impression").locator(".record-row-title").first).toHaveText("Second impression")
    try await submit.click()
    try await expect(row(tree, "impression").locator(".testament-draft-message"))
      .toHaveText("The impression must have a digitization under it.")
    try await expect(page).toHaveURL("the form") { $0.path == Self.testamentForm }

    // Restructured by the outline's moves: the digitization picked up,
    // moved after the impression and put under it.
    let grip = manifest.locator(".outliner-handle").first
    try await grip.click()
    try await grip.press("ArrowDown")
    try await grip.press("ArrowRight")
    try await grip.press("Enter")
    try await expect(row(tree, "impression").locator(".record-row-number").first).toHaveText("1.1")
    try await expect(manifest.locator(".record-row-number").first).toHaveText("1.1.1")
    try await Self.shoot(page, "submit-testament-dragged", from: tree)

    try await submit.click()
    try await expect(page, timeout: .seconds(15)).toHaveURL("the Mission Control page") {
      $0.path == "/mission-control"
    }
    let row = try TestAdmin.query(
      """
      SELECT e.title || '|' || coalesce(e.carrier, '') || '|' || coalesce(e.edition, '') || '|'
        || coalesce(e.copy_label, '') || '|' || coalesce(e.chosen_biblio_record_id::text, '') || '|' || count(o.id)
        FROM bibliographic_evidences e LEFT JOIN bibliographic_overtures o ON o.bibliographic_evidence_id = e.id
        WHERE e.source_url = '\(source)/new' GROUP BY e.id;
      """
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(row == "\(name)|printed|Second edition|||1", "\(row)")
  }

  /// A chosen record: the form's Submit waits, disabled, and the record's
  /// "Submit Amendment" carries what was typed into its amendment, the new
  /// testament's nodes added at the top of its tree after its edition;
  /// added under the edition by its +, a copy and its digitization taking
  /// the edition's carrier, the copy removable (the digitization then under
  /// the edition, whose + puts it back); under a digitization it is refused.
  /// Submitted: the record's own fields, the inherited carrier and the
  /// placement ride on the evidence and its overture.
  private func placedTestament(_ page: Page, work: ScratchWork, source: String) async throws {
    try await page.openHydrated(Self.testamentForm)
    let form = page.locator(".submit-testament-form")
    let field = form.locator(".record-choice-field-view")
    let dropdown = field.locator(".dropdown-view")
    let typed = form.locator(".submit-testament-tree")
    try await choose(typed.locator(".dropdown-view:has(#testament-carrier)"), "printed")
    try await row(typed, "edition").locator("input[name='edition']").fill("Kept aside")

    try await dropdown.locator(".dropdown-trigger").click()
    try await dropdown.locator(".dropdown-search-input").fill(work.suffix)
    try await dropdown.locator(
      ".dropdown-options-list[data-dropdown-results='true'] .dropdown-option[data-value='\(work.recordID)']"
    ).click()
    try await expect(field.locator("input[name='biblio-record']")).toHaveValue(work.recordID)
    let amend = field.locator("[data-record-choice-amendment] .record-choice-amendment-button")
    try await expect(amend, timeout: .seconds(15)).toBeVisible()
    try await expect(form.locator(".record-actions button[type='submit']")).toBeDisabled()
    try await amend.click()
    try await expect(page, timeout: .seconds(15)).toHaveURL("the record's amendment") {
      $0.path == "\(work.path)/amendments/new"
    }

    // Its edition fixed (1), the new testament's nodes after it (2),
    // carried in.
    let tree = page.locator(".testament-outliner-view")
    let edition = row(tree, "edition")
    try await expect(node(tree, "edition")).toHaveAttribute("data-outliner-removed", "false")
    try await expect(edition.locator(".record-row-number").first).toHaveText("2")
    try await expect(row(tree, "copy").locator(".record-row-number").first).toHaveText("2.1")
    try await expect(row(tree, "manifest").locator(".record-row-number").first).toHaveText("2.1.1")
    try await expect(tree.locator(".outliner-item:not([data-testament-draft]) .outliner-handle").first)
      .toBeDisabled()
    try await expect(tree.locator("input[name='placement-version']")).toHaveValue(work.versionID)
    try await expect(edition.locator("input[name='edition']")).toHaveValue("Kept aside")
    try await expect(edition.locator(".record-row-title").first).toHaveText("Kept aside")

    // One testament an amendment: the tree's + hidden while it is in. Its
    // edition taken out by its own −, its copy and digitization stand at
    // the top, and the copy moves under the record's edition: a copy and
    // its digitization, the edition's carrier taken.
    let recordEdition = tree.locator(".outliner-item[data-outliner-id^='edition-']:not([data-testament-draft])").first
    let addUnder = recordEdition.locator(":scope > .outliner-footer .testament-outliner-add-own")
    try await expect(addUnder).toBeHidden()
    try await controls(tree, "edition").locator(".testament-draft-remove-level").click()
    try await expect(node(tree, "edition")).toHaveAttribute("data-outliner-removed", "true")
    let copy = row(tree, "copy")
    let number = copy.locator(".record-row-number").first
    try await expect(number).toHaveText("2")
    let grip = copy.locator(".outliner-handle").first
    try await grip.click()
    try await grip.press("ArrowRight")
    try await grip.press("Enter")
    try await expect(number).toHaveText("1.2")
    try await expect(row(tree, "manifest").locator(".record-row-number").first).toHaveText("1.2.1")
    try await expect(copy.locator(".testament-metadata-view-acquisition")).toBeVisible()
    try await expect(row(tree, "manifest").locator(".activity-statement-view[data-as-namespace='digitization']"))
      .toBeVisible()
    try await expect(tree.locator("#new-testament-carrier")).toBeDisabled()
    // Named by its copy label as it is typed.
    try await copy.locator("input[name='copyLabel']").fill("Copy 2")
    try await expect(copy.locator(".record-row-title").first).toHaveText("Copy 2")
    // Under the digitization above it: refused, in the tree's words.
    let handle = copy.locator(".outliner-handle").first
    try await handle.click()
    try await handle.press("ArrowRight")
    try await expect(tree.locator(".outliner-feedback .alert-content"))
      .toHaveText("Nothing can go under a digitization: its semblances attest it.")
    try await handle.press("Escape")
    try await expect(number).toHaveText("1.2")

    // Submitted: its own edition, kept aside, is not posted.
    let manifest = row(tree, "manifest")
    try await manifest.locator(".combobox-view:has(input[name='provider-dropdown']) .text-input-input")
      .fill("British Library")
    try await manifest.locator("input[name='source-url']").fill("\(source)/placed")
    try await page.locator("button[type='submit'][form='amendment-new']").click()
    try await expect(page, timeout: .seconds(15)).toHaveURL("the Mission Control page") {
      $0.path == "/mission-control"
    }
    let evidence = try TestAdmin.query(
      "SELECT id FROM bibliographic_evidences WHERE source_url = '\(source)/placed';"
    ).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    #expect(!evidence.isEmpty, "No evidence.")
    let row = try TestAdmin.query(
      """
      SELECT e.title || '|' || coalesce(e.carrier, '') || '|' || coalesce(e.copy_label, '') || '|'
        || coalesce(e.edition, '') || '|' || e.chosen_biblio_record_id::text || '|' || o.chosen_biblio_record_id::text
        FROM bibliographic_evidences e JOIN bibliographic_overtures o ON o.bibliographic_evidence_id = e.id
        WHERE e.source_url = '\(source)/placed';
      """
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    let record = work.recordID.lowercased()
    #expect(row == "\(work.title)|printed|Copy 2||\(record)|\(record)", "\(row)")
    let placement = try TestAdmin.query(
      "SELECT placement_json FROM bibliographic_evidences WHERE source_url = '\(source)/placed';")
    let shape = try JSONSerialization.jsonObject(with: Data(placement.utf8)) as? [String: [String: Any]] ?? [:]
    let placedCopy = shape.first { $0.key.lowercased() == "copy-\(evidence.lowercased())" }
    let placedManifest = shape.first { $0.key.lowercased() == "manifest-\(evidence.lowercased())" }
    #expect((placedCopy?.value["parent"] as? String)?.hasPrefix("edition-") == true, "\(placement)")
    #expect((placedCopy?.value["position"] as? Int) == 1, "\(placement)")
    #expect((placedManifest?.value["parent"] as? String)?.lowercased() == placedCopy?.key.lowercased(), "\(placement)")
    #expect(shape.keys.contains { $0.lowercased() == "edition-\(evidence.lowercased())" } == false)
  }

  // MARK: - From a record's page

  /// A record's page offers its one road in—Submit Amendment on a
  /// work's, which opens the record's amendment; Submit Sentiment on a
  /// word's, which opens the form with the record chosen: its fields frozen,
  /// its tree drawn. Signed out, the button is there all the same and says
  /// so in an alert, as the form's Submit does; no page explains it in prose.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aRecordsPageOpensItsSubmissionWithItChosen(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let word = try ScratchWord(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        for (path, label) in [(work.path, "Submit Amendment"), (word.path, "Submit Sentiment")] {
          try await page.openHydrated(path)
          // Its one action: on a phone full width, wider content-width
          // (user, 2026-09-30).
          let shape = try await page.locator(".record-actions .sign-in-gate-actions").evaluate(
            """
            (g) => {
              const w = g.closest('.record-actions').getBoundingClientRect().width;
              const rs = [...g.querySelectorAll(':scope > * .button-view')].map((b) => b.getBoundingClientRect());
              const full = rs.every((r) => Math.abs(r.width - w) < 2);
              const narrow = rs.every((r) => r.width < w / 2);
              return rs.length + (full ? ':full' : narrow ? ':content' : ':mixed');
            }
            """
          ).string ?? ""
          if layout == .phone {
            #expect(shape == "1:full", "\(label)'s page: its action full width on a phone, not \(shape)")
          } else {
            #expect(shape == "1:content", "\(label)'s page: its action content-width, not \(shape)")
          }
          try await page.locator(".record-actions a").filter(hasText: label).click()
        }
        // The word's form, the record chosen, its tree drawn.
        try await expect(page, timeout: .seconds(15)).toHaveURL("the form, the record chosen") {
          $0.query?.contains("record=\(word.recordID)") == true
        }
        let chosen = page.locator(".submit-sentiment-form .record-choice-field-view input[name='lexico-record']")
        try await expect(chosen).toHaveValue(word.recordID)
        try await expect(page.locator(".submit-sentiment-form .record-choice-apparatus"), timeout: .seconds(15))
          .toHaveCount(1)
        try await expect(page.locator(".submit-sentiment-tree .outliner-item[data-outliner-id='new']")).toHaveCount(1)
        // The work's amendment.
        try await page.openHydrated(work.path)
        try await page.locator(".record-actions a").filter(hasText: "Submit Amendment").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the record's amendment") {
          $0.path == "\(work.path)/amendments/new"
        }
        try await expect(page.locator(".testament-outliner-view")).toHaveCount(1)
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
      }
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(work.path)
        try await page.locator(".record-actions a").filter(hasText: "Submit Amendment").click()
        try await expect(page.locator(".record-actions .alert-content")).toHaveText("Sign in to submit an amendment.")
        #expect(URL(string: try await page.url())?.path == work.path)
        try await page.openHydrated(Self.sentimentForm)
        try await expect(page.locator("body")).not.toContainText("Sign in to submit a sentiment.")
        try await page.locator(".record-actions button[type='submit']").click()
        try await expect(page.locator(".record-actions .alert-content")).toHaveText("Sign in to submit a sentiment.")
        #expect(URL(string: try await page.url())?.path == Self.sentimentForm)
      }
    } catch {
      word.remove()
      work.remove()
      try await admin.remove(after: error)
    }
    word.remove()
    work.remove()
    try await admin.remove()
  }

  // MARK: - Submit Sentiment

  @Test(arguments: gnorium.engines, Layout.allCases)
  func aSentimentIsOneNewNodeInItsRecordsTree(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin)
    let suffix = String(UUID().uuidString.prefix(8)).lowercased()
    let definition = "A web tests sense \(suffix)"
    func clean() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        CREATE TEMP TABLE mine AS SELECT id, batch_id FROM lexicographic_evidences
          WHERE sentiment_json LIKE '%\(definition)%';
        DELETE FROM lexicographic_overtures WHERE lexicographic_evidence_id IN (SELECT id FROM mine);
        DELETE FROM lexicographic_evidences WHERE id IN (SELECT id FROM mine);
        DELETE FROM submissions WHERE id IN (SELECT batch_id FROM mine);
        COMMIT;
        """)
    }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await newSentiment(page, suffix: suffix, definition: definition)
        try await placedSentiment(page, word: word, definition: definition)
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      clean()
      word.remove()
      try await admin.remove(after: error)
    }
    clean()
    word.remove()
    try await admin.remove()
  }

  /// A new record: its language, title and type typed, its tree the new
  /// sentiment alone, named by its definition as it is typed; submitted,
  /// an evidence and its overture with no record chosen.
  private func newSentiment(_ page: Page, suffix: String, definition: String) async throws {
    try await page.openHydrated(Self.sentimentForm)
    try await expect(page).toHaveTitle("Submit Sentiment | Mission Control | Gnorium")
    let form = page.locator(".submit-sentiment-form")
    try await expect(form.locator(".record-choice-field-view .dropdown-selected-text")).toHaveText("New record")
    let tree = form.locator(".submit-sentiment-tree")
    try await expect(tree.locator(".record-row-view")).toHaveCount(1)
    let draft = tree.locator("[data-submission-draft='true']")
    let title = draft.locator(".record-row-title").first
    try await expect(title).toHaveText("—")
    try await expect(form.locator(".framed-accordion-view")).toHaveCount(0)
    let apparatus = form.locator(".submit-sentiment-apparatus")
    try await expect(apparatus).toContainText("First attestation")
    try await apparatus.locator("input[name='title']").fill("webtestsnew\(suffix)")
    try await set(page, [("type", "noun")])
    try await draft.locator("#definition").fill(definition)
    try await expect(title).toHaveText(definition)
    try await form.locator(".record-actions button[type='submit']").click()
    try await expect(page, timeout: .seconds(15)).toHaveURL("its overture's page") {
      $0.path.hasPrefix("/mission-control/overtures/lexicographic/")
    }
    let row = try TestAdmin.query(
      """
      SELECT (e.title_form_json::json ->> 'title') || '|' || coalesce(e.chosen_lexico_record_id::text, '') || '|'
        || count(o.id)
        FROM lexicographic_evidences e LEFT JOIN lexicographic_overtures o ON o.lexicographic_evidence_id = e.id
        WHERE e.sentiment_json LIKE '%\(definition)%' GROUP BY e.id;
      """
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(row == "webtestsnew\(suffix)||1", "\(row)")
  }

  /// A chosen record: its fields as its page shows them, in place of the
  /// editable ones; its tree its own (a branch and its leaf), the new
  /// sentiment after the branch; placed under the branch, after the leaf;
  /// under the leaf, refused. Submitted: the record's own title, the choice
  /// and the placement ride on the evidence and its overture.
  private func placedSentiment(_ page: Page, word: ScratchWord, definition: String) async throws {
    try await page.openHydrated(Self.sentimentForm)
    let form = page.locator(".submit-sentiment-form")
    let field = form.locator(".record-choice-field-view")
    let dropdown = field.locator(".dropdown-view")
    let tree = form.locator(".submit-sentiment-tree")
    try await dropdown.locator(".dropdown-trigger").click()
    try await dropdown.locator(".dropdown-search-input").fill(word.title)
    try await dropdown.locator(
      ".dropdown-options-list[data-dropdown-results='true'] .dropdown-option[data-value='\(word.recordID)']"
    ).click()
    try await expect(field.locator("input[name='lexico-record']")).toHaveValue(word.recordID)
    try await expect(tree.locator(".outliner-view"), timeout: .seconds(15)).toHaveCount(1)
    let apparatus = form.locator(".submit-sentiment-apparatus")
    try await expect(apparatus.locator(".record-choice-apparatus")).toContainText(word.title)
    try await expect(apparatus.locator("input[name='title']")).toHaveCount(0)

    let draft = tree.locator(".outliner-item[data-outliner-id='new']")
    let number = draft.locator(".record-row-number").first
    try await expect(number).toHaveText("2")
    let handle = draft.locator(".outliner-handle").first
    try await handle.click()
    try await page.locator(".outliner-toolbar [data-outliner-action='indent']").click()
    try await page.locator(".outliner-toolbar [data-outliner-action='done']").click()
    try await expect(number).toHaveText("1.2")
    try await handle.click()
    try await handle.press("ArrowRight")
    try await expect(tree.locator(".outliner-feedback .alert-content"))
      .toHaveText("A more abstract sentiment can't go under a more concrete one.")
    try await handle.press("Escape")
    try await expect(number).toHaveText("1.2")

    try await draft.locator("#definition").fill("\(definition), placed")
    try await expect(draft.locator(".record-row-title").first).toHaveText("\(definition), placed")
    try await form.locator(".record-actions button[type='submit']").click()
    try await expect(page, timeout: .seconds(15)).toHaveURL("its overture's page") {
      $0.path.hasPrefix("/mission-control/overtures/lexicographic/")
    }
    let row = try TestAdmin.query(
      """
      SELECT (e.title_form_json::json ->> 'title') || '|' || e.chosen_lexico_record_id::text || '|'
        || o.chosen_lexico_record_id::text || '|' || e.placement_json
        FROM lexicographic_evidences e JOIN lexicographic_overtures o ON o.lexicographic_evidence_id = e.id
        WHERE e.sentiment_json LIKE '%\(definition), placed%';
      """
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    let record = word.recordID.lowercased()
    #expect(row.hasPrefix("\(word.title)|\(record)|\(record)|"), "\(row)")
    #expect(row.contains(#""parent":"s-1""#) && row.contains(#""position":1"#), "\(row)")
  }
}
