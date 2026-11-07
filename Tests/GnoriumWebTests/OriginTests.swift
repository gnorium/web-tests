import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A work's ORIGIN: on Submit Testament an Origin block in the work (no
/// "This is a translation" box), a tree of steps (the site's one tree,
/// `OutlinerView`), each a flat node beside the tree's spine: a relation, a
/// record field (searched, two rows an option) and, once a record is
/// picked, its testaments to name one by; with no record, the work as
/// typed. The tree's one row of steppers adds and removes (user,
/// 2026-11-03): "‹ + Origin 1.1. ›" a step at the place stepped to (under a
/// step with no record, flush with it, its number saying how deep, or
/// after any), "‹ − Origin 1. ›" a step chosen. The page never wider than
/// the screen, the tree no scrollport of its own (user, 2026-11-03); a
/// menu opened in a deep step stands by its field. Removing a step with
/// steps under it asks first. The form posts the tree as one JSON list (the submit event is
/// dispatched by hand, which runs the form's script but never posts). On a
/// record page, the Origin section after the Metadata is the same tree, each
/// step its relations, what it came from (Language › Title, linked where it
/// is a record; its type), date, certainty and voices, "—" where unknown,
/// with the tree in one sentence above it; and the source record lists its
/// translations. A throwaway admin owns two
/// scratch works, removed after.
@Suite("Origin", .serialized)
struct OriginTests {
  static let form = "/mission-control/submit/bibliographic/testament"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func originRowsAndTheRecordPage(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let original = try ScratchWork(owner: admin)
    let translation = try ScratchWork(owner: admin)
    let typed = "Web tests Old English \(translation.suffix)"
    do {
      // The translation's origin, as a permit writes it: a typed Old
      // English step, which is a translation of the original's record.
      let step = UUID().uuidString
      let deeper = UUID().uuidString
      _ = try TestAdmin.query(
        """
        INSERT INTO biblio_record_origins (id, step_id, biblio_record_id, parent_id, position, target_record_id, typed_json, created_at)
          VALUES ('\(step)', gen_random_uuid(), '\(translation.recordID)', NULL, 0, NULL,
            '{"language":"ang","title":"\(typed)","type":"treatise","date":{"era":"anno_domini","year":890,"yearQualifier":"circa"}}', now());
        INSERT INTO biblio_record_origin_relations (id, origin_id, position, relation)
          VALUES ('\(UUID().uuidString)', '\(step)', 0, 'translation_of'),
            ('\(UUID().uuidString)', '\(step)', 1, 'abridgment_of');
        INSERT INTO biblio_record_origins (id, step_id, biblio_record_id, parent_id, position, target_record_id, typed_json, created_at)
          VALUES ('\(deeper)', gen_random_uuid(), '\(translation.recordID)', '\(step)', 0,
            '\(original.recordID)', NULL, now());
        INSERT INTO biblio_record_origin_relations (id, origin_id, position, relation)
          VALUES ('\(UUID().uuidString)', '\(deeper)', 0, 'translation_of');
        """)
      try await run(
        engine: engine, viewport: layout.viewport(for: engine), admin: admin, original: original,
        translation: translation, typed: typed)
    } catch {
      translation.remove()
      original.remove()
      try await admin.remove(after: error)
    }
    translation.remove()
    original.remove()
    try await admin.remove()
  }

  /// A deep chain is drawn whole, however deep, scrolling sideways on a
  /// phone and never the page. A loop no write lets in (written here as
  /// rows directly) draws the record it comes back to as a plain row
  /// (named, linked) with no steps under it, and no "…" anywhere. The first
  /// work's origin: fourteen typed steps, each under the last, the deepest
  /// naming the second work, whose own origin names the first. A form's
  /// record field, picking the second work for the first, says the origin
  /// leads back.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aDeepChainAndALoop(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let first = try ScratchWork(owner: admin)
    let second = try ScratchWork(owner: admin)
    let typedDepth = 14
    do {
      var sql = ""
      var parent = "NULL"
      for level in 0..<typedDepth {
        let step = UUID().uuidString
        sql += """
          INSERT INTO biblio_record_origins (id, step_id, biblio_record_id, parent_id, position, target_record_id, typed_json, created_at)
            VALUES ('\(step)', gen_random_uuid(), '\(first.recordID)', \(parent), 0, NULL,
              '{"language":"ang","title":"Web tests deep \(level + 1) \(first.suffix)","type":"treatise"}', now());
          INSERT INTO biblio_record_origin_relations (id, origin_id, position, relation)
            VALUES ('\(UUID().uuidString)', '\(step)', 0, 'translation_of');

          """
        parent = "'\(step)'"
      }
      let toSecond = UUID().uuidString
      let back = UUID().uuidString
      sql += """
        INSERT INTO biblio_record_origins (id, step_id, biblio_record_id, parent_id, position, target_record_id, typed_json, created_at)
          VALUES ('\(toSecond)', gen_random_uuid(), '\(first.recordID)', \(parent), 0, '\(second.recordID)', NULL, now());
        INSERT INTO biblio_record_origin_relations (id, origin_id, position, relation)
          VALUES ('\(UUID().uuidString)', '\(toSecond)', 0, 'translation_of');
        INSERT INTO biblio_record_origins (id, step_id, biblio_record_id, parent_id, position, target_record_id, typed_json, created_at)
          VALUES ('\(back)', gen_random_uuid(), '\(second.recordID)', NULL, 0, '\(first.recordID)', NULL, now());
        INSERT INTO biblio_record_origin_relations (id, origin_id, position, relation)
          VALUES ('\(UUID().uuidString)', '\(back)', 0, 'based_on');
        """
      _ = try TestAdmin.query(sql)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(first.path)
        let tree = page.locator("#origin .origin-view")
        try await expect(tree).toHaveCount(1)
        // Every step: the typed ones, the second work, and the first again,
        // each its fields as the form's step has them, read (user,
        // 2026-11-05).
        let steps = tree.locator(".origin-step-fields-view")
        try await expect(steps).toHaveCount(typedDepth + 2)
        try await expect(steps.nth(typedDepth - 1).locator("input[id$='-name']")).toHaveValue(
          "Web tests deep \(typedDepth) \(first.suffix)")
        // A record step's record field names it, never a link (metadata
        // never links to a record, user 2026-10-03).
        let named = ".origin-record-field-view .dropdown-selected-text .breadcrumb-label-text"
        try await expect(steps.nth(typedDepth).locator(named)).toHaveText(second.title)
        try await expect(steps.nth(typedDepth).locator("a[href='\(second.path)']")).toHaveCount(0)
        // The first work again: a plain row, its record field naming it,
        // with nothing under it.
        let repeated = steps.last
        try await expect(repeated.locator(named)).toHaveText(first.title)
        try await expect(repeated.locator("a[href='\(first.path)']")).toHaveCount(0)
        // Its relation, and the record's own year and voice, in the form's
        // controls. Its evidence is its Outgoing citations now (user,
        // 2026-11-03), none drawn on a record's page for a step with none.
        try await expect(repeated.locator("input[id$='-relation']")).toHaveValue("based_on")
        try await expect(repeated.locator("input[id$='-year']")).toHaveValue("1958")
        try await expect(repeated.locator("input[id$='-voice-item1-text-input']")).toHaveValue(first.author)
        try await expect(repeated.locator(".outgoing-citations-view")).toHaveCount(0)
        let shape = try await tree.evaluate(
          """
          (tree) => {
            const items = [...tree.querySelectorAll('.outliner-item')];
            const last = items[items.length - 1];
            const outliner = tree.querySelector('.outliner-view');
            return {
              leaf: !last.querySelector('.outliner-list .outliner-item'),
              ellipsis: tree.textContent.includes('…'),
              cut: tree.querySelectorAll('.origin-cut').length,
              scrolls: getComputedStyle(outliner).overflowX !== 'visible',
              page: document.documentElement.scrollWidth > window.innerWidth,
              reach: Math.max(...[...tree.querySelectorAll('.outliner-node')].map((n) => n.getBoundingClientRect().right + scrollX)) > window.innerWidth,
            };
          }
          """)
        #expect(shape["leaf"].bool == true, "the repeated record has no steps under it: \(shape)")
        #expect(shape["ellipsis"].bool == false && shape["cut"].int == 0, "no cut: \(shape)")
        // The tree never scrolls on its own, nor widens the page (user,
        // 2026-11-03): flat, its steps wrap to the screen.
        #expect(shape["scrolls"].bool == false, "the tree has no scrollport of its own: \(shape)")
        #expect(shape["page"].bool == false && shape["reach"].bool == false, "the page no wider than the screen: \(shape)")

        // The record field a form draws for the second work, filing for the
        // first: its error under the field; filing for nothing, none. (Its
        // search's failure, drawn with it and shown only once a search
        // fails, is not the field's error: `OptionsStatusView`.)
        let field = try await page.evaluate(
          """
          (async () => {
            const url = (own) => '/mission-control/record-choices/biblio-record/origin?name=origin-1-record&record=\(second.recordID)' + own;
            const errors = (html) => {
              const box = document.createElement('template');
              box.innerHTML = html;
              return [...box.content.querySelectorAll('.field-validation-message-view')]
                .filter((message) => !message.closest('.options-status-view'))
                .map((message) => message.textContent.trim());
            };
            const looped = errors(await (await fetch(url('&own=\(first.recordID)'))).text());
            const fresh = errors(await (await fetch(url(''))).text());
            return {
              looped: looped.some((text) => text.includes('This origin leads back to this record.')),
              fresh: fresh.length > 0,
            };
          })()
          """)
        #expect(field["looped"].bool == true && field["fresh"].bool == false, "\(field)")
      }
    } catch {
      second.remove()
      first.remove()
      try await admin.remove(after: error)
    }
    second.remove()
    first.remove()
    try await admin.remove()
  }

  /// The Submit forms say their origin in one sentence above the tree, as
  /// the record page does (user, 2026-11-01), rebuilt as any origin field
  /// changes: hidden while no step names anything, then the relation, the
  /// language as a sentence names it, the term and its class, never a date.
  /// The bibliographic form and the lexicographic one alike.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func theFormSaysItsOriginInOneSentence(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        for (url, field, term, type, said) in [
          (Self.form, "title", "Gesta Danorum", "chronicle", "A translation of the Latin Gesta Danorum (chronicle)."),
          ("/mission-control/submit/lexicographic/sentiment", "form", "ancora", "noun", "Borrowed from Latin ancora (noun)."),
        ] {
          try await page.openHydrated(url)
          let block = page.locator(".origin-field-view").first
          // Its own section, headed "Origin", between the Metadata and the
          // tree, never a field in the Metadata (user, 2026-11-03): no
          // field label of its own.
          try await expect(page.locator("#origin > .record-section-title")).toHaveText("Origin")
          try await expect(page.locator("#origin .origin-field-view")).toHaveCount(1)
          try await expect(page.locator("#record-metadata .origin-field-view")).toHaveCount(0)
          try await expect(block.locator(":scope > .field-view")).toHaveCount(0)
          let placed = try await page.evaluate(
            """
            (() => {
              const [m, o, t] = ['#metadata', '#origin', '#record-tree'].map((s) => document.querySelector(s));
              const after = (a, b) => !!(a && b && (a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING));
              return after(m, o) && after(o, t);
            })()
            """
          ).bool
          #expect(placed == true, "\(url): Origin is not between the Metadata and the tree")
          let sentence = block.locator(".origin-sentence-view")
          try await expect(sentence).toHaveCount(1)
          try await expect(sentence).toBeHidden()
          let row = block.locator("[data-origin-row='true']").first
          let key = try await row.getAttribute("data-origin-key") ?? ""
          // Typed: the sentence appears and follows each keystroke.
          try await row.locator("#\(key)-\(field)").fill(term)
          try await expect(sentence).toBeVisible()
          try await expect(sentence).toHaveText("\(term).")
          let relation = row.locator(".dropdown-view").first
          try await relation.locator(".dropdown-trigger").click()
          try await relation
            .locator(".dropdown-option[data-value='\(field == "title" ? "translation_of" : "borrowed_from")']").click()
          try await page.keyboard.press("Escape")
          // While its list is on its way, the open menu shows a wait under
          // the options it draws, the rotating ring sector, gone once the
          // list is in; a search typed meanwhile waits the same way
          // (`OptionsStatusView`). Watched as what it says turns busy and
          // back, since the list may come at once.
          _ = try await page.evaluate(
            """
            (() => {
              const status = document.querySelector('.dropdown-view:has(#\(key)-language) .dropdown-menu > .options-status-view');
              const wait = status.querySelector(':scope > .options-status-loading');
              window.languageWaits = [];
              new MutationObserver(() => window.languageWaits.push(
                `${status.dataset.state}:${getComputedStyle(wait).display}`
              )).observe(status, { attributes: true, attributeFilter: ['data-state'] });
            })()
            """)
          for (suffix, value, name) in [("language", "lat", "Latin"), ("type", type, type)] {
            let dropdown = row.locator(".dropdown-view:has(#\(key)-\(suffix))")
            try await dropdown.locator(".dropdown-trigger").click()
            // A long list is searched first.
            let search = dropdown.locator(".dropdown-search-input .search-input")
            if try await search.count() > 0 { try await search.fill(name) }
            try await dropdown.locator(".dropdown-option[data-value='\(value)']").filter(visible: true).first.click()
          }
          try await expect(sentence).toHaveText(said)
          try await expect(sentence.locator(".origin-sentence-language")).toHaveText("Latin")
          try await expect(sentence.locator(".origin-sentence-term")).toHaveAttribute("lang", "lat")
          // A date is data, never said.
          try await row.locator("#\(key)-year").fill("1200")
          try await expect(sentence).toHaveText(said)

          // Every language comes from the server (user, 2026-11-05): the
          // page draws only the chosen one, and the first open takes the
          // first 100, the languages with the most records first, the note
          // after them (asked once, whatever the page's language dropdowns).
          let language = row.locator(".dropdown-view:has(#\(key)-language)")
          let search = language.locator(".dropdown-search-input .search-input")
          let results = language.locator(".dropdown-options-list[data-dropdown-results='true']")
          let ownList = language.locator(".dropdown-options-list:not([data-dropdown-results])")
          let own = ownList.locator(":scope > .dropdown-option")
          try await expect(ownList.locator(":scope > .dropdown-note")).toHaveText("Showing the first 100.")
          // The wait first, as the menu opened on the list's ask; nothing
          // said at the end; never a failure.
          let waits = (try await page.evaluate("window.languageWaits.join(' ')").string ?? "")
            .split(separator: " ").map(String.init)
          #expect(
            waits.first == "busy:flex" && waits.last == "idle:none"
              && waits.allSatisfy { $0 == "busy:flex" || $0 == "idle:none" },
            "\(url): the wait while the list came: \(waits)")
          let listed = try await own.count()
          #expect((100...101).contains(listed), "the first 100, and Latin kept if they lack it: \(listed)")
          // Middle French, which a search finds (it has no native name: its
          // English name alone), chosen, stays chosen when the dropdown
          // searches again (user, 2026-11-05): kept in its own list—first,
          // where the first 100 lack it—where the sentence reads its name,
          // which carries no date.
          let ownMiddleFrench = ownList.locator(":scope > .dropdown-option[data-value='frm']")
          let middleFrenchListed = try await ownMiddleFrench.count() > 0
          try await language.locator(".dropdown-trigger").click()
          try await search.fill("Middle French")
          try await expect(results.locator(".dropdown-option[data-value='frm']")).toHaveText("Middle French")
          try await results.locator(".dropdown-option[data-value='frm']").click()
          let middleFrench = said.replacingOccurrences(of: "Latin", with: "Middle French")
          try await expect(sentence).toHaveText(middleFrench)
          try await language.locator(".dropdown-trigger").click()
          try await search.fill("Latin")
          try await expect(results.locator(".dropdown-option[data-value='lat']")).toBeVisible()
          try await expect(results.locator(".dropdown-option[data-value='frm']")).toHaveCount(0)
          try await page.keyboard.press("Escape")
          if !middleFrenchListed { try await expect(own.first).toHaveAttribute("data-value", "frm") }
          try await expect(ownMiddleFrench).toHaveAttribute("data-selected", "true")
          try await expect(language.locator(".dropdown-option[data-value='frm']")).toHaveCount(1)
          // Rebuilt as a field changes: the language still named.
          try await row.locator("#\(key)-year").fill("1300")
          try await expect(sentence).toHaveText(middleFrench)
          try await expect(sentence.locator(".origin-sentence-language")).toHaveText("Middle French")

          // The record's own Language takes the same list, never asked
          // again: one ask a page, every language dropdown sharing it.
          let recordLanguage = page.locator(
            ".dropdown-view:has(\(field == "title" ? "#work-language" : "#language"))")
          try await recordLanguage.locator(".dropdown-trigger").click()
          try await expect(
            recordLanguage.locator(".dropdown-options-list:not([data-dropdown-results]) > .dropdown-note")
          ).toHaveText("Showing the first 100.")
          // The list already in: no wait.
          try await expect(recordLanguage.locator(".options-status-loading")).toBeHidden()
          try await page.keyboard.press("Escape")
          let asked = try await page.evaluate(
            """
            performance.getEntriesByType('resource')
              .filter((entry) => new URL(entry.name).pathname === '/languages/options' && !new URL(entry.name).search)
              .length
            """
          ).int
          #expect(asked == 1, "\(url): the list asked \(asked ?? -1) times")
        }
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }

  /// A first list that fails (user, 2026-11-05): the wait gives way to one
  /// vague message in its place, a field's error, the reason in the log
  /// alone; the menu keeps its search box. The next open asks again, the
  /// message gone while it waits, and once the list is in the options show
  /// and the message never comes back. The first ask is failed in the page
  /// (`fetch` wrapped, as the registration tests stop theirs), shortly, as
  /// a server's error would come; the second reaches the server.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aFailedListSaysSoAndIsAskedAgain(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(Self.form)
        let language = page.locator(".dropdown-view:has(#work-language)")
        let menu = language.locator(".dropdown-menu")
        let status = menu.locator(":scope > .options-status-view")
        let wait = status.locator(":scope > .options-status-loading")
        let failed = status.locator(":scope > .options-status-failed")
        let ownList = menu.locator(":scope > .dropdown-options-list:not([data-dropdown-results])")
        // Each change of what it says recorded as it turns busy or failed
        // and back: what it says, then the wait's display and the message's.
        #expect(
          try await page.evaluate(
            """
            (() => {
              window.listAsks = 0;
              const fetched = window.fetch;
              window.fetch = (url, options) => {
                const asked = new URL(String(url), location.href);
                if (asked.pathname === '/languages/options' && !asked.search && window.listAsks++ === 0) {
                  return new Promise((resolve) => setTimeout(() => resolve(new Response('', { status: 503 })), 100));
                }
                return fetched(url, options);
              };
              const status = document.querySelector('.dropdown-view:has(#work-language) .dropdown-menu > .options-status-view');
              const shown = (row) => getComputedStyle(status.querySelector(`:scope > .options-status-${row}`)).display;
              window.listStates = [];
              new MutationObserver(() => window.listStates.push(`${status.dataset.state}:${shown('loading')}:${shown('failed')}`))
                .observe(status, { attributes: true, attributeFilter: ['data-state'] });
              return true;
            })()
            """, as: Bool.self))

        // The first open: the message in the wait's place, a one-line
        // option's row right under the options the page drew, no note.
        try await language.locator(".dropdown-trigger").click()
        try await expect(failed).toBeVisible()
        try await expect(failed.locator(".field-validation-message-text")).toHaveText(
          "The options could not be loaded.")
        try await expect(failed.locator(".field-validation-message-view")).toHaveAttribute("data-status", "error")
        try await expect(wait).toBeHidden()
        try await expect(ownList.locator(":scope > .dropdown-note")).toHaveCount(0)
        try await expect(language.locator(".dropdown-search-input .search-input")).toBeVisible()
        let place = try await menu.evaluate(
          """
          (menu) => {
            const list = menu.querySelector(':scope > .dropdown-options-list').getBoundingClientRect();
            const row = menu.querySelector(':scope > .options-status-view > .options-status-failed').getBoundingClientRect();
            return { under: Math.abs(row.top - list.bottom) < 1, tall: row.height >= 40 };
          }
          """)
        #expect(place["under"].bool == true && place["tall"].bool == true, "in the wait's place: \(place)")
        // Why, in the log alone (the bridge's).
        let logged = try await page.diagnostics().contains {
          $0.kind == .consoleError && $0.message.contains("Fragment load failed")
            && $0.message.contains("/languages/options")
        }
        #expect(logged, "the reason is logged")
        try await page.keyboard.press("Escape")

        // The next open asks again: the list comes, the message gone.
        try await language.locator(".dropdown-trigger").click()
        try await expect(ownList.locator(":scope > .dropdown-note")).toHaveText("Showing the first 100.")
        try await expect(failed).toBeHidden()
        try await expect(wait).toBeHidden()
        let listed = try await ownList.locator(":scope > .dropdown-option").count()
        #expect(listed >= 100, "the first 100: \(listed)")
        try await page.keyboard.press("Escape")
        // Once in, never asked again, and the message never back.
        try await language.locator(".dropdown-trigger").click()
        try await expect(ownList.locator(":scope > .dropdown-note")).toHaveText("Showing the first 100.")
        try await expect(failed).toBeHidden()
        try await page.keyboard.press("Escape")

        let states = try await page.evaluate("window.listStates.join(' ')").string
        #expect(
          states == "busy:flex:none failed:none:flex busy:flex:none idle:none:none",
          "the wait, the message, the wait again without it, then neither: \(states ?? "—")")
        let asks = try await page.evaluate("window.listAsks").int
        #expect(asks == 2, "asked, failed, and asked once more: \(asks ?? -1)")
        let reached = try await page.evaluate(
          """
          performance.getEntriesByType('resource')
            .filter((entry) => new URL(entry.name).pathname === '/languages/options' && !new URL(entry.name).search)
            .length
          """
        ).int
        #expect(reached == 1, "the second ask reached the server: \(reached ?? -1)")
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }

  /// A search that fails says so as its list does (user, 2026-11-05): from
  /// the key on, the wait under the options it shows, then one vague
  /// message in the wait's place, a field's error, those options kept—the
  /// language chosen among them still listed and chosen. The next open,
  /// and the next key, ask again, the message gone. An earlier query's
  /// answer, or its failure, never shows and ends no wait. The searches are
  /// answered in the page (`fetch` wrapped, as the list's failure is), each
  /// planned query as its plan says: failed after a moment, or passed on to
  /// the server late.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aFailedSearchSaysSoAndALateOneNever(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(Self.form)
        let language = page.locator(".dropdown-view:has(#work-language)")
        let menu = language.locator(".dropdown-menu")
        let status = menu.locator(":scope > .options-status-view")
        let wait = status.locator(":scope > .options-status-loading")
        let failed = status.locator(":scope > .options-status-failed")
        let search = language.locator(".dropdown-search-input .search-input")
        let ownList = menu.locator(":scope > .dropdown-options-list:not([data-dropdown-results])")
        let results = menu.locator(":scope > .dropdown-options-list[data-dropdown-results='true']")
        let chosen = ownList.locator(":scope > .dropdown-option[data-value='frm']")
        #expect(
          try await page.evaluate(
            """
            (() => {
              window.searchAsks = [];
              window.searchAnswered = [];
              const plans = {
                'Web tests fails': { status: 503, delay: 300 },
                'Web tests late': { status: 503, delay: 1500 },
                'Old English': { delay: 1500 },
              };
              const fetched = window.fetch;
              window.fetch = (url, options) => {
                const asked = new URL(String(url), location.href);
                const query = asked.searchParams.get('q');
                const plan = asked.pathname === '/languages/options' && query !== null ? plans[query] : undefined;
                if (query !== null) window.searchAsks.push(query);
                if (!plan) return fetched(url, options);
                return new Promise((resolve) => setTimeout(resolve, plan.delay))
                  .then(() => plan.status ? new Response('', { status: plan.status }) : fetched(url, options))
                  .then((response) => { window.searchAnswered.push(query); return response; });
              };
              const status = document.querySelector('.dropdown-view:has(#work-language) .dropdown-menu > .options-status-view');
              window.searchStates = [];
              new MutationObserver(() => window.searchStates.push(status.dataset.state))
                .observe(status, { attributes: true, attributeFilter: ['data-state'] });
              return true;
            })()
            """, as: Bool.self))
        func states() async throws -> String {
          try await page.evaluate("window.searchStates.splice(0).join(' ')").string ?? ""
        }
        func asked(_ query: String) async throws {
          _ = try await page.evaluate(
            """
            new Promise((resolve) => {
              const check = () => window.searchAsks.includes('\(query)') ? resolve(true) : setTimeout(check, 20);
              check();
            })
            """)
        }
        // Its planned answer handed to the bridge, and a moment for the
        // bridge to tell the dropdown.
        func answered(_ query: String) async throws {
          _ = try await page.evaluate(
            """
            new Promise((resolve) => {
              const check = () => window.searchAnswered.includes('\(query)')
                ? setTimeout(() => resolve(true), 300) : setTimeout(check, 20);
              check();
            })
            """)
        }

        // Middle French, chosen by a search: kept in its own list.
        try await language.locator(".dropdown-trigger").click()
        try await expect(ownList.locator(":scope > .dropdown-note")).toHaveText("Showing the first 100.")
        try await search.fill("Middle French")
        try await results.locator(".dropdown-option[data-value='frm']").click()
        try await expect(page.locator("#work-language")).toHaveValue("frm")
        _ = try await states()

        // A search that fails: the wait, then the message in its place, a
        // one-line option's row under its own list, Middle French still
        // listed and chosen there and in the field.
        try await language.locator(".dropdown-trigger").click()
        try await search.fill("Web tests fails")
        try await expect(failed).toBeVisible()
        try await expect(failed.locator(".field-validation-message-text")).toHaveText(
          "The options could not be loaded.")
        try await expect(failed.locator(".field-validation-message-view")).toHaveAttribute("data-status", "error")
        try await expect(wait).toBeHidden()
        try await expect(ownList).not.toHaveAttribute("hidden")
        try await expect(chosen).toHaveAttribute("data-selected", "true")
        try await expect(page.locator("#work-language")).toHaveValue("frm")
        try await expect(language.locator(".dropdown-selected-text")).toHaveText("Middle French")
        let place = try await menu.evaluate(
          """
          (menu) => {
            const list = menu.querySelector(':scope > .dropdown-options-list:not([hidden])').getBoundingClientRect();
            const row = menu.querySelector(':scope > .options-status-view > .options-status-failed').getBoundingClientRect();
            return { under: Math.abs(row.top - list.bottom) < 1, tall: row.height >= 40 };
          }
          """)
        #expect(place["under"].bool == true && place["tall"].bool == true, "in the wait's place: \(place)")
        #expect(try await states() == "busy failed", "the wait, then the message")

        // The next open asks nothing until a key, the message gone; the
        // next key asks again.
        try await page.keyboard.press("Escape")
        try await language.locator(".dropdown-trigger").click()
        try await expect(failed).toBeHidden()
        try await search.fill("Web tests fails")
        try await expect(failed).toBeVisible()
        try await search.fill("Latin")
        try await expect(results.locator(".dropdown-option[data-value='lat']")).toBeVisible()
        try await expect(failed).toBeHidden()
        try await expect(wait).toBeHidden()
        #expect(
          try await states() == "idle busy failed busy idle",
          "closed, nothing said; the wait and the message again; the wait, then the answer")
        let fails = try await page.evaluate("window.searchAsks.filter((q) => q === 'Web tests fails').length").int
        #expect(fails == 2, "the failed query asked again: \(fails ?? -1)")

        // An earlier query's failure, late, never shows, and ends no wait.
        try await search.fill("Web tests late")
        try await asked("Web tests late")
        try await search.fill("Latin")
        try await expect(results.locator(".dropdown-option[data-value='lat']")).toBeVisible()
        try await answered("Web tests late")
        try await expect(failed).toBeHidden()
        try await expect(status).toHaveAttribute("data-state", "idle")
        #expect(try await states() == "busy idle", "one wait, never the late failure")

        // An earlier query's answer, late, never shows.
        try await search.fill("Old English")
        try await asked("Old English")
        try await search.fill("Latin")
        try await expect(results.locator(".dropdown-option[data-value='lat']")).toBeVisible()
        try await answered("Old English")
        try await expect(results.locator(".dropdown-option[data-value='ang']")).toHaveCount(0)
        try await expect(results.locator(".dropdown-option[data-value='lat']")).toBeVisible()
        try await page.keyboard.press("Escape")
        // Chosen still, through every failure.
        try await expect(page.locator("#work-language")).toHaveValue("frm")
        try await expect(chosen).toHaveAttribute("data-selected", "true")
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }

  private func run(
    engine: BrowserEngine, viewport: Viewport, admin: TestAdmin, original: ScratchWork, translation: ScratchWork,
    typed: String
  ) async throws {
    try await withPage(engine, gnorium, viewport: viewport, cookies: [admin.cookie]) { page in
      try await page.openHydrated(Self.form)
      let form = page.locator(".submit-testament-form")
      // No translation box and no chain: an Origin block in the work.
      try await expect(form.locator(".is-translation-checkbox-wrapper")).toHaveCount(0)
      try await expect(form.locator(".translation-chain-view")).toHaveCount(0)
      let block = form.locator(".origin-field-view")
      try await expect(block).toHaveCount(1)
      // No heading; one row to start, as the voices have.
      try await expect(block.locator(".origin-field-heading")).toHaveCount(0)
      // A step's card in a list of the tree: the top level's, or a step's own.
      let cards = ":scope > .outliner-item > .outliner-row > .outliner-node > [data-origin-row='true']"
      let top = block.locator(".origin-field-steps > .outliner-list")
      let rows = top.locator(cards)
      try await expect(rows).toHaveCount(1)
      let items = top.locator(":scope > .outliner-item")
      // No step has controls of its own: the tree's one row of steppers
      // after it adds and removes (user, 2026-11-03).
      try await expect(items.first.locator(":scope > .outliner-footer")).toHaveCount(0)
      let stepper = TreeStepper(in: block)
      try await expect(stepper.row).toHaveCount(1)

      // The row: its relation (a plain noun), its record field, its typed
      // fields while no record is picked. The stepper's "+ Origin 2."
      // ("Add origin 2.") at first, after the last step; stepped back,
      // "+ Origin 1.1.", a step under it: the icon, the noun and the number
      // the new step will get.
      let first = rows.first
      try await expect(first.locator(".origin-record-field-view")).toHaveCount(1)
      try await expect(stepper.addButton).toHaveAttribute("aria-label", "Add origin 2.")
      try await expect(stepper.addButton).toHaveText("Origin 2.")
      try await expect(stepper.addButton.locator("svg.plus-icon-view")).toHaveCount(1)
      #expect(try await stepper.choices("add") == ["Add origin 1.1.", "Add origin 2."])
      try await stepper.choose("add", "Add origin 2.")
      // The form keeps one step at least (user, 2026-09-29): a lone step
      // cannot go, so the box can never go.
      try await expect(stepper.removeButton).toBeDisabled()
      try await expect(stepper.removeButton.locator("svg.minus-icon-view")).toHaveCount(1)
      // The Biblio-record field and the Metadata under it, a field's gap
      // apart (spacing16), never touching.
      let apart = try await form.evaluate(
        "(f) => { const b = f.querySelector('#metadata > .record-section-body'); const [x, y] = b.children; return Math.round(y.getBoundingClientRect().top - x.getBoundingClientRect().bottom) }"
      ).int
      #expect(apart == 16, "the Biblio-record field and the Metadata should be 16px apart, not \(String(describing: apart))")
      try await expect(first).toContainText("Relation")
      let relation = first.locator(".dropdown-view").first
      // Its tooltip, as the bubble says it when shown.
      let tooltip = { () async throws -> String in
        try await relation.locator(".dropdown-label [data-tooltip='true']").hover()
        let bubble = page.locator(".tooltip-view[data-portal='true'][data-visible='true'] .tooltip-content")
        try await expect(bubble).toHaveCount(1)
        let text = try await bubble.evaluate("(e) => e.textContent.trim()").string ?? ""
        // Away again, so the bubble covers nothing the test clicks next.
        try await relation.locator(".dropdown-label-text").hover()
        try await expect(bubble).toHaveCount(0)
        return text
      }
      #expect(try await tooltip() == "The relation of the origin.")
      // A work's relations in FRBR's order: Transformation (another type of
      // work) after Adaptation (the same type).
      try await expect(relation.locator(".dropdown-option .dropdown-option-display-text")).toHaveTexts([
        "Translation", "Adaptation", "Transformation", "Abridgment", "Continuation", "Exposition", "Derivation",
        "Compilation", "Conflation",
      ])
      // Several relations to one work (user, 2026-09-29): the menu stays
      // open while they are chosen, the closed field names them in order.
      try await relation.locator(".dropdown-trigger").click()
      try await relation.locator(".dropdown-option[data-value='translation_of']").click()
      try await relation.locator(".dropdown-option[data-value='abridgment_of']").click()
      try await expect(relation.locator(".dropdown-menu")).toHaveAttribute("data-open", "true")
      try await expect(relation.locator(".dropdown-option.is-selected")).toHaveCount(2)
      // Each option's checkbox says whether it is chosen, under the pointer
      // too: a second click on one takes it out, the menu still open.
      try await expect(relation.locator(".dropdown-option .dropdown-option-checkbox")).toHaveCount(9)
      try await expect(relation.locator(".dropdown-option-checkmark").filter(visible: true)).toHaveCount(2)
      try await relation.locator(".dropdown-option[data-value='abridgment_of']").click()
      try await expect(relation.locator(".dropdown-option-checkmark").filter(visible: true)).toHaveCount(1)
      try await expect(relation.locator(".dropdown-menu")).toHaveAttribute("data-open", "true")
      try await relation.locator(".dropdown-option[data-value='abridgment_of']").click()
      // Escape closes it, as a click on the field or outside does.
      try await page.keyboard.press("Escape")
      try await expect(relation.locator(".dropdown-menu")).toHaveAttribute("data-open", "false")
      try await relation.locator(".dropdown-trigger").click()
      try await expect(relation.locator(".dropdown-menu")).toHaveAttribute("data-open", "true")
      try await relation.locator(".dropdown-trigger").click()
      try await expect(relation.locator(".dropdown-menu")).toHaveAttribute("data-open", "false")
      try await expect(relation.locator(".dropdown-selected-text")).toHaveText("Translation and Abridgment")
      // The tooltip now says what each means.
      #expect(try await tooltip() == "A rendering of the work in another language. A shortened version of the work.")
      // How sure it is: optional, certain unless said.
      let certainty = first.locator(".dropdown-view").nth(1)
      try await expect(first).toContainText("Certainty")
      try await certainty.locator(".dropdown-trigger").click()
      try await certainty.locator(".dropdown-option[data-value='probable']").click()
      try await expect(certainty.locator(".dropdown-selected-text")).toHaveText("Probable")
      let record = first.locator(".origin-field-record .origin-record-field-view")
      try await expect(record.locator("legend")).toContainText("Biblio-record")
      let typedFields = first.locator(".origin-field-typed")
      try await expect(typedFields).toBeVisible()

      // Pick the original's record: the typed fields go; its testaments
      // follow, to name one by.
      // The pointer off the Title's info icon the closing menu left it on, so
      // its bubble covers nothing the test clicks next.
      try await certainty.locator(".dropdown-label-text").hover()
      let picker = record.locator(".dropdown-view").first
      try await picker.locator(".dropdown-trigger").click()
      try await picker.locator(".dropdown-search-input .search-input").fill(original.suffix)
      let found = picker.locator(
        ".dropdown-options-list[data-dropdown-results='true'] .dropdown-option[data-value='\(original.recordID)']")
      try await expect(found.locator(".breadcrumb-label-text")).toHaveText(original.title)
      try await found.click()
      try await expect(typedFields).toBeHidden()
      // A record's origin is its own: no place under a picked record.
      #expect(try await stepper.choices("add") == ["Add origin 2."])
      let node = first.locator(".origin-record-field-view .dropdown-view").nth(1)
      // Its Value (user, 2026-11-02): the record's testaments, valued by
      // their ids, each by its number and its value.
      try await expect(node.locator(".dropdown-label")).toContainText("Value")
      let edition = node.locator(".dropdown-option").filter(hasText: "First edition")
      try await expect(edition).toHaveCount(1)
      let editionID = try await edition.getAttribute("data-value") ?? ""
      try await certainty.locator(".dropdown-label-text").hover()
      try await node.locator(".dropdown-trigger").click()
      try await edition.click()
      // The form's sentence names the record, its term previewing it (and
      // the node named) without leaving the form (user, 2026-11-01).
      let formTerm = block.locator(".origin-sentence-view button[data-gloss-preview]")
      try await expect(formTerm).toHaveText(original.title)
      try await expect(formTerm).toHaveAttribute("data-gloss-preview", "\(original.path)/preview?node=\(editionID)")
      try await formTerm.click()
      let formSheet = page.locator(".gloss-sheet")
      try await expect(formSheet).toHaveAttribute("data-state", "open")
      let heading = formSheet.locator(".gloss-sheet-title a.record-preview-heading")
      try await expect(heading).toHaveCount(1)
      let href = try await heading.getAttribute("href") ?? ""
      #expect(href.hasPrefix("\(original.path)#record-row-"), "the node's row: \(href)")
      #expect(try await page.evaluate("location.pathname").string == Self.form)
      try await page.keyboard.press("Escape")
      try await expect(formSheet).toHaveAttribute("data-state", "closed")

      // A second row, typed, after the first ("+ Origin 2."): a step
      // under it gives it an origin of its own.
      try await stepper.add("Add origin 2.")
      try await expect(rows).toHaveCount(2)
      let second = rows.nth(1)
      // Numbered as the first is: "2." before its title.
      try await expect(second.locator(".record-node-number")).toHaveText("2")
      // Its record field is asked for once it is on the page: settled, the
      // row stops moving what is under it.
      try await expect(second.locator(".origin-record-field-view")).toHaveCount(1)
      // Two steps: either may go now, the last chosen at first ("−
      // Origin 2."); a new one goes after the first, under the typed
      // second, or after it.
      try await expect(stepper.removeButton).toBeEnabled()
      try await expect(stepper.removeButton).toHaveText("Origin 2.")
      try await expect(stepper.removeButton).toHaveAttribute("aria-label", "Remove origin 2.")
      #expect(try await stepper.choices("remove") == ["Remove origin 1.", "Remove origin 2."])
      #expect(try await stepper.choices("add") == ["Add origin 2.", "Add origin 2.1.", "Add origin 3."])
      // Each stepper whole on one row, its chevrons round its button.
      let whole = try await stepper.row.evaluate(
        """
        (r) => [...r.querySelectorAll('.outliner-stepper-add, .outliner-stepper-remove')].every((p) => {
          const [prev, button, next] = [p.querySelector('.pagination-prev'), p.querySelector('.outliner-stepper-button'), p.querySelector('.pagination-next')].map((e) => e.getBoundingClientRect());
          return Math.abs(prev.top + prev.height / 2 - (button.top + button.height / 2)) < 1 && prev.right <= button.left && button.right <= next.left; })
        """
      ).bool
      #expect(whole == true, "each stepper whole on one row: ‹ button ›")
      // A record one step names is not offered to another (user,
      // 2026-09-29): the original, picked in the first, is withheld from the
      // second's record field, searched for by name too.
      let secondPicker = second.locator(".origin-record-field-view .dropdown-view").first
      try await expect(secondPicker).toHaveAttribute("data-excluded-values", original.recordID)
      try await secondPicker.locator(".dropdown-trigger").click()
      try await secondPicker.locator(".dropdown-search-input .search-input").fill(original.suffix)
      let withheld = secondPicker.locator(
        ".dropdown-options-list[data-dropdown-results='true'] .dropdown-option[data-value='\(original.recordID)']")
      try await expect(withheld).toHaveAttribute("data-excluded", "true")
      try await expect(withheld).toBeHidden()
      try await page.keyboard.press("Escape")
      let secondRelation = second.locator(".dropdown-view").first
      try await secondRelation.locator(".dropdown-trigger").click()
      try await secondRelation.locator(".dropdown-option[data-value='adaptation_of']").click()
      try await secondRelation.locator(".dropdown-trigger").click()
      try await second.locator("input[name$='-title']").first.fill("Web tests typed work")
      // Its type, from the work's closed list (no "Other"), and its date as
      // every date of ours: a range shows its end once chosen, in a row
      // added after the page loaded too.
      let secondKey = try await second.getAttribute("data-origin-key") ?? ""
      let secondType = second.locator(".dropdown-view:has(#\(secondKey)-type)")
      try await expect(secondType.locator(".dropdown-option[data-value='other']")).toHaveCount(0)
      try await secondType.locator(".dropdown-trigger").click()
      try await secondType.locator(".dropdown-search-input .search-input").fill("Treatise")
      try await secondType.locator(".dropdown-option[data-value='treatise']").filter(visible: true).first.click()
      let secondDate = second.locator(".origin-field-typed > .form-date-view")
      try await expect(secondDate).toHaveCount(1)
      let yearEnd = secondDate.locator("input[name='\(secondKey)-year-end']")
      try await expect(yearEnd).toBeHidden()
      let qualifier = secondDate.locator(".dropdown-view:has(#\(secondKey)-year-qualifier)")
      try await qualifier.locator(".dropdown-trigger").click()
      try await qualifier.locator(".dropdown-option[data-value='range']").click()
      try await expect(yearEnd).toBeVisible()
      try await secondDate.locator("input[name='\(secondKey)-year']").fill("1560")
      try await yearEnd.fill("1565")
      // Its voices a row each, as the work's own: a role and a name.
      let voiceList = second.locator(".origin-field-typed > .form-items-view")
      let voiceRows = voiceList.locator("[data-item-section='true']:not([data-item-template] *)")
      try await expect(voiceRows).toHaveCount(1)
      try await voiceRows.first.locator(".text-input-input").fill("Ann Author")
      try await voiceList.locator("[data-item-add-btn='true'] button").click()
      try await expect(voiceRows).toHaveCount(2)
      try await voiceRows.nth(1).locator(".dropdown-trigger").click()
      try await voiceRows.nth(1).locator(".dropdown-option[data-value='translator']").click()
      try await voiceRows.nth(1).locator(".text-input-input").fill("Bea Author")
      // Its own step goes under it in the tree, flush with it.
      let secondItem = block.locator(".outliner-item[data-origin-step='\(secondKey)']")
      try await stepper.add("Add origin 2.1.")
      let nested = secondItem.locator(":scope > .outliner-list").locator(cards)
      try await expect(nested).toHaveCount(1)
      let indent = try await secondItem.evaluate(
        "(item) => { const own = item.querySelector(':scope > .outliner-row > .outliner-node'); const under = item.querySelector(':scope > .outliner-list .outliner-node'); return Math.round(under.getBoundingClientRect().left - own.getBoundingClientRect().left) }"
      ).int
      // Flush with it, no card round it and no indent (user, 2026-11-03).
      #expect(indent == 0, "a step under a step stands flush with it, not \(String(describing: indent))px in")
      try await expect(nested.first.locator(".origin-record-field-view")).toHaveCount(1)
      try await expect(nested.first.locator(".record-node-number")).toHaveText("2.1")
      // The steppers name it, and the places round it.
      #expect(try await stepper.choices("remove") == ["Remove origin 1.", "Remove origin 2.", "Remove origin 2.1."])
      #expect(
        try await stepper.choices("add") == [
          "Add origin 2.", "Add origin 2.1.", "Add origin 2.1.1.", "Add origin 2.2.", "Add origin 3.",
        ])
      let nestedRelation = nested.first.locator(".dropdown-view").first
      try await nestedRelation.locator(".dropdown-trigger").click()
      try await nestedRelation.locator(".dropdown-option[data-value='translation_of']").click()
      try await nestedRelation.locator(".dropdown-trigger").click()
      try await nested.first.locator("input[name$='-title']").first.fill("Web tests deeper work")

      // What the form posts: the rows in order, the typed row's own under it.
      let posted = try await form.evaluate(
        """
        (form) => {
          // The page's own check would stop an unfinished form's submit
          // before its script writes the JSON: this reads the script alone.
          form.removeAttribute('novalidate');
          form.dispatchEvent(new Event('submit', { cancelable: true }));
          return form.querySelector('.origin-field-json').value;
        }
        """
      ).string ?? ""
      let json = try JSONSerialization.jsonObject(with: Data(posted.utf8)) as? [[String: Any]] ?? []
      #expect(json.count == 2, "\(posted)")
      #expect(json.first?["relations"] as? [String] == ["translation_of", "abridgment_of"], "\(posted)")
      #expect(json.first?["certainty"] as? String == "probable")
      #expect(json.first?["record"] as? String == original.recordID)
      #expect(json.first?["node"] as? String == editionID, "\(posted)")
      let secondPosted = json.count > 1 ? json[1] : [:]
      #expect(secondPosted["relations"] as? [String] == ["adaptation_of"])
      let secondTyped = secondPosted["typed"] as? [String: Any] ?? [:]
      #expect(secondTyped["title"] as? String == "Web tests typed work")
      #expect(secondTyped["type"] as? String == "treatise", "\(posted)")
      let date = secondTyped["date"] as? [String: Any] ?? [:]
      #expect(date["yearQualifier"] as? String == "range", "\(posted)")
      #expect(date["era"] as? String == "anno_domini")
      #expect(date["year"] as? Int == 1560)
      #expect(date["yearEnd"] as? Int == 1565)
      #expect(date["eraEnd"] as? String == "anno_domini")
      let voices = (secondTyped["voices"] as? [[String: Any]] ?? []).map {
        "\($0["role"] as? String ?? ""):\($0["name"] as? String ?? "")"
      }
      #expect(voices == ["author:Ann Author", "translator:Bea Author"])
      let deeper = secondPosted["origins"] as? [[String: Any]] ?? []
      #expect(deeper.count == 1)
      #expect((deeper.first?["typed"] as? [String: Any])?["title"] as? String == "Web tests deeper work")

      // Unset the pick: "—", the testaments go, the typed fields come back.
      try await picker.locator(".dropdown-trigger").click()
      // The menu settled open before its option is aimed at.
      let chosen = picker.locator(".dropdown-option[data-value='\(original.recordID)']").first
      try await expect(chosen).toBeVisible()
      try await chosen.click()
      try await expect(first.locator(".origin-record-field-view")).not.toContainText("Testament")
      try await expect(typedFields).toBeVisible()
      // A step with a step under it asks before it goes: Cancel keeps both.
      let removeDialog = block.locator(".origin-field-remove-dialog")
      try await stepper.remove("Remove origin 2.")
      try await expect(removeDialog).toHaveAttribute("open")
      try await removeDialog.locator(".dialog-default-button button").click()
      try await expect(removeDialog).not.toHaveAttribute("open")
      try await expect(rows).toHaveCount(2)
      try await expect(nested).toHaveCount(1)
      // Remove confirms it: the step goes with the one under it.
      try await stepper.remove("Remove origin 2.")
      try await removeDialog.locator(".dialog-primary-button button").click()
      try await expect(rows).toHaveCount(1)
      try await expect(block.locator("[data-origin-row='true']")).toHaveCount(1)
      // The last step stays: "− Origin" disabled again.
      try await expect(stepper.removeButton).toBeDisabled()

      // Nothing scrolls sideways.
      let overflow = try await page.evaluate("document.documentElement.scrollWidth > window.innerWidth").bool
      #expect(overflow == false)

      // A deep origin, six steps each under the last (user, 2026-09-30):
      // flat, every step as wide as the first, the page never wider than
      // the screen, the tree no scrollport of its own (user, 2026-11-03).
      for depth in 1..<6 {
        // Under the deepest step: 1.1, then 1.1.1, …
        let number = Array(repeating: "1", count: depth + 1).joined(separator: ".")
        try await stepper.add("Add origin \(number).")
        try await expect(block.locator("[data-origin-row='true']")).toHaveCount(depth + 1)
        try await expect(block.locator("[data-origin-row='true']").last.locator(".origin-record-field-view"))
          .toHaveCount(1)
      }
      let deep = try await block.evaluate(
        """
        (block) => {
          const outliner = block.querySelector('.origin-field-steps');
          const widths = [...block.querySelectorAll('.outliner-node')].map((n) => n.getBoundingClientRect().width);
          return {
            narrowest: Math.round(Math.min(...widths)), widest: Math.round(Math.max(...widths)),
            scrolls: getComputedStyle(outliner).overflowX !== 'visible',
            page: document.documentElement.scrollWidth > window.innerWidth,
            reach: Math.max(...[...block.querySelectorAll('.outliner-node')].map((n) => n.getBoundingClientRect().right + scrollX)) > window.innerWidth,
          };
        }
        """)
      #expect(deep["narrowest"] == deep["widest"], "a deep step as wide as the first: \(deep)")
      #expect(deep["scrolls"].bool == false, "the tree has no scrollport of its own")
      #expect(deep["page"].bool == false && deep["reach"].bool == false, "the page no wider than the screen: \(deep)")
      // A menu opened in the deepest step stands by its field, on screen.
      let deepest = block.locator("[data-origin-row='true']").last
      _ = try await deepest.evaluate("(row) => row.scrollIntoView({ block: 'center' })")
      let deepRelation = deepest.locator(".dropdown-view").first
      try await deepRelation.locator(".dropdown-trigger").click()
      let placed = try await deepRelation.evaluate(
        """
        (view) => {
          const menu = view.querySelector('.dropdown-menu');
          const field = view.querySelector('.dropdown-container').getBoundingClientRect();
          const box = menu.getBoundingClientRect();
          return {
            fixed: getComputedStyle(menu).position === 'fixed',
            start: Math.abs(Math.round(box.left - field.left)) <= 1,
            under: Math.abs(Math.round(box.top - field.bottom)) <= 6,
            inside: box.right <= window.innerWidth + 1,
          };
        }
        """)
      #expect(placed["start"].bool == true && placed["under"].bool == true, "\(placed)")
      #expect(placed["inside"].bool == true, "the deep step's menu stays on the screen: \(placed)")
      try await deepRelation.locator(".dropdown-trigger").click()

      // The translation's page: an Origin section after the Metadata, the
      // tree of its steps—the typed step, and under it, indented, the
      // original's record, linked.
      try await page.openHydrated(translation.path)
      let tree = page.locator("#origin .origin-view")
      try await expect(tree).toHaveCount(1)
      try await expect(page.locator("#origin .record-section-title")).toHaveText("Origin")
      try await expect(page.locator("#record-origin")).toHaveCount(0)
      let order = try await page.evaluate(
        """
        (() => {
          const metadata = document.querySelector('#record-metadata');
          const origin = document.querySelector('#origin');
          return !!(metadata && origin && (metadata.compareDocumentPosition(origin) & Node.DOCUMENT_POSITION_FOLLOWING));
        })()
        """
      ).bool
      #expect(order == true, "Origin is not after Metadata")
      // Each step's fields as the form's step has them, read (user,
      // 2026-11-05): its labels in the form's order, on the record's own
      // page only the fields it has.
      let steps = tree.locator(".origin-step-fields-view")
      try await expect(steps).toHaveCount(2)
      let typedStep = steps.first
      try await expect(typedStep.locator(".dropdown-label-text, .text-input-label")).toHaveTexts([
        "Relation", "Certainty", "Language", "Title", "Class", "Year qualifier", "Era", "Year",
      ])
      try await expect(typedStep.locator("#origin-tree-step-1-relation")).toHaveValue("translation_of,abridgment_of")
      try await expect(typedStep.locator("#origin-tree-step-1-language")).toHaveValue("ang")
      try await expect(typedStep.locator("#origin-tree-step-1-name")).toHaveValue(typed)
      try await expect(typedStep.locator("#origin-tree-step-1-type")).toHaveValue("treatise")
      try await expect(typedStep.locator("#origin-tree-step-1-year-qualifier")).toHaveValue("circa")
      try await expect(typedStep.locator("#origin-tree-step-1-year")).toHaveValue("890")
      // Its evidence is its Outgoing citations now (user, 2026-11-03), none
      // drawn on a record's page for a step with none.
      try await expect(typedStep.locator(".outgoing-citations-view")).toHaveCount(0)
      try await expect(typedStep.locator("a")).toHaveCount(0)
      // The original, a step under the typed one: its record field naming
      // it, never a link (metadata never links to a record, user
      // 2026-10-03), its own fields filled from it as the form fills them.
      let recordStep = tree.locator(
        ".outliner-view > .outliner-list > .outliner-item > .outliner-list > .outliner-item .origin-step-fields-view")
      try await expect(recordStep).toHaveCount(1)
      try await expect(
        recordStep.locator(".origin-record-field-view .dropdown-selected-text .breadcrumb-label-text")
      ).toHaveText(original.title)
      try await expect(recordStep.locator("a[href='\(original.path)']")).toHaveCount(0)
      try await expect(recordStep.locator("#origin-tree-step-1-1-relation")).toHaveValue("translation_of")
      try await expect(recordStep.locator("#origin-tree-step-1-1-type")).toHaveValue("report")
      try await expect(recordStep.locator("#origin-tree-step-1-1-year")).toHaveValue("1958")
      try await expect(recordStep.locator("#origin-tree-step-1-1-voice-item1-text-input")).toHaveValue(original.author)
      // Above the tree, the tree in one sentence: each step's relations,
      // its voice's, its language (at the prose's weight, never semibold:
      // user, 2026-11-03), its title (linked where it is
      // a record, never italic) and its class, never a date (an etymology
      // has none, user 2026-11-01); a step's own origin after ", ".
      let sentence = page.locator("#origin .origin-sentence-view")
      try await expect(sentence).toHaveText(
        "A translation and abridgment of the Old English \(typed) (treatise), a translation of "
          + "\(original.author)'s English \(original.title) (report).")
      try await expect(sentence.locator(".origin-sentence-language")).toHaveTexts(["Old English", "English"])
      // A term never navigates (user, 2026-11-01): a control that previews.
      try await expect(sentence.locator("a")).toHaveCount(0)
      try await expect(sentence.locator("button[data-gloss-preview] .origin-sentence-term")).toHaveText(original.title)
      let look = try await page.evaluate(
        """
        (() => {
          const s = document.querySelector('#origin .origin-sentence-view');
          const tree = document.querySelector('#origin .origin-view');
          const language = s.querySelector('.origin-sentence-language');
          const term = s.querySelector('.origin-sentence-term');
          return {
            above: !!(s.compareDocumentPosition(tree) & Node.DOCUMENT_POSITION_FOLLOWING),
            weight: getComputedStyle(language).fontWeight,
            style: getComputedStyle(term).fontStyle,
            lang: term.getAttribute('lang'),
          };
        })()
        """)
      #expect(look["above"].bool == true, "\(look)")
      #expect(look["weight"].string == "400", "\(look)")
      #expect(look["style"].string == "normal", "\(look)")
      #expect(look["lang"].string == "ang", "\(look)")

      // A record's term previews it in the gloss sheet (user, 2026-11-01):
      // its heading—language, title and class—the link to the record. On a
      // wide screen a click opens it as a popover beside the term, at least
      // 320 wide and at most 320 tall, the page staying where it is, open
      // until a click outside; a hover opens nothing (user, 2026-11-01). On
      // a narrow one a tap opens the sheet over the screen. Esc closes
      // either.
      let term = sentence.locator("button[data-gloss-preview]")
      try await expect(term).toHaveCount(1)
      try await expect(term).toHaveAttribute("aria-haspopup", "dialog")
      try await expect(term).toHaveCSS("cursor", "help")
      let sheet = page.locator(".gloss-sheet")
      let wide = try await page.evaluate("innerWidth >= 769").bool == true
      if wide {
        // A hover alone opens nothing.
        try await term.hover()
        try await expect(sheet).toHaveAttribute("data-state", "closed")
      }
      try await term.click()
      try await expect(sheet).toHaveAttribute("data-state", "open")
      try await expect(sheet).toHaveAttribute("data-placement", wide ? "popover" : "viewport")
      try await expect(term).toHaveAttribute("aria-expanded", "true")
      try await expect(sheet.locator(".gloss-sheet-title")).toContainText(original.title)
      try await expect(sheet.locator(".gloss-sheet-title")).toContainText("Report")
      try await expect(sheet.locator(".gloss-sheet-title a.record-preview-heading")).toHaveAttribute("href", original.path)
      try await expect(sheet.locator(".record-preview-link")).toHaveCount(0)
      let popover = try await sheet.evaluate(
        """
        (sheet) => {
          const panel = sheet.querySelector('.sheet-panel').getBoundingClientRect();
          const term = document.querySelector('#origin .origin-sentence-view button[data-gloss-preview]').getBoundingClientRect();
          return {
            width: panel.width, height: panel.height,
            beside: panel.top >= term.bottom || panel.bottom <= term.top,
            inside: panel.left >= 0 && panel.right <= innerWidth,
            path: location.pathname,
          };
        }
        """)
      #expect(popover["path"].string == translation.path, "a preview never navigates: \(popover)")
      if wide {
        #expect((popover["width"].double ?? 0) >= 320 && (popover["height"].double ?? 0) <= 320, "\(popover)")
        #expect(popover["beside"].bool == true && popover["inside"].bool == true, "\(popover)")
        // Its cursors: the question mark over its ground, the hand over its
        // link, its words too.
        let cursors = try await sheet.evaluate(
          """
          (sheet) => [getComputedStyle(sheet.querySelector('.sheet-panel')).cursor,
            getComputedStyle(sheet.querySelector('a.record-preview-heading')).cursor,
            getComputedStyle(sheet.querySelector('a.record-preview-heading .record-label-meta')).cursor].join('|')
          """)
        #expect(cursors.string == "help|pointer|pointer", "\(cursors)")
        // The pointer leaving keeps it open, the page where it was; a click
        // outside closes it, and a click opens it again.
        let outside = sentence.locator(".origin-sentence-language").first
        try await outside.hover()
        try await expect(sheet).toHaveAttribute("data-state", "open")
        #expect(try await page.evaluate("location.pathname").string == translation.path)
        try await outside.click()
        try await expect(sheet).toHaveAttribute("data-state", "closed")
        try await term.click()
        try await expect(sheet).toHaveAttribute("data-state", "open")
      }
      try await page.keyboard.press("Escape")
      try await expect(sheet).toHaveAttribute("data-state", "closed")
      try await expect(term).toHaveAttribute("aria-expanded", "false")

      // The original lists it under "Translated into", as "Contains"
      // answers "Contained in".
      try await page.openHydrated(original.path)
      try await expect(page.locator(".record-sidebar-view a[href='\(translation.path)']").first).toBeAttached()
      try await expect(page.locator(".record-sidebar-view").first).toContainText("Translated into")

      // A word's origin may name nothing: an Imitation or a Coinage hides
      // the row's record field and typed fields; another relation brings
      // them back.
      try await page.openHydrated("/mission-control/submit/lexicographic/sentiment")
      let wordRow = page.locator(".origin-field-view [data-origin-row='true']").first
      try await expect(wordRow.locator(".origin-record-field-view")).toHaveCount(1)
      let wordRelation = wordRow.locator(".dropdown-view").first
      // A word may be a calque (a loan translation), with a borrowing too.
      try await expect(wordRelation.locator(".dropdown-option[data-value='calque_of']")).toHaveAttribute(
        "data-display", "Calque")
      try await wordRelation.locator(".dropdown-trigger").click()
      try await wordRelation.locator(".dropdown-option[data-value='coinage']").click()
      // Its typed fields two groups (user, 2026-11-02): its Value under the
      // record field, then its Language, Title and Class.
      let wordTyped = wordRow.locator(".origin-field-typed")
      try await expect(wordTyped).toHaveCount(2)
      try await expect(wordRow.locator(".origin-field-record")).toBeHidden()
      for index in 0..<2 { try await expect(wordTyped.nth(index)).toBeHidden() }
      // Unchosen, and another chosen: the fields come back.
      try await wordRelation.locator(".dropdown-option[data-value='coinage']").click()
      try await wordRelation.locator(".dropdown-option[data-value='eponym_of']").click()
      // Closed by Esc: its search field stands over its trigger while open.
      try await page.keyboard.press("Escape")
      try await expect(wordRow.locator(".origin-field-record")).toBeVisible()
      for index in 0..<2 { try await expect(wordTyped.nth(index)).toBeVisible() }
      // A word's typed step: its word class from the closed list, and its
      // date as every date of ours.
      let wordKey = try await wordRow.getAttribute("data-origin-key") ?? ""
      let wordType = wordRow.locator(".dropdown-view:has(#\(wordKey)-type)")
      try await expect(wordType.locator(".dropdown-option[data-value='verb']")).toHaveCount(1)
      try await expect(wordType.locator(".dropdown-option[data-value='other']")).toHaveCount(0)
      try await expect(wordRow.locator(".origin-field-typed > .form-date-view")).toHaveCount(1)
    }
  }
}
