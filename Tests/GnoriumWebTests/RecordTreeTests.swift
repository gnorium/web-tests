import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A record page's testament tree is the shared tree, drawn flat as a
/// thread is (user, 2026-11-03): no card, no rule and no indent. One spine
/// runs down the tree's start through every node's marker, a disc a
/// locution's avatar's size (40, 32 on a phone), which breaks it and is the node's fold
/// control ("Collapse testament 1."), its scrim showing its chevron under
/// the pointer and folded. Right after the marker the node is one column,
/// its heading (its value's box alone, its number, date and info the
/// box's columns) and its body at one x whatever its number; its heading
/// folds nothing, nor does its info, which opens its tooltip. A node's stretch of the spine runs
/// from under its marker beside what it would fold, darkens under the
/// pointer, and a click on it, at its very top too, folds the node. Below
/// the marker of the tree's last node in sight, at any depth, open or
/// folded, the line hangs from no node: dashed whole, on a little past the
/// tree's foot, that node's stretch, which folds or opens it too. Closing a row hides the rows under it with its
/// body; opening it shows them again. The fixture work holds an edition
/// and its manifest.
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

        // No toggle column, no card, no rule and no indent: every marker
        // on the spine, an avatar's disc (40, 32 on a phone); every
        // heading, its number first, and every body right after the
        // marker, 16px on, at one x.
        let disc: Double = layout.viewport(for: engine).width < 480 ? 32 : 40
        let list = try #require(try await tree.locator(":scope > .outliner-list").boundingBox())
        let spineLeft = try #require(
          try await tree.locator(":scope > .outliner-list").evaluate(
            "(list) => parseFloat(getComputedStyle(list, '::before').left)"
          ).double)
        let spineX = list.x + spineLeft + 0.5
        let fold = edition.locator(":scope > .outliner-row .outliner-marker").first
        let innerFold = manifest.locator(":scope > .outliner-row .outliner-marker").first
        let marker = try #require(try await fold.boundingBox())
        let innerMarker = try #require(try await innerFold.boundingBox())
        #expect(abs(marker.width - disc) < 0.5 && abs(marker.height - disc) < 0.5, "the marker is no avatar's disc: \(marker)")
        #expect(abs(marker.x - innerMarker.x) < 0.5, "the markers do not stand at one x")
        #expect(abs(marker.x + marker.width / 2 - spineX) < 1, "the spine does not run through the marker: \(marker.x), \(spineX)")
        let top = try #require(
          try await edition.locator(":scope > .outliner-row .record-node-heading").first.boundingBox())
        let under = try #require(
          try await manifest.locator(":scope > .outliner-row .record-node-heading").first.boundingBox())
        #expect(abs(top.x - (marker.x + marker.width + 16)) < 1, "the heading does not start right after its marker")
        #expect(abs(under.x - top.x) < 1, "the headings do not start at one x: \(top.x), \(under.x)")
        // Its number inside its value's box (user, 2026-11-03): the box's
        // first column, subtle, on the value's first line, the value's
        // words in the column after it; none of its own in the heading.
        let heading = edition.locator(":scope > .outliner-row .record-node-heading").first
        try await expect(heading.locator(":scope > .record-node-number")).toHaveCount(0)
        let column = try await heading.evaluate(
          """
          (h) => {
            const box = h.querySelector('.node-value-box')
            const number = box.firstElementChild
            const text = box.querySelector(':scope > .node-value-text')
            const n = number.getBoundingClientRect(), t = text.getBoundingClientRect()
            const probe = document.createElement('span')
            probe.style.color = 'var(--color-subtle)'
            h.appendChild(probe)
            const subtle = getComputedStyle(probe).color
            probe.remove()
            return [number.className, number.textContent, Math.abs(n.top - t.top) < 1, n.right <= t.left,
              getComputedStyle(number).color === subtle].join(' ')
          }
          """).string
        #expect(column == "node-value-number record-node-number outliner-number 1. true true true", "the number is not the box's first column: \(String(describing: column))")
        // The rest of the heading in the box too (user, 2026-11-03): its
        // date and its info its last columns, on the value's first line,
        // the value's words ending before them; the heading the box alone.
        let ends = try await heading.evaluate(
          """
          (h) => {
            const box = h.querySelector('.node-value-box')
            const info = box.lastElementChild, date = box.querySelector(':scope > .node-value-date')
            const b = box.getBoundingClientRect(), i = info.getBoundingClientRect()
            const t = box.querySelector(':scope > .node-value-text').getBoundingClientRect()
            return [info.classList.contains('node-value-info'), h.children.length,
              i.left >= b.left && i.right <= b.right, Math.abs(i.top - t.top) < 1,
              t.right <= (date || info).getBoundingClientRect().left,
              !date || Math.abs(date.getBoundingClientRect().top - t.top) < 1].join(' ')
          }
          """).string
        #expect(ends == "true 1 true true true true", "the date and the info are not the box's last columns: \(String(describing: ends))")
        let frame = try await edition.evaluate(
          """
          (item) => {
            const s = getComputedStyle(item)
            const own = getComputedStyle(item.querySelector(':scope > .outliner-row [data-outliner-own-accordion=true]'))
            return [s.borderTopWidth, s.borderLeftWidth, s.borderBottomWidth, own.borderTopWidth, own.borderLeftWidth].join(' ')
          }
          """).string
        #expect(frame == "0px 0px 0px 0px 0px", "a node is unframed and unruled: \(String(describing: frame))")
        // Its marker is its fold control, named for what a press does, its
        // chevron down open and to the side folded; no chevron at its
        // heading's end.
        try await expect(edition.locator(":scope > .outliner-row .record-node-heading .animated-right-down-chevron-view")).toHaveCount(0)
        try await expect(fold.locator(".animated-right-down-chevron-view")).toHaveAttribute("data-expanded", "true")
        try await expect(innerFold.locator(".animated-right-down-chevron-view")).toHaveAttribute("data-expanded", "false")
        try await expect(fold).toHaveAttribute("aria-label", "Collapse testament 1.")
        try await expect(fold).toHaveAttribute("aria-expanded", "true")
        try await expect(innerFold).toHaveAttribute("aria-label", "Expand testament 1.1.")
        // Folded, its scrim stays over it; open, only under the pointer.
        try await expect(innerFold.locator(".outliner-marker-scrim")).toBeVisible()
        try await expect(fold.locator(".outliner-marker-scrim")).toBeHidden()
        // Ringed as a locution's avatar is (user, 2026-11-03): one 1px
        // border outside its disc, which keeps its full size, a control's
        // base border.
        let restRing = try await fold.discRing()
        #expect(restRing == "rest", "the marker is not ringed as an avatar is: \(restRing)")

        // The spine: one line down the tree's start, a thread's, through
        // the middle of every marker, solid from under the first marker to
        // the last node's in sight, where the dashed hang starts
        // (`expectHanging`).
        let spine = try await tree.locator(":scope > .outliner-list").evaluate(
          """
          (list) => {
            const s = getComputedStyle(list, '::before')
            const first = list.querySelector('.outliner-marker').getBoundingClientRect()
            return [s.width, parseFloat(s.left) >= 0,
              Math.abs(list.getBoundingClientRect().top + parseFloat(s.top) - first.bottom) < 1].join(' ')
          }
          """).string
        #expect(spine == "1px true true", "the tree has no continuous spine: \(String(describing: spine))")
        // The hang is the tree's own room (user, 2026-11-03): reserved at
        // its end, so nothing after the tree meets the fade.
        let room = try await tree.evaluate("(t) => getComputedStyle(t).paddingBottom").string
        #expect(room == "32px", "the tree keeps no room for its spine's hang: \(String(describing: room))")

        // A node's stretch of it: from directly under its marker, beside
        // its body and the rows under it, darkening under the pointer; the
        // last node's in sight, the hang, its own (user, 2026-11-05).
        let rail = edition.locator(":scope > .outliner-rail")
        try await expect(rail).toHaveAttribute("aria-hidden", "true")
        try await expect(rail).toHaveCSS("cursor", "pointer")
        let railBox = try #require(try await rail.boundingBox())
        #expect(abs(railBox.x + railBox.width / 2 + 0.5 - spineX) < 1, "the rail is not on the spine")
        #expect(abs(railBox.y - (marker.y + marker.height)) < 1, "the rail does not start directly under the marker")
        #expect(
          abs(railBox.y + railBox.height - (innerMarker.y + innerMarker.height)) < 1,
          "the rail does not run beside the rows under it to where the hang starts, and no further")
        // The closed manifest, the tree's last node in sight: its stretch is
        // the hang, from under its marker past the tree's foot, dashed
        // whole (user, 2026-11-05).
        try await Self.expectHanging(below: manifest)
        let line = rail.locator(".rail-line")
        let resting = try await line.evaluate("(l) => getComputedStyle(l).backgroundColor").string
        _ = try await rail.evaluate(
          "(rail) => { window.scrollBy(0, rail.getBoundingClientRect().top - innerHeight / 2); return true }")
        let shown = try #require(try await rail.boundingBox())
        // Its very top, directly under the marker: the stretch, whole.
        let topmost = (x: shown.x + shown.width / 2, y: shown.y + 1)
        try await page.mouse.move(x: topmost.x, y: topmost.y)
        let hovered = try await line.evaluate("(l) => getComputedStyle(l).backgroundColor").string
        #expect(resting != hovered, "the stretch does not darken under the pointer: \(String(describing: resting))")

        // Its heading folds nothing, and has no accordion chevron of its own.
        let summary = edition.locator(":scope > .outliner-row > .outliner-node .accordion-summary").first
        try await expect(summary.locator(".accordion-expand-icon")).toBeHidden()
        try await summary.click()
        try await expect(edition).toHaveAttribute("data-outliner-collapsed", "false")
        try await expect(manifest).toBeVisible()
        // Nor does its info, its own control: a click opens its tooltip.
        try await heading.locator(".node-value-info").first.click()
        try await expect(page.locator(".tooltip-view[data-portal='true'][data-visible='true'] .tooltip-content"))
          .toHaveCount(1)
        try await expect(edition).toHaveAttribute("data-outliner-collapsed", "false")
        try await expect(manifest).toBeVisible()
        try await page.keyboard.press("Escape")
        // One column: its body under its heading, from the tree's one x
        // right after the marker (its disc and 16px in, `OutlinerView.markerSpace`),
        // whatever its number.
        let bodyX = { (item: Locator) async throws -> Double in
          try #require(try await item.evaluate(
            "(i) => { const c = i.querySelector(':scope > .outliner-row .accordion-content'); return c.getBoundingClientRect().left + parseFloat(getComputedStyle(c).paddingInlineStart) - i.closest('.outliner-view > .outliner-list').getBoundingClientRect().left }"
          ).double)
        }
        let body = try await bodyX(edition)
        #expect(abs(body - (disc + 16)) < 1, "the body does not start right after the marker: \(body)px")
        _ = try await innerFold.evaluate("(f) => { f.click(); return true }")
        try await expect(manifest).toHaveAttribute("data-outliner-collapsed", "false")
        let innerBody = try await bodyX(manifest)
        #expect(abs(innerBody - body) < 1, "the bodies do not start at one x: \(body), \(innerBody)")
        _ = try await innerFold.evaluate("(f) => { f.click(); return true }")
        try await expect(manifest).toHaveAttribute("data-outliner-collapsed", "true")
        // Its marker: closed, the rows under it go with its body.
        try await fold.click()
        try await expect(edition).toHaveAttribute("data-outliner-collapsed", "true")
        try await expect(manifest).toBeHidden()
        try await expect(fold).toHaveAttribute("aria-label", "Expand testament 1.")
        try await fold.click()
        try await expect(edition).toHaveAttribute("data-outliner-collapsed", "false")
        try await expect(manifest).toBeVisible()
        // Its stretch folds it the same way, from its very top; folded, it
        // has none, and its chevron opens it again.
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
        // Folded, the manifest's stretch is the hang below the tree, and a
        // click there opens the manifest, as its chevron would, never folds
        // the edition (user, 2026-11-03); open, its stretch is still the
        // hang, dashed from under its marker beside its body.
        let manifestRail = manifest.locator(":scope > .outliner-rail")
        _ = try await manifestRail.evaluate(
          "(rail) => { window.scrollBy(0, rail.getBoundingClientRect().top - innerHeight / 2); return true }")
        let hang = try #require(try await manifestRail.boundingBox())
        try await page.mouse.click(x: hang.x + hang.width / 2, y: hang.y + 4)
        try await expect(manifest).toHaveAttribute("data-outliner-collapsed", "false")
        try await expect(edition).toHaveAttribute("data-outliner-collapsed", "false")
        try await Self.expectHanging(below: manifest)
        try await innerFold.click()
        try await expect(manifest).toHaveAttribute("data-outliner-collapsed", "true")
        // A node's Metadata holds its fields alone (user, 2026-10-09): no
        // image count, no other fact that is none of its fields.
        try await expect(tree.locator(".record-node-metadata > .datum-view")).toHaveCount(0)
        try await expect(tree.locator(".record-node-metadata").getByText("Frames", exact: true)).toHaveCount(0)
        // Focused from the keyboard, its ring is the focus ring every
        // control wears, as a locution's avatar's (user, 2026-11-03).
        try await fold.press("Enter")
        try await expect(edition).toHaveAttribute("data-outliner-collapsed", "true")
        try await fold.press("Enter")
        try await expect(edition).toHaveAttribute("data-outliner-collapsed", "false")
        let focusRing = try await fold.discRing()
        #expect(focusRing == "focus", "the focused marker does not wear the focus ring: \(focusRing)")
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      work.remove()
      try await admin.remove(after: error)
    }
    work.remove()
    try await admin.remove()
  }

  /// The tree's last node in sight: its stretch (its rail) is the hang
  /// (user, 2026-11-05), the whole of the line below where the node leaves
  /// it, hanging from no node: from directly under its marker to the
  /// line's end, 32px past its foot, one native dashed border its whole
  /// length, over no other line (the solid spine above it ends where it
  /// starts), and it folds or opens the node under the pointer.
  static func expectHanging(below item: Locator) async throws {
    let hang = try await item.evaluate(
      """
      (item) => {
        const rail = item.querySelector(':scope > .outliner-rail');
        const marker = item.querySelector(':scope > .outliner-row .outliner-marker').getBoundingClientRect();
        const list = item.closest('.outliner-view > .outliner-list');
        const r = rail.getBoundingClientRect(), i = item.getBoundingClientRect();
        const l = list.getBoundingClientRect();
        const near = (a, b) => Math.abs(a - b) < 1;
        const spine = getComputedStyle(list, '::before');
        const line = rail.querySelector('.rail-line');
        const drawn = getComputedStyle(line), d = line.getBoundingClientRect();
        return [getComputedStyle(rail).cursor,
          near(r.top, marker.bottom) ? 'from-marker' : `from ${r.top - marker.bottom}`,
          Math.round(r.bottom - i.bottom), near(d.top, r.top) && near(d.bottom, r.bottom),
          drawn.borderInlineStartStyle, drawn.borderInlineStartWidth, drawn.backgroundImage,
          spine.borderInlineStartStyle,
          near(l.bottom - parseFloat(spine.bottom), r.top) ? 'solid-to-hang' : `solid-to ${l.bottom - parseFloat(spine.bottom) - r.top}`,
          getComputedStyle(list, '::after').content].join(' ');
      }
      """
    ).string
    #expect(
      hang == "pointer from-marker 32 true dashed 1px none none solid-to-hang none",
      "the last node's stretch is not the whole hang, dashed: \(String(describing: hang))")
  }
}
