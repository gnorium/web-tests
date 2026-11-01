import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A frozen form's placeholders are disabled gray (user, 2026-11-01): a
/// disabled text area's placeholder (a node's Note) has the same color as a
/// disabled text input's, `--color-disabled`, both `color` and
/// `-webkit-text-fill-color`. A throwaway admin's scratch work, given a
/// work note so its record page draws the frozen Note, removed after.
@Suite("Disabled placeholder", .serialized)
struct DisabledPlaceholderTests {
  @Test(arguments: gnorium.engines)
  func aDisabledTextAreasPlaceholderMatchesATextInputs(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    do {
      _ = try TestAdmin.query(
        """
        UPDATE biblio_record_versions
          SET metadata_json = (metadata_json::jsonb || '{"workNote":"A note."}'::jsonb)::text
          WHERE id = '\(work.versionID.lowercased())';
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated(work.path)
        try await expect(page.locator("textarea.text-area-input:disabled[placeholder]").first).toBeAttached()
        let colors: [String] = try await page.evaluate(
          """
          (() => {
            const probe = document.createElement('span');
            probe.style.color = 'var(--color-disabled)';
            document.body.append(probe);
            const disabled = getComputedStyle(probe).color;
            probe.remove();
            const area = document.querySelector('.text-area-view textarea.text-area-input:disabled[placeholder]');
            const input = document.querySelector('.text-input-view input.text-input-input:disabled[placeholder]');
            const of = (element) => {
              const style = getComputedStyle(element, '::placeholder');
              return [style.color, style.webkitTextFillColor];
            };
            return [disabled, ...of(area), ...of(input)];
          })()
          """, as: [String].self)
        try #require(colors.count == 5)
        let disabled = colors[0]
        #expect(colors[1] == disabled, "text area placeholder color")
        #expect(colors[2] == disabled, "text area placeholder fill")
        #expect(colors[3] == disabled, "text input placeholder color")
        #expect(colors[4] == disabled, "text input placeholder fill")
        try await page.expectNoErrors()
      }
    } catch {
      work.remove()
      try await admin.remove(after: error)
    }
    work.remove()
    try await admin.remove()
  }
}
