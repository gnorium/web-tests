import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Every label sits 8px from its control (user, 2026-09-30), by its
/// parent's flex gap, never a margin: a field's label (FieldView), a
/// dropdown's, a combobox's, a text input's and a text area's own label
/// rows, and a fieldset field's legend (FieldView isFieldset). A fieldset's
/// rendered legend sits outside its flex layout, so the gap never reached
/// it; the legend is floated, an ordinary flex item, and stays the
/// fieldset's name. Nothing is submitted. A throwaway admin, removed after,
/// and a scratch word whose madrigal's Revise page holds a text area with
/// its own label (a sentiment's Label): Submit Sentiment has none
/// since its label is the machine's (user, 2026-10-09).
@Suite("Fieldset spacing", .serialized)
struct FieldsetSpacingTests {
  static let forms = [
    "/mission-control/submit/bibliographic/evidence-testament",
    "/mission-control/submit/lexicographic/evidence-sentiment",
    // A label field's label (FieldView, not a fieldset).
    "/account/password",
  ]

  @Test(arguments: gnorium.engines, Layout.allCases)
  func everyLabelSitsEightPixelsFromItsControl(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin, submitted: true)
    // A labeled text area: a sentiment's Label on its madrigal's Revise page.
    let forms = Self.forms + ["/mission-control/madrigals/lexicographic/\(word.madrigalID)/revise"]
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        var seen: Set<String> = []
        for form in forms {
          try await page.openHydrated(form)
          // Label bottom → control top of every shown field, rounded to
          // the pixel, by kind.
          let spacing = try await page.evaluate(
            """
            (() => {
              const gaps = (selector) => [...document.querySelectorAll(selector)]
                .map((label) => {
                  const control = label.nextElementSibling;
                  if (!control) return null;
                  const a = label.getBoundingClientRect(), b = control.getBoundingClientRect();
                  if (a.height === 0 || b.height === 0) return null;
                  return Math.round(b.top - a.bottom);
                })
                .filter((gap) => gap !== null);
              const margins = [...document.querySelectorAll(
                '.text-input-label-row, .text-area-label-row, .combobox-label, .dropdown-label, .label-view')]
                .filter((label) => label.getBoundingClientRect().height > 0)
                .map((label) => getComputedStyle(label).marginBlockEnd)
                .filter((margin) => margin !== '0px');
              return JSON.stringify({
                label: gaps('label.field-view > .label-view'),
                dropdown: gaps('.dropdown-view > label.dropdown-label'),
                combobox: gaps('.combobox-view > label.combobox-label'),
                textInput: gaps('.text-input-view > .text-input-label-row'),
                textArea: gaps('.text-area-field > .text-area-label-row'),
                fieldset: gaps('fieldset.field-view > legend'),
                margins: margins.length,
              });
            })()
            """)
          let text = spacing.string ?? "{}"
          let json = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] ?? [:]
          var kinds: [String: Set<Int>] = [:]
          for (kind, value) in json {
            if let gaps = value as? [Int], !gaps.isEmpty { kinds[kind] = Set(gaps) }
          }
          for (kind, gaps) in kinds {
            #expect(gaps == [8], "\(form): \(kind) label → control is \(gaps), not 8px")
          }
          #expect(json["margins"] as? Int == 0, "\(form): a label is spaced by a margin")
          seen.formUnion(kinds.keys)
          // Still the fieldset's accessible name.
          let named = try await page.evaluate(
            """
            (() => [...document.querySelectorAll('fieldset.field-view')]
              .every((fieldset) => fieldset.querySelector(':scope > legend') !== null
                && getComputedStyle(fieldset.querySelector(':scope > legend')).float !== 'none'))()
            """)
          #expect(named.bool == true, "\(form): a fieldset field has no floated legend")
        }
        // Every kind of field was measured across the forms.
        for kind in ["label", "dropdown", "combobox", "textInput", "textArea", "fieldset"] {
          #expect(seen.contains(kind), "no \(kind) field was measured")
        }
      }
    } catch {
      word.remove()
      try await admin.remove(after: error)
    }
    word.remove()
    try await admin.remove()
  }
}
