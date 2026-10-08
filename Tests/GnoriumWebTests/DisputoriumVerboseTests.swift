import Testing
import WebTests
import WebTestsTesting

@Suite("Disputorium verbose record scope", .serialized)
struct DisputoriumVerboseTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func overtureRuleOpensOnlyRecordWorkAndRestoresDefaultMetadata(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/mission-control/overtures/lexicographic/C0FFEE00-0000-4000-8000-000000000130")
      let toggle = page.locator(".lexicographic-overture-view .disputorium-core-content > .apparatus-rule-view .verbose-toggle-button-control")
      try await expect(toggle).toHaveAttribute("aria-pressed", "false")
      try await expect(page.locator("#apparatus-metadata")).toHaveAttribute("data-expanded", "true")
      #expect(try await page.evaluate("""
        (()=>{const work=document.querySelector('.lexicographic-overture-view .disputorium-core-work');const rule=work.previousElementSibling;
          const metadata=work.querySelector('.record-metadata-change > .metadata-accordion-view > .accordion-view');
          const fields=[...work.querySelectorAll('#apparatus-metadata [data-metadata-added=true]')];
          const probe=document.createElement('span');document.body.append(probe);probe.style.borderColor='var(--border-color-base)';const neutral=getComputedStyle(probe).borderTopColor;
          probe.style.borderColor='var(--border-color-green)';const green=getComputedStyle(probe).borderTopColor;probe.remove();
          return rule.classList.contains('apparatus-rule-view') && metadata && getComputedStyle(metadata).borderTopColor===neutral
            && fields.length>0 && fields.every(e=>getComputedStyle(e).borderTopColor===green)
            && !work.querySelector('.prompt-instances-view');})()
        """, as: Bool.self))
      try await toggle.click()
      try await expect(toggle).toHaveAttribute("aria-pressed", "true")
      try await expect(page.locator(".lexicographic-overture-view .disputorium-core-work .accordion-details[data-expanded=false]")).toHaveCount(0)
      try await toggle.click()
      try await expect(toggle).toHaveAttribute("aria-pressed", "false")
      try await expect(page.locator("#apparatus-metadata")).toHaveAttribute("data-expanded", "true")
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }
}
