import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A table's column is resized by its heading's handle: a drag widens it, a
/// double-click fits it to its values (TableView). A column that fits its
/// heading (`fitsHeader`, the records lists' Treatment) can still be dragged
/// wider, and a double-click fits it back to its heading alone. With a mouse,
/// at desktop width.
@Suite("Table resize", .serialized)
struct TableResizeTests {
  struct Width: Decodable {
    let width: Double
  }

  /// The column heading's rendered width.
  static func width(_ page: Page, _ column: String) async throws -> Double {
    try await page.evaluate(
      "({ width: document.querySelector(\"main .table-table th[data-table-column-id='\(column)']\").getBoundingClientRect().width })",
      as: Width.self
    ).width
  }

  /// Drags `column`'s handle `by` pixels along the line, in steps.
  static func drag(_ page: Page, _ column: String, by distance: Double) async throws {
    let handle = page.locator("main .table-table th[data-table-column-id='\(column)'] .table-resizer")
    guard let box = try await handle.boundingBox() else {
      Issue.record("\(column): its resize handle is not shown")
      return
    }
    let x = box.x + box.width / 2
    let y = box.y + box.height / 2
    try await page.mouse.down(x: x, y: y)
    for step in 1...4 {
      try await page.mouse.move(x: x + distance * Double(step) / 4, y: y)
    }
    try await page.mouse.up(x: x + distance, y: y)
  }

  static func fit(_ page: Page, _ column: String) async throws {
    try await page.locator("main .table-table th[data-table-column-id='\(column)'] .table-resizer").dblclick()
  }

  @Test(arguments: gnorium.engines)
  func aColumnIsDraggedWiderAndFitsOnADoubleClick(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine)) { page in
      for (path, column) in [("/lexico-records", "language"), ("/biblio-records", "type"), ("/mission-control/lifecycles", nil)] {
        try await page.openHydrated(path)
        try await page.expectNoErrors()
        let id: String
        if let column {
          id = column
        } else {
          // The first column with a handle shown.
          id = try await page.evaluate(
            """
            [...document.querySelectorAll('main .table-table th[data-table-column-id]')]
              .find((th) => { const r = th.querySelector('.table-resizer'); return r && r.getBoundingClientRect().width > 0 })
              .getAttribute('data-table-column-id')
            """, as: String.self)
        }
        let before = try await Self.width(page, id)
        try await Self.drag(page, id, by: 120)
        let dragged = try await Self.width(page, id)
        #expect(dragged > before + 100, "\(path) \(id): dragged 120 wider, \(before) became \(dragged)")
        try await Self.fit(page, id)
        let fitted = try await Self.width(page, id)
        #expect(fitted < dragged - 20, "\(path) \(id): a double-click left it \(fitted) (dragged to \(dragged))")
      }
    }
  }

  @Test(arguments: gnorium.engines)
  func aColumnThatFitsItsHeadingIsDraggedWiderAndFitsBack(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine)) { page in
      for path in ["/biblio-records", "/lexico-records"] {
        try await page.openHydrated(path)
        try await page.expectNoErrors()
        try await expect(page.locator("main th[data-table-column-id='treatment']")).toHaveAttribute("data-fits-header", "true")
        let before = try await Self.width(page, "treatment")
        try await Self.drag(page, "treatment", by: 120)
        let dragged = try await Self.width(page, "treatment")
        #expect(dragged > before + 100, "\(path): Treatment dragged 120 wider, \(before) became \(dragged)")
        try await Self.fit(page, "treatment")
        let fitted = try await Self.width(page, "treatment")
        let heading = try await page.evaluate(
          """
          (() => {
            const th = document.querySelector("main th[data-table-column-id='treatment']")
            const style = getComputedStyle(th)
            return { width: th.querySelector('.table-header-label, .table-sort-button').scrollWidth
              + parseFloat(style.paddingLeft) + parseFloat(style.paddingRight) }
          })()
          """, as: Width.self
        ).width
        #expect(fitted < dragged - 20, "\(path): a double-click left Treatment \(fitted) (dragged to \(dragged))")
        #expect(abs(fitted - heading) < 4, "\(path): Treatment fits to \(fitted), its heading is \(heading)")
      }
    }
  }
}
