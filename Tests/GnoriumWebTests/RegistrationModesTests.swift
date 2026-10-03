import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Verified registration modes", .serialized)
struct RegistrationModesTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func verifyEmailBeforeCredentialsAndSubmitFrozenEmailContext(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    guard let fixture = ProcessInfo.processInfo.environment["GNORIUM_REGISTER_FIXTURE_PATH"] else {
      try Test.cancel("Export both registration modes first.")
    }
    let publicDirectory = URL(fileURLWithPath: "/Users/Madhavik/Downloads/Gnorium/gnorium-web/Public")
    for complete in [false, true] {
      let file = publicDirectory.appendingPathComponent("register-fixture-\(UUID()).html")
      try Data(contentsOf: URL(fileURLWithPath: fixture + (complete ? ".complete.html" : ""))).write(to: file)
      defer { try? FileManager.default.removeItem(at: file) }
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
        try await page.openHydrated("/\(file.lastPathComponent)")
        let form = page.locator(".register-form")
        try await expect(form.locator("#email")).toHaveCount(complete ? 0 : 1)
        for field in ["full-name", "username", "password", "confirmPassword", "terms-and-policy"] {
          try await expect(form.locator("#\(field)")).toHaveCount(complete ? 1 : 0)
        }
        _ = try await page.evaluate("""
          (() => {
            window.__registrationRequests = [];
            const original = window.fetch;
            window.fetch = async (url, options) => {
              if (String(url) === '/auth/register' && options?.method?.toUpperCase() === 'POST') {
                window.__registrationRequests.push(String(options.body));
                return new Response(JSON.stringify({success:false,message:'Fixture intercepted safely.'}), {status:400});
              }
              return original(url, options);
            };
            return true;
          })()
          """, as: Bool.self)
        if complete {
          try await expect(page.locator(".datum-view")).toContainText("verified@example.test")
          #expect(try await page.evaluate("document.querySelector('.register-form input[name=email]') === null", as: Bool.self))
          try await form.locator("#full-name").fill("Fixture Reader")
          try await form.locator("#username").fill("READER_TEST")
          try await expect(form.locator("#username")).toHaveValue("reader_test")
          try await form.locator("#password").fill("Sandbox9!NotReal")
          try await form.locator("#confirmPassword").fill("Sandbox9!NotReal")
          try await form.locator("#terms-and-policy").click()
        } else {
          try await form.locator("#email").fill("reader@example.test")
        }
        try await form.locator("button[type=submit]").click()
        try await expect(form.locator(".register-alerts")).toContainText("Fixture intercepted safely.")
        let requests = try await page.evaluate("window.__registrationRequests", as: [String].self)
        #expect(requests.count == 1)
        let payload = requests[0]
        if complete {
          #expect(payload.contains("username=reader_test"))
          #expect(try await page.evaluate("new URLSearchParams(window.__registrationRequests[0]).get('password') === 'Sandbox9!NotReal'", as: Bool.self))
          #expect(payload.contains("terms-and-policy="))
          #expect(!payload.contains("email="), "Email ownership comes from the server challenge, not client-editable data")
        } else {
          #expect(payload.contains("email=reader%40example.test"))
          #expect(!payload.contains("username=") && !payload.contains("password=") && !payload.contains("terms-and-policy="))
        }
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
    }
  }
}
