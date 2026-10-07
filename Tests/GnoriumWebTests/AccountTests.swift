import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The account page (`/account`), which the navbar's menu links to and
/// which holds everything about the account: Profile,
/// Change Password, Multi-Factor Authentication and Admin Console (admins only), and Delete
/// Account. The menu
/// itself keeps one account link and Sign Out (a POST form). And the email
/// verification reminder: a warning alert at the top of the page's content,
/// whose Resend Email sends a new link and whose close control dismisses it.
/// The accounts are throwaway ones, made for the test and removed after.
@Suite("Account")
struct AccountTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func theAccountPageHoldsTheAccountsLinks(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    for asAdmin in [false, true] {
      try await Self.checkAccountPage(engine: engine, layout: layout, asAdmin: asAdmin)
    }
  }

  static func checkAccountPage(engine: BrowserEngine, layout: Layout, asAdmin: Bool) async throws {
    let account = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: asAdmin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [account.cookie]) { page in
        try await page.openHydrated("/")
        // The menu: one link to the account page, none of what it holds, and
        // Sign Out (the POST form), which lives here, not on the account page.
        let menu = page.locator("#navbar-ellipsis-menu")
        try await expect(menu.locator("a.ellipsis-menu-link[href='/account']")).toHaveCount(1)
        try await expect(menu.locator("a[href='/account/delete']")).toHaveCount(0)
        try await expect(menu.locator("a[href='/account/password']")).toHaveCount(0)
        try await expect(menu.locator("a[href='/admin-console']")).toHaveCount(0)
        try await expect(menu.locator("form[action='/auth/sign-out'][method='post']")).toHaveCount(1)
        try await page.locator("[data-navbar-ellipsis]").filter(visible: true).first.click()
        // Once the menu has finished opening: a click while it slides in
        // lands wherever the link was a frame ago.
        _ = try await page.evaluate(
          "Promise.all(document.getAnimations().filter(a => a.effect?.getTiming().iterations !== Infinity).map(a => a.finished.catch(() => null))).then(() => 1)", as: Int.self)
        try await menu.locator("a.ellipsis-menu-link[href='/account']").click()
        try await expect(page).toHaveURL("/account")
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")

        try await expect(page.locator(".account-core-title")).toHaveText("Account")
        try await expect(page.locator(".account-core-subtitle")).toContainText("@\(account.username)")
        let links = page.locator("nav.account-links")
        try await expect(links.locator("a[href='/users/\(account.username)']")).toContainText("Profile")
        try await expect(links.locator("a[href='/account/profile']")).toHaveCount(0)
        try await expect(links.locator("a[href='/account/password']")).toContainText("Change Password")
        try await expect(links.locator("a[href='/account/delete']")).toContainText("Delete Account")
        try await expect(links.locator("a[href='/admin-console/mfa/setup']")).toHaveCount(asAdmin ? 1 : 0)
        if asAdmin {
          try await expect(links.locator("a[href='/admin-console/mfa/setup']")).toHaveText("Multi‑Factor Authentication")
        }
        try await expect(links.locator("a[href='/admin-console']")).toHaveCount(asAdmin ? 1 : 0)
        try await expect(links.locator("form[action='/auth/sign-out']")).toHaveCount(0)
        try await expect(page.locator("a[href='/auth/sign-out']")).toHaveCount(0)
        // Every row has its icon, and every row is as wide as the list.
        let rows = try await page.evaluate(
          """
          [...document.querySelectorAll('nav.account-links .button-view')].map(b => ({
            label: b.textContent.trim(),
            icon: !!b.querySelector('svg'),
            width: Math.round(b.getBoundingClientRect().width),
            list: Math.round(b.closest('nav').getBoundingClientRect().width)
          }))
          """, as: [Row].self)
        #expect(rows.count == (asAdmin ? 5 : 3))
        for row in rows {
          #expect(row.icon, "\(row.label) has no icon")
          #expect(row.width == row.list)
        }

        let linked = try await page.evaluate(
          "[...document.querySelectorAll('link[rel=stylesheet]')].map(l => new URL(l.href).pathname)", as: [String].self)
        #expect(linked.contains { $0.contains("/style-sheets/account-view.") }, "\(linked)")
        if let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"] {
          try await page.screenshot(
            to: URL(fileURLWithPath: directory).appendingPathComponent("account-\(layout)-\(asAdmin ? "admin" : "user").png"))
        }
        try await expect(page.locator(".account-provider-row .button-view")).toHaveCSS("height", "40px")
        try await expect(page.locator(".account-provider-password")).not.toBeVisible()
        try await page.locator(".account-provider-row .button-view").click()
        try await expect(page).toHaveURL("/account")
        try await expect(page.locator(".account-provider-password")).toBeVisible()
        try await expect(page.locator(".account-provider-password .label-text")).toHaveCSS("font-size", "14px")
        let focused = try await page.evaluate("document.activeElement?.id === 'google-password'", as: Bool.self)
        #expect(focused, "Clicking Connect should reveal and focus password confirmation")
        let passwordAboveProvider = try await page.evaluate("document.querySelector('.account-provider-password').getBoundingClientRect().bottom <= document.querySelector('.account-provider-row').getBoundingClientRect().top", as: Bool.self)
        #expect(passwordAboveProvider, "Password confirmation belongs above the Google row inside Links")
        try await links.locator("a[href='/users/\(account.username)']").click()
        try await expect(page.locator(".user-profile-actions a[href='/account/profile']")).toBeVisible()
        try await page.locator(".user-profile-actions a[href='/account/profile']").click()
        try await expect(page).toHaveURL("/account/profile")
        try await expect(page.locator(".account-core-title")).toHaveText("Edit Profile")
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    } catch {
      try await account.remove(after: error)
    }
    try await account.remove()
  }

  struct Row: Decodable {
    let label: String
    let icon: Bool
    let width: Double
    let list: Double
  }

  /// The reminder for an unverified address: the design system's warning
  /// alert inside the page's content (under the navbar, not above the whole
  /// page), spaced by the section's gap; Resend Email sends a new link, and
  /// the alert's own close control dismisses it.
  @Test(
    .disabled(
      "No account can be unverified while signed in: registration verifies the address first, and sign-in requires it. The reminder returns with changing one's email, as the new address's pending verification (user, 2026-10-07)."),
    arguments: gnorium.engines, Layout.allCases)
  func theVerificationReminderResendsAndDismisses(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let account = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    do {
      let linkBefore = try Self.verificationToken(account)
      // Registration's own link starts the minute Resend Email waits
      // (`EmailVerification.resendCooldown`): issued a minute ago, as an
      // address that never got it would be by the time anyone asks again.
      _ = try TestAdmin.query(
        "UPDATE email_verification_tokens SET expires_at = expires_at - interval '61 seconds' FROM users WHERE users.id = email_verification_tokens.user_id AND users.username = '\(account.username)';"
      )
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [account.cookie]) { page in
        try await page.openHydrated("/account")
        let banner = page.locator(".email-verification-banner-view")
        try await expect(banner).toBeVisible()
        try await expect(banner).toContainText(account.username + "@gnorium.test")
        let placement = try await page.evaluate(
          """
          (() => {
            const banner = document.querySelector('.email-verification-banner-view');
            const navbar = document.querySelector('.navbar-view');
            return {
              alert: banner.classList.contains('alert-view') && banner.classList.contains('alert-orange'),
              inSection: banner.parentElement.classList.contains('page-section'),
              belowNavbar: banner.getBoundingClientRect().top >= navbar.getBoundingClientRect().bottom,
              margin: getComputedStyle(banner).marginBlockEnd,
            };
          })()
          """, as: Placement.self)
        #expect(placement.alert, "a warning AlertView")
        #expect(placement.inSection, "at the top of the page's content")
        #expect(placement.belowNavbar)
        #expect(placement.margin == "0px", "spaced by its parent's gap, not a margin")
        let resend = banner.getByRole(.button, name: "Resend Email")
        try await expect(resend).toBeVisible()
        try await expect(resend).toHaveAttribute("data-weight", "plain")
        try await page.expectNoHorizontalOverflow()

        try await resend.click()
        // The outcome is its own green alert just above the banner; the
        // button then waits a minute, counting down.
        try await expect(page.locator(".email-verification-banner-notices .alert-view.alert-green"))
          .toContainText("We sent a new verification link")
        try await expect(banner.locator(".button-label")).toContainText("Resend in ")
        try await expect(banner.locator("button.email-verification-banner-resend")).toBeDisabled()

        try await banner.locator(".alert-dismiss").click()
        try await expect(banner).toBeHidden()
        try await page.expectNoErrors()
      }
      let linkAfter = try Self.verificationToken(account)
      #expect(!linkAfter.isEmpty && linkAfter != linkBefore, "a new link was issued")
    } catch {
      try await account.remove(after: error)
    }
    try await account.remove()
  }

  struct Placement: Decodable {
    let alert: Bool
    let inSection: Bool
    let belowNavbar: Bool
    let margin: String
  }

  /// The id of the account's current verification link (a new link
  /// replaces the old).
  static func verificationToken(_ account: TestAdmin) throws -> String {
    try TestAdmin.query(
      "SELECT email_verification_tokens.id FROM email_verification_tokens JOIN users ON users.id = email_verification_tokens.user_id WHERE users.username = '\(account.username)';"
    )
  }
}
