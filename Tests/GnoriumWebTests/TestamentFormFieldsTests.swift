import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The testament form's fields (user, 2026-09-27): no notes field, no
/// image count; the publication statement stays, and an edition's format and
/// extent, a copy's dimension and former owners, an impression's manufacture
/// and an issue's distribution are back on their levels (user, 2026-11-01).
/// Nothing is submitted. Needs a signed-in account, made for the test and
/// removed after.
@Suite("Testament form fields")
struct TestamentFormFieldsTests {
  static let form = "/mission-control/submit/bibliographic/testament"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func theRemovedFieldsAreGone(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(Self.form)
        let form = page.locator(".submit-testament-form")
        try await expect(form.locator("input[name='title']")).toHaveCount(1)
        for gone in ["[name='notes']", ".former-owners-view", "#testament-image-count"] {
          try await expect(form.locator(gone)).toHaveCount(0)
        }
        // Back on their levels (user, 2026-11-01): the edition's format and
        // extent, the copy's dimension and former owners, the impression's
        // manufacture and the issue's distribution.
        for back in [
          "[name='format']", "[name='dimension_size']", "[name='dimension_unit']", "[name='extent']",
          "[name='extent_unit']", "[data-item-list='former-owner']", "[data-as-namespace='manufacture']",
          "[data-as-namespace='distribution']",
        ] {
          try await expect(form.locator(back)).toHaveCount(1)
        }
        try await expect(form.locator("[data-as-namespace='publication']")).toHaveCount(1)
        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }

  /// A row's value keeps its own label, placeholder and tooltip whatever
  /// is chosen above it (user, 2026-11-01): "Name" on an agent row under
  /// any role, "Identifier" on a reference row under any scheme—never
  /// "Printer name" or "STC name".
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aRowsValueLabelIsFixed(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(Self.form)
        // Every row as the page holds it after a role or scheme is chosen
        // on it, and the tooltip each row's value is served with (the bubble
        // is portaled to <body> once hydrated, so it is read from the HTML).
        let json = try await page.evaluate(
          """
          (async () => {
            const served = new DOMParser().parseFromString(
              await (await fetch(location.href)).text(), 'text/html');
            const form = document.querySelector('.submit-testament-form');
            const out = {};
            for (const list of ['as-publication', 'citation-number']) {
              const tooltips = [...served.querySelectorAll(`[data-item-list='${list}'] [data-item-section="true"]`)]
                .map((row) => row.querySelector('[id$="-text-input"]').closest('div:has(> .text-input-label-row)')
                  .querySelector('.tooltip-content').textContent.trim());
              const group = form.querySelector(`[data-item-list='${list}']`);
              group.querySelector('[data-item-add-btn="true"] button').click();
              const rows = [...group.querySelectorAll('[data-item-section="true"]')]
                .filter((r) => !r.closest('[data-item-template]'));
              out[list] = {
                tooltips,
                rows: rows.map((row) => {
                  const choice = row.querySelector('[id$="-dropdown"]');
                  const option = row.querySelector('.dropdown-option[data-value]');
                  choice.value = option ? option.getAttribute('data-value') : 'stc';
                  choice.dispatchEvent(new Event('change'));
                  const input = row.querySelector('[id$="-text-input"]');
                  const labelRow = input.closest('div:has(> .text-input-label-row)').querySelector('.text-input-label-row');
                  return {
                    chosen: choice.value,
                    label: labelRow.querySelector('.text-input-label').textContent.trim(),
                    placeholder: input.getAttribute('placeholder'),
                    retold: labelRow.querySelector('.tooltip-trigger').getAttribute('data-tooltip-text')
                  };
                })
              };
            }
            return JSON.stringify(out);
          })()
          """
        ).string ?? "{}"
        struct Row: Decodable { let chosen: String; let label: String; let placeholder: String?; let retold: String? }
        struct List: Decodable { let tooltips: [String]; let rows: [Row] }
        let lists = try JSONDecoder().decode([String: List].self, from: Data(json.utf8))
        let agents = try #require(lists["as-publication"])
        let references = try #require(lists["citation-number"])
        #expect(!agents.rows.isEmpty && !references.rows.isEmpty && !agents.tooltips.isEmpty
          && !references.tooltips.isEmpty, "no rows: \(json)")
        for row in agents.rows {
          #expect(row.label == "Name", "agent label under \(row.chosen): \(row.label)")
          #expect(row.placeholder == "Name")
          #expect(row.retold == nil, "agent tooltip retold under \(row.chosen): \(row.retold ?? "")")
        }
        for tooltip in agents.tooltips {
          #expect(tooltip == "Name of a person or body who took part in the publication.")
        }
        for row in references.rows {
          #expect(row.label == "Identifier", "reference label under \(row.chosen): \(row.label)")
          #expect(row.placeholder == "Identifier")
          #expect(row.retold == nil, "reference tooltip retold under \(row.chosen): \(row.retold ?? "")")
        }
        for tooltip in references.tooltips {
          #expect(tooltip == "The identifier within the classification scheme.")
        }
        try await page.expectNoErrors()
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }
}
