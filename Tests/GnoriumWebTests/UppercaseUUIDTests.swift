import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A UUID has one text form, upper case (user, 2026-11-03): a page's
/// address naming a real object by its UUID in lower case is not found—never
/// redirected, never read as the same object—and the same address in upper
/// case is the object's page.
@Suite("Uppercase UUIDs", .serialized)
struct UppercaseUUIDTests {
  @Test(arguments: gnorium.engines)
  func aLowercaseUUIDInAPageAddressIsNotFound(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work: ScratchWork
    do {
      work = try ScratchWork(owner: admin)
    } catch {
      try await admin.remove(after: error)
    }
    do {
      try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine), cookies: [admin.cookie]) { page in
        let path = "/mission-control/madrigals/bibliographic/\(work.madrigalID)"
        #expect(path != path.lowercased(), "the madrigal's UUID holds letters")
        let lower = try await page.goto(path.lowercased())
        #expect(lower.status == 404, "\(path.lowercased()) answered \(String(describing: lower.status))")
        let upper = try await page.goto(path)
        #expect(upper.status == 200, "\(path) answered \(String(describing: upper.status))")
      }
    } catch {
      work.remove()
      try await admin.remove(after: error)
    }
    work.remove()
    try await admin.remove()
  }
}
