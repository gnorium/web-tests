import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A testament's CARRIER and CONTAINER (user, 2026-09-28). On Submit
/// Testament the Carrier is required, comes first under the work and shows
/// the one event it calls for (user, 2026-09-28): none before it is chosen;
/// a manuscript (typescript, inscription) its copy's Production; a printed
/// testament, a recording or a born-digital text its Publication. The
/// Origin row's actions sit one field gap below its fields. "Other" in a
/// dropdown opens a required field to name the value. The Domain list is
/// grouped by main class in the LCC outline's own captions, an open option
/// wrapping, the closed control fading its end. The Publication card
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
      try await run(engine: engine, layout: layout, admin: admin, host: host, article: article)
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
    engine: BrowserEngine, layout: Layout, admin: TestAdmin, host: ScratchWork, article: ScratchWork
  ) async throws {
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
      try await page.openHydrated(Self.form)
      let form = page.locator(".submit-testament-form")
      let carrier = form.locator(".dropdown-view:has(#testament-carrier)")
      let publication = form.locator(".activity-statement-view[data-as-namespace='publication']")
      let production = form.locator(".activity-statement-view[data-as-namespace='production']")
      try await expect(form).toContainText("Carrier")
      // Required: no "(optional)" beside its label.
      try await expect(carrier).not.toContainText("optional")
      // Before a carrier is chosen, neither card.
      try await expect(publication).toBeHidden()
      try await expect(production).toBeHidden()
      try await expect(carrier.locator(".dropdown-option .dropdown-option-display-text")).toHaveTexts([
        "Manuscript", "Typescript", "Inscription", "Printed", "Audio Recording", "Video Recording", "Digital",
      ])

      func choose(_ value: String) async throws {
        try await carrier.locator(".dropdown-trigger").click()
        try await carrier.locator(".dropdown-option[data-value='\(value)']").click()
      }
      // Each carrier shows exactly its card, and switching swaps them: a
      // manuscript, a typescript or an inscription its Production; a
      // printed testament, a recording or a born-digital text its
      // Publication.
      for (value, madeByProduction) in [
        ("manuscript", true), ("printed", false), ("typescript", true), ("audio_recording", false),
        ("inscription", true), ("video_recording", false), ("digital", false),
      ] {
        try await choose(value)
        if madeByProduction {
          try await expect(production).toBeVisible()
          try await expect(publication).toBeHidden()
        } else {
          try await expect(publication).toBeVisible()
          try await expect(production).toBeHidden()
        }
      }
      try await choose("printed")

      // The Origin row's actions sit one field gap below its last field,
      // as its fields are spaced.
      let gaps = try await page.evaluate(
        """
        (() => {
          const row = document.querySelector('.origin-field-view-row');
          const shown = [...row.children].filter((c) => c.getBoundingClientRect().height > 0);
          const actions = row.querySelector(':scope > .origin-field-view-actions');
          const before = shown[shown.indexOf(actions) - 1];
          const [a, b] = shown;
          const typed = row.querySelector(':scope > .origin-field-view-typed');
          const last = [...typed.children].filter((c) => getComputedStyle(c).display !== 'none').pop();
          return {
            field: Math.round(b.getBoundingClientRect().top - a.getBoundingClientRect().bottom),
            actions: Math.round(actions.getBoundingClientRect().top - last.getBoundingClientRect().bottom),
            typedEnd: Math.round(typed.getBoundingClientRect().bottom - last.getBoundingClientRect().bottom),
          };
        })()
        """)
      #expect(gaps["typedEnd"].int == 0, "No empty slot at the end of the typed fields.")
      #expect(gaps["actions"].int == gaps["field"].int, "The actions sit one field gap below the fields.")

      // "Other" opens a required field right below it to name the value,
      // and choosing anything else hides it: the container's type, a genre.
      // Chosen as a reader chooses in a long list: its name typed into the
      // menu's search, the match clicked.
      func pick(_ dropdown: Locator, _ value: String) async throws {
        try await dropdown.locator(".dropdown-trigger").click()
        let option = dropdown.locator(".dropdown-option[data-value='\(value)']")
        let name = try await option.getAttribute("data-display") ?? value
        try await dropdown.locator(".dropdown-search-input").fill(name)
        try await option.filter(visible: true).first.click()
      }
      for (control, other, value) in [
        ("#work-genre-item1-text-input", "work-genre-item1-other", "tragedy")
      ] {
        // The first: a row list's hidden template carries the same ids.
        let dropdown = form.locator(".dropdown-view:has(\(control))").first
        let named = form.locator("input[name='\(other)']").first
        try await expect(named).toBeHidden()
        try await pick(dropdown, "other")
        try await expect(named).toBeVisible()
        let required = try await named.evaluate("(e) => e.required").bool
        #expect(required == true, "\(other) is required while shown.")
        try await pick(dropdown, value)
        try await expect(named).toBeHidden()
        let stillRequired = try await named.evaluate("(e) => e.required").bool
        #expect(stillRequired == false, "\(other) is not required while hidden.")
      }

      // A type is identity: the work's Type and the container's are closed
      // lists, with no "Other".
      for control in ["#work-type", "#container-type"] {
        let dropdown = form.locator(".dropdown-view:has(\(control))").first
        try await expect(dropdown.locator(".dropdown-option[data-value='other']")).toHaveCount(0)
      }
      try await expect(form.locator("input[name='container-type-other']")).toHaveCount(0)

      // The Container shows for a work that can be published in another
      // (a play: Hamlet in the First Folio) and hides for one that is itself
      // a container kind (a journal), live as the Type changes.
      let workType = form.locator(".dropdown-view:has(#work-type)")
      let containerGroup = form.locator(".container-field-view")
      try await pick(workType, "journal")
      try await expect(containerGroup).toBeHidden()
      try await pick(workType, "play")
      try await expect(containerGroup).toBeVisible()

      // The Domain list, grouped by main class, the Library of Congress
      // Classification outline's captions whole, each after its notation:
      // an open option wraps to show all of it; the closed control keeps
      // one line and fades its end.
      let domain = form.locator(".dropdown-view:has(#work-domain-item1-text-input)").first
      let caption = "D World history and history of Europe, Asia, Africa, Australia, New Zealand, etc."
      try await domain.locator(".dropdown-trigger").click()
      let head = domain.locator(".dropdown-option[data-value='classD']")
      try await expect(head).toHaveAttribute("data-depth", "0")
      let mathematics = domain.locator(".dropdown-option[data-value='QA']")
      try await expect(mathematics).toHaveAttribute("data-depth", "1")
      try await expect(mathematics.locator(".dropdown-option-display-text")).toHaveText("QA Mathematics")
      try await expect(domain.locator(".dropdown-option[data-value='law']")).toHaveCount(0)
      let open = try await head.locator(".dropdown-option-display-text").evaluate(
        "(e) => ({ text: e.textContent.trim(), lines: Math.round(e.getBoundingClientRect().height / parseFloat(getComputedStyle(e).lineHeight)), wraps: getComputedStyle(e).whiteSpace === 'normal', cut: e.scrollWidth > e.clientWidth, mask: getComputedStyle(e).webkitMaskImage || getComputedStyle(e).maskImage || '' })")
      #expect(open["text"].string == caption)
      #expect(open["wraps"].bool == true, "The open option wraps.")
      if layout == .phone { #expect((open["lines"].int ?? 0) > 1, "At phone width it takes more than one line.") }
      #expect(open["cut"].bool == false, "Nothing of it is cut.")
      #expect(!(open["mask"].string ?? "").contains("gradient"), "No fade in the open list.")
      try await head.click()
      let closed = domain.locator(".dropdown-selected-text")
      try await expect(closed).toHaveText(caption)
      // At phone width the caption runs past the control; wider, it may fit.
      if layout == .phone { try await expect(closed).toHaveAttribute("data-overflowing", "true") }
      let shut = try await closed.evaluate(
        "(e) => ({ nowrap: getComputedStyle(e).whiteSpace === 'nowrap', over: e.scrollWidth > e.clientWidth, mask: getComputedStyle(e).webkitMaskImage || getComputedStyle(e).maskImage || '', expand: e.getAttribute('data-edge-fade') })")
      #expect(shut["nowrap"].bool == true, "The closed control keeps one line.")
      #expect((shut["mask"].string ?? "").contains("gradient") == (shut["over"].bool ?? false), "Its end fades exactly when it runs past.")
      #expect(shut["expand"].string != "expand", "No tap-to-expand.")

      // The Container, in the Publication card: its record field asked for
      // on the page, the typed host while none is chosen, the locator.
      let container = publication.locator(".container-field-view")
      try await expect(container.locator("legend").first).toHaveText("Container")
      try await expect(container.locator(".origin-record-field-view legend")).toContainText("Record")
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
      try await expect(container.locator(".origin-record-field-view")).toContainText("Testament")
      try await expect(container.locator(".container-field-view-typed")).toBeHidden()

      // The work's Domains, a row each, as its Genres: the Library of
      // Congress Classification's classes.
      let domains = form.locator("[data-item-list='work-domain']")
      try await expect(domains).toHaveCount(1)
      try await expect(domains.locator(".dropdown-option[data-value='classK']").first).toBeAttached()
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
