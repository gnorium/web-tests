import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The overlay lays a board's edition on its image where the image has it
/// (user, 2026-11-03: Hamlet Q1's front cover, image 1 of 81, overlay on:
/// its tooled frame and corner ornaments drawn at 0.63 of the cover's gilt
/// frame, hung toward its top center). A page with no type of its own is
/// set in its leaf as its type area, 38 em across it (xml-utilities `TEIPage.leafTypeArea`),
/// so its scan's em, the overlay's type scale (`data-scan-em`), is its
/// leaf's (`TEIPage.scanWidth`), never its work's, whose text pages'
/// photographs run 80.61 em across. The cover as dev holds it, its scan
/// served on this machine; at rest, its frame's box lands on its zone on
/// the image. A throwaway contributor's scratch madrigal; Chrome, desktop.
@Suite("Artifact leaf overlay", .serialized)
struct ArtifactLeafOverlayTests {
  /// The cover's figure on screen against its zone on the image, each edge's
  /// distance a share of the image's size there, and its width over the
  /// zone's.
  struct Landing: Decodable {
    let off: [Double]
    let scale: Double
  }

  static let width = 6120
  static let height = 6630

  /// The cover as integrated (dev, 2026-11-03, p15150coll3:1360): the work's
  /// frame in the header, the board's tooled frame a figure at its zone, its
  /// lettering a line at its line break's.
  static func document(image: String) -> String {
    #"<TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><encodingDesc><tagsDecl>"#
      + #"<rendition xml:id="text-block" scheme="css" selector="text">font-size:85.44px;inline-size:26.47em;block-size:47.94em;margin:7.42em 13.26em 11.23em 9.33em;max-inline-size:80.61em</rendition>"#
      + "</tagsDecl></encodingDesc></teiHeader>"
      + #"<facsimile><surface n="Front cover" ulx="0" uly="0" lrx="1000" lry="1000"><graphic url="\#(image)" width="\#(width)px" height="\#(height)px"/>"#
      + #"<zone xml:id="p1-z-fig-2" ulx="173" uly="61" lrx="882" lry="938"/><zone xml:id="p1-z-L2" ulx="417" uly="238" lrx="637" lry="259"/>"#
      + #"<zone xml:id="p1-textblock" type="textblock" points="172.3,64.24 879.57,59.61 884.82,936.85 175.7,941.07"/>"#
      + #"<zone type="leaf" points="144.85,53.4 890.9,53.4 890.9,945.42 144.85,945.42"/></surface></facsimile>"#
      + ##"<text><body><pb n="Front cover" facs="\##(image)" rend="color(yellow)"/><figure facs="#p1-z-fig-2"/>"##
      + ##"<lb facs="#p1-z-L2"/><note type="binding" subtype="copy" style="letter-spacing:0.527em">HAMLET</note></body></text></TEI>"##
  }

  static let landing = """
    (() => {
      const page = document.querySelector(".artifact-markup .tei-page[data-active='true']");
      const figure = page.querySelector('.tei-figure[data-zone]');
      const image = document.querySelector('.image-view[data-active="true"] .image-tile-compositor');
      const f = figure.getBoundingClientRect(), b = image.getBoundingClientRect();
      const [l, t, r, bt] = figure.dataset.zone.split(' ').map(Number);
      const zone = [b.x + l / 1000 * b.width, b.y + t / 1000 * b.height, b.x + r / 1000 * b.width, b.y + bt / 1000 * b.height];
      const edges = [f.left, f.top, f.right, f.bottom];
      return {off: edges.map((e, i) => (e - zone[i]) / (i % 2 ? b.height : b.width)), scale: f.width / (zone[2] - zone[0])};
    })()
    """

  @Test(arguments: [BrowserEngine.chrome])
  func aCoversFrameLandsOnItsZoneOnTheImage(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let server = try await FixtureServer(files: [:])
    defer { server.stop() }
    let base = server.baseURL
    let (w, h) = (Self.width, Self.height)
    server.serve(
      .init(
        contentType: "application/json",
        body: Data(
          #"{"id":"\#(base)/manifest.json","type":"Manifest","label":{"en":["Cover"]},"items":[{"id":"\#(base)/canvas/1","type":"Canvas","width":\#(w),"height":\#(h),"label":{"en":["Front cover"]},"items":[{"type":"AnnotationPage","items":[{"body":{"id":"\#(base)/page-1/full/max/0/default.jpg","service":[{"id":"\#(base)/page-1","type":"ImageService3"}]}}]}]}]}"#
            .utf8)), at: "/manifest.json")
    server.serve(
      .init(
        contentType: "application/json",
        body: Data(
          #"{"@context":"http://iiif.io/api/image/3/context.json","id":"\#(base)/page-1","type":"ImageService3","protocol":"http://iiif.io/api/image","profile":"level0","width":\#(w),"height":\#(h)}"#
            .utf8)), at: "/page-1/info.json")
    // A dark board, its gilt frame at the zone.
    server.serve(
      .init(
        contentType: "image/svg+xml",
        body: Data(
          ##"<svg xmlns="http://www.w3.org/2000/svg" width="\##(w)" height="\##(h)"><rect width="\##(w)" height="\##(h)" fill="#333635"/><rect x="1059" y="404" width="4339" height="5814" fill="none" stroke="#c9a227" stroke-width="40"/></svg>"##
            .utf8)), at: "/page-1/*")
    let contributor = try await TestAdmin.create(baseURL: gnorium.baseURL, admin: false)
    let commit = try ScratchCommit(owner: contributor, sourceURL: base + "/manifest.json")
    let json = String(
      decoding: try JSONSerialization.data(withJSONObject: ["teiXml": Self.document(image: base + "/page-1/full/max/0/default.jpg")]),
      as: UTF8.self)
    do {
      _ = try TestAdmin.query(
        "UPDATE bibliographic_madrigals SET proposed_content_json = '\(json.replacingOccurrences(of: "'", with: "''"))' WHERE id = '\(commit.madrigalID)'")
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [contributor.cookie]) { page in
        try await page.openHydrated("\(commit.madrigalPath)?image=1")
        let view = page.locator(".artifact-view").first
        if try await view.getAttribute("data-canvas-shown") != "true" {
          try await page.locator(".artifact-canvas-toggle button").first.click()
        }
        try await expect(view).toHaveAttribute("data-canvas-shown", "true")
        try await expect(page.locator(".image-view[data-active='true'] .image-tile-image[data-loaded='true']").first).toBeAttached()
        try await page.locator(".artifact-overlay-toggle button").first.click()
        try await expect(view).toHaveAttribute("data-overlay-active", "true")
        try await Task.sleep(for: .milliseconds(1500))
        let landing = try await page.evaluate(Self.landing, as: Landing.self)
        // Within a hundredth of the image either way: at the work's em it stood 0.64 of its zone's size, its
        // sides 13 hundredths in and its foot 32 up.
        #expect(abs(landing.scale - 1) < 0.01, "the frame is \(landing.scale) of its zone's width")
        #expect(landing.off.allSatisfy { abs($0) < 0.01 }, "the frame's edges are off its zone by \(landing.off)")
      }
    } catch {
      commit.remove()
      try await contributor.remove(after: error)
    }
    commit.remove()
    try await contributor.remove()
  }
}
