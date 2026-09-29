import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A fieldset field (FieldView isFieldset: its label a legend) keeps the
/// same label → control spacing as a label field. A fieldset's rendered
/// legend sits outside its flex layout, so the gap never reached it; the
/// legend is floated, an ordinary flex item, and stays the fieldset's name.
/// Nothing is submitted. A throwaway admin, removed after.
@Suite("Fieldset spacing", .serialized)
struct FieldsetSpacingTests {
  static let forms = [
    "/mission-control/submit/bibliographic/evidence-testament",
    "/mission-control/submit/lexicographic/evidence-sentiment",
  ]

  @Test(arguments: gnorium.engines, Layout.allCases)
  func aLegendSitsAsFarFromItsControlAsALabel(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        for form in Self.forms {
          try await page.openHydrated(form)
          // Label bottom → control top of every shown field, rounded to
          // the pixel: a field's label (FieldView's, a dropdown's) and a
          // fieldset field's legend apart. (TextInputView's label row is
          // its own, smaller: 14px text, 4px above its box.)
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
              return JSON.stringify({
                labels: gaps('label.field-view > .label-view, .dropdown-view > label.dropdown-label'),
                fieldsets: gaps('fieldset.field-view > legend'),
              });
            })()
            """)
          let text = spacing.string ?? "{}"
          let json = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: [Int]] ?? [:]
          let labels = Set(json["labels"] ?? [])
          let fieldsets = Set(json["fieldsets"] ?? [])
          #expect(labels.count == 1, "\(form): labeled fields do not share one spacing: \(labels)")
          #expect(!fieldsets.isEmpty, "\(form): no fieldset field shown")
          #expect(fieldsets == labels, "\(form): fieldset spacing \(fieldsets) is not the label spacing \(labels)")
          // Still the fieldset's accessible name.
          let named = try await page.evaluate(
            """
            (() => [...document.querySelectorAll('fieldset.field-view')]
              .every((fieldset) => fieldset.querySelector(':scope > legend') !== null
                && getComputedStyle(fieldset.querySelector(':scope > legend')).float !== 'none'))()
            """)
          #expect(named.bool == true, "\(form): a fieldset field has no floated legend")
        }
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }
}
