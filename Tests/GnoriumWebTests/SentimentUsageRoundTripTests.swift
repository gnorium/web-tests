import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Sentiment usage survives unrelated revisions", .serialized)
struct SentimentUsageRoundTripTests {
  @Test
  func retainedLabelsWithCommasAndPunctuationRemainWhole() async throws {
    guard gnorium.engines.contains(.chrome) else { try Test.cancel("Chrome is not among the engines.") }
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let word = try ScratchWord(owner: admin, submitted: true)
    let labels = ["chiefly US, informal", "100% colloquial; \"quoted\"", " rare, régional "]
    let labelsJSON = String(decoding: try JSONEncoder().encode(labels), as: UTF8.self)
    let path = "/mission-control/madrigals/lexicographic/\(word.madrigalID)"
    func remove() {
      _ = try? TestAdmin.query("DELETE FROM revisions WHERE revisable_id = '\(word.madrigalID.lowercased())';")
      word.remove()
    }
    do {
      _ = try TestAdmin.query(
        """
        UPDATE lexicographic_madrigals
        SET proposed_content_json = jsonb_set(proposed_content_json::jsonb,
          '{record,senses,0,usage,register}', '\(labelsJSON)'::jsonb)::text
        WHERE id = '\(word.madrigalID.lowercased())';
        """)
      try await withPage(.chrome, gnorium, viewport: .desktop, cookies: [admin.cookie]) { page in
        try await page.openHydrated("\(path)/revise")
        let register = page.locator(".dropdown-view:has(input[name='sentiment-0-register'])")
        // Each retained value is one selected option, including the comma
        // and punctuation; duplicate old/new choices are not rendered.
        try await expect(register.locator(".dropdown-option[data-selected='true']")).toHaveCount(labels.count)
        try await expect(register.locator(".dropdown-trigger")).toContainText(labels[0])
        let selected = try await register.locator("input[name='sentiment-0-register']").evaluate(
          "(el) => el.value.split(',').map(decodeURIComponent)")
        #expect(selected.array?.compactMap(\.string) == labels)
        try await page.locator("textarea[name='sentiment-0-label']").fill("A branch description revised independently.")
        try await page.locator(".revision-form button[type='submit']").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the madrigal at its locution", where: {
          $0.path.lowercased() == path.lowercased() && ($0.fragment ?? "").hasPrefix("revision-")
        })
        try await page.expectNoErrors()
      }
      let filed = try TestAdmin.query(
        """
        SELECT content_json FROM revisions
        WHERE revisable_id = '\(word.madrigalID.lowercased())' AND status = 'pending' AND content_json IS NOT NULL;
        """)
      let content = try #require(JSONSerialization.jsonObject(with: Data(filed.utf8)) as? [String: Any])
      let sentiments = try #require(content["sentiments"] as? [[String: Any]])
      let usage = try #require(sentiments[0]["usage"] as? [String: Any])
      #expect(usage["register"] as? [String] == labels)
      #expect(sentiments[0]["label"] as? String == "A branch description revised independently.")
    } catch {
      remove()
      try await admin.remove(after: error)
    }
    remove()
    try await admin.remove()
  }
}
