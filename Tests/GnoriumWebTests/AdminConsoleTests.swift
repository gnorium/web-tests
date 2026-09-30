import CryptoKit
import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The admin console, as a throwaway admin uses it. Every page is drawn with
/// its own stylesheet; MFA goes from setup to its recovery codes (shown
/// once), a sign-in with a recovery code, new codes and off again; bulk
/// delete in the table browser is a POST behind a dialog. The MFA codes are
/// worked out here from the secret the page shows, which is never printed.
/// Nothing is changed but the test admin's own MFA and sessions; the account
/// is removed afterwards.
///
/// `GNORIUM_SCREENSHOT_DIR` keeps a screenshot of every page.
@Suite("Admin console")
struct AdminConsoleTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func everyPageIsStyled(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let viewport = layout.viewport(for: engine)
    do {
      try await withPage(engine, gnorium, viewport: viewport, cookies: [admin.cookie]) { page in
        // Setup: the page, then the code from its secret; the recovery codes after.
        _ = try await Self.enableMFA(page, layout: layout)
        try await page.locator("a.recovery-codes-continue").click()
        try await expect(page).toHaveURL("/admin-console")

        let userID = try admin.column("id")
        try await Self.open(page, "/admin-console", sheet: "admin-console-dashboard-view", layout: layout, name: "dashboard")
        try await Self.open(page, "/admin-console/users", sheet: "users-view", layout: layout, name: "users")
        try await Self.open(page, "/admin-console/users/\(userID)", sheet: "admin-console-user-view", layout: layout, name: "user")
        try await Self.open(page, "/admin-console/database", sheet: "database-view", layout: layout, name: "database")
        // Its own sidebar sheet, apart from the shared sidebar's.
        try await expect(page.locator(".admin-sidebar-view.admin-console-sidebar-view").first).toBeAttached()
        try await Self.expectLinked(page, sheet: "admin-sidebar-view", name: "database")
        // A table of the schema's own, not people's.
        try await page.locator("a[href='/admin-console/database/_fluent_migrations']").click()
        try await expect(page).toHaveURL("/admin-console/database/_fluent_migrations")
        try await Self.check(page, sheet: "table-browser-view", layout: layout, name: "table")
        let rowID = try #require(
          try await page.locator(".table-browser-data tbody tr").first.getAttribute("data-row-id"))
        try await Self.open(
          page, "/admin-console/database/_fluent_migrations/\(rowID)", sheet: "table-row-details-view",
          layout: layout, name: "row")
        try await Self.open(
          page, "/admin-console/database/_fluent_migrations/\(rowID)/edit", sheet: "table-row-editor-view",
          layout: layout, name: "row-edit")
        try await Self.open(page, "/admin-console/mfa/manage", sheet: "manage-mfa-view", layout: layout, name: "mfa-manage")
        // Verify: the step after a password sign-in.
        try await Self.open(page, "/admin-console/mfa/verify", sheet: "verify-mfa-view", layout: layout, name: "mfa-verify")
        let verify = page.locator("form.verify-mfa-form")
        try await expect(verify.getByLabel("Code")).toHaveAttribute("inputmode", "numeric")
        try await expect(verify.getByLabel("Code")).toHaveAttribute("maxlength", "6")
        try await expect(page.locator("form.verify-mfa-recovery-form #verify-mfa-recovery-code")).toBeVisible()
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }

  /// MFA end to end: on, its recovery codes shown once, signed out and in
  /// again with one of them (which then works no more), new codes in place
  /// of the old, and off with a current code.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func mfaRecoveryCodesAndManagement(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let viewport = layout.viewport(for: engine)
    do {
      try await withPage(engine, gnorium, viewport: viewport, cookies: [admin.cookie]) { page in
        let (secret, codes) = try await Self.enableMFA(page, layout: layout)
        #expect(try admin.column("totp_enabled") == "true")
        let stored = try admin.column("recovery_codes_hash")
        for code in codes { #expect(!stored.contains(code), "only hashes are stored") }

        // Shown once: Security now leads to the management page, which
        // never shows a code.
        try await page.locator("a.recovery-codes-continue").click()
        try await expect(page).toHaveURL("/admin-console")
        try await expect(page.locator(".admin-console-sidebar-view a[href='/admin-console/mfa/manage']").first)
          .toBeAttached()
        try await page.openHydrated("/admin-console/mfa/setup")
        try await expect(page).toHaveURL("/admin-console/mfa/manage")
        try await Self.check(page, sheet: "manage-mfa-view", layout: layout, name: "mfa-manage")
        try await expect(page.locator(".recovery-codes-list")).toHaveCount(0)
        let shownAgain = try await page.evaluate(
          "document.documentElement.outerHTML.includes(\(Self.quoted(codes[0])))", as: Bool.self)
        #expect(!shownAgain, "a recovery code is never shown again")
        try await expect(page.locator(".manage-mfa-view")).toContainText("8 of 8 unused")

        // Signed out (from the account page) and in again, with a recovery code.
        try await page.openHydrated("/account")
        try await page.locator("form.account-sign-out button[type='submit']").click()
        try await expect(page.locator("a.ellipsis-menu-link[href='/auth/sign-in']"), timeout: .seconds(20))
          .toHaveCount(1)
        try await page.openHydrated("/admin-console/sign-in")
        try await page.locator("#username").fill(admin.username)
        try await page.locator("#password").fill(admin.password)
        try await page.locator("form:has(#password) button[type='submit']").click()
        try await expect(page).toHaveURL("/admin-console/mfa/verify")
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
        try await page.locator("#verify-mfa-recovery-code").fill(codes[0])
        try await page.getByRole(.button, name: "Use Recovery Code").click()
        try await expect(page).toHaveURL("/admin-console")

        // It worked once.
        try await page.openHydrated("/admin-console/mfa/verify")
        try await page.locator("#verify-mfa-recovery-code").fill(codes[0])
        try await page.getByRole(.button, name: "Use Recovery Code").click()
        try await expect(page).toHaveURL("/admin-console/mfa/verify?error=invalid-recovery-code")
        try await expect(page.locator(".page-alerts .alert-view")).toContainText("used already")
        try await page.openHydrated("/admin-console/mfa/manage")
        try await expect(page.locator(".manage-mfa-view")).toContainText("7 of 8 unused")

        // New codes, shown once; the old ones are gone.
        try await page.getByRole(.button, name: "Regenerate Recovery Codes").click()
        try await expect(page.locator(".recovery-codes-view")).toBeVisible()
        try await Self.check(page, sheet: "recovery-codes-view", layout: layout, name: "mfa-regenerated")
        let fresh = try await Self.shownCodes(page)
        #expect(fresh.count == 8)
        #expect(Set(fresh).isDisjoint(with: codes))
        try await page.locator("a.recovery-codes-continue").click()
        try await expect(page).toHaveURL("/admin-console/mfa/manage")
        try await expect(page.locator(".manage-mfa-view")).toContainText("8 of 8 unused")

        // Off, with a current code: a wrong one changes nothing.
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
        try await page.locator("#manage-mfa-code").fill("000000")
        try await page.getByRole(.button, name: "Turn Off MFA").click()
        try await expect(page).toHaveURL("/admin-console/mfa/manage?error=invalid")
        #expect(try admin.column("totp_enabled") == "true")
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
        try await page.locator("#manage-mfa-code").fill(try Self.code(secret: secret))
        try await page.getByRole(.button, name: "Turn Off MFA").click()
        try await expect(page).toHaveURL("/admin-console/mfa/setup?notice=disabled")
        try await expect(page.locator(".page-alerts .alert-view")).toContainText("is off")
        #expect(try admin.column("totp_enabled") == "false")
        #expect(try admin.column("totp_secret") == "")
        #expect(try admin.column("recovery_codes_hash") == "")
        try await page.openHydrated("/admin-console")
        try await expect(page.locator(".admin-console-sidebar-view a[href='/admin-console/mfa/setup']").first)
          .toBeAttached()
      }
      let actions = try TestAdmin.query(
        "SELECT string_agg(event_logs.action, ',' ORDER BY event_logs.created_at) FROM event_logs JOIN users ON users.id = event_logs.user_id WHERE users.username = '\(admin.username)' AND event_logs.action IN ('mfa_enable','recovery_code_use','recovery_codes_regenerate','mfa_disable');"
      )
      #expect(actions == "mfa_enable,recovery_code_use,recovery_codes_regenerate,mfa_disable", "logged: \(actions)")
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }

  /// Bulk delete in the table browser: a dialog asks, and its Delete posts a
  /// form (never a GET). The row is one of the test admin's own sessions.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func bulkDeleteIsAPostAfterADialog(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let viewport = layout.viewport(for: engine)
    do {
      try await admin.signIn()
      let throwaway = try admin.newestSessionID()
      let before = try admin.sessionCount()
      try await withPage(engine, gnorium, viewport: viewport, cookies: [admin.cookie]) { page in
        try await Self.open(page, "/admin-console/database/sessions", sheet: "table-browser-view", layout: layout, name: "sessions")
        try await expect(page.locator("form.table-browser-delete-form[method='post'][action='/admin-console/database/sessions/delete']"))
          .toHaveCount(1)
        try await page.locator("#row-\(throwaway)").check()
        try await expect(page.locator(".selection-count")).toHaveText("1 selected")

        // Cancel deletes nothing.
        let dialog = page.locator(".table-browser-delete-dialog")
        try await page.locator(".action-delete").click()
        try await expect(dialog).toHaveAttribute("data-open", "true")
        try await expect(dialog.locator(".dialog-header-title")).toHaveText("Delete 1 row?")
        try await dialog.locator(".dialog-default-button button").click()
        try await expect(dialog).toHaveAttribute("data-open", "false")
        #expect(try admin.sessionCount() == before)

        try await page.locator(".action-delete").click()
        try await dialog.locator(".dialog-primary-button button").click()
        // The answer is the table again, without the row.
        try await expect(page.locator("#row-\(throwaway)")).toHaveCount(0)
        try await expect(page).toHaveURL("/admin-console/database/sessions")
        try await expect(page.locator(".table-browser-view")).toBeVisible()
      }
      #expect(try admin.sessionCount() == before - 1, "the one row is deleted")
      #expect(
        try TestAdmin.query("SELECT COUNT(*) FROM sessions WHERE id = '\(throwaway)';") == "0",
        "and it is the throwaway session")
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }

  /// Sets up MFA from the setup page and returns its secret and the
  /// recovery codes the next page shows.
  static func enableMFA(_ page: Page, layout: Layout) async throws -> (secret: String, codes: [String]) {
    try await Self.open(page, "/admin-console/mfa/setup", sheet: "setup-mfa-view", layout: layout, name: "mfa-setup")
    let form = page.locator("form.setup-mfa-form")
    try await expect(form.getByLabel("Code")).toHaveAttribute("inputmode", "numeric")
    try await expect(form.getByLabel("Code")).toHaveAttribute("autocomplete", "one-time-code")
    try await expect(page.locator(".setup-mfa-qr-code img")).toBeVisible()
    let secret = try await page.locator(".setup-mfa-secret code").textContent()
    try await form.getByLabel("Code").fill(try Self.code(secret: secret))
    try await form.getByRole(.button, name: "Enable MFA").click()

    // The recovery codes, once: to copy, or to download as a text file.
    try await expect(page.locator(".recovery-codes-view")).toBeVisible()
    try await Self.check(page, sheet: "recovery-codes-view", layout: layout, name: "mfa-recovery-codes")
    try await Self.expectLinked(page, sheet: "copyable-code-view", name: "mfa-recovery-codes")
    try await expect(page.locator(".page-alerts .alert-view")).toContainText("won't be shown again")
    try await expect(page.locator(".recovery-codes-list .copyable-code-copy")).toHaveAttribute(
      "aria-label", "Copy recovery codes")
    let download = page.locator("a.recovery-codes-download")
    try await expect(download).toHaveAttribute("download", "gnorium-recovery-codes.txt")
    let href = try #require(try await download.getAttribute("href"))
    #expect(href.hasPrefix("data:text/plain;charset=utf-8,"))
    let codes = try await Self.shownCodes(page)
    #expect(codes.count == 8)
    for code in codes { #expect(href.contains(code), "the file holds \(code)") }
    return (secret, codes)
  }

  /// The recovery codes the page shows, one a line.
  static func shownCodes(_ page: Page) async throws -> [String] {
    // The raw text, lines and all (a locator's text is whitespace-normalized).
    let text = try await page.evaluate(
      "document.querySelector('.recovery-codes-list code').textContent", as: String.self)
    let codes = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    for code in codes {
      #expect(code.range(of: "^[A-Z2-9]{4}-[A-Z2-9]{4}$", options: .regularExpression) != nil, "\(code)")
    }
    return codes
  }

  static func quoted(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") + "'"
  }

  static func open(_ page: Page, _ path: String, sheet: String, layout: Layout, name: String) async throws {
    try await page.openHydrated(path)
    try await check(page, sheet: sheet, layout: layout, name: name)
  }

  /// The page's view is there and its stylesheet is linked (a view the
  /// stylesheet emitter never built is drawn bare), and the page fits and is
  /// quiet.
  static func check(_ page: Page, sheet: String, layout: Layout, name: String) async throws {
    try await expect(page.locator(".\(sheet)").first).toBeAttached()
    try await expectLinked(page, sheet: sheet, name: name)
    if let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"] {
      try await page.screenshot(to: URL(fileURLWithPath: directory).appendingPathComponent("admin-\(layout)-\(name).png"))
    }
    try await page.expectNoHorizontalOverflow()
    try await page.expectNoErrors()
  }

  static func expectLinked(_ page: Page, sheet: String, name: String) async throws {
    let linked = try await page.evaluate(
      "[...document.querySelectorAll('link[rel=stylesheet]')].map(l => new URL(l.href).pathname)", as: [String].self)
    #expect(linked.contains { $0.contains("/style-sheets/\(sheet).") }, "\(name): \(sheet).css is not linked: \(linked)")
  }

  /// The current RFC 6238 code (SHA-1, 30 seconds, 6 digits) for a base32 secret.
  static func code(secret: String) throws -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    var bits = 0
    var value = 0
    var key: [UInt8] = []
    for character in secret.uppercased() where character != "=" && !character.isWhitespace {
      guard let index = alphabet.firstIndex(of: character) else { throw WebTestError("The secret is not base32.") }
      value = (value << 5) | index
      bits += 5
      if bits >= 8 {
        key.append(UInt8((value >> (bits - 8)) & 0xFF))
        bits -= 8
      }
    }
    var counter = UInt64(Date().timeIntervalSince1970 / 30).bigEndian
    let message = Data(bytes: &counter, count: 8)
    let mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    let offset = Int(mac[mac.count - 1] & 0x0F)
    let number =
      (UInt32(mac[offset] & 0x7F) << 24) | (UInt32(mac[offset + 1]) << 16) | (UInt32(mac[offset + 2]) << 8)
      | UInt32(mac[offset + 3])
    return String(format: "%06d", number % 1_000_000)
  }
}
