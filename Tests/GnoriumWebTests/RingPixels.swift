import Foundation
import Testing
import WebTests

/// The ring read off the screen, not the style sheet: a computed style
/// cannot say whether another layer paints over the inset outline, only
/// the pixels can. The screenshot is decoded in the page (a canvas) and
/// each side of the pane's box is sampled across its edge.
enum RingPixels {
  /// Per side, the device pixels of the ring color within a window across
  /// the edge, as a picture ("..XX...."), and the count of those pixels.
  struct Side: Decodable {
    var picture: String
    var count: Int
    var samples: String
  }

  struct Reading: Decodable {
    var scale: Double
    var top: Side
    var right: Side
    var bottom: Side
    var left: Side
  }

  /// Reads the pane's box of `.artifact-view` at `selector`'s ring color
  /// (a CSS variable name such as `--border-color-orange`).
  ///
  /// On a phone the box can stand wider than the horizontal scrollport it
  /// sits in (the amendment outliner scrolls), so its start edges are read
  /// with that scrollport at its start and its end edge at its end.
  static func read(_ page: Page, colorVariable: String) async throws -> Reading {
    let start = try await capture(page, colorVariable: colorVariable, end: false)
    let end = try await capture(page, colorVariable: colorVariable, end: true)
    return Reading(scale: start.scale, top: start.top, right: end.right, bottom: start.bottom, left: start.left)
  }

  private static func capture(_ page: Page, colorVariable: String, end: Bool) async throws -> Reading {
    // The box fully on screen first, where a screenshot can see it.
    _ = try await page.evaluate(
      """
      (() => {
        const box = document.querySelector('.artifact-markup-box')
        box.scrollIntoView({block: 'center'})
        for (let el = box.parentElement; el; el = el.parentElement) {
          if (el.scrollWidth > el.clientWidth && getComputedStyle(el).overflowX !== 'visible') {
            el.scrollLeft = \(end ? "el.scrollWidth" : "0")
          }
        }
        return 1
      })()
      """,
      as: Int.self)
    let data = try await page.screenshot()
    if let directory = ProcessInfo.processInfo.environment["GNORIUM_SCREENSHOT_DIR"] {
      try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("ring-\(UUID().uuidString.prefix(6)).png"))
    }
    let png = data.base64EncodedString()
    return try await page.evaluate(
      """
      (async () => {
        const probe = document.createElement('span'); document.body.append(probe)
        probe.style.borderColor = 'var(\(colorVariable))'
        probe.style.borderStyle = 'solid'
        const ringColor = getComputedStyle(probe).borderTopColor; probe.remove()
        const bytes = Uint8Array.from(atob('\(png)'), (c) => c.charCodeAt(0))
        const bitmap = await createImageBitmap(new Blob([bytes], {type: 'image/png'}), {colorSpaceConversion: 'none'})
        const canvas = document.createElement('canvas'); canvas.width = bitmap.width; canvas.height = bitmap.height
        const context = canvas.getContext('2d', {willReadFrequently: true}); context.drawImage(bitmap, 0, 0)
        const scale = bitmap.width / innerWidth
        const box = document.querySelector('.artifact-markup-box').getBoundingClientRect()
        const paint = document.createElement('canvas').getContext('2d', {willReadFrequently: true})
        paint.fillStyle = ringColor; paint.fillRect(0, 0, 1, 1)
        const ring = Array.from(paint.getImageData(0, 0, 1, 1).data)
        const near = (x, y) => {
          const p = context.getImageData(x, y, 1, 1).data
          return Math.abs(p[0] - ring[0]) < 10 && Math.abs(p[1] - ring[1]) < 10 && Math.abs(p[2] - ring[2]) < 10
        }
        // Three CSS pixels outside the edge to six inside it.
        const side = (horizontal, edge, mid) => {
          const from = Math.round(edge * scale) - Math.round(3 * scale), to = Math.round(edge * scale) + Math.round(6 * scale)
          let picture = '', count = 0, samples = ''
          for (let d = from; d < to; d++) {
            samples += Array.from(context.getImageData(horizontal ? Math.round(mid * scale) : d, horizontal ? d : Math.round(mid * scale), 1, 1).data.slice(0, 3)).join(',') + ' '
            const hit = horizontal ? near(Math.round(mid * scale), d) : near(d, Math.round(mid * scale))
            picture += hit ? 'X' : '.'; if (hit) count++
          }
          return {picture, count, samples: samples + ' ring ' + ring.join(',') + ' box ' + [box.left, box.right, box.top, box.bottom, innerWidth, innerHeight, scrollX, document.documentElement.scrollWidth, visualViewport.offsetLeft, visualViewport.width, visualViewport.scale].join(',')}
        }
        const midX = Math.max(box.left, 0) / 2 + Math.min(box.right, innerWidth) / 2
        const midY = Math.max(box.top, 0) / 2 + Math.min(box.bottom, innerHeight) / 2
        // The far edges look inward: the window runs 6 outside to 3 inside by mirroring.
        const mirror = (s) => ({picture: s.picture.split('').reverse().join(''), count: s.count, samples: s.samples})
        return {
          scale,
          top: side(true, box.top, midX),
          left: side(false, box.left, midY),
          bottom: mirror(side(true, box.bottom, midX)),
          right: mirror(side(false, box.right, midY)),
        }
      })()
      """, as: Reading.self)
  }

  /// The ring is two CSS pixels thick on every side: 2 × scale device
  /// pixels, in one unbroken run.
  static func expectTwoPixels(_ reading: Reading, _ context: String) {
    let wanted = Int((2 * reading.scale).rounded())
    for (name, side) in [("top", reading.top), ("right", reading.right), ("bottom", reading.bottom), ("left", reading.left)] {
      #expect(
        side.count == wanted && side.picture.contains(String(repeating: "X", count: wanted)),
        "\(context): \(name) ring is \(side.count) device px (\(side.picture)) \(side.samples), wanted \(wanted) at scale \(reading.scale)")
    }
  }
}
