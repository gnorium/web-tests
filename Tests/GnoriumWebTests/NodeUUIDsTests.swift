import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Every testament has its own UUID (user, 2026-10-12;
/// design-notes/node-uuids.md): a freshly made madrigal and its record read
/// their stored trees, and each testament's header ends with an info
/// tooltip holding its whole UUID, its row named by it.
@Suite("Node UUIDs", .serialized)
struct NodeUUIDsTests {
  @Test(arguments: gnorium.engines)
  func aFreshMadrigalAndItsRecordShowTheirTestamentsUUIDs(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    defer { work.remove() }
    let shape = try TestAdmin.query(
      "SELECT shape_json FROM biblio_record_versions WHERE id = '\(work.versionID.lowercased())';")
    let edition = try #require(
      shape.firstMatch(of: /"edition-[0-9A-F-]+":\{[^}]*"uuid":"([0-9A-F-]{36})"/).map { String($0.1) }, "\(shape)")
    try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine), cookies: [admin.cookie]) { page in
      let madrigal = try await page.goto("/mission-control/madrigals/bibliographic/\(work.madrigalID.lowercased())")
      #expect(madrigal.status == 200)
      let record = try await page.goto(work.path)
      #expect(record.status == 200)
      try await page.openHydrated(work.path)
      let row = page.locator("#record-row-\(edition)")
      try await expect(row).toHaveCount(1)
      let tip = row.locator(".record-row-uuid").first
      let before = try await row.evaluate("(d) => d.open")
      try await tip.click()
      try await expect(page.locator(".tooltip-view[data-portal='true'][data-visible='true'] .tooltip-content"))
        .toHaveText(edition)
      // The tooltip is read, not opened: the row stays as it was.
      try await Task.sleep(for: .milliseconds(400))
      let after = try await row.evaluate("(d) => d.open")
      #expect(before == after)
    }
  }
}
