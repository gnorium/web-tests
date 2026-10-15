import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A locution folds to its byline from its avatar, as a thread folds a
/// comment: hovered, a scrim over the avatar shows the chevron; pressed—by
/// mouse, Enter or Space—the words, attachments, session, actions and
/// footer fold away with the accordion's motion, the byline stays; the
/// fold is kept for the session, so a reload reads the thread as it was
/// left. The thread's acts do not fold.
@Suite("Locution collapse", .serialized)
struct LocutionCollapseTests {
  /// Presses the locution's avatar in the page and reads its fold's height
  /// before, 100ms in (the motion is the accordion's 250ms), and once it
  /// has ended: [before, during, after].
  static func press(_ locutionID: String) -> String {
    """
    (async () => {
      const root = document.getElementById('locution-\(locutionID.uppercased())');
      const fold = root.querySelector('.locution-fold');
      const height = () => fold.getBoundingClientRect().height;
      const before = height();
      root.querySelector('.locution-collapse').click();
      await new Promise(r => setTimeout(r, 100));
      const during = height();
      await new Promise(r => setTimeout(r, 600));
      return [before, during, height()];
    })()
    """
  }

  @Test(arguments: [BrowserEngine.chrome])
  func theAvatarFoldsALocutionToItsByline(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let reader = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let scratch: ScratchCommit
    do { scratch = try ScratchCommit(owner: reader) } catch { try await reader.remove(after: error) }
    let locutionID = UUID().uuidString.lowercased()
    func removeLocution() {
      _ = try? TestAdmin.query("DELETE FROM locutions WHERE id = '\(locutionID)';")
    }
    do {
      let readerID = try reader.column("id")
      _ = try TestAdmin.query(
        """
        INSERT INTO locutions (id, locutable_type, locutable_id, author_id, content, created_at)
          VALUES ('\(locutionID)', 'bibliographic_madrigal', '\(scratch.madrigalID.lowercased())', '\(readerID)',
                  'The long s is consistent through the page.', now());
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [reader.cookie]) { page in
        try await page.openHydrated(scratch.madrigalPath)
        let locution = page.locator("#locution-\(locutionID.uppercased())")
        let toggle = locution.locator("button.locution-collapse")
        let overlay = toggle.locator(".locution-collapse-overlay")
        let body = locution.locator(".locution-body")
        let header = locution.locator(".locution-header")
        try await expect(toggle).toHaveAttribute("aria-expanded", "true")
        try await expect(toggle).toHaveAttribute("aria-label", "Collapse locution")
        try await expect(body).toBeVisible()
        // The acts beside it do not fold.
        try await expect(page.locator(".locution-thread-event .locution-collapse")).toHaveCount(0)

        // Hovered, the scrim and its chevron cover the avatar.
        try await expect(overlay).toHaveCSS("display", "none")
        try await toggle.hover()
        try await expect(overlay).toHaveCSS("display", "flex")
        let chevron = overlay.locator(".animated-right-down-chevron-view")
        try await expect(chevron).toBeVisible()
        try await expect(chevron).toHaveAttribute("data-expanded", "true")

        // Pressed: it folds as an accordion does—partway shortly after the
        // press, strictly between its open height and 0—then the byline alone.
        let folding = try await page.evaluate(Self.press(locutionID), as: [Double].self)
        #expect(folding[0] > 0 && folding[2] == 0, "Open, then folded: \(folding)")
        #expect(folding[1] > 0 && folding[1] < folding[0], "Mid-fold, a height between: \(folding)")
        try await expect(locution).toHaveAttribute("data-collapsed", "true")
        try await expect(locution).toHaveAttribute("data-motion", "idle")
        try await expect(toggle).toHaveAttribute("aria-expanded", "false")
        try await expect(toggle).toHaveAttribute("aria-label", "Expand locution")
        try await expect(body).toBeHidden()
        try await expect(locution.locator(".reactions-view")).toBeHidden()
        try await expect(header).toBeVisible()
        try await expect(chevron).toHaveAttribute("data-expanded", "false")

        // Kept for the session: a reload reads it folded.
        _ = try await page.reload()
        try await expect(page.locator("html"), timeout: .seconds(20))
          .toHaveAttribute("data-wasm-status", "started")
        try await expect(toggle).toHaveAttribute("aria-expanded", "false")
        try await expect(body).toBeHidden()
        try await expect(header).toBeVisible()

        // The keyboard: Enter opens it, Space folds it, Enter opens it again.
        try await toggle.press("Enter")
        try await expect(toggle).toHaveAttribute("aria-expanded", "true")
        try await expect(body).toBeVisible()
        try await toggle.press("Space")
        try await expect(toggle).toHaveAttribute("aria-expanded", "false")
        try await expect(body).toBeHidden()
        try await toggle.press("Enter")
        try await expect(toggle).toHaveAttribute("aria-label", "Collapse locution")
        try await expect(locution).toHaveAttribute("data-collapsed", "false")
        try await expect(body).toBeVisible()
        try await expect(locution.locator(".reactions-view")).toBeVisible()

        // Opening moves the same way back: partway, then whole.
        try await toggle.press("Enter")
        try await expect(toggle).toHaveAttribute("aria-expanded", "false")
        try await expect(locution).toHaveAttribute("data-motion", "idle")
        let opening = try await page.evaluate(Self.press(locutionID), as: [Double].self)
        #expect(opening[0] == 0 && opening[2] > 0, "Folded, then open: \(opening)")
        #expect(opening[1] > 0 && opening[1] < opening[2], "Mid-open, a height between: \(opening)")
        try await expect(toggle).toHaveAttribute("aria-expanded", "true")
        try await expect(body).toBeVisible()

        // Expanded, it stays so across a reload.
        _ = try await page.reload()
        try await expect(page.locator("html"), timeout: .seconds(20))
          .toHaveAttribute("data-wasm-status", "started")
        try await expect(toggle).toHaveAttribute("aria-expanded", "true")
        try await expect(body).toBeVisible()
        try await page.expectNoErrors()
      }
    } catch {
      removeLocution()
      scratch.remove()
      try await reader.remove(after: error)
    }
    removeLocution()
    scratch.remove()
    try await reader.remove()
  }
}
