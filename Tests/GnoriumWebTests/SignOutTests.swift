import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Sign out, on the account page (which the navbar's menu links to): a form
/// that POSTs (never a link a page elsewhere could follow), drawn like the
/// page's other rows, which ends the session on the server and signs the
/// browser out. The account is a throwaway `TestAdmin`, made for the test
/// and removed after.
@Suite("Sign out")
struct SignOutTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func signingOutPostsFromTheAccountPage(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      // Registering opened one session and signing in another (this browser's).
      let before = try admin.sessionCount()
      #expect(before >= 1)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        _ = try await page.goto("/account", waitUntil: .load)
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")

        // A POST form, and no sign-out link anywhere.
        let form = page.locator("form.account-sign-out[action='/auth/sign-out'][method='post']")
        try await expect(form).toHaveCount(1)
        try await expect(page.locator("a[href='/auth/sign-out']")).toHaveCount(0)
        let button = form.locator("button[type='submit']")
        try await expect(button).toHaveCount(1)
        try await expect(button).toContainText("Sign Out")

        // It looks like its neighbors: the same width, height and weight as Change password.
        let neighbour = page.locator("nav.account-links a.button-view[href='/account/password']")
        let own = try #require(try await button.boundingBox())
        let other = try #require(try await neighbour.boundingBox())
        #expect(abs(own.width - other.width) < 1)
        #expect(abs(own.height - other.height) < 1)
        try await expect(button).toHaveAttribute("data-weight", "quiet")
        try await expect(neighbour).toHaveAttribute("data-weight", "quiet")

        try await button.click()
        try await expect(page.locator("a.ellipsis-menu-link[href='/auth/sign-in']"), timeout: .seconds(20))
          .toHaveCount(1)
      }
      #expect(try admin.sessionCount() == before - 1, "this browser's session is gone from the server")
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }
}
