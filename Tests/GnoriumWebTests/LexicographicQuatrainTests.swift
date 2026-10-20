import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A lexicographic quatrain's page: its measurements exactly as its closing
/// session's tools gave them—the funnel, each count opening its quotes, the
/// dated quotes year by year, and the declared flags by kind. A scratch
/// quatrain built by SQL (dev has no model) over one sentiment of a
/// throwaway admin's overture, removed after.
@Suite("Lexicographic quatrain")
struct LexicographicQuatrainTests {
  /// The scratch rows: a committed overture holding one sentiment, and a
  /// submitted quatrain over it with its frozen selection, four scores (one
  /// gated), a passed closing session and its declaration.
  struct Scratch {
    let quatrainID: String
    let overtureID: String
    let sentimentID: String
    let title: String
    private let fountainID: String
    private let owner: String

    var path: String { "/mission-control/quatrains/lexicographic/\(quatrainID)" }

    init(owner: TestAdmin) throws {
      self.owner = owner.username
      let user = try owner.column("id")
      func id() -> String { UUID().uuidString.lowercased() }
      let submission = id()
      fountainID = id()
      overtureID = id()
      quatrainID = id()
      sentimentID = id()
      let nocturne = id()
      let version = id()
      title = "webtestsquatrain\(quatrainID.prefix(8))"
      let form = #"{"title":"\#(title)","languageCode":"eng","class":"noun","spellings":[],"inflections":[],"origin":{"etymons":[],"citations":[],"derivation":""}}"#
      let counts = [
        ("gated", 0, 1), ("duplicate", 0, 0), ("knowledge_rich", 0, 0), ("earliest", 1, 0), ("latest", 1, 0),
        ("informative", 0, 1),
      ].map { "\"\($0.0)\":{\"selected\":\($0.1),\"dropped\":\($0.2)}" }.joined(separator: ",")
      let selection = """
        {"generation":17,"budget":6000,"tokenizer":"web-tests","measures":{"philology_tools":"0.4.0",\
        "change_point_test":{"alpha":"1/20","permutations":999}},"information":{"polysemy_entropy":0,"divergences":[]},\
        "pool":{"quotes":4,"assigned":4,"unassigned":0,"not_indexed":0,"superseded":0,"within_phrase":0,\
        "key_mismatch":1,"furniture":0,"title_uncertain":0,"duplicates":0,"works":1,"dated":3,"span":[1600,1650],\
        "untagged":0},"sentiments":[{"sentiment_id":"\(sentimentID)","candidates":4,"within_phrase":0,\
        "counts":{\(counts)},"budget":6000,"tokens":40,"dispersion":"0","works":1,"dated":3,"earliest":1600,\
        "latest":1650,"collocates":[{"lemma":"river","f_sc":2,"f_s":3,"f_c":9,"logdice":12.5,"front":true}],\
        "entropy":1.5,"vocabulary":4,"coverage":0.75,"step_coverage":{"knowledge_rich":null,"earliest":0.5,\
        "latest":0.6,"informative":0.75},"change_points":[]}]}
        """
      // One score: its row as the quote selection gives it, none anchored.
      func score(_ quote: String, step: String, selected: Bool, rank: Int?, year: Int, testament: String) -> String {
        let row = #"{"quote_id":"\#(quote)","sentence":"Upon the ⟦\#(title)⟧ of the river.","context_lemmas":["river"],"anchor":null}"#
        return """
          ('\(quatrainID)', '\(sentimentID)', '\(quote)', '\(version)', 'img1', 'w\(quote)', '\(step)', \(selected),
            \(rank.map(String.init) ?? "NULL"), \(step == "gated" ? "'key_mismatch'" : "NULL"), \(year),
            \(step == "gated" ? "NULL" : "2.5"), '\(title)', '\(title)', 'noun', '\(testament)', '\(year)', NULL, '\(row)')
          """
      }
      let scores = [
        score("q1", step: "earliest", selected: true, rank: 1, year: 1600, testament: "The First Folio"),
        score("q2", step: "informative", selected: false, rank: nil, year: 1600, testament: "A Second Book"),
        score("q3", step: "latest", selected: true, rank: 2, year: 1650, testament: "A Late Book"),
        score("q4", step: "gated", selected: false, rank: nil, year: 1500, testament: "A Gated Book"),
      ].joined(separator: ",\n")
      let judgment = #"{"notes":"Inspected the dates.","flags":[{"kind":"splitting","note":"Two groups by date.","sentiments":["\#(sentimentID)"]},{"kind":"dating","note":"One date stands apart.","quotes":["q3"]}]}"#
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO submissions (id, user_id) VALUES ('\(submission)', '\(user)');
        INSERT INTO lexicographic_fountains (id, batch_id, language, order_in_batch, processing_status,
          title_form_json, anchors_json, created_at)
          VALUES ('\(fountainID)', '\(submission)', 'eng', 0, 'pending', '\(form)', '[]', now());
        INSERT INTO lexicographic_overtures (id, lexicographic_fountain_id, title_form_json, anchors_json,
          committed_by_user_id, committed_at, created_at)
          VALUES ('\(overtureID)', '\(fountainID)', '\(form)', '[]', '\(user)', now(), now());
        INSERT INTO sentiment_inventories (language_code, lemma, class, version) VALUES ('eng', '\(title)', 'noun', 1);
        INSERT INTO sentiments (uuid, lexicographic_overture_id, language_code, lemma, class, inventory_version,
          definition_text, definition_key, provisional)
          VALUES ('\(sentimentID)', '\(overtureID)', 'eng', '\(title)', 'noun', 1,
            'The land alongside a web test.', 'the land alongside a web test', true);
        INSERT INTO lexicographic_quatrains (id, lexicographic_overture_id, requested_by_user_id, sentiment_uuids_json,
          index_generation, budget_json, quote_selection_json, processing_status, created_at, updated_at, completed_at)
          VALUES ('\(quatrainID)', '\(overtureID)', '\(user)', '["\(sentimentID)"]', 17, '{"budget":6000}',
            '\(selection)', 'submitted', now(), now(), now());
        INSERT INTO lexicographic_calibration_scores (lexicographic_quatrain_id, sentiment_uuid, quote_id, version_id,
          image_id, word_id, step, selected, rank, gate, dated_year, surprise, surface, lemma, class, testament, date,
          cert, row_json)
          VALUES \(scores);
        INSERT INTO lexicographic_calibration_nocturnes (id, lexicographic_quatrain_id, process, instance, provider, model,
          duration_ms, rounds, result, created_at, finished_at)
          VALUES ('\(nocturne)', '\(quatrainID)', 'calibration', 1, 'DeepSeek', 'deepseek-flash', 1200, 2, 'passed',
            now(), now());
        INSERT INTO lexicographic_calibration_declarations (lexicographic_calibration_nocturne_id, judgment_json,
          tool_hashes_json, header_tei, selection_sha256)
          VALUES ('\(nocturne)', '\(judgment)', '{}', '<teiHeader/>', '\(String(repeating: "d", count: 64))');
        COMMIT;
        """)
    }

    func remove() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM model_calls WHERE lexicographic_calibration_nocturne_id IN
          (SELECT id FROM lexicographic_calibration_nocturnes WHERE lexicographic_quatrain_id = '\(quatrainID)');
        DELETE FROM lexicographic_quatrains WHERE id = '\(quatrainID)';
        DELETE FROM sentiments WHERE uuid = '\(sentimentID)';
        DELETE FROM sentiment_inventories WHERE language_code = 'eng' AND lemma = '\(title)' AND class = 'noun';
        DELETE FROM locutions WHERE locutable_type = 'lexicographic_overture' AND locutable_id = '\(overtureID)';
        DELETE FROM lexicographic_overtures WHERE id = '\(overtureID)';
        UPDATE lexicographic_fountains SET deleted_at = now(), deleted_by = '\(owner)'
          WHERE id = '\(fountainID)' AND deleted_at IS NULL;
        COMMIT;
        """)
    }
  }

  @Test(arguments: gnorium.engines)
  func theQuatrainPageShowsItsMeasurementsAsTheToolsGaveThem(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch = try Scratch(owner: admin)
    do {
      try await withPage(engine, gnorium, cookies: [admin.cookie]) { page in
        try await page.openHydrated(scratch.path)
        try await expect(page.locator("h1").first).toHaveText("Lexicographic Quatrain")
        try await expect(page.locator(".computorium-core-header-status-chip").first).toContainText("Submitted")

        // The record's figures, as frozen.
        let pool = page.locator(".calibration-measurements-pool-table tbody tr")
        try await expect(pool.filter(hasText: "Key mismatch").first).toContainText("1")
        try await expect(pool.filter(hasText: "Span").first).toContainText("1600–1650")

        // The sentiment, by its definition; its funnel's counts as measured.
        let sentiment = page.locator("#calibration-sentiment-\(scratch.sentimentID)")
        try await expect(sentiment.locator("summary").first).toContainText("The land alongside a web test.")
        try await sentiment.locator("summary").first.click()
        let funnel = sentiment.locator(".calibration-measurements-funnel-table tbody tr")
        try await expect(funnel).toHaveCount(6)
        let earliest = funnel.filter(hasText: "Earliest").first
        try await expect(earliest).toContainText("1")
        try await expect(funnel.filter(hasText: "Gated").first).toContainText("1")

        // A count opens its quotes: the accordion it names, its testament.
        let list = page.locator("#calibration-\(scratch.sentimentID)-earliest-selected")
        try await expect(list.locator(".calibration-measurements-quote").first).toBeHidden()
        try await earliest.locator("a[href='#calibration-\(scratch.sentimentID)-earliest-selected']").click()
        try await expect(list.locator(".calibration-measurements-quote")).toHaveCount(1)
        try await expect(list.locator(".calibration-measurements-quote").first).toBeVisible()
        try await expect(list.locator(".calibration-measurements-quote").first).toContainText("The First Folio")
        try await expect(list.locator(".calibration-measurements-quote").first).toContainText("1600")

        // Why each selected quote: its surprise and context words.
        let selected = sentiment.locator(".calibration-measurements-selected-table tbody tr")
        try await expect(selected).toHaveCount(2)
        try await expect(selected.first).toContainText("2.5")
        try await expect(selected.first).toContainText("river")

        // Year by year: each exact year of the open quotes, in all and
        // selected; the gated quote's year is not among them.
        let years = sentiment.locator(".calibration-measurements-timeline-table tbody tr")
        try await expect(years).toHaveCount(2)
        try await expect(years.nth(0)).toContainText("1600")
        try await expect(years.nth(0).locator("td").nth(1)).toHaveText("2")
        try await expect(years.nth(0).locator("td").nth(2)).toHaveText("1")
        try await expect(years.nth(1)).toContainText("1650")
        try await expect(sentiment.locator(".calibration-measurements-timeline-table")).not.toContainText("1500")

        // The flags, by kind; a kind with none is unknown.
        let flags = page.locator("#calibration-flags")
        try await expect(flags.locator("[data-kind='splitting'] .calibration-measurements-flag"))
          .toContainText("Two groups by date.")
        try await expect(flags.locator("[data-kind='dating'] .calibration-measurements-flag"))
          .toContainText("One date stands apart.")
        try await expect(flags.locator("[data-kind='dating'] .calibration-measurements-flag")).toContainText("q3")
        try await expect(flags.locator("section[data-kind='lumping']")).toContainText("—")
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      scratch.remove()
      try await admin.remove(after: error)
    }
    scratch.remove()
    try await admin.remove()
  }
}
