import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A record page's testament tree is the shared tree, drawn flat as a
/// thread is (user, 2026-11-03): no card, no rule and no indent. Each
/// node's number stands centered on the tree's spine, as a locution's
/// avatar, as wide as that number is, and is its fold control
/// ("Collapse testament 1."); its heading, which folds nothing and has no
/// chevron, and its body start right after its own number, 8px on, so a
/// deeper node's start further in. A node's stretch of the spine runs from
/// directly under its number's scrim beside what it would fold, darkens
/// under the pointer, and a click on it, at its very top too, folds the
/// node; closed, a node has none. Below the tree's last node the spine
/// runs on a little, fading out: that node's own stretch, open or closed,
/// which folds it too. Closing a row hides the rows under it with its body;
/// opening it shows them again. The fixture work holds an
/// edition and its manifest.
@Suite("Record tree", .serialized)
struct RecordTreeTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aRowsOwnChevronCollapsesTheRowsUnderIt(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated(work.path)
        let tree = page.locator(".outliner-view").first
        let edition = tree.locator(".outliner-item[data-outliner-id^='edition-']").first
        let manifest = tree.locator(".outliner-item[data-outliner-id^='manifest-']").first
        try await expect(edition).toHaveAttribute("data-outliner-accordion", "true")
        try await expect(tree.locator(".outliner-toggle")).toHaveCount(0)
        try await expect(manifest).toBeVisible()

        // No toggle column, no card, no rule and no indent: every number
        // centered on the spine, as wide as it is ("1." narrower than
        // "1.1."), and every heading right after its own number, 8px on.
        let list = try #require(try await tree.locator(":scope > .outliner-list").boundingBox())
        let spineLeft = try #require(
          try await tree.locator(":scope > .outliner-list").evaluate(
            "(list) => parseFloat(getComputedStyle(list, '::before').left)"
          ).double)
        let spineX = list.x + spineLeft + 0.5
        let fold = edition.locator(":scope > .outliner-row .record-node-fold").first
        let innerFold = manifest.locator(":scope > .outliner-row .record-node-fold").first
        let number = try #require(try await fold.boundingBox())
        let innerNumber = try #require(try await innerFold.boundingBox())
        let anchor = try #require(
          try await edition.locator(":scope > .outliner-row .record-node-anchor").first.boundingBox())
        let innerAnchor = try #require(
          try await manifest.locator(":scope > .outliner-row .record-node-anchor").first.boundingBox())
        let top = try #require(
          try await edition.locator(":scope > .outliner-row .accordion-summary").first.boundingBox())
        let under = try #require(
          try await manifest.locator(":scope > .outliner-row .accordion-summary").first.boundingBox())
        #expect(
          abs(number.x + number.width / 2 - spineX) < 1 && abs(innerNumber.x + innerNumber.width / 2 - spineX) < 1,
          "a number is not centered on the spine: \(number.x + number.width / 2), \(innerNumber.x + innerNumber.width / 2), \(spineX)")
        #expect(innerNumber.width > number.width + 1, "a number is not as wide as it is")
        #expect(innerAnchor.width > anchor.width + 1, "the numbers stand in one column")
        #expect(number.width <= anchor.width + 0.5 && innerNumber.width <= innerAnchor.width + 0.5, "a number overflows its place")
        #expect(abs(top.x - (anchor.x + anchor.width + 8)) < 1, "the heading does not start right after its number")
        #expect(abs(under.x - (innerAnchor.x + innerAnchor.width + 8)) < 1, "the heading under it does not start right after its number")
        let frame = try await edition.evaluate(
          """
          (item) => {
            const s = getComputedStyle(item)
            const own = getComputedStyle(item.querySelector(':scope > .outliner-row [data-outliner-own-accordion=true]'))
            return [s.borderTopWidth, s.borderLeftWidth, s.borderBottomWidth, own.borderTopWidth, own.borderLeftWidth].join(' ')
          }
          """).string
        #expect(frame == "0px 0px 0px 0px 0px", "a node is unframed and unruled: \(String(describing: frame))")
        // Its number is its fold control, named for what a press does.
        try await expect(fold).toHaveAttribute("aria-label", "Collapse testament 1.")
        try await expect(fold).toHaveAttribute("aria-expanded", "true")
        try await expect(innerFold).toHaveAttribute("aria-label", "Expand testament 1.1.")

        // The spine: one line down the tree, a thread's, in far enough for
        // the widest number's half, from under the first number (never
        // above it or through it) to 16px past the last node's foot.
        let spine = try await tree.locator(":scope > .outliner-list").evaluate(
          """
          (list) => {
            const s = getComputedStyle(list, '::before')
            const first = list.querySelector('.record-node-fold').getBoundingClientRect()
            return [s.width, parseFloat(s.left) >= 0,
              Math.abs(list.getBoundingClientRect().top + parseFloat(s.top) - first.bottom) < 1,
              Math.round(parseFloat(s.bottom))].join(' ')
          }
          """).string
        #expect(spine == "1px true true -16", "the tree has no continuous spine: \(String(describing: spine))")
        #expect(innerNumber.x >= list.x - 0.5, "the widest number does not fit left of the spine's start")

        // A node's stretch of it: from directly under its number's scrim (a
        // large control's height round its line, a medium one's on a phone)
        // beside its body and the rows under it, darkening under the
        // pointer.
        let rail = edition.locator(":scope > .outliner-rail")
        try await expect(rail).toHaveAttribute("aria-hidden", "true")
        try await expect(rail).toHaveCSS("cursor", "pointer")
        let railBox = try #require(try await rail.boundingBox())
        let inner = try #require(try await manifest.boundingBox())
        #expect(abs(railBox.x + railBox.width / 2 + 0.5 - spineX) < 1, "the rail is not on the spine")
        let scrim: Double = layout.viewport(for: engine).width < 480 ? 40 : 48
        #expect(
          abs(railBox.y - (number.y + number.height / 2 + scrim / 2)) < 1,
          "the rail does not start directly under the number's scrim")
        #expect(railBox.y + railBox.height >= inner.y + inner.height, "the rail stops short of the rows under it")
        // The closed manifest has nothing to fold: no stretch of its own.
        try await expect(manifest.locator(":scope > .outliner-rail")).toBeHidden()
        // The edition, the tree's last node: its stretch runs on below it,
        // fading out, as the spine does.
        try await Self.expectHanging(below: edition)
        let line = rail.locator(".rail-line")
        let resting = try await line.evaluate("(l) => getComputedStyle(l).backgroundColor").string
        _ = try await rail.evaluate(
          "(rail) => { window.scrollBy(0, rail.getBoundingClientRect().top - innerHeight / 2); return true }")
        let shown = try #require(try await rail.boundingBox())
        // Its very top, directly under the number: the stretch, whole.
        let topmost = (x: shown.x + shown.width / 2, y: shown.y + 1)
        try await page.mouse.move(x: topmost.x, y: topmost.y)
        let hovered = try await line.evaluate("(l) => getComputedStyle(l).backgroundColor").string
        #expect(resting != hovered, "the stretch does not darken under the pointer: \(String(describing: resting))")

        // Its heading folds nothing, and has no chevron.
        let summary = edition.locator(":scope > .outliner-row > .outliner-node .accordion-summary").first
        try await expect(summary.locator(".accordion-expand-icon")).toBeHidden()
        try await summary.click()
        try await expect(edition).toHaveAttribute("data-outliner-collapsed", "false")
        try await expect(manifest).toBeVisible()
        // Its body starts where its heading does.
        let body = try #require(
          try await edition.locator(":scope > .outliner-row .accordion-content-clip").first.boundingBox())
        #expect(abs(body.x - top.x) < 1, "the body does not start where its heading does: \(body.x - top.x)px")
        // Its number: closed, the rows under it go with its body.
        try await fold.click()
        try await expect(edition).toHaveAttribute("data-outliner-collapsed", "true")
        try await expect(manifest).toBeHidden()
        try await expect(fold).toHaveAttribute("aria-label", "Expand testament 1.")
        try await fold.click()
        try await expect(edition).toHaveAttribute("data-outliner-collapsed", "false")
        try await expect(manifest).toBeVisible()
        // Its stretch folds it the same way, from its very top; folded, it
        // has none, and its number opens it again.
        try await page.mouse.click(x: topmost.x, y: topmost.y)
        try await expect(edition).toHaveAttribute("data-outliner-collapsed", "true")
        try await expect(manifest).toBeHidden()
        // Closed, the last node's stretch is the part hanging below it
        // alone, and a click there opens it again.
        try await Self.expectHanging(below: edition)
        let hanging = try #require(try await rail.boundingBox())
        try await page.mouse.click(x: hanging.x + hanging.width / 2, y: hanging.y + 4)
        try await expect(edition).toHaveAttribute("data-outliner-collapsed", "false")
        try await expect(manifest).toBeVisible()
        try await fold.click()
        try await expect(edition).toHaveAttribute("data-outliner-collapsed", "true")
        try await fold.click()
        try await expect(edition).toHaveAttribute("data-outliner-collapsed", "false")
        try await expect(manifest).toBeVisible()
        try await expect(fold).toHaveAttribute("aria-expanded", "true")
        // A node's Metadata holds its fields alone (user, 2026-10-09): no
        // image count, no other fact that is none of its fields.
        try await expect(tree.locator(".record-node-metadata > .datum-view")).toHaveCount(0)
        try await expect(tree.locator(".record-node-metadata").getByText("Images", exact: true)).toHaveCount(0)
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      work.remove()
      try await admin.remove(after: error)
    }
    work.remove()
    try await admin.remove()
  }

  /// The tree's last node: its stretch (its rail) runs 16px on below its
  /// foot, as the spine does, both fading out to nothing there, and folds
  /// it under the pointer.
  static func expectHanging(below item: Locator) async throws {
    let hang = try await item.evaluate(
      """
      (item) => {
        const rail = item.querySelector(':scope > .outliner-rail');
        const list = item.closest('.outliner-view > .outliner-list');
        const r = rail.getBoundingClientRect(), i = item.getBoundingClientRect();
        const spine = getComputedStyle(list, '::before');
        const mask = getComputedStyle(rail.querySelector('.rail-line')).maskImage
          || getComputedStyle(rail.querySelector('.rail-line')).webkitMaskImage;
        return [getComputedStyle(rail).cursor, Math.round(r.bottom - i.bottom),
          Math.round(parseFloat(spine.bottom)), /rgba.0, 0, 0, 0.|transparent/.test(spine.backgroundImage), /rgba.0, 0, 0, 0.|transparent/.test(mask)].join(' ');
      }
      """
    ).string
    #expect(hang == "pointer 16 -16 true true", "the last node's stretch does not hang below it, fading: \(String(describing: hang))")
  }
}
