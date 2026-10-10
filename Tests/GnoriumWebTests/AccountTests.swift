import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The account page (`/account`), which the navbar's menu links to and
/// which holds everything about the account: Profile,
/// Password, Authentication and Admin Console (admins only), and Delete
/// Account. The menu
/// itself keeps one account link and Sign Out (a POST form). And changing
/// the email address: the new one's verification reminder, a warning alert
/// at the top of the page's content, whose Resend Email sends a new link and
/// whose close control dismisses it.
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
        try await expect(links.locator("a[href='/account/password']")).toHaveText("Password")
        try await expect(links.locator("a[href='/account/delete']")).toContainText("Delete Account")
        try await expect(links.locator("a[href='/admin-console/authentication/setup']")).toHaveCount(asAdmin ? 1 : 0)
        if asAdmin {
          try await expect(links.locator("a[href='/admin-console/authentication/setup']")).toHaveText("Authentication")
        }
        try await expect(links.locator("a[href='/admin-console']")).toHaveCount(asAdmin ? 1 : 0)
        try await expect(links.locator("form[action='/auth/sign-out']")).toHaveCount(0)
        try await expect(page.locator("a[href='/auth/sign-out']")).toHaveCount(0)
        // Every row is a plain link, one per row, with its icon at the text's
        // size: the link color (Delete Account too: red is for the button on
        // its page), no button background.
        let rows = try await page.evaluate(
          """
          [...document.querySelectorAll('nav.account-links > *')].map(a => {
            const svg = a.querySelector('svg'), style = getComputedStyle(a)
            return {
              label: a.textContent.trim(),
              link: a.matches('a.link-view') && !a.matches('.button-view'),
              iconSize: svg ? Math.round(svg.getBoundingClientRect().height) : 0,
              fontSize: parseFloat(style.fontSize),
              color: style.color,
              background: style.backgroundColor,
              top: Math.round(a.getBoundingClientRect().top)
            }
          })
          """, as: [Row].self)
        #expect(rows.count == (asAdmin ? 5 : 3))
        for (index, row) in rows.enumerated() {
          #expect(row.link, "\(row.label) is not a plain link")
          #expect(row.iconSize == 16 && Double(row.iconSize) == row.fontSize, "\(row.label): icon \(row.iconSize), text \(row.fontSize)")
          #expect(row.color == rows[0].color, "\(row.label) is \(row.color)")
          #expect(row.background == "rgba(0, 0, 0, 0)", "\(row.label) has background \(row.background)")
          if index > 0 { #expect(row.top > rows[index - 1].top, "\(row.label) shares a row") }
        }
        try await expect(links).toHaveCSS("flex-direction", "column")
        // Delete Account turns red on hover, its icon with it.
        let deleteLink = links.locator("a[href='/account/delete']")
        try await expect(links.locator("a.link-red-hover[href='/account/delete']")).toHaveCount(1)
        if layout != .phone {
          try await deleteLink.hover()
          let hovered = try await page.evaluate(
            """
            (() => { const a = document.querySelector("nav.account-links a[href='/account/delete']")
              return [getComputedStyle(a).color, getComputedStyle(a.querySelector('svg')).color] })()
            """, as: [String].self)
          #expect(hovered[0] != rows[0].color, "Delete Account stays \(hovered[0]) on hover")
          #expect(hovered[1] == hovered[0], "The icon is \(hovered[1]), the text \(hovered[0])")
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
        try await expect(page.locator(".account-provider-password .label-text")).toHaveCSS("font-size", "16px")
        let focused = try await page.evaluate("document.activeElement?.id === 'google-password'", as: Bool.self)
        #expect(focused, "Clicking Connect should reveal and focus password confirmation")
        let passwordAboveProvider = try await page.evaluate("document.querySelector('.account-provider-password').getBoundingClientRect().bottom <= document.querySelector('.account-provider-row').getBoundingClientRect().top", as: Bool.self)
        #expect(passwordAboveProvider, "Password confirmation belongs above the Google row inside Links")
        try await links.locator("a[href='/users/\(account.username)']").click()
        try await expect(page.locator(".user-profile-actions a[href='/account/profile']")).toBeVisible()
        try await page.locator(".user-profile-actions a[href='/account/profile']").click()
        // The click navigates at once (the server logs the request); the
        // address changes when the page answers, which with every suite
        // running can take longer than the usual 5s.
        try await expect(page, timeout: .seconds(15)).toHaveURL("/account/profile")
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
    let link: Bool
    let iconSize: Int
    let fontSize: Double
    let color: String
    let background: String
    let top: Int
  }

  /// Changing one's email address: Edit Profile keeps the new address
  /// pending and sends it a link, and the account keeps its verified address
  /// meanwhile. The reminder is the design system's warning alert inside the
  /// page's content (under the navbar, not above the whole page), spaced by
  /// the section's gap; Resend Email sends a new link, and the alert's own
  /// close control dismisses it. Opening the link switches the address.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func theVerificationReminderResendsAndDismisses(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let account = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let current = account.username + "@gnorium.test"
    let pending = account.username + "_new@gnorium.test"
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [account.cookie]) { page in
        try await page.openHydrated("/account/profile")
        try await expect(page.locator("#email")).toHaveValue(current)
        // No helper texts under Email or Current password; the password
        // field is hidden (out of the tab order) until the address differs.
        try await expect(page.locator("#email-description")).toHaveCount(0)
        try await expect(page.locator("#edit-profile-password-field")).toHaveAttribute("hidden")
        try await page.locator("#email").fill(pending)
        try await expect(page.locator("#edit-profile-password")).toBeVisible()
        try await expect(page.locator("#edit-profile-password-description")).toHaveCount(0)
        try await page.locator("#email").fill(current)
        try await expect(page.locator("#edit-profile-password-field"), timeout: .seconds(5)).toHaveAttribute("hidden")
        try await page.locator("#email").fill(pending)
        try await expect(page.locator("#edit-profile-password")).toBeVisible()
        // Saved without the password: the field says so, the address is unchanged.
        try await page.getByRole(.button, name: "Save Profile").click()
        try await expect(page.locator("#edit-profile-password-validation-message")).toContainText("Enter your current password")
        try await expect(page.locator("#edit-profile-password")).toBeVisible()
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
        try await page.locator("#edit-profile-password").fill(account.password)
        try await page.getByRole(.button, name: "Save Profile").click()
        try await expect(page).toHaveURL("/account/profile?saved=email")
        try await expect(page.locator(".edit-profile-view .alert-view.alert-green")).toContainText("a link was sent to \(pending); your account keeps its current address until you open it")
        try await expect(page.locator("#email")).toHaveValue(current)
        try await expect(page.locator("a[href='/account']").filter(hasText: "Back to account")).toHaveCount(0)
      }
      // The old address is still the account's, and still verified.
      #expect(
        try TestAdmin.query("SELECT email || ' ' || email_verified::text || ' ' || coalesce(pending_email, '—') FROM users WHERE username = '\(account.username)';")
          == "\(current) true \(pending)")
      let linkBefore = try Self.verificationToken(account)
      #expect(!linkBefore.isEmpty, "the new address was sent a link")
      // The change's own link starts the minute Resend Email waits
      // (`EmailVerification.resendCooldown`): issued a minute ago, as a
      // link that never arrived would be by the time anyone asks again.
      _ = try TestAdmin.query(
        "UPDATE email_verification_tokens SET expires_at = expires_at - interval '61 seconds' FROM users WHERE users.id = email_verification_tokens.user_id AND users.username = '\(account.username)';"
      )
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [account.cookie]) { page in
        try await page.openHydrated("/account")
        let banner = page.locator(".email-verification-banner-view")
        try await expect(banner).toBeVisible()
        try await expect(banner.locator(".email-verification-banner-message")).toHaveText(
          "Verify your new address \(pending): open the link we sent to it.")
        try await expect(banner.locator(".email-verification-banner-message strong")).toHaveCSS("font-weight", "600")
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
          .toContainText("We sent a new verification link to \(pending).")
        try await expect(banner.locator(".button-label")).toContainText("Resend in ")
        try await expect(banner.locator("button.email-verification-banner-resend")).toBeDisabled()

        try await banner.locator(".alert-dismiss").click()
        try await expect(banner).toBeHidden()
        try await page.expectNoErrors()
      }
      let linkAfter = try Self.verificationToken(account)
      #expect(!linkAfter.isEmpty && linkAfter != linkBefore, "a new link was issued")

      // Opening the link: the link's token is only ever in the email, so
      // the test gives the row one it knows.
      let token = UUID().uuidString.lowercased()
      _ = try TestAdmin.query(
        "UPDATE email_verification_tokens SET token_hash = encode(sha256(convert_to('\(token)', 'UTF8')), 'hex') FROM users WHERE users.id = email_verification_tokens.user_id AND users.username = '\(account.username)';"
      )
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [account.cookie]) { page in
        try await page.openHydrated("/auth/verify-email?token=\(token)")
        try await expect(page.locator(".verify-email-view")).toContainText("Your email address is now \(pending).")
        try await page.openHydrated("/account")
        try await expect(page.locator(".email-verification-banner-view")).toHaveCount(0)
        try await page.expectNoErrors()
      }
      #expect(
        try TestAdmin.query("SELECT email || ' ' || email_verified::text || ' ' || coalesce(pending_email, '—') FROM users WHERE username = '\(account.username)';")
          == "\(pending) true —")
      #expect(try Self.verificationToken(account).isEmpty, "the link works once")
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
