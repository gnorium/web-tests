import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Sign Out, from the account menu: a form that POSTs (never a link a page
/// elsewhere could follow), drawn like the menu's other buttons, which ends
/// the session on the server and signs the browser out. The account is a
/// throwaway `TestAdmin`, made for the test and removed after.
@Suite("Sign out")
struct SignOutTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func signingOutPostsFromTheAccountMenu(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      // Registering opened one session and signing in another (this browser's).
      let before = try admin.sessionCount()
      #expect(before >= 1)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        _ = try await page.goto("/account/password", waitUntil: .load)
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")

        // A POST form, and no sign-out link anywhere.
        let form = page.locator("form.ellipsis-menu-link[action='/auth/sign-out'][method='post']")
        try await expect(form).toHaveCount(1)
        try await expect(page.locator("a[href='/auth/sign-out']")).toHaveCount(0)
        let button = form.locator("button[type='submit']")
        try await expect(button).toHaveCount(1)
        try await expect(button).toContainText("Sign Out")

        try await page.locator("[data-navbar-ellipsis]").filter(visible: true).first.click()
        try await expect(button).toBeVisible()

        // It looks like its neighbours: the same width and height as Delete Account.
        let neighbour = page.locator("a.ellipsis-menu-link[href='/account/delete'] .button-view")
        let own = try #require(try await button.boundingBox())
        let other = try #require(try await neighbour.boundingBox())
        #expect(abs(own.width - other.width) < 1)
        #expect(abs(own.height - other.height) < 1)
        let ownClass = try await button.getAttribute("class")
        let otherClass = try await neighbour.getAttribute("class")
        #expect(ownClass == otherClass, "the same button classes")

        try await button.click()
        try await expect(page.locator("a.ellipsis-menu-link[href='/auth/sign-in']"), timeout: .seconds(20))
          .toHaveCount(1)
      }
      #expect(try admin.sessionCount() == before - 1, "this browser's session is gone from the server")
    } catch {
      await admin.remove()
      throw error
    }
    await admin.remove()
  }
}
