import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Delete Account, as its owner uses it: the page is reached from the
/// account page, refuses a wrong password, and, with the right one and the
/// box ticked, erases the account's private data and signs it out. The
/// account is a throwaway `TestAdmin`, made for the test and removed after.
@Suite("Delete account")
struct DeleteAccountTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func anAccountDeletesItself(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        // The account page links here.
        _ = try await page.goto("/account", waitUntil: .load)
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
        try await page.locator("nav.account-links a[href='/account/delete']").click()
        try await expect(page).toHaveURL("/account/delete")
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
        try await expect(page.locator(".delete-account-view .account-core-title")).toHaveText("Delete Account")
        try await expect(page.locator(".delete-account-summary")).toContainText("@\(admin.username)")

        // A wrong password deletes nothing.
        try await page.locator("#delete-account-password").fill("not the password")
        try await page.locator("#delete-account-confirm").check()
        try await page.locator("form[action='/account/delete'] button[type='submit']").click()
        try await expect(page.locator(".page-alerts .alert-view")).toContainText("current password")
        #expect(try admin.column("email") == "\(admin.username)@gnorium.test")

        // Unticked, the form isn't sent (once the answer's page is hydrated).
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
        try await page.locator("#delete-account-password").fill(admin.password)
        try await page.locator("form[action='/account/delete'] button[type='submit']").click()
        try await expect(page.locator("#delete-account-confirm-validation-message")).toBeVisible()
        #expect(try admin.column("deleted_at") == "")

        try await page.locator("#delete-account-confirm").check()
        try await page.locator("form[action='/account/delete'] button[type='submit']").click()
        try await expect(page.locator(".page-alerts .alert-view")).toContainText("Your account is deleted")
      }
      // The row stays, for the username on its contributions; nothing
      // private is left on it.
      #expect(try admin.column("username") == admin.username)
      #expect(try admin.column("email") == "")
      #expect(try admin.column("password_hash") == "")
      #expect(try admin.column("first_name") == "")
      #expect(try admin.column("deleted_at") != "")
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }
}
