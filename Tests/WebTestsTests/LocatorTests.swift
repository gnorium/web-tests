import Foundation
import Testing
import WebTests
import WebTestsTesting

// The library against pages it writes itself: no server needed.

let configuration = BrowserTestConfiguration.fromEnvironment(prefix: "WEB_TESTS", defaultBaseURL: "about:blank")

@Suite("Locators and auto-waiting")
struct LocatorTests {
  @Test(arguments: configuration.engines)
  func findsByRoleTextAndLabel(engine: BrowserEngine) async throws {
    try await withPage(engine, configuration) { page in
      try await page.setContent(
        """
        <main>
          <h1>Settings</h1>
          <label for="email">Email address</label><input id="email">
          <input aria-label="Search the site" type="search">
          <button>Save <span aria-hidden="true">✓</span></button>
          <button style="display:none">Save hidden</button>
          <a href="#one">First link</a> <a href="#two">Second link</a>
          <p>Some <b>bold</b> words</p>
        </main>
        """)
      try await expect(page.getByRole(.heading, name: "settings")).toBeVisible()
      try await expect(page.getByRole(.button, name: "Save", exact: true)).toHaveCount(1)
      try await expect(page.getByRole(.link)).toHaveCount(2)
      try await expect(page.getByRole(.link).last).toHaveText("Second link")
      try await expect(page.getByLabel("Email address")).toHaveAttribute("id", "email")
      try await expect(page.getByRole(.searchbox, name: "Search the site")).toBeVisible()
      try await expect(page.getByText("bold words", exact: true)).toHaveCount(0)
      try await expect(page.getByText("Some bold words")).toHaveText("Some bold words")
      try await expect(page.locator("main").getByText("bold", exact: true)).toHaveCount(1)
    }
  }

  @Test(arguments: configuration.engines)
  func clickWaitsForAnElementThatAppearsLater(engine: BrowserEngine) async throws {
    try await withPage(engine, configuration) { page in
      try await page.setContent(
        """
        <div id="out">idle</div>
        <script>
          setTimeout(() => {
            const b = document.createElement('button');
            b.textContent = 'Late';
            b.onclick = () => document.getElementById('out').textContent = 'clicked';
            document.body.append(b);
          }, 400);
        </script>
        """)
      try await page.getByRole(.button, name: "Late").click()
      try await expect(page.locator("#out")).toHaveText("clicked")
    }
  }

  @Test(arguments: configuration.engines)
  func clickWaitsForAnimationAndEnablement(engine: BrowserEngine) async throws {
    try await withPage(engine, configuration) { page in
      try await page.setContent(
        """
        <style>
          #b { position: relative; left: 0; transition: left 300ms linear; }
          #b.moved { left: 200px; }
        </style>
        <button id="b" disabled onclick="this.textContent = 'done'">Go</button>
        <script>
          requestAnimationFrame(() => document.getElementById('b').classList.add('moved'));
          setTimeout(() => document.getElementById('b').disabled = false, 350);
        </script>
        """)
      try await page.locator("#b").click()
      try await expect(page.locator("#b")).toHaveText("done")
    }
  }

  @Test(arguments: configuration.engines)
  func aCoveredElementIsReportedNotClicked(engine: BrowserEngine) async throws {
    try await withPage(engine, configuration) { page in
      try await page.setContent(
        """
        <button id="under" onclick="this.textContent = 'hit'">Under</button>
        <div id="veil" style="position:fixed; inset:0; background:rgb(0 0 0 / 0.2)"></div>
        """)
      page.defaultTimeout = .milliseconds(600)
      do {
        try await page.locator("#under").click()
        Issue.record("the click went through the overlay")
      } catch let error as WebTestError {
        #expect(error.message.contains("would receive the pointer event"))
        #expect(error.message.contains("veil"))
      }
      try await expect(page.locator("#under")).toHaveText("Under")
    }
  }

  @Test(arguments: configuration.engines)
  func strictModeRefusesAmbiguousActions(engine: BrowserEngine) async throws {
    try await withPage(engine, configuration) { page in
      try await page.setContent("<button>One</button><button>Two</button>")
      page.defaultTimeout = .milliseconds(300)
      do {
        try await page.getByRole(.button).click()
        Issue.record("an ambiguous click went through")
      } catch let error as WebTestError {
        #expect(error.message.contains("strict mode"))
        #expect(error.message.contains("2 elements"))
      }
    }
  }

  @Test(arguments: configuration.engines)
  func fillTypeAndKeys(engine: BrowserEngine) async throws {
    try await withPage(engine, configuration) { page in
      try await page.setContent(
        """
        <input id="name" value="old">
        <div id="log"></div>
        <script>
          const log = document.getElementById('log');
          document.addEventListener('keydown', (e) => log.textContent += (e.shiftKey ? 'Shift+' : '') + e.key + ' ');
        </script>
        """)
      let field = page.locator("#name")
      try await field.fill("Ada Lovelace")
      try await expect(field).toHaveValue("Ada Lovelace")
      try await field.fill("")
      try await expect(field).toHaveValue("")
      try await field.type("ab")
      try await expect(field).toHaveValue("ab")
      try await field.press("PageDown")
      try await page.keyboard.press("Escape")
      try await page.keyboard.press("ArrowRight")
      try await expect(page.locator("#log")).toContainText("PageDown Escape ArrowRight")
      // safaridriver sends Shift with a named key as a keydown whose `key` is
      // empty (Safari 27), so the chord is checked where it arrives intact.
      if engine == .chrome {
        try await page.keyboard.press("Shift+PageDown")
        try await expect(page.locator("#log")).toContainText("Shift+PageDown")
      }
    }
  }

  @Test(arguments: configuration.engines)
  func cssAndLayoutReads(engine: BrowserEngine) async throws {
    try await withPage(engine, configuration) { page in
      try await page.setContent(
        """
        <nav style="display:flex; flex-wrap:wrap; gap:8px; width:300px">
          <a href="#">A</a><a href="#">B</a>
        </nav>
        <div id="wide" style="width:3000px; height:10px"></div>
        """)
      try await expect(page.locator("nav")).toHaveCSS("flex-wrap", "wrap")
      let box = try #require(try await page.locator("nav").boundingBox())
      #expect(box.width == 300)
      let overflow = try #require(try await page.horizontalOverflow())
      #expect(overflow.offenders.contains { $0.contains("wide") })
      try await page.evaluate("document.getElementById('wide').remove()")
      try await page.expectNoHorizontalOverflow()
    }
  }

  @Test(arguments: configuration.engines)
  func collectsConsoleErrorsAndExceptions(engine: BrowserEngine) async throws {
    try await withPage(engine, configuration) { page in
      // The error comes from the page's own script: Safari reports errors
      // from WebDriver-injected code only as "Script error.".
      try await page.setContent(
        """
        <button onclick="setTimeout(() => { console.error('boom from test'); throw new Error('thrown from test'); }, 0)">Fail</button>
        """)
      try await page.expectNoErrors()
      try await page.getByRole(.button, name: "Fail").click()
      try await Task.sleep(for: .milliseconds(200))
      let diagnostics = try await page.diagnostics()
      #expect(diagnostics.contains { $0.kind == .consoleError && $0.message.contains("boom from test") })
      #expect(diagnostics.contains { $0.kind == .pageError && $0.message.contains("thrown from test") })
    }
  }
}
