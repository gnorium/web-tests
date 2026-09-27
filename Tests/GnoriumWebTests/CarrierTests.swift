import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A testament's CARRIER and CONTAINER (user, 2026-09-28). On Submit
/// Testament the Carrier comes first under the work and shows the event it
/// calls for: a manuscript (typescript, inscription) its copy's Production
/// and no Publication; a printed testament its Publication and no
/// Production; a recording or a born-digital text both. The Publication card
/// holds the Container: its record field (asked of the server, as an
/// origin's is), the host as typed while no record is chosen, and the
/// locator. A record contained in another says so in prose ("Contained in
/// the English report …, volume 1, pages 3–5."), and the host lists it in
/// what it Contains. A throwaway admin owns two scratch works, removed after.
@Suite("Carrier", .serialized)
struct CarrierTests {
  static let form = "/mission-control/submit/bibliographic/evidence-testament"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func theCarrierShowsItsEventAndTheContainerItsHost(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let host = try ScratchWork(owner: admin)
    let article = try ScratchWork(owner: admin)
    do {
      // The article's version, as a permit writes it: contained in the host.
      _ = try TestAdmin.query(
        """
        UPDATE biblio_record_versions
          SET metadata_json = replace(metadata_json, '"edition":"First edition"',
            '"edition":"First edition","carrier":"printed","container":{"record":"\(host.recordID)","title":"\(host.title)","volume":"1","pages":"3-5"}')
          WHERE id = '\(article.versionID.lowercased())';
        """)
      try await run(engine: engine, viewport: layout.viewport(for: engine), admin: admin, host: host, article: article)
    } catch {
      article.remove()
      host.remove()
      await admin.remove()
      throw error
    }
    article.remove()
    host.remove()
    await admin.remove()
  }

  private func run(
    engine: BrowserEngine, viewport: Viewport, admin: TestAdmin, host: ScratchWork, article: ScratchWork
  ) async throws {
    try await withPage(engine, gnorium, viewport: viewport, cookies: [admin.cookie]) { page in
      try await page.openHydrated(Self.form)
      let form = page.locator(".submit-testament-form")
      let carrier = form.locator(".dropdown-view:has(#testament-carrier)")
      let publication = form.locator(".activity-statement-view[data-as-namespace='publication']")
      let production = form.locator(".activity-statement-view[data-as-namespace='production']")
      try await expect(form).toContainText("Carrier")
      // Before a carrier is chosen, both cards.
      try await expect(publication).toBeVisible()
      try await expect(production).toBeVisible()
      try await expect(carrier.locator(".dropdown-option .dropdown-option-display-text")).toHaveTexts([
        "Manuscript", "Typescript", "Inscription", "Printed", "Audio Recording", "Video Recording", "Digital",
      ])

      func choose(_ value: String) async throws {
        try await carrier.locator(".dropdown-trigger").click()
        try await carrier.locator(".dropdown-option[data-value='\(value)']").click()
      }
      // A manuscript: its Production, no Publication.
      try await choose("manuscript")
      try await expect(publication).toBeHidden()
      try await expect(production).toBeVisible()
      // Printed: its Publication, no Production.
      try await choose("printed")
      try await expect(publication).toBeVisible()
      try await expect(production).toBeHidden()
      // A recording: both, as an unissued one has a Production.
      try await choose("audio_recording")
      try await expect(publication).toBeVisible()
      try await expect(production).toBeVisible()

      // The Container, in the Publication card: its record field asked for
      // on the page, the typed host while none is chosen, the locator.
      let container = publication.locator(".container-field-view")
      try await expect(container.locator("legend").first).toHaveText("Container")
      try await expect(container.locator(".origin-record-field-view legend")).toContainText("Container record")
      try await expect(container.locator(".container-field-view-typed")).toBeVisible()
      for name in ["container-volume", "container-issue", "container-pages"] {
        try await expect(container.locator("input[name='\(name)']")).toHaveCount(1)
      }
      let picker = container.locator(".origin-record-field-view .dropdown-view").first
      try await picker.locator(".dropdown-trigger").click()
      try await picker.locator(".dropdown-search-input").fill(host.suffix)
      let found = picker.locator(
        ".dropdown-options-list[data-dropdown-results='true'] .dropdown-option[data-value='\(host.recordID)']")
      try await found.click()
      // A host chosen: its testaments to name one by, no typed host.
      try await expect(container.locator(".origin-record-field-view")).toContainText("Container testament")
      try await expect(container.locator(".container-field-view-typed")).toBeHidden()

      // The work's Domains, a row each, as its Genres: the UDC Summary's
      // classes.
      let domains = form.locator("[data-item-list='work-domain']")
      try await expect(domains).toHaveCount(1)
      try await expect(domains.locator(".dropdown-option[data-value='law']").first).toBeAttached()
      try await expect(form).toContainText("+ Add domain")

      // Nothing scrolls sideways.
      let overflow = try await page.evaluate("document.documentElement.scrollWidth > window.innerWidth").bool
      #expect(overflow == false)

      // The records list's Carrier filter: the article's testament is
      // printed, so it is listed for printed and not for manuscript.
      try await page.openHydrated("/biblio-records?carrier=printed")
      try await expect(page.locator(".filter-bar-view")).toContainText("Carrier")
      try await expect(page.locator("a[href='\(article.path)']").first).toBeAttached()
      try await page.openHydrated("/biblio-records?carrier=manuscript")
      try await expect(page.locator("a[href='\(article.path)']")).toHaveCount(0)

      // The article's page: a Container section after its Metadata, in prose.
      try await page.openHydrated(article.path)
      try await expect(page.locator("#container .record-section-title")).toHaveText("Container")
      let prose = page.locator("#container .contained-in-view p")
      try await expect(prose).toHaveText("Contained in the English report \(host.title), volume 1, pages 3–5.")
      try await expect(prose.locator("a[href='\(host.path)']")).toHaveCount(1)

      // The host lists it under Contains.
      try await page.openHydrated(host.path)
      let contains = page.locator(".record-sidebar-view a[href='\(article.path)']").first
      try await expect(contains).toBeAttached()
      try await expect(contains).toContainText("volume 1, pages 3–5")
    }
  }
}
