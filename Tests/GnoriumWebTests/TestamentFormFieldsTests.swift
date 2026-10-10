import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The testament form keeps only the fields that date the text, identify
/// the witness, locate its source or make its reuse legal (user,
/// 2026-09-27): no format, dimension, extent, former owners or notes, and no
/// manufacture or distribution statement; the publication statement stays.
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
        for gone in [
          "[name='format']", "[name='dimension_size']", "[name='dimension_unit']", "[name='extent']",
          "[name='extent_unit']", "[name='notes']", "[data-item-list='former-owner']",
          ".former-owners-view", "[data-as-namespace='manufacture']", "[data-as-namespace='distribution']",
          "#testament-resemblance-count",
        ] {
          try await expect(form.locator(gone)).toHaveCount(0)
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
}
