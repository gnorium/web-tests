import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An avatar, added and removed on the profile page by a contributor with
/// one accepted contribution (seeded), and shown in the navbar's menu. And
/// a locution's two gaps: what was said as one block, twice the gap above
/// its footer row. Throwaway accounts; the dev server keeps avatars in a
/// directory.
@Suite("Avatars")
struct AvatarTests {
  /// A 6×4 red PNG.
  static let png = Data(
    base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAYAAAAECAIAAAAiZtkUAAAAEUlEQVR4nGM4ISeHhhjIFQIArqkYYZdivB4AAAAASUVORK5CYII=")!

  @Test(arguments: gnorium.engines)
  func aContributorAddsAndRemovesAnAvatar(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let picture = FileManager.default.temporaryDirectory.appendingPathComponent("avatar-\(UUID().uuidString).png")
    try Self.png.write(to: picture)
    defer { try? FileManager.default.removeItem(at: picture) }
    do {
      try await withPage(engine, gnorium, cookies: [contributor.cookie]) { page in
        // Before any accepted contribution: the gate's sentence, no file input.
        try await page.openHydrated("/account/profile")
        try await expect(page.locator(".edit-profile-avatar .field-validation-message-text"))
          .toHaveText("Avatars open after your first accepted contribution.")
        try await expect(page.locator("#avatar-file")).toHaveCount(0)
        try await expect(page.locator("#navbar-ellipsis-menu .ellipsis-account .avatar-letter")).toBeAttached()

        // One accepted revision, seeded, opens avatars.
        _ = try TestAdmin.query(
          "INSERT INTO revisions (id, revisable_type, revisable_id, content_json, status, requested_by_user_id, evaluated_by_user_id, created_at, evaluated_at) SELECT gen_random_uuid(), 'bibliographicMadrigal', gen_random_uuid(), '{}', 'accepted', id, id, now(), now() FROM users WHERE username = '\(contributor.username)';"
        )
        try await page.openHydrated("/account/profile")
        // The avatar's forms stand outside the profile form (a form inside
        // a form is dropped, and the profile form took the upload); the
        // field's controls name them.
        try await expect(page.locator("form[action='/account/profile'] form")).toHaveCount(0)
        try await expect(page.locator("form#avatar-form[action='/account/avatar']")).toHaveCount(1)
        try await expect(page.locator("#avatar-file")).toHaveAttribute("form", "avatar-form")
        try await expect(page.locator(".edit-profile-avatar-add")).toHaveAttribute("form", "avatar-form")
        // The native control is hidden; the disc and "+ Avatar" are centered.
        let field = page.locator(".edit-profile-avatar")
        try await expect(field).toHaveCSS("align-items", "center")
        try await expect(page.locator("#avatar-file")).toHaveCSS("position", "absolute")
        try await expect(page.locator("#avatar-description")).toHaveText("A square picture, up to 5 MB; it is checked for unsafe content.")
        // With no file chosen, "+ Avatar" opens the picker instead of submitting.
        try await page.locator(".edit-profile-avatar-add").click()
        try await expect(page).toHaveURL("/account/profile")
        // A chosen file is named under the disc; the button then submits.
        try await page.locator("#avatar-file").setInputFiles([picture.path])
        try await expect(page.locator("#avatar-description")).toHaveText("Chosen: \(picture.lastPathComponent)")
        try await page.locator(".edit-profile-avatar-add").click()
        try await expect(page).toHaveURL("/account/profile?avatar=saved")
        try await expect(page.locator(".edit-profile-view .alert-view.alert-green")).toContainText("Your avatar has been saved")
        let avatarURL = try #require(try await page.locator(".edit-profile-avatar .avatar-view img").evaluate("el => el.getAttribute('src')").string)
        #expect(avatarURL.hasPrefix("/avatars/"))
        #expect(try contributor.column("avatar_key").hasSuffix(".webp"))
        // The navbar's menu shows it.
        try await expect(page.locator("#navbar-ellipsis-menu .ellipsis-account .avatar-view img")).toHaveAttribute("src", avatarURL)
        try await expect(page.locator("#navbar-ellipsis-menu .ellipsis-account .avatar-letter")).toHaveCount(0)

        // "− Avatar" takes it away, and the disc returns.
        try await page.locator(".edit-profile-avatar-remove").click()
        try await expect(page).toHaveURL("/account/profile?avatar=removed")
        try await expect(page.locator(".edit-profile-view .alert-view.alert-green")).toContainText("Your avatar has been removed")
        try await expect(page.locator(".edit-profile-avatar .avatar-letter")).toBeAttached()
        try await expect(page.locator("#navbar-ellipsis-menu .ellipsis-account .avatar-letter")).toBeAttached()
        #expect(try contributor.column("avatar_key") == "")
      }
    } catch {
      _ = try? TestAdmin.query("DELETE FROM revisions WHERE requested_by_user_id = (SELECT id FROM users WHERE username = '\(contributor.username)');")
      try await contributor.remove(after: error)
    }
    _ = try TestAdmin.query("DELETE FROM revisions WHERE requested_by_user_id = (SELECT id FROM users WHERE username = '\(contributor.username)');")
    try await contributor.remove()
  }

  @Test(arguments: gnorium.engines)
  func aLocutionsTwoGaps(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    do {
      try await withPage(engine, gnorium, cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/locutions")
        let first = page.locator(".locution-view").first
        try await expect(first).toBeAttached()
        // Byline and body in one block, 4px apart; 8px between that block
        // and the footer row.
        try await expect(first.locator(".locution-content").first).toHaveCSS("row-gap", "8px")
        try await expect(first.locator(".locution-said").first).toHaveCSS("row-gap", "4px")
        try await expect(first.locator(".locution-said .locution-header").first).toBeAttached()
        try await expect(first.locator(".locution-content > .reactions-view").first).toBeAttached()
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }
}
