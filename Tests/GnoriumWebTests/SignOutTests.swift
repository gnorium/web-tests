import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Sign out, in the navbar's menu: a form that POSTs (never a link a page
/// elsewhere could follow), drawn like the menu's Account row, which ends the
/// session on the server and signs the browser out. The account page holds
/// no sign-out of its own. The account is a throwaway `TestAdmin`, made for
/// the test and removed after.
@Suite("Sign out")
struct SignOutTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func signingOutPostsFromTheNavbarMenu(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      // Registering opened one session and signing in another (this browser's).
      let before = try admin.sessionCount()
      #expect(before >= 1)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        _ = try await page.goto("/account", waitUntil: .load)
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")

        // A POST form in the menu, none on the account page, and no sign-out link anywhere.
        try await expect(page.locator("nav.account-links form[action='/auth/sign-out']")).toHaveCount(0)
        let menu = page.locator("#navbar-ellipsis-menu")
        let form = menu.locator("form[action='/auth/sign-out'][method='post']")
        try await expect(form).toHaveCount(1)
        try await expect(page.locator("a[href='/auth/sign-out']")).toHaveCount(0)
        let button = form.locator("button[type='submit']")
        try await expect(button).toHaveCount(1)
        try await expect(button).toContainText("Sign Out")

        try await page.locator("[data-navbar-ellipsis]").filter(visible: true).first.click()
        // Once the menu has finished opening: a click while it slides in
        // lands wherever the button was a frame ago.
        _ = try await page.evaluate(
          "Promise.all(document.getAnimations().filter(a => a.effect?.getTiming().iterations !== Infinity).map(a => a.finished.catch(() => null))).then(() => 1)", as: Int.self)

        // It looks like its neighbor: the same width and height as Account.
        let neighbor = menu.locator("a.ellipsis-menu-link[href='/account']")
        let own = try #require(try await button.boundingBox())
        let other = try #require(try await neighbor.boundingBox())
        #expect(abs(own.width - other.width) < 1)
        #expect(abs(own.height - other.height) < 1)

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
