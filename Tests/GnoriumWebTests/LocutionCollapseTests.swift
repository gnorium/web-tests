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
  /// has ended, and the byline's gap to it at the same moments: [before,
  /// during, after, gap before, gap during, gap after].
  static func press(_ locutionID: String) -> String {
    """
    (async () => {
      const root = document.getElementById('locution-\(locutionID.uppercased())');
      const fold = root.querySelector('.locution-fold');
      const height = () => fold.getBoundingClientRect().height;
      const gap = () => parseFloat(getComputedStyle(root.querySelector('.locution-content')).rowGap);
      const before = height(), gapBefore = gap();
      root.querySelector('.locution-collapse').click();
      await new Promise(r => setTimeout(r, 100));
      const during = height(), gapDuring = gap();
      await new Promise(r => setTimeout(r, 600));
      return [before, during, height(), gapBefore, gapDuring, gap()];
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
        try await expect(page.locator(".thread-event .locution-collapse")).toHaveCount(0)

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
        // The byline's gap folds on the same clock: 8, between, 0.
        #expect(folding[3] == 8 && folding[4] > 0 && folding[4] < 8 && folding[5] == 0, "The gap folds with it: \(folding)")
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
        #expect(opening[3] == 0 && opening[4] > 0 && opening[4] < 8 && opening[5] == 8, "The gap opens with it: \(opening)")
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

  /// The section's toggle folds the whole thread over each locution's own
  /// fold, never into it (user, 2026-10-18): one folded by its avatar,
  /// then all folded and opened again, is still folded; the others open.
  @Test(arguments: [BrowserEngine.chrome])
  func expandAllReturnsEachLocutionToItsOwnFold(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let reader = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let scratch: ScratchCommit
    do { scratch = try ScratchCommit(owner: reader) } catch { try await reader.remove(after: error) }
    let openID = UUID().uuidString.lowercased()
    let foldedID = UUID().uuidString.lowercased()
    func removeLocutions() {
      _ = try? TestAdmin.query("DELETE FROM locutions WHERE id IN ('\(openID)', '\(foldedID)');")
    }
    do {
      let readerID = try reader.column("id")
      let madrigalID = scratch.madrigalID.lowercased()
      _ = try TestAdmin.query(
        """
        INSERT INTO locutions (id, locutable_type, locutable_id, author_id, content, created_at)
          VALUES ('\(openID)', 'bibliographic_madrigal', '\(madrigalID)', '\(readerID)',
                  'The long s is consistent.', now() - interval '1 minute'),
                 ('\(foldedID)', 'bibliographic_madrigal', '\(madrigalID)', '\(readerID)',
                  'The catchword is misread.', now());
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [reader.cookie]) { page in
        try await page.openHydrated(scratch.madrigalPath)
        let open = page.locator("#locution-\(openID.uppercased())")
        let folded = page.locator("#locution-\(foldedID.uppercased())")
        let toggle = page.locator(".thread-collapse")
        let section = page.locator(".thread-view")
        let content = page.locator(".thread-section-content")
        let count = page.locator(".thread-count")
        try await expect(toggle).toHaveAttribute("aria-expanded", "true")
        try await expect(toggle).toHaveAttribute("aria-label", "Collapse locutions")
        try await expect(content).toBeVisible()

        // One locution folded by its avatar, inside the open section.
        try await folded.locator("button.locution-collapse").click()
        try await expect(folded).toHaveAttribute("data-collapsed", "true")
        try await expect(open).toHaveAttribute("data-collapsed", "false")

        // The section folds with a motion: partway shortly after the press.
        let motion = try await page.evaluate(
          """
          (async () => {
            const clip = document.querySelector('.thread-section');
            const before = clip.getBoundingClientRect().height;
            document.querySelector('.thread-collapse').click();
            await new Promise(r => setTimeout(r, 100));
            const during = clip.getBoundingClientRect().height;
            await new Promise(r => setTimeout(r, 600));
            return [before, during, clip.getBoundingClientRect().height];
          })()
          """, as: [Double].self)
        #expect(motion[0] > 0 && motion[2] == 0, "Open, then folded: \(motion)")
        #expect(motion[1] > 0 && motion[1] < motion[0], "Mid-fold, a height between: \(motion)")
        try await expect(section).toHaveAttribute("data-section-collapsed", "true")
        try await expect(toggle).toHaveAttribute("aria-expanded", "false")
        try await expect(toggle).toHaveAttribute("aria-label", "Expand locutions")
        try await expect(content).toBeHidden()
        try await expect(open).toBeHidden()
        try await expect(page.locator("#thread-form")).toBeHidden()
        // The count stays.
        try await expect(count).toBeVisible()
        try await expect(count).toHaveText("2")

        // Kept for the session across a reload and another visit of the page
        // kind (what a roster row switch does to the thread).
        _ = try await page.reload()
        try await expect(page.locator("html"), timeout: .seconds(20))
          .toHaveAttribute("data-wasm-status", "started")
        try await expect(toggle).toHaveAttribute("aria-expanded", "false")
        try await expect(content).toBeHidden()
        try await expect(count).toBeVisible()
        try await page.openHydrated(scratch.madrigalPath + "?roster=other")
        try await expect(toggle).toHaveAttribute("aria-expanded", "false")
        try await expect(content).toBeHidden()

        // Opened: every locution as its own fold left it.
        try await toggle.click()
        try await expect(section).toHaveAttribute("data-section-collapsed", "false")
        try await expect(section).toHaveAttribute("data-section-motion", "idle")
        try await expect(toggle).toHaveAttribute("aria-expanded", "true")
        try await expect(open.locator(".locution-body")).toBeVisible()
        try await expect(page.locator("#thread-form")).toBeVisible()
        try await expect(folded).toHaveAttribute("data-collapsed", "true")
        try await expect(folded.locator("button.locution-collapse")).toHaveAttribute("aria-expanded", "false")
        // A locution's own toggle still works inside the open section.
        try await folded.locator("button.locution-collapse").click()
        try await expect(folded).toHaveAttribute("data-collapsed", "false")
        try await page.expectNoErrors()
      }
    } catch {
      removeLocutions()
      scratch.remove()
      try await reader.remove(after: error)
    }
    removeLocutions()
    scratch.remove()
    try await reader.remove()
  }

  /// A section of more than a page is paged, a hundred entries each, oldest
  /// first: it opens on the last page (the newest), the pager sits at the
  /// bottom right inside the collapsible body, the count badge keeps the
  /// whole, `?locutions=1` opens the first page, and only the page asked
  /// for is in the document.
  @Test(arguments: [BrowserEngine.chrome])
  func aLongSectionIsPagedAndOpensOnItsLastPage(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let reader = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let scratch: ScratchCommit
    do { scratch = try ScratchCommit(owner: reader) } catch { try await reader.remove(after: error) }
    let madrigalID = scratch.madrigalID.lowercased()
    let firstID = UUID().uuidString.lowercased()
    let lastID = UUID().uuidString.lowercased()
    func removeLocutions() {
      _ = try? TestAdmin.query("DELETE FROM locutions WHERE locutable_id = '\(madrigalID)';")
    }
    do {
      let readerID = try reader.column("id")
      _ = try TestAdmin.query(
        """
        INSERT INTO locutions (id, locutable_type, locutable_id, author_id, content, created_at)
          SELECT CASE n WHEN 1 THEN '\(firstID)'::uuid WHEN 150 THEN '\(lastID)'::uuid ELSE gen_random_uuid() END,
                 'bibliographic_madrigal', '\(madrigalID)', '\(readerID)',
                 'Locution ' || n, now() - ((150 - n) || ' seconds')::interval
          FROM generate_series(1, 150) AS n;
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [reader.cookie]) { page in
        try await page.openHydrated(scratch.madrigalPath)
        let pager = page.locator(".thread-section-content .thread-pages .pagination-view")
        try await expect(pager).toBeVisible()
        // Newest page: 50 of 150, in the document; the badge is the whole.
        try await expect(page.locator(".thread-timeline .locution-view")).toHaveCount(50)
        try await expect(page.locator(".thread-count")).toHaveText("150")
        try await expect(page.locator("text=Locution 150")).toBeVisible()
        try await expect(page.locator("text=Locution 1 ").first).toHaveCount(0)

        // The footer reads as the tables': the range at the start, the pager
        // at the end.
        try await expect(page.locator(".pagination-info")).toHaveText("101–150 of 150 locutions")
        try await expect(page.locator(".table-pagination-controls")).toBeVisible()

        // A link to an item on another page opens the page holding it.
        try await page.openHydrated(scratch.madrigalPath + "#locution-\(firstID.uppercased())")
        try await expect(page.locator("#locution-\(firstID.uppercased())")).toBeInViewport()
        try await expect(page.locator(".pagination-info")).toHaveText("1–100 of 150 locutions")
        // And back to the last page for the newest: where a posted reply or
        // any new item lands (the page after posting has no page asked for).
        try await page.openHydrated(scratch.madrigalPath + "#locution-\(lastID.uppercased())")
        try await expect(page.locator("#locution-\(lastID.uppercased())")).toBeInViewport()
        try await expect(page.locator(".pagination-info")).toHaveText("101–150 of 150 locutions")

        // The first page by its query: a hundred.
        try await page.openHydrated(scratch.madrigalPath + "?locutions=1")
        try await expect(page.locator(".thread-timeline .locution-view")).toHaveCount(100)
        try await expect(page.locator(".thread-count")).toHaveText("150")
        // A locution's own fold still works there.
        let first = page.locator(".thread-timeline .locution-view").first
        try await first.locator("button.locution-collapse").click()
        try await expect(first).toHaveAttribute("data-collapsed", "true")

        // Folding the section hides the pager with the rest.
        try await page.locator(".thread-collapse").click()
        try await expect(pager).toBeHidden()
        try await expect(page.locator(".thread-count")).toBeVisible()
        try await page.locator(".thread-collapse").click()
        try await expect(pager).toBeVisible()
        try await page.expectNoErrors()
      }
    } catch {
      removeLocutions()
      scratch.remove()
      try await reader.remove(after: error)
    }
    removeLocutions()
    scratch.remove()
    try await reader.remove()
  }
}
