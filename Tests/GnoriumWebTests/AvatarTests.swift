import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An avatar, added and removed on the profile page by a contributor with
/// one accepted contribution (seeded), saved by Save Profile, and shown in
/// the navbar's menu: the picture goes from the browser straight to the
/// store's upload form (on the dev server, the directory store's own
/// `/avatars/uploads`), and the profile is sent with its key. And a
/// locution's two gaps: what was said as one block, twice the gap above
/// its footer row. Throwaway accounts.
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
    // Over 5 MB: refused before anything is sent to the store.
    let large = FileManager.default.temporaryDirectory.appendingPathComponent("avatar-large-\(UUID().uuidString).png")
    try (Self.png + Data(count: 5 * 1024 * 1024)).write(to: large)
    defer {
      try? FileManager.default.removeItem(at: picture)
      try? FileManager.default.removeItem(at: large)
    }
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
        // One form, one Save Profile: the Avatar field is the profile form's
        // first, a fieldset (the disc is a plain preview, no label to click),
        // and its file control has no name (the picture never rides the form).
        try await expect(page.locator("#avatar-form")).toHaveCount(0)
        try await expect(page.locator(".edit-profile-form fieldset.field-view .edit-profile-avatar")).toHaveCount(1)
        try await expect(page.locator(".edit-profile-form #avatar-file:not([name])")).toHaveCount(1)
        try await expect(page.locator(".edit-profile-form button[type='submit']")).toHaveCount(1)
        try await expect(page.locator(".edit-profile-form button[type='submit']")).toHaveText("Save Profile")
        // No helper text.
        try await expect(page.getByText("checked for unsafe content")).toHaveCount(0)
        // The native control is hidden; the disc and "+ Avatar" are centered;
        // "− Avatar" waits for an avatar.
        let field = page.locator(".edit-profile-avatar")
        try await expect(field).toHaveCSS("align-items", "center")
        try await expect(page.locator("#avatar-file")).toHaveCSS("position", "absolute")
        try await expect(page.locator(".edit-profile-avatar-add")).toBeVisible()
        try await expect(page.locator(".edit-profile-avatar-remove")).toBeHidden()
        try await expect(page.locator(".edit-profile-avatar .avatar-view")).toHaveCSS("cursor", "auto")

        // Too large: the field says so, nothing is sent.
        try await page.locator("#avatar-file").setInputFiles([large.path])
        try await page.locator(".edit-profile-form button[type='submit']").click()
        try await expect(page.locator("#avatar-file-validation-message")).toContainText("Choose a picture of at most 5 MB.")
        try await expect(page).toHaveURL("/account/profile")

        // A chosen picture previews in the disc, from the local file; "− Avatar"
        // takes the place of "+ Avatar", and the old message goes.
        try await page.locator("#avatar-file").setInputFiles([picture.path])
        let preview = page.locator(".edit-profile-avatar .avatar-view img.avatar-image")
        try await expect(preview).toHaveCount(1)
        let previewSource = try await preview.getAttribute("src") ?? ""
        #expect(previewSource.hasPrefix("blob:"), "the preview is the local file: \(previewSource)")
        try await expect(page.locator(".edit-profile-avatar .avatar-letter")).toHaveCount(0)
        try await expect(page.locator(".edit-profile-avatar-add")).toBeHidden()
        try await expect(page.locator(".edit-profile-avatar-remove")).toBeVisible()
        try await expect(page.locator("#avatar-file-validation-message")).toHaveCount(0)

        // Save Profile: the picture to the store, then the profile with its key.
        try await page.locator(".edit-profile-form button[type='submit']").click()
        try await expect(page).toHaveURL("/account/profile?saved=1")
        try await expect(page.locator(".edit-profile-view .alert-view.alert-green")).toContainText("Your profile has been updated")
        let avatarURL = try #require(try await page.locator(".edit-profile-avatar .avatar-view img").evaluate("el => el.getAttribute('src')").string)
        #expect(avatarURL.hasPrefix("/avatars/"))
        #expect(try contributor.column("avatar_key").hasSuffix(".webp"))
        try await expect(page.locator(".edit-profile-avatar-add")).toBeHidden()
        try await expect(page.locator(".edit-profile-avatar-remove")).toBeVisible()
        // The navbar's menu shows it.
        try await expect(page.locator("#navbar-ellipsis-menu .ellipsis-account .avatar-view img")).toHaveAttribute("src", avatarURL)
        try await expect(page.locator("#navbar-ellipsis-menu .ellipsis-account .avatar-letter")).toHaveCount(0)

        // Avatar to Username is the gap of Username to Full name.
        let gaps = try await page.evaluate(
          """
          (() => {
            const field = el => el.closest('.field-input-wrapper').parentElement.getBoundingClientRect();
            const avatar = field(document.querySelector('.edit-profile-avatar'));
            const username = field(document.querySelector('#username'));
            const fullName = field(document.querySelector('#full-name'));
            return [username.top - avatar.bottom, fullName.top - username.bottom];
          })()
          """, as: [Double].self)
        #expect(gaps.count == 2 && abs(gaps[0] - gaps[1]) < 0.5, "Avatar→Username vs Username→Full name: \(gaps)")

        // "− Avatar" (on the page hydrated again): the initial returns and
        // "+ Avatar" takes its place; Save Profile removes it.
        try await page.openHydrated("/account/profile")
        try await expect(page.locator(".edit-profile-avatar .avatar-view img")).toHaveAttribute("src", avatarURL)
        try await page.locator(".edit-profile-avatar-remove").click()
        try await expect(page.locator(".edit-profile-avatar .avatar-letter")).toBeAttached()
        try await expect(page.locator(".edit-profile-avatar .avatar-image")).toHaveCount(0)
        try await expect(page.locator(".edit-profile-avatar-add")).toBeVisible()
        try await expect(page.locator(".edit-profile-avatar-remove")).toBeHidden()
        try await page.locator(".edit-profile-form button[type='submit']").click()
        try await expect(page).toHaveURL("/account/profile?saved=1")
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
