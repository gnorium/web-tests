import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Screenshots of every colored surface, in light, dark and increased
/// contrast, to COLOR_TOUR_DIR/<phase>-…png (a scratch tour, not a test of
/// behavior; skipped without COLOR_TOUR_DIR).
@Suite("Color tour", .serialized)
struct ColorTourTests {
  static let inks = ["pink", "red", "orange", "brown", "yellow", "olive", "yellow-green", "green", "blue", "purple",
    "white", "gray", "black", "violet", "cyan"]

  static func tei() -> String {
    let lines = inks.map { "<p><hi rend=\"color(\($0))\">\($0) ink, a needle</hi></p>" }.joined()
    let tei = "<TEI><text><body><pb n=\"1\" facs=\"https://web-tests.invalid/iiif/p1/full/max/0/default.jpg\"/>"
      + "<p>Plain text with a needle and another needle.</p>" + lines
      + "<pb n=\"2\" facs=\"https://web-tests.invalid/iiif/p2/full/max/0/default.jpg\"/><p>Second page.</p></body></text></TEI>"
    return String(decoding: try! JSONSerialization.data(withJSONObject: ["teiXml": tei]), as: UTF8.self)
      .replacingOccurrences(of: "'", with: "''")
  }

  static func shots(_ page: Page, _ name: String, _ selector: String) async throws {
    guard let folder = ProcessInfo.processInfo.environment["COLOR_TOUR_DIR"] else { return }
    let phase = ProcessInfo.processInfo.environment["COLOR_TOUR_PHASE"] ?? "shot"
    let directory = URL(fileURLWithPath: folder)
    _ = try await page.evaluate(
      "(() => { const e = document.querySelector(\"\(selector)\"); if (e) { e.scrollIntoView({block: 'start'}); window.scrollBy(0, -16) } return 1 })()",
      as: Int.self)
    for (scheme, contrast) in [("light", "less"), ("dark", "less"), ("light", "more"), ("dark", "more")] {
      _ = try await page.evaluate(
        "(() => { const r = document.documentElement; r.setAttribute('data-color-scheme', '\(scheme)'); r.setAttribute('data-contrast', '\(contrast)'); return 1 })()",
        as: Int.self)
      try await Task.sleep(for: .milliseconds(150))
      try await page.screenshot(to: directory.appendingPathComponent("\(phase)-\(name)-\(scheme)\(contrast == "more" ? "-more" : "").png"))
    }
    _ = try await page.evaluate(
      "(() => { const r = document.documentElement; r.setAttribute('data-color-scheme', 'light'); r.setAttribute('data-contrast', 'less'); return 1 })()",
      as: Int.self)
  }

  @Test(arguments: [BrowserEngine.chrome])
  func tour(engine: BrowserEngine) async throws {
    guard ProcessInfo.processInfo.environment["COLOR_TOUR_DIR"] != nil else { return }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchCommit(owner: admin)
    let user = try admin.column("id")
    let a = UUID().uuidString.uppercased(), b = UUID().uuidString.uppercased(), c = UUID().uuidString.uppercased()
    let call = UUID().uuidString.lowercased()
    func remove() {
      _ = try? TestAdmin.query("DELETE FROM revisions WHERE id IN ('\(a)', '\(b)', '\(c)')")
      _ = try? TestAdmin.query("DELETE FROM locutions WHERE locutable_id = '\(work.madrigalID.lowercased())'")
      work.remove()
    }
    do {
      _ = try TestAdmin.query(
        "UPDATE bibliographic_madrigals SET proposed_content_json = '\(Self.tei())' WHERE id = '\(work.madrigalID)'")
      let slot = "bibliographic_explication"
      func sql(_ text: String) -> String { text.replacingOccurrences(of: "'", with: "''") }
      let system = try TestAdmin.query(
        "SELECT system_prompt FROM prompt_vignettes WHERE id = (SELECT vignette_id FROM active_prompt_vignettes WHERE slot = '\(slot)')")
      let task = try TestAdmin.query(
        "SELECT task_prompt FROM prompt_vignettes WHERE id = (SELECT vignette_id FROM active_prompt_vignettes WHERE slot = '\(slot)')")
      for (id, proposed, offset, status) in [
        (a, system + "\nWeb tests A.", 3, "accepted"), (c, system + "\nWeb tests C.", 4, "pending"),
        (b, system.replacingOccurrences(of: "the", with: "thee", options: [], range: system.range(of: "the")) , 2, "pending"),
      ] {
        let evaluated = status == "accepted" ? "'\(user)', now()" : "NULL, NULL"
        _ = try TestAdmin.query("""
          INSERT INTO revisions (id, revisable_type, revisable_id, prompt_changes_json, status, requested_by_user_id, evaluated_by_user_id, evaluated_at, created_at)
          VALUES ('\(id)', 'bibliographicMadrigal', '\(work.madrigalID)', json_build_array(json_build_object('slot', '\(slot)', 'prompt', 'main', 'previous', json_build_object('system', '\(sql(system))', 'task', '\(sql(task))'),
              'proposed', json_build_object('system', '\(sql(proposed))', 'task', '\(sql(task))')))::text, '\(status)', '\(user)', \(evaluated), now() - interval '\(offset) minute')
          """)
      }
      _ = try TestAdmin.query("""
        INSERT INTO locutions (id, locutable_type, locutable_id, author_id, content, kind, call_status, query, evidence_id, evidence_kind, call_process, created_at)
        VALUES ('\(call)', 'bibliographic_madrigal', '\(work.madrigalID.lowercased())', '\(user)', '@gnorium check the [first page](#).', 'call', 'pending', 'check the first page', 'https://web-tests.invalid/iiif/p1', 'canvas', 'explication', now())
        """)
      try await withPage(engine, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated(work.madrigalPath)
        let viewer = page.locator(".madrigal-object .artifact-view")
        try await expect(viewer.locator(".artifact-markup .tei-page[data-active='true']"), timeout: .seconds(15)).toHaveCount(1)
        try await Self.shots(page, "logo-header", "body")
        try await Self.shots(page, "tei-inks", ".madrigal-object .artifact-view")
        try await viewer.locator(".artifact-xml-toggle button").click()
        try await Self.shots(page, "raw-tei", ".madrigal-object .artifact-view")
        try await viewer.locator(".artifact-xml-toggle button").click()
        try await viewer.locator(".testament-find-button button").click()
        try await viewer.locator(".testament-find-input input").fill("needle")
        try await expect(viewer.locator(".testament-find-count"), timeout: .seconds(10)).toContainText("of")
        try await Self.shots(page, "find", ".madrigal-object .artifact-view")
        try await viewer.locator(".testament-find-button button").click()
        try await Self.shots(page, "roster", "#madrigal-images")
        try await Self.shots(page, "thread", "#revision-\(b)")
        try await Self.shots(page, "chip-links", "#locution-\(call.uppercased())")
        try await page.openHydrated("\(work.madrigalPath)/revisions/\(c)")
        try await Self.shots(page, "alert-diff", ".prompt-clash-view")
        try await page.openHydrated("\(work.madrigalPath)/revisions/\(b)")
        _ = try? await page.locator(".prompt-text-markdown-toggle button").first.click()
        try await Self.shots(page, "diff-marks", ".prompt-change-view")
        try await page.openHydrated("/mission-control")
        try await Self.shots(page, "tabs", "body")
        // The logo in three candidate colors, the navbar's and the home page's.
        for (variant, hex) in [("blue", "#00B0FF"), ("cyan", "#00E5FF")] {
          try await page.openHydrated("/")
          _ = try await page.evaluate(
            "(() => { document.documentElement.style.setProperty('--color-blue', '\(hex)'); return 1 })()",
            as: Int.self)
          try await Self.shots(page, "logo-\(variant)", "body")
        }
      }
    } catch {
      remove()
      try await admin.remove(after: error)
    }
    remove()
    try await admin.remove()
  }
}
