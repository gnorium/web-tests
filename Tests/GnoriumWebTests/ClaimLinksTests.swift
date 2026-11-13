import Foundation
import Testing
import WebTests
import WebTestsTesting

/// A node's fields and the incoming supports that claim them, linked both
/// ways as a form changes (user, 2026-11-05): on a live form (Submit
/// Testament's copy, the same Incoming supports a Revise form draws), a
/// citation claiming the Copy field makes the field's label a link to its
/// card and the value its Claim shows a link back (user, 2026-11-06), its
/// label "Claim" plain: a click on the value's words follows it, one on the
/// chevron opens the menu, Enter on the trigger too, and no option is a
/// link. Another claim picked, both follow it. A citation claiming a former
/// owner links that row's legend, and of its Claim's trail only the field,
/// "Former owner", links back to it, the chevron and the name plain. A
/// field's link lands on its card's Claim, never the card's last quote.
/// Each citation removed, the label is plain again. A field no citation
/// claims never links.
@Suite("Claim links")
struct ClaimLinksTests {
  static let form = "/mission-control/submit/bibliographic/testament"

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aCitationLinksTheFieldItClaims(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated(Self.form)
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.openHydrated(Self.form)

      let view = page.locator(".outgoing-citations-view:has(#outgoing-citations-5)")
      try await expect(view).toHaveCount(1)
      let label = page.locator("[data-claim='copyLabel'] .text-input-label")
      try await expect(label).toHaveCount(1)
      try await expect(label).toHaveText("Copy")
      // Unclaimed: plain.
      try await expect(label.locator("a.claim-link")).toHaveCount(0)
      try await expect(page.locator(".claim-link")).toHaveCount(0)

      // A citation claiming the Copy field.
      try await view.locator(".outgoing-citations-actions .outgoing-citations-add").click()
      let cards = view.locator(".outgoing-citations-list > .outgoing-citation-group")
      try await expect(cards).toHaveCount(1)
      let card = cards.first
      let claim = card.locator(".outgoing-citation-claim")
      try await claim.locator(".dropdown-trigger").click()
      try await claim.locator(".dropdown-option[data-value='copyLabel']").filter(visible: true).first.click()
      let cardID = try await card.evaluate("(c) => c.id").string ?? ""
      #expect(!cardID.isEmpty, "a new card has an id of its own")

      // The field's label links to the card, the value the card's Claim
      // shows to the field, the words of each as they were; the label
      // "Claim" plain.
      let fieldLink = label.locator("a.claim-link")
      try await expect(fieldLink).toHaveCount(1)
      try await expect(fieldLink).toHaveAttribute("href", "#" + cardID)
      try await expect(label).toHaveText("Copy")
      let labelID = try await label.evaluate("(l) => l.id").string ?? ""
      #expect(!labelID.isEmpty, "the field's label is where the claim leads")
      let valueLink = claim.locator(".dropdown-trigger .dropdown-selected-text a.claim-link")
      try await expect(valueLink).toHaveCount(1)
      try await expect(valueLink).toHaveAttribute("href", "#" + labelID)
      try await expect(valueLink).toHaveText("Copy")
      try await expect(claim.locator(".dropdown-label-text a")).toHaveCount(0)
      try await expect(claim.locator(".dropdown-label-text")).toHaveText("Claim")
      // No other field links.
      try await expect(page.locator("[data-claim='holdingInstitution'] a.claim-link")).toHaveCount(0)

      // The label followed: the card's Claim in view, at the card's top,
      // never its last quote.
      try await fieldLink.click()
      let shown = try await claim.evaluate(
        "(c) => { const r = c.getBoundingClientRect(); return r.top >= 0 && r.bottom <= innerHeight; }"
      ).bool
      #expect(shown == true, "the card's Claim brought into view")
      // The value followed: the field in view, the Claim's menu not opened.
      try await valueLink.click()
      let back = try await label.evaluate(
        "(l) => { const r = l.getBoundingClientRect(); return r.bottom > 0 && r.top < innerHeight; }"
      ).bool
      #expect(back == true, "the field brought into view")
      try await expect(claim.locator(".is-open")).toHaveCount(0)
      // The chevron opens the menu, as ever; no option of it is a link.
      try await claim.locator(".dropdown-chevron").first.click()
      try await expect(claim.locator(".is-open")).toHaveCount(1)
      try await expect(claim.locator(".dropdown-option a")).toHaveCount(0)
      try await page.keyboard.press("Escape")
      try await expect(claim.locator(".is-open")).toHaveCount(0)
      // Enter on the trigger opens it too.
      try await claim.locator("button.dropdown-trigger").first.press("Enter")
      try await expect(claim.locator(".is-open")).toHaveCount(1)
      try await page.keyboard.press("Escape")
      try await expect(claim.locator(".is-open")).toHaveCount(0)

      // Another claim picked: the value leads to its field, that field's
      // label to the card, the Copy label plain again.
      let holding = page.locator("[data-claim='holdingInstitution'] .combobox-label-text")
      try await claim.locator(".dropdown-chevron").first.click()
      try await claim.locator(".dropdown-option[data-value='holdingInstitution']").filter(visible: true).first.click()
      try await expect(holding.locator("a.claim-link")).toHaveCount(1)
      try await expect(holding.locator("a.claim-link")).toHaveAttribute("href", "#" + cardID)
      let holdingID = try await holding.evaluate("(l) => l.id").string ?? ""
      #expect(!holdingID.isEmpty, "the Holding institution's label is where the claim leads now")
      try await expect(valueLink).toHaveAttribute("href", "#" + holdingID)
      try await expect(valueLink).toHaveText("Holding institution")
      try await expect(fieldLink).toHaveCount(0)
      try await expect(label).toHaveText("Copy")

      // A former owner's row, claimed, links from its legend.
      try await page.locator("input[name='former-owner-item1-text-input']").fill("Henry E. Huntington")
      try await view.locator(".outgoing-citations-actions .outgoing-citations-add").click()
      try await expect(cards).toHaveCount(2)
      let ownerID = try await cards.nth(1).evaluate("(c) => c.id").string ?? ""
      #expect(!ownerID.isEmpty, "a new card has an id of its own")
      let ownerClaim = page.locator("#" + ownerID + " .outgoing-citation-claim")
      try await ownerClaim.locator(".dropdown-trigger").click()
      try await ownerClaim.locator(".dropdown-option[data-value^='formerOwners:']").filter(visible: true).first.click()
      let legend = page.locator(
        "[data-item-list='former-owner'] > [data-item-section='true'] > .form-item-legend").first
      try await expect(legend.locator("a.claim-link")).toHaveCount(1)
      try await expect(legend.locator("a.claim-link")).toHaveAttribute("href", "#" + ownerID)
      try await expect(legend).toHaveText("Former owner")
      // Of its value's trail, the field alone the link to the row's legend;
      // the chevron and the name plain.
      let ownerValue = ownerClaim.locator(".dropdown-selected-text a.claim-link")
      try await expect(ownerValue).toHaveCount(1)
      try await expect(ownerValue).toHaveText("Former owner")
      try await expect(ownerClaim.locator(".dropdown-selected-text .breadcrumb-label-context a.claim-link"))
        .toHaveCount(1)
      try await expect(ownerClaim.locator(".dropdown-selected-text .breadcrumb-label-text a")).toHaveCount(0)
      try await expect(ownerClaim.locator(".dropdown-selected-text .breadcrumb-separator-view a")).toHaveCount(0)
      try await expect(ownerClaim.locator(".dropdown-selected-text .breadcrumb-label-text"))
        .toHaveText("Henry E. Huntington")
      let legendID = try await legend.evaluate("(l) => l.id").string ?? ""
      #expect(!legendID.isEmpty, "the row's legend is where its claim leads")
      try await expect(ownerValue).toHaveAttribute("href", "#" + legendID)
      try await expect(ownerClaim.locator(".dropdown-label-text a")).toHaveCount(0)
      // Both ways: the legend lands on the owner's Claim, its card's top;
      // the Claim's field on the legend.
      try await legend.locator("a.claim-link").click()
      let atClaim = try await ownerClaim.evaluate(
        "(c) => { const r = c.getBoundingClientRect(); return r.top >= 0 && r.bottom <= innerHeight; }"
      ).bool
      #expect(atClaim == true, "the owner's citation landed on at its Claim")
      try await ownerValue.click()
      let atLegend = try await legend.evaluate(
        "(l) => { const r = l.getBoundingClientRect(); return r.top >= 0 && r.bottom <= innerHeight; }"
      ).bool
      #expect(atLegend == true, "the row's legend landed on")
      try await expect(ownerClaim.locator(".is-open")).toHaveCount(0)

      // Each citation removed: its field's label plain again.
      for _ in 0..<2 {
        try await cards.first.locator(".quote-passage-actions .quote-passage-citation-remove").click()
      }
      try await expect(cards).toHaveCount(0)
      try await expect(label.locator("a.claim-link")).toHaveCount(0)
      try await expect(label).toHaveText("Copy")
      try await expect(holding.locator("a.claim-link")).toHaveCount(0)
      try await expect(holding).toHaveText("Holding institution")
      try await expect(legend.locator("a.claim-link")).toHaveCount(0)
      try await expect(legend).toHaveText("Former owner")
      try await page.expectNoHorizontalOverflow()
      _ = try await page.evaluate("localStorage.removeItem('gnorium:draft:' + location.pathname)")
      try await page.expectNoErrors()
    }
  }
}
