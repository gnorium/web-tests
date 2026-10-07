import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Razorpay sponsorship checkout", .serialized)
struct SponsorCheckoutTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func serverIssuedCheckoutAndReceipt(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    guard let fixture = ProcessInfo.processInfo.environment["GNORIUM_SPONSOR_CHECKOUT_FIXTURE_PATH"],
      let receiptFixture = ProcessInfo.processInfo.environment["GNORIUM_SPONSOR_RECEIPT_FIXTURE_PATH"] else {
      try Test.cancel("Export actual checkout and receipt views first.")
    }
    let name = "sponsor-checkout-\(UUID().uuidString).html"
    let receiptName = "sponsor-receipt-\(UUID().uuidString).html"
    let directory = URL(fileURLWithPath: "/Users/Madhavik/Downloads/Gnorium/gnorium-web/Public")
    let file = directory.appendingPathComponent(name), receiptFile = directory.appendingPathComponent(receiptName)
    try Data(contentsOf: URL(fileURLWithPath: fixture)).write(to: file)
    try Data(contentsOf: URL(fileURLWithPath: receiptFixture)).write(to: receiptFile)
    defer { try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: receiptFile) }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/\(name)")
      try await expect(page.locator("main.sponsor-content")).toContainText("Test checkout: no money will be charged")
      try await expect(page.locator("main.sponsor-content")).toContainText("120 payments")
      _ = try await page.evaluate("""
        (() => {
          window.__sponsorCalls = [];
          window.__checkoutFailure = false;
          const original = window.fetch;
          window.fetch = async (url, options) => {
            if (String(url).startsWith('/sponsor-gnorium/checkout')) {
              const body = JSON.parse(options.body);
              window.__sponsorCalls.push({url:String(url),body});
              if (window.__checkoutFailure) return new Response(JSON.stringify({reason:'Please try again.'}), {status:503});
              const result = String(url).endsWith('/confirm') ? {status:'captured'} : {
                checkoutID:'fixture', keyID:'rzp_test_fixture', orderID:body.frequency==='once'?'order_fixture':null,
                subscriptionID:body.frequency==='monthly'?'sub_fixture':null,
                amount:60000,currency:'INR',monthlyCycles:120,statusToken:'fixture-token'
              };
              return new Response(JSON.stringify(result), {status:200});
            }
            return original(url,options);
          };
          window.Razorpay = class {
            constructor(options) { window.__razorpayOptions = options; }
            on() {}
            open() { window.__checkoutOpened = true; }
          };
          return true;
        })();
        """, as: Bool.self)
      try await expect(page.locator("[data-dropdown-id=sponsor-frequency] button")).toHaveCSS("background-color", "rgb(255, 255, 255)")
      let frequencyStyle = try await page.evaluate("""
        (()=>{const b=document.querySelector('[data-dropdown-id=sponsor-frequency] button');
          const text=b.querySelector('.dropdown-selected-text');const form=document.querySelector('#sponsor-checkout-form');
          const font=getComputedStyle(text).fontSize, width=b.getBoundingClientRect().width, parentWidth=form.getBoundingClientRect().width, background=getComputedStyle(b).backgroundColor;
          const probe=document.createElement('span');probe.style.backgroundColor='var(--background-color-base)';document.body.append(probe);
          const white=getComputedStyle(probe).backgroundColor;probe.remove();
          return JSON.stringify({ok:!b.disabled && font==='16px' && Math.abs(width-parentWidth)<2 && background===white,font,width,parentWidth,background,white});})()
        """, as: String.self)
      #expect(frequencyStyle.contains("\"ok\":true"), Comment(rawValue: frequencyStyle))
      try await expect(page.locator("#sponsor-amount")).toHaveAttribute("min", "1")
      #expect(try await page.evaluate("""
        (()=>{const label=document.querySelector('label[for=sponsor-profile]');
          return getComputedStyle(label).fontSize==='16px' && getComputedStyle(document.querySelector('#sponsor-amount')).fontSize==='16px'
            && [...document.querySelectorAll('main.sponsor-content > p')].every(p=>getComputedStyle(p).fontSize==='16px');})()
        """, as: Bool.self), "Body, amount and explication checkbox use consistent 16px text")
      try await expect(page.locator("#sponsor-profile")).toBeChecked(false)
      try await page.locator("#sponsor-amount").fill("500")
      try await page.locator("#sponsor-profile").check()
      try await page.locator("#sponsor-checkout-form button[type=submit]").click()
      try await expect(page.locator("#sponsor-checkout-receipt a")).toContainText("View Sponsorship Receipt")
      let once = try await page.evaluate("""
        JSON.stringify({call:window.__sponsorCalls[0],amount:window.__razorpayOptions.amount,
          order:window.__razorpayOptions.order_id,key:window.__razorpayOptions.key});
        """, as: String.self)
      #expect(once.contains("\"amount\":\"500\""))
      #expect(once.contains("\"showOnProfile\":true"))
      #expect(once.contains("\"amount\":60000"), "Checkout uses server-issued amount, not editable browser input")
      #expect(once.contains("order_fixture"))
      _ = try await page.evaluate("""
        (async () => { await window.__razorpayOptions.handler({razorpay_payment_id:'pay_fixture',razorpay_order_id:'order_fixture',razorpay_signature:'signature-fixture'}); return true; })();
        """, as: Bool.self)
      try await expect(page.locator("#sponsor-checkout-status")).toContainText("Your sponsorship receipt shows")
      let confirm = try await page.evaluate("JSON.stringify(window.__sponsorCalls[1])", as: String.self)
      #expect(confirm.contains("/confirm"))
      #expect(confirm.contains("fixture-token"))
      #expect(confirm.contains("pay_fixture"))
      #expect(confirm.contains("order_fixture"))
      #expect(!confirm.contains("grossUSD") && !confirm.contains("netUSD"))
      // Exercise the actual control: setting its hidden input bypasses broken menus.
      try await page.locator("[data-dropdown-id=sponsor-frequency] button").click()
      try await expect(page.locator("#sponsor-checkout-form .dropdown-view [data-dropdown-menu]")).toHaveAttribute("data-open", "true")
      try await page.locator("#sponsor-checkout-form .dropdown-view [data-dropdown-option][data-value=monthly]").click()
      try await expect(page.locator("[data-dropdown-id=sponsor-frequency] .dropdown-selected-text")).toContainText("Monthly")
      try await expect(page.locator("#sponsor-checkout-form .dropdown-view [data-dropdown-menu]")).toHaveAttribute("data-open", "false")
      #expect(try await page.evaluate("document.querySelector('[name=frequency]').value === 'monthly'", as: Bool.self))
      try await page.locator("#sponsor-checkout-form button[type=submit]").click()
      try await expect(page.locator("#sponsor-checkout-receipt a")).toHaveAttribute("href", "/sponsor-gnorium/receipts/fixture?token=fixture-token")
      _ = try await page.evaluate("(async () => { for(let i=0;i<100 && window.__razorpayOptions.subscription_id!=='sub_fixture';i++) await new Promise(r=>setTimeout(r,10)); return true; })()", as: Bool.self)
      #expect(try await page.evaluate("window.__razorpayOptions.subscription_id === 'sub_fixture'", as: Bool.self))
      #expect(try await page.evaluate("window.__sponsorCalls[2].body.frequency === 'monthly'", as: Bool.self),
        "A genuine Monthly selection must reach the checkout request")
      _ = try await page.evaluate("window.__razorpayOptions.modal.ondismiss(); window.__checkoutFailure=true; true;", as: Bool.self)
      try await page.locator("#sponsor-checkout-form button[type=submit]").click()
      try await expect(page.locator("#sponsor-checkout-status")).toContainText("Please try again")
      #expect(try await page.evaluate("!document.querySelector('#sponsor-checkout-form button[type=submit]').disabled", as: Bool.self))
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
      try await page.openHydrated("/\(receiptName)")
      _ = try await page.evaluate("""
        (() => { window.fetch=async (url,options) => { window.__cancelBody=JSON.parse(options.body); return new Response('{}',{status:200}); }; return true; })();
        """, as: Bool.self)
      try await page.locator("#sponsor-cancel-form button").click()
      try await expect(page.locator("#sponsor-cancel-status")).toContainText("No further payments")
      #expect(try await page.evaluate("window.__cancelBody.statusToken==='fixture-token'", as: Bool.self))
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }
}
