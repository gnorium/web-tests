import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Submit Testament reads the testament its Source URL names as the record
/// page reads one (user, 2026-10-03): the server reads the IIIF manifest,
/// and the record page's viewer shows its semblances, with no ordinance
/// pane, since nothing is recognized yet. A URL cleared takes the viewer
/// away, and the field's own validation asks for one. A manifest the server
/// cannot read takes it away too, with an error under the field that blocks
/// the form for that URL: the submit would be refused for it.
///
/// The manifests are served by a fixture server on this machine
/// (`FixtureServer`), which the dev server may fetch because `.env.dev`
/// sets `MANIFEST_FETCH_ALLOW_LOOPBACK=true`. The images are not served and
/// need not load. Nothing is submitted. Needs a signed-in account, made for
/// the test and removed after.
@Suite("Submit Testament reader")
struct SubmitTestamentReaderTests {
  static let form = "/mission-control/submit/bibliographic/evidence-testament"

  /// A IIIF v3 manifest of three pages.
  static var manifest: Data {
    let canvases = (1...3).map { index in
      let service = "/web-tests-iiif/submit-reader-\(index)"
      return #"{"type":"Canvas","width":1000,"height":1400,"label":{"none":["p\#(index)"]},"items":[{"items":[{"body":{"id":"\#(service)/full/max/0/default.jpg","service":[{"id":"\#(service)"}]}}]}]}"#
    }
    return Data(#"{"type":"Manifest","label":{"none":["Web tests"]},"items":[\#(canvases.joined(separator: ","))]}"#.utf8)
  }

  static func fixtures() async throws -> FixtureServer {
    try await FixtureServer(files: [
      "/manifest.json": .init(contentType: "application/ld+json", body: manifest),
      // JSON, but no manifest: nothing to page.
      "/not-a-manifest.json": .init(contentType: "application/json", body: Data("{}".utf8)),
    ])
  }

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func theSourceURLShowsItsSemblances(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let fixtures = try await Self.fixtures()
    defer { fixtures.stop() }
    let manifestURL = fixtures.baseURL + "/manifest.json"
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(Self.form)
        let form = page.locator(".submit-testament-form")
        let reader = form.locator(".submit-testament-reader")
        let source = form.locator("input[name='source-url']")
        let message = form.locator("#testament-source-url-validation-message .field-validation-message-text")

        // No URL: no viewer.
        try await expect(reader).toBeHidden()
        try await expect(reader.locator(".testament-view")).toHaveCount(0)

        // A manifest: its semblances, paged, and no ordinance pane or
        // switch to put the images away.
        try await source.fill(manifestURL)
        try await expect(reader).toBeVisible()
        let viewer = reader.locator(".artifact-view")
        try await expect(viewer).toHaveCount(1)
        try await expect(viewer).toHaveAttribute("data-artifact-hydrated", "true")
        try await expect(viewer.locator("#artifact-page-total")).toHaveText("3")
        try await expect(viewer.locator(".artifact-object")).toBeVisible()
        try await expect(viewer.locator(".artifact-transcript")).toHaveCount(0)
        try await expect(viewer.locator(".artifact-canvas-toggle")).toHaveCount(0)
        try await expect(message).toHaveCount(0)

        // Not a manifest: the viewer goes, and the field says why, an error
        // that blocks the form for this URL.
        try await source.fill(fixtures.baseURL + "/not-a-manifest.json")
        try await expect(message).toHaveText("The source URL can't be read.")
        try await expect(source).toHaveAttribute("aria-invalid", "true")
        try await expect(reader).toBeHidden()
        try await expect(reader.locator(".testament-view")).toHaveCount(0)

        // Nothing answers: it could not be fetched.
        try await source.fill(fixtures.baseURL + "/gone.json")
        try await expect(message).toHaveText("The source URL can't be read.")
        try await expect(reader).toBeHidden()

        // A manifest again: the error goes, the viewer comes back.
        try await source.fill(manifestURL)
        try await expect(reader).toBeVisible()
        try await expect(reader.locator(".artifact-view #artifact-page-total")).toHaveText("3")
        try await expect(message).toHaveCount(0)
        #expect(try await source.getAttribute("aria-invalid") == nil, "a readable manifest left the field invalid")

        // Cleared: the viewer goes, and the field asks to be filled in.
        try await source.fill("")
        try await expect(reader).toBeHidden()
        try await expect(reader.locator(".testament-view")).toHaveCount(0)
        try await expect(message).toHaveText("Fill in this field.")

        // The fixture's images are not served: their requests fail.
        try await page.expectNoErrors(ignoring: ["/web-tests-iiif/"])
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      try await admin.remove(after: error)
    }
    try await admin.remove()
  }
}
