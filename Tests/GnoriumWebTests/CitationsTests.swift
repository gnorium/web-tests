import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The citation graph (user, 2026-09-28). A proposal's Citations list every
/// reference its text makes to another work and every word it cites as a
/// word, where each is and what it links to, as the resolver found it; a
/// signed-in reader suggests another link as a modification, which an admin
/// accepts, and the link is then a person's. A cited work's page says how
/// many works cite it and lists them in its "Citations". Phone and desktop,
/// Chrome headless.
@Suite("Citations", .serialized)
struct CitationsTests {
  /// Every word of `text` a <w>, as the recognition tags it.
  static func words(_ text: String) -> String {
    text.split(separator: " ").map { "<w lemma=\"\($0.lowercased())\" type=\"proper_noun\">\($0)</w>" }
      .joined(separator: " ")
  }

  /// A page quoting `work` and naming it by its author and title (words 4
  /// to 11), and citing "placement" as a word (word 15).
  static func tei(citing work: ScratchWork) -> String {
    """
    <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt><title>t</title></titleStmt></fileDesc></teiHeader><text><body>
    <pb n="1" facs="https://example.org/iiif/web-tests-citations/full/1300,/0/default.jpg"/>
    <p><s ana="#autonomy-0"><w lemma="as" type="preposition">As</w> <cit><quote><w lemma="the" type="article">the</w> <w lemma="report" type="noun">report</w></quote> <bibl><author>\(words(work.author))</author><pc>,</pc> <title>\(words(work.title))</title></bibl></cit> <w lemma="say" type="verb">says</w><pc>,</pc> <w lemma="the" type="article">the</w> <w lemma="word" type="noun">word</w> <mentioned><w lemma="placement" type="noun">placement</w></mentioned><pc>.</pc><lb/></s></p>
    </body></text></TEI>
    """
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aProposalListsItsCitationsAndAPersonsLinkIsSuggestedThenAccepted(engine: BrowserEngine, layout: Layout)
    async throws
  {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let cited = try ScratchWork(owner: admin)
    let reading = try ScratchReading(owner: admin, tei: Self.tei(citing: cited))
    func cleanUp() async throws {
      _ = try? TestAdmin.query("DELETE FROM modifications WHERE modifiable_id = '\(reading.proposalID)';")
      reading.remove()
      cited.remove()
      try await admin.remove()
    }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(reading.path)
        let citations = page.locator(".proposal-citations-view")
        try await expect(citations.locator(".proposal-citations-view-count")).toHaveText("2 citations")
        try await citations.locator(".accordion-summary").first.click()
        // Pending: read from its transcript, held at Permit, as its Entries.
        try await expect(citations.locator(".proposal-citations-view-note")).toContainText("held once it is permitted")
        let rows = citations.locator(".proposal-citation")
        try await expect(rows).toHaveCount(2)
        // The reference, resolved by its title and its author: the cited work.
        let reference = rows.nth(0)
        try await expect(reference).toContainText("Reference")
        // Named by its words, never by where it is.
        try await expect(reference).not.toContainText("l. 1, w.")
        try await expect(reference).toContainText("the report")
        try await expect(reference.locator("a[href='\(cited.path)']")).toHaveCount(1)
        try await expect(reference.locator("a[href='/users/gnorium']")).toHaveCount(1)
        try await expect(reference).toContainText("title+voices")
        // The word cited as a word: no lexico-record holds it.
        try await expect(rows.nth(1)).toContainText("Word cited")
        try await expect(rows.nth(1)).toContainText("placement")
        // Its record field is asked for once in view, the resolver's record chosen.
        _ = try await reference.evaluate("(el) => el.scrollIntoView({block: 'center'})")
        let field = reference.locator(".proposal-citations-view-record .origin-record-field-view")
        try await expect(field).toHaveCount(1)
        try await expect(field).toContainText("Cited record")
        try await page.expectNoHorizontalOverflow()

        // Suggest it as it stands: a modification, pending an admin.
        let submit = reference.locator("button[type='submit']")
        _ = try await submit.evaluate("(b) => b.scrollIntoView({block: 'center'})")
        try await expect(submit).toBeVisible()
        // Once its record field is settled on the resolver's record.
        try await expect(reference.locator("input[name='citation-record-0']")).toHaveValue(cited.recordID)
        // Pressed on the element itself: a coordinate click could land on
        // the record field's popover as it settles.
        _ = try await submit.evaluate("(b) => b.click()")
        // Back on the proposal, its thread says so.
        let thread = page.locator(".intervention-thread-view")
        try await expect(thread).toContainText("the citation “Web … \(cited.suffix)”")
        try await page.waitForLoadState()
        // Accepted, the link is a person's.
        let modification = try TestAdmin.query(
          "SELECT upper(id::text) FROM modifications WHERE modifiable_id = '\(reading.proposalID)' AND target = 'citation';"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!modification.isEmpty)
        try await thread.locator("form[action$='/modifications/\(modification)/accept'] button").first.click()
        try await expect(page.locator(".intervention-thread-view")).toContainText("accepted by")
        try await page.waitForLoadState()
        let accepted = page.locator(".proposal-citations-view")
        try await accepted.locator(".accordion-summary").first.click()
        try await expect(accepted.locator(".proposal-citation").nth(0)).toContainText("A person, by a modification accepted here")
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      do { try await cleanUp() } catch let removal {
        throw WebTestError("\(error)\n…and cleaning up failed too: \(removal)")
      }
      throw error
    }
    try await cleanUp()
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aCitedWorkSaysHowManyWorksCiteItAndListsThem(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let cited = try ScratchWork(owner: admin)
    let citing = try ScratchWork(owner: admin)
    // A citation of the one by the other's version, as a permit's reading
    // leaves it: standoff, resolved.
    let citation = UUID().uuidString.lowercased()
    let extraction = UUID().uuidString.lowercased()
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO citations (id, biblio_record_version_id, biblio_record_id, testament_id, permitted_at, canvas_id, page,
        start_line, start_word, start_surface, end_line, end_word, end_surface, element, kind, surface, parts_json,
        language_code, status, decided_by, cited_biblio_record_id, confidence, basis, resolver_version, resolved_at, created_at)
        VALUES ('\(citation)', '\(citing.versionID.lowercased())', '\(citing.recordID.lowercased())', '\(citing.recordID.lowercased())',
          now(), 'c', 1, 1, 1, 'Report', 1, 1, 'Report', 'bibl', 'work', 'Report', '{}', 'eng', 'resolved', 'resolver',
          '\(cited.recordID.lowercased())', 0.7, 'title', 'citation-resolver-v1', now(), now());
      INSERT INTO citation_extractions (id, biblio_record_version_id, testament_id, permitted_at, citations_version, count, extracted_at)
        VALUES ('\(extraction)', '\(citing.versionID.lowercased())', '\(citing.recordID.lowercased())', now(), 'tei-bibl-ref-mentioned-v3', 1, now());
      COMMIT;
      """)
    func cleanUp() async throws {
      _ = try? TestAdmin.query(
        "DELETE FROM citations WHERE id = '\(citation)'; DELETE FROM citation_extractions WHERE id = '\(extraction)';")
      citing.remove()
      cited.remove()
      try await admin.remove()
    }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(cited.path)
        // Its Citations: the citing work, with how many.
        let citations = page.locator("#record-citations")
        try await citations.locator(".accordion-summary").first.click()
        let row = citations.locator(".citations-view-work")
        try await expect(row.locator("a[href='\(citing.path)']")).toHaveCount(1)
        try await expect(row.locator(".citations-view-count")).toHaveText("1 citation")
        let metadata = page.locator("#record-metadata")
        try await metadata.locator(".accordion-summary").first.click()
        let datum = metadata.locator(".datum-view").filter(hasText: "Citations")
        try await expect(datum.locator(".datum-value")).toHaveText("1 work")
        try await page.expectNoHorizontalOverflow()
        // The citing work cites; nothing cites it.
        try await page.openHydrated(citing.path)
        let own = page.locator("#record-metadata")
        try await own.locator(".accordion-summary").first.click()
        try await expect(own.locator(".datum-view").filter(hasText: "Citations").locator(".datum-value")).toHaveText("0 works")
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

/// A proposal's Entries (user, 2026-09-29): a pending proposal's headed
/// entries, previewed from its own transcript (the utterances service's
/// `/entries/preview`, nothing stored; its body says so, no header chip—user,
/// 2026-09-30) and listed above Citations, each with the
/// record it is the entry for as the resolver linked it; a signed-in reader
/// suggests another record (or none) as a modification, which an admin
/// accepts, and the entry's link is then a person's, fixed. Phone and
/// desktop, Chrome headless.
@Suite("Entry links", .serialized)
struct EntryLinksTests {
  /// A page whose bibliography lists `work` by its author and title: one
  /// headed entry, for a work.
  static func tei(listing work: ScratchWork) -> String {
    """
    <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc><titleStmt><title>t</title></titleStmt></fileDesc></teiHeader><text><body>
    <pb n="1" facs="https://example.org/iiif/web-tests-entries/full/1300,/0/default.jpg"/>
    <listBibl><bibl><author>\(CitationsTests.words(work.author))</author><pc>,</pc> <title>\(CitationsTests.words(work.title))</title></bibl><lb/></listBibl>
    </body></text></TEI>
    """
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aProposalListsItsEntriesAndAPersonsLinkIsSuggestedThenAccepted(engine: BrowserEngine, layout: Layout)
    async throws
  {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let target = try ScratchWork(owner: admin)
    let reading = try ScratchReading(owner: admin, tei: Self.tei(listing: target))
    func cleanUp() async throws {
      _ = try? TestAdmin.query("DELETE FROM modifications WHERE modifiable_id = '\(reading.proposalID)';")
      reading.remove()
      target.remove()
      try await admin.remove()
    }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(reading.path)
        let entries = page.locator(".proposal-entries-view")
        try await expect(entries.locator(".proposal-entries-view-count")).toHaveText("1 entry")
        try await expect(entries.locator(".proposal-entries-view-heading .info-chip-view")).toHaveCount(0)
        // Entries always come above Citations.
        let order = try await page.evaluate(
          "(() => { const e = document.querySelector('.proposal-entries-view'), c = document.querySelector('.proposal-citations-view'); return e && c && (e.compareDocumentPosition(c) & Node.DOCUMENT_POSITION_FOLLOWING) ? 'above' : 'not above'; })()"
        ).string
        #expect(order == "above")
        try await entries.locator(".accordion-summary").first.click()
        try await expect(entries.locator(".proposal-entries-view-note")).toContainText("held once it is permitted")
        let row = entries.locator(".proposal-entry")
        try await expect(row).toHaveCount(1)
        try await expect(row).toContainText("Heading")
        try await expect(row).toContainText(target.title)
        try await expect(row.locator("a[href='\(target.path)']")).toHaveCount(1)
        try await expect(row.locator("a[href='/users/gnorium']")).toHaveCount(1)
        try await expect(row).toContainText("title+voices")
        // Its record field is asked for once in view, the resolver's record chosen; no node.
        _ = try await row.evaluate("(el) => el.scrollIntoView({block: 'center'})")
        let field = row.locator(".proposal-entries-view-record .origin-record-field-view")
        try await expect(field).toHaveCount(1)
        try await expect(field).toContainText("Entry for")
        try await expect(row.locator("input[name='entry-record-0']")).toHaveValue(target.recordID)
        try await expect(row.locator("[name='entry-record-0-node']")).toHaveCount(0)
        try await page.expectNoHorizontalOverflow()

        // Suggested as it stands: a modification, pending an admin.
        let submit = row.locator("button[type='submit']")
        _ = try await submit.evaluate("(b) => { b.scrollIntoView({block: 'center'}); b.click() }")
        let thread = page.locator(".intervention-thread-view")
        try await expect(thread).toContainText("the entry “")
        try await page.waitForLoadState()
        let modification = try TestAdmin.query(
          "SELECT upper(id::text) FROM modifications WHERE modifiable_id = '\(reading.proposalID)' AND target = 'entry';"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!modification.isEmpty)
        try await thread.locator("form[action$='/modifications/\(modification)/accept'] button").first.click()
        try await expect(page.locator(".intervention-thread-view")).toContainText("accepted by")
        try await page.waitForLoadState()
        // Accepted: the proposal holds the person's link, fixed.
        let accepted = page.locator(".proposal-entries-view")
        try await accepted.locator(".accordion-summary").first.click()
        try await expect(accepted.locator(".proposal-entry").nth(0)).toContainText("A person, by a modification accepted here")
        let links = try TestAdmin.query(
          "SELECT entry_links_json FROM bibliographic_proposals WHERE id = '\(reading.proposalID)';")
        #expect(links.lowercased().contains(target.recordID.lowercased()))
        #expect(links.lowercased().contains(modification.lowercased()))
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      do { try await cleanUp() } catch let removal {
        throw WebTestError("\(error)\n…and cleaning up failed too: \(removal)")
      }
      throw error
    }
    try await cleanUp()
  }

  /// A permitted version's entries are unknown until the utterances service has
  /// read them (user, 2026-09-30): "—", never "0 entries"; once read (its
  /// `entry_extractions` row), the count, 0 as surely as many.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aPermittedVersionsEntriesAreUnknownUntilRead(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let target = try ScratchWork(owner: admin)
    let scratch = try ScratchTestament(owner: admin, tei: Self.tei(listing: target))
    func cleanUp() async throws {
      scratch.remove()
      target.remove()
      try await admin.remove()
    }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(scratch.reading.path)
        let entries = page.locator(".proposal-entries-view")
        try await expect(entries.locator(".proposal-entries-view-count")).toHaveText("—")
        try await expect(entries.locator(".proposal-entries-view-body")).toContainText("Not read yet")
        try await expect(entries.locator(".proposal-entries-view-note")).toHaveCount(0)
        // Read, with none.
        _ = try TestAdmin.query(
          """
          INSERT INTO entry_extractions (id, biblio_record_version_id, count, extracted_at)
            VALUES ('\(UUID().uuidString.lowercased())', '\(scratch.versionID)', 0, now());
          """)
        try await page.openHydrated(scratch.reading.path)
        try await expect(entries.locator(".proposal-entries-view-count")).toHaveText("0 entries")
        try await page.expectNoHorizontalOverflow()
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
