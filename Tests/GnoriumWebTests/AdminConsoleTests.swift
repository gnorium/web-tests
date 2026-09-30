import CryptoKit
import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Every admin console page is drawn with its own stylesheet: a throwaway
/// admin sets up multi-factor authentication (the code is worked out here
/// from the secret the page shows, which is never printed), then opens each
/// page of the console. Each page must link a stylesheet for its view, fit
/// the screen and log no errors. Nothing is changed but the test admin's own
/// MFA; the account is removed afterwards.
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
        // Setup: the page, then the code from its secret.
        try await Self.open(page, "/admin-console/mfa/setup", sheet: "setup-mfa-view", layout: layout, name: "mfa-setup")
        let form = page.locator("form.setup-mfa-form")
        try await expect(form.getByLabel("Code")).toHaveAttribute("inputmode", "numeric")
        try await expect(form.getByLabel("Code")).toHaveAttribute("autocomplete", "one-time-code")
        try await expect(page.locator(".setup-mfa-qr-code img")).toBeVisible()
        let secret = try await page.locator(".setup-mfa-secret code").textContent()
        try await form.getByLabel("Code").fill(try Self.code(secret: secret))
        try await form.getByRole(.button, name: "Enable MFA").click()
        try await expect(page).toHaveURL("/admin-console")

        let userID = try admin.column("id")
        try await Self.open(page, "/admin-console", sheet: "admin-console-dashboard-view", layout: layout, name: "dashboard")
        try await Self.open(page, "/admin-console/users", sheet: "users-view", layout: layout, name: "users")
        try await Self.open(page, "/admin-console/users/\(userID)", sheet: "admin-console-user-view", layout: layout, name: "user")
        try await Self.open(page, "/admin-console/database", sheet: "database-view", layout: layout, name: "database")
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
        // Verify: the step after a password sign-in.
        try await Self.open(page, "/admin-console/mfa/verify", sheet: "verify-mfa-view", layout: layout, name: "mfa-verify")
        let verify = page.locator("form.verify-mfa-view")
        try await expect(verify.getByLabel("Code")).toHaveAttribute("inputmode", "numeric")
        try await expect(verify.getByLabel("Code")).toHaveAttribute("maxlength", "6")
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
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
    let linked = try await page.evaluate(
      "[...document.querySelectorAll('link[rel=stylesheet]')].map(l => new URL(l.href).pathname)", as: [String].self)
    #expect(linked.contains { $0.contains("/style-sheets/\(sheet).") }, "\(name): \(sheet).css is not linked: \(linked)")
    if let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"] {
      try await page.screenshot(to: URL(fileURLWithPath: directory).appendingPathComponent("admin-\(layout)-\(name).png"))
    }
    try await page.expectNoHorizontalOverflow()
    try await page.expectNoErrors()
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
