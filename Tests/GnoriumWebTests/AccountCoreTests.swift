import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Every sidebar-less, centred-card page sits in `AccountCoreView`: one card,
/// the same width, padding and title on every page, centred both ways
/// between the site header and the footer, and never wider than the screen.
/// Nothing is submitted; the tokens below are fake.
@Suite("Account core")
struct AccountCoreTests {
  static let paths = [
    "/auth/sign-in",
    "/auth/register",
    // With no sign-in with Google waiting, the card says to start again.
    "/auth/choose-your-username",
    "/auth/forgot-password",
    "/auth/reset-password?token=not-a-real-token",
    "/admin-console/sign-in?error=invalid",
    "/auth/verify-email?token=not-a-real-token",
  ]

  /// The card's frame, measured in the page: its gaps to the header and the
  /// footer, its width and padding, its title's size and weight, and whether
  /// the page scrolls sideways.
  struct Frame: Decodable, CustomStringConvertible {
    let top: Double
    let bottom: Double
    let left: Double
    let right: Double
    let width: Double
    let padding: String
    let titleSize: String
    let titleWeight: String
    let titleAlign: String
    let overflow: Double

    var description: String {
      "top \(top), bottom \(bottom), left \(left), right \(right), width \(width), padding \(padding), title \(titleSize)/\(titleWeight)/\(titleAlign), overflow \(overflow)"
    }
  }

  static let measure = """
    (() => {
      const card = document.querySelector('.account-core-card').getBoundingClientRect();
      const header = document.querySelector('.navbar-view').getBoundingClientRect();
      const footer = document.querySelector('.layout-footer-wrapper').getBoundingClientRect();
      const style = getComputedStyle(document.querySelector('.account-core-card'));
      const title = getComputedStyle(document.querySelector('.account-core-title'));
      return {
        top: card.top - header.bottom,
        bottom: footer.top - card.bottom,
        left: card.left,
        right: document.documentElement.clientWidth - card.right,
        width: card.width,
        padding: style.padding,
        titleSize: title.fontSize,
        titleWeight: title.fontWeight,
        titleAlign: title.textAlign,
        overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      };
    })()
    """

  static func frame(of page: Page, at path: String) async throws -> Frame {
    // Some of these answer 400 (a fake token) and still draw the page.
    _ = try await page.goto(path, waitUntil: .load)
    try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")
    try await expect(page.locator(".account-core-card")).toBeVisible()
    return try await page.evaluate(measure, as: Frame.self)
  }

  static func check(_ frames: [(String, Frame)]) {
    for (path, frame) in frames {
      #expect(abs(frame.top - frame.bottom) <= 1, "\(path): the card is off centre: \(frame)")
      #expect(frame.overflow <= 0, "\(path): the page scrolls sideways: \(frame)")
      // 40 in at full width; 24 on a phone, where the card is narrower
      // than its 480 and "Continue with Google" must keep to one line.
      #expect(frame.padding == (frame.width >= 480 ? "40px" : "24px"), "\(path): \(frame)")
      #expect(frame.titleSize == "28px", "\(path): \(frame)")
      #expect(frame.titleWeight == "400", "\(path): \(frame)")
      #expect(frame.titleAlign == "center", "\(path): \(frame)")
      #expect(abs(frame.left - frame.right) <= 1, "\(path): the card is off centre sideways: \(frame)")
      #expect(frame.width <= 480.5, "\(path): the card is wider than 480: \(frame)")
      // The same width on every page.
      #expect(abs(frame.width - frames[0].1.width) <= 1, "\(path): \(frame.width) wide, \(frames[0].0) is \(frames[0].1.width)")
    }
  }

  @Test(arguments: gnorium.engines, Layout.allCases)
  func everyCardIsTheSameAndCentred(engine: BrowserEngine, layout: Layout) async throws {
    let viewport = layout.viewport(for: engine)
    try await withPage(engine, gnorium, viewport: viewport) { page in
      var frames: [(String, Frame)] = []
      for path in Self.paths {
        frames.append((path, try await Self.frame(of: page, at: path)))
      }
      Self.check(frames)
      // The admin console's refusal is drawn, at the top of the card; text
      // that isn't one of its codes never is.
      _ = try await page.goto("/admin-console/sign-in?error=invalid", waitUntil: .load)
      try await expect(page.locator(".account-core-card .page-alerts .alert-view")).toBeVisible()
      _ = try await page.goto("/admin-console/sign-in?error=Call+this+number", waitUntil: .load)
      try await expect(page.locator(".account-core-card .page-alerts .alert-view")).toHaveCount(0)
    }
  }

  /// Change password and Delete account are signed in only.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func changePasswordIsTheSameCard(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let viewport = layout.viewport(for: engine)
    do {
      try await withPage(engine, gnorium, viewport: viewport, cookies: [admin.cookie]) { page in
        // Beside Forgot password's, so the width is compared too.
        Self.check([
          ("/auth/forgot-password", try await Self.frame(of: page, at: "/auth/forgot-password")),
          ("/account/password", try await Self.frame(of: page, at: "/account/password")),
          ("/account/delete", try await Self.frame(of: page, at: "/account/delete")),
        ])
      }
    } catch {
      await admin.remove()
      throw error
    }
    await admin.remove()
  }
}
