import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Account forms validate themselves: the form has `novalidate`, so the
/// browser never shows its own bubble, and our message sits under each
/// field instead, tied to it by `aria-invalid` and `aria-describedby`.
/// Nothing is ever sent: every submit here is invalid on purpose.
@Suite("Field validation")
struct FieldValidationTests {
  @Test(arguments: gnorium.engines, Layout.allCases)
  func anEmptySignInShowsInlineErrorsAndNoBubble(engine: BrowserEngine, layout: Layout) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/auth/sign-in")
      let form = page.locator("form.sign-in-form")
      // `novalidate`: the browser's constraint bubble can't show.
      try await expect(form).toHaveAttribute("novalidate")

      try await form.locator("button[type='submit']").click()

      let identity = page.locator("#email-or-username")
      let identityMessage = page.locator("#email-or-username-validation-message")
      try await expect(identityMessage).toBeVisible()
      try await expect(identityMessage).toHaveText("Enter your email or username.")
      try await expect(identityMessage.locator("svg.error-icon-view")).toHaveCount(1)
      try await expect(identity).toHaveAttribute("aria-invalid", "true")
      try await expect(identity).toHaveAttribute("aria-describedby", "email-or-username-validation-message")
      try await expect(identity).toBeFocused()

      let password = page.locator("#password")
      // Codex's error state: the control's own border turns red (the
      // focused one shows the focus ring over it).
      let redBorder = try await password.evaluate(
        """
        async (el) => {
          // Past the border's colour transition.
          await new Promise((resolve) => setTimeout(resolve, 500));
          const probe = document.createElement('div');
          probe.style.color = 'var(--border-color-red)';
          document.body.append(probe);
          const red = getComputedStyle(probe).color;
          probe.remove();
          return el.closest('.text-input-view').classList.contains('text-input-error')
            && getComputedStyle(el).borderTopColor === red;
        }
        """)
      #expect(redBorder.bool == true, "the empty password field is not drawn in its red error state")

      try await expect(page.locator("#password-validation-message")).toHaveText("Enter your password.")
      try await expect(password).toHaveAttribute("aria-invalid", "true")

      // Refused before the page's own handler: no request, no alert.
      try await expect(page.locator(".sign-in-alerts .alert-view")).toHaveCount(0)
      try await expect(page).toHaveURL("the sign-in page") { $0.path == "/auth/sign-in" }

      // Touched now: the message goes as soon as the field is fixed.
      try await identity.fill("a")
      try await expect(identityMessage).toHaveCount(0)
      #expect(try await identity.getAttribute("aria-invalid") == nil)
      #expect(try await identity.getAttribute("aria-describedby") == nil)
      // …and comes back when it is emptied again.
      try await identity.fill("")
      try await expect(identityMessage).toHaveText("Enter your email or username.")

      try await page.expectNoErrors()
      try await page.expectNoHorizontalOverflow()
    }
  }

  @Test(arguments: gnorium.engines)
  func registerNamesEachBrokenRule(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine)) { page in
      try await page.openHydrated("/auth/register")
      try await page.locator("#username").fill("ab")
      try await page.locator("#email").fill("not-an-email")
      try await page.locator("#password").fill("one")
      try await page.locator("#confirmPassword").fill("two")
      try await page.locator("form.register-form button[type='submit']").click()

      try await expect(page.locator("#first-name-validation-message")).toHaveText("Enter your first name.")
      try await expect(page.locator("#first-name")).toBeFocused()
      try await expect(page.locator("#username-validation-message")).toHaveText("A username is 3–20 characters.")
      try await expect(page.locator("#email-validation-message")).toHaveText("Enter a valid email address.")
      try await expect(page.locator("#confirmPassword-validation-message")).toHaveText("The passwords don't match.")
      try await expect(page.locator("#terms-and-policy-validation-message")).toHaveText(
        "Agree to the Terms of Service and Privacy Policy to register.")
      try await expect(page.locator("#password-validation-message")).toHaveCount(0)

      // A confirmation follows the field it repeats.
      try await page.locator("#password").fill("two")
      try await expect(page.locator("#confirmPassword-validation-message")).toHaveCount(0)
      // The username's other rule.
      try await page.locator("#username").fill("Ab!")
      try await expect(page.locator("#username-validation-message")).toHaveText(
        "Use lowercase letters, digits, and underscores only.")

      try await expect(page.locator(".register-alerts .alert-view")).toHaveCount(0)
      try await page.expectNoErrors()
    }
  }
}
