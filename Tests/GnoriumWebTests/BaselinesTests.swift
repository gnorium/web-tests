import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Baselines are public (user, 2026-09-29): Mission Control › Baselines
/// lists a kind's baselines, a kind to a tab, by language and script with a
/// chart of CER against cost per page and a table of baselines, then every
/// dollar the kind spent on models; the gold the item response fit finds; a baseline's page shows its scores, what ran and each item's diff against the gold; a
/// dataset's page says how its gold was made. Signed out, on phone and
/// desktop, with nothing scrolling sideways.
@Suite("Baselines", .serialized)
struct BaselinesTests {
  struct Width: Decodable { let overflow: Double }
  static let overflow = "({ overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth })"

  static func sql(_ text: String) -> String { text.replacingOccurrences(of: "'", with: "''") }

  static func insert(datasetID: String, runID: String, name: String) throws {
    let item = """
      {"id": "p1", "label": "Page one", "language": "en", "script": "Latn", "direction": "ltr", "canvas": 1,
       "image": null, "thumbnail": null, "gold_provenance": {"kind": "machine-assisted",
       "statement": "Checked word by word by an AI agent; pending human review.", "verified_by": null, "date": null},
       "gold": "a minnte of ſome\\nlonger line", "has_gold_markup": false, "notes": []}
      """
    let document = """
      {"name": "\(name)", "version": "1", "title": "Web test set \(name)", "task": "bibliographic-explication", "description": "",
       "provenance": "Machine-assisted: pending human review.", "license": {"id": "CC-BY-SA-4.0", "url": null, "holder": null},
       "source": {"manifest": null, "url": null, "holder": null, "call_number": null, "rights": null, "set": null},
       "normalization": {"map": {}, "remove": [], "no_space_before": []}, "reading_fold": {}, "known_readings": 1,
       "gold_redistributed": true, "items": [\(item)]}
      """
    let interval = #"{"value": 0.08, "low": 0.04, "high": 0.12, "lines": 2}"#
    let metrics = """
      {"items": 1, "cer": \(interval), "cer_letters": \(interval), "wer": \(interval), "fidelity": {"long_s":
       {"label": "Long s (ſ)", "gold": 1, "kept": 0, "spurious": 0, "rate": 0}},
       "memorization": {"listed": 1, "printed": 0, "known": 1, "other": 0, "missing": 0, "rate": 1},
       "markup": {"counts": {"w": 5, "s": 1, "lb": 2}, "precision_recall": null}}
      """
    let result = """
      {"item": "p1", "label": "Page one", "language": "en", "script": "Latn", "direction": "ltr",
       "gold_provenance": "machine-assisted", "gold_graphemes": 28, "gold_words": 6, "run_graphemes": 28, "run_words": 6,
       "char_errors": 2, "cer": 0.07, "word_errors": 2, "wer": 0.33, "letter_errors": 2, "cer_letters": 0.08,
       "fidelity": {}, "memorization": {"listed": 1, "printed": 0, "known": 1, "other": 0, "missing": 0, "rate": 1,
         "places": [{"printed": "minnte", "occurrence": 1, "known": ["minute"], "edition": "modern editions",
         "written": "minute", "outcome": "known"}]}, "markup": null, "lines": [[2, 16, 2, 4, 2, 13], [0, 12, 0, 2, 0, 11]],
       "gold_text": "a minnte of ſome\\nlonger line", "transcript": "a minute of some\\nlonger line", "diff": []}
      """
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO baseline_datasets (id, name, version, title, task, provenance, license, item_count, dataset_json)
        VALUES ('\(datasetID)', '\(name)', '1', 'Web test set \(name)', 'bibliographic-explication',
          'Machine-assisted: pending human review.', 'CC-BY-SA-4.0', 1, '\(sql(document))');
      INSERT INTO baselines (id, baseline_dataset_id, process, provider, model, prompt_version, label, code_json,
          settings_json, metrics_json, items_json, notes, total_cost_usd, input_tokens, output_tokens, reasoning_tokens,
          cached_tokens, started_at, finished_at)
        VALUES ('\(runID)', '\(datasetID)', 'bibliographic_explication', 'deepseek', 'deepseek-flash', 'webtest', 'Web test run',
          '{"gnorium-server": "webtest"}', '{}',
          '\(sql(#"{"overall": \#(metrics), "groups": [{"language": "en", "script": "Latn", "direction": "ltr", "metrics": \#(metrics)}]}"#))',
          '\(sql("[\(result)]"))', '', 0.05, 1000, 100, 50, 800, now() - interval '10 minutes', now());
      INSERT INTO model_calls (id, process, purpose, provider, model, input_tokens, output_tokens, latency_ms, started_at,
          finished_at, cost_usd, baseline_id)
        VALUES (gen_random_uuid(), 'bibliographic_explication', 'explication', 'deepseek', 'deepseek-flash', 1000, 100, 1000,
          now() - interval '10 minutes', now() - interval '9 minutes', 0.05, '\(runID)');
      COMMIT;
      """)
  }

  static func remove(datasetID: String, runID: String) {
    _ = try? TestAdmin.query(
      """
      DELETE FROM model_calls WHERE baseline_id = '\(runID)';
      DELETE FROM baselines WHERE id = '\(runID)';
      DELETE FROM baseline_datasets WHERE id = '\(datasetID)';
      """)
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func baselinesArePublicWithTheirScoresCostAndDiffs(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let datasetID = UUID().uuidString.lowercased()
    let runID = UUID().uuidString.lowercased()
    let name = "web-tests-\(UUID().uuidString.prefix(8).lowercased())"
    try Self.insert(datasetID: datasetID, runID: runID, name: name)
    defer { Self.remove(datasetID: datasetID, runID: runID) }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/mission-control/baselines")
      try await expect(page.locator("a[href='/mission-control/baselines']").first).toBeAttached()
      try await expect(page.locator(".mission-control-core-tabs a[href='/mission-control/baselines/lexicographic']"))
        .toBeAttached()
      let group = page.locator("#en-Latn")
      try await expect(group.locator("h2")).toHaveText("English · Latin")
      let dataset = group.locator(".baselines-dataset").filter(hasText: "Web test set \(name)")
      try await expect(dataset.locator(".baseline-cost-chart-view circle")).toHaveCount(1)
      try await expect(dataset.locator("a[href='/mission-control/baselines/\(runID)']")).toHaveText("Web test run")
      try await expect(dataset.getByText("8.00% (4.00–12.00)")).toBeAttached()
      // Spending: baselines' part of it, beside production's.
      try await expect(page.locator("#spending").getByText("Baselines (", exact: false)).toBeAttached()
      try await expect(page.locator("#spending .baseline-spending-table").first).toBeAttached()
      // Gold, as the item response fit finds it (user, 2026-10-17):
      // how many permitted pages are gold, the configurations, the gold
      // pages, arbitration's revisers and the runs; Run baseline is an
      // admin's, there is no Fit now, and no page takes a vote.
      let gold = page.locator("#gold")
      try await expect(gold.locator(".baseline-gold-summary")).toBeAttached()
      try await expect(gold.locator(".baseline-gold-heading"))
        .toHaveTexts(["Configurations", "Gold pages", "Revisers", "Baseline runs"])
      try await expect(gold.getByText("Fit now", exact: true)).toHaveCount(0)
      try await expect(gold.locator(".baseline-gold-run-form")).toHaveCount(0)
      try await expect(page.locator(".baseline-hard-vote-view")).toHaveCount(0)
      try await expect(page.locator("[data-table-column-id='hard']")).toHaveCount(0)
      #expect(try await page.evaluate(Self.overflow, as: Width.self).overflow <= 0)

      try await page.openHydrated("/mission-control/baselines/\(runID)")
      try await expect(page.locator("h1")).toHaveText("Web test run")
      try await expect(page.getByText("CER (95% CI)").first).toBeAttached()
      try await expect(page.locator("#item-p1 .diff-view")).toBeAttached()
      try await expect(page.locator("#item-p1").getByText("the reading of modern editions", exact: false)).toBeAttached()
      try await expect(page.locator("#what-ran").getByText("deepseek-flash").first).toBeAttached()
      // A process without its kind: the page is the kind's.
      try await expect(page.locator("#what-ran").getByText("Explication", exact: true).first).toBeAttached()
      #expect(try await page.evaluate(Self.overflow, as: Width.self).overflow <= 0)

      try await page.openHydrated("/mission-control/baselines/datasets/\(datasetID)")
      try await expect(page.getByText("Machine-assisted: pending human review.").first).toBeAttached()
      try await expect(page.locator("#items").getByText("Page one")).toBeAttached()
      #expect(try await page.evaluate(Self.overflow, as: Width.self).overflow <= 0)

      // The baselines tables filter by the Mission Control rule (user,
      // 2026-10-09): every filterable column in column order—Baseline,
      // Model (a combobox), Prompt, the scores and costs (ranges)—then
      // Created by (the machine's), Created on and Created at.
      let runs = page.locator("#baselines")
      let options = runs.locator(".filter-bar-view .filter-bar-row").first
        .locator(".filter-bar-field-picker .dropdown-option")
      try await expect(options).toHaveTexts([
        "Baseline", "Model", "Prompt", "CER (95% CI)", "WER", "Memorization", "Cost per page", "Total cost",
        "Created by", "Created on", "Created at",
      ])
      try await expect(runs.locator("[data-table-column-id='createdBy']").first).toBeAttached()
      try await runs.locator(".filter-bar-add-btn").first.click()
      let row = runs.locator(".filter-bar-row").last
      try await row.locator(".filter-bar-field-picker .dropdown-trigger").click()
      try await row.locator(".filter-bar-field-picker .dropdown-option[data-value='model']").click()
      try await row.locator("input[data-combobox-input='true']").type("FLASH")
      let suggestion = row.locator(".combobox-option[data-value='deepseek-flash']")
      try await expect(suggestion).toBeVisible()
      try await suggestion.click()
      try await runs.locator(".filter-bar-apply").click()
      try await expect(page).toHaveURL("model=deepseek-flash") { url in
        url.query?.contains("model=deepseek-flash") == true
      }
      try await expect(page.locator("#baselines a[href='/mission-control/baselines/\(runID)']")).toBeAttached()
      // A model no baseline has: none matches.
      try await page.openHydrated("/mission-control/baselines/datasets/\(datasetID)?model=none")
      try await expect(page.locator("#baselines").getByText("No baseline matches these filters.")).toBeAttached()
      #expect(try await page.evaluate(Self.overflow, as: Width.self).overflow <= 0)
    }
  }
}
