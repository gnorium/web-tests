# WebTests, as used in [gnorium.com](https://gnorium.com)

Browser tests in Swift, after Playwright: real Chrome and real Safari, locators that wait until an element can be acted on, and assertions that retry until the page catches up.

## Overview

WebTests drives the browsers already on a Mac. Chrome is launched headless from its installed app and spoken to over the Chrome DevTools Protocol; Safari is driven through the `safaridriver` that ships with macOS, over W3C WebDriver. Nothing is downloaded: no bundled browser, no chromedriver. Both engines sit behind one `BrowserDriver` protocol, so every test runs on both, and a third backend (WebDriver BiDi, the iOS Simulator) is three protocols away.

Zero dependencies beyond Foundation and, for the test fixture, swift-testing.

## Features

- **Two engines, one API**: Chrome (CDP) and Safari (WebDriver), picked per test
- **Isolation**: a fresh browser context per test; one shared browser process per run
- **Locators**: CSS, ARIA role and accessible name, text, label; chained, `nth`, `first`, `last`, `filter(hasText:)`
- **Auto-waiting actions**: `click`, `tap`, `fill`, `type`, `press`, `hover`, `check`, `focus` wait for attached, visible, stable, enabled and hit-testable
- **Real input**: mouse, touch and key events through the protocol, not synthetic DOM events
- **Web-first assertions**: `expect(locator).toBeVisible()`, `toHaveText`, `toHaveCSS`, `toHaveCount`, `.not`, `expect(page).toHaveURL`, all retried until a timeout
- **Diagnostics**: console errors, uncaught exceptions, failed and 4xx/5xx requests, horizontal overflow with the elements that cause it
- **Failure artifacts**: a screenshot, the page's text and its diagnostics, saved and printed on every failure
- **Emulation**: viewport size, device scale, touch and a mobile user agent (Chrome)

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/gnorium/web-tests", branch: "main")
]
```

```swift
.testTarget(
    name: "YourWebTests",
    dependencies: [
        .product(name: "WebTests", package: "web-tests"),
        .product(name: "WebTestsTesting", package: "web-tests"),
    ]
)
```

## Usage

```swift
import Testing
import WebTests
import WebTestsTesting

let site = BrowserTestConfiguration.fromEnvironment(prefix: "MYSITE", defaultBaseURL: "http://localhost:8080")

@Test(arguments: site.engines)
func signInPageHydrates(engine: BrowserEngine) async throws {
    try await withPage(engine, site, viewport: .phone) { page in
        try await page.goto("/auth/sign-in", waitUntil: .networkIdle)
        try await expect(page.getByRole(.heading, name: "Sign in")).toBeVisible()

        try await page.getByLabel("Email or username").fill("reader@example.com")
        try await page.getByRole(.button, name: "Continue").click()
        try await expect(page.getByRole(.alert)).toContainText("password")

        try await page.expectNoErrors()
        try await page.expectNoHorizontalOverflow()
    }
}
```

`withPage` launches (or reuses) the engine's browser, opens a fresh context and page at the given viewport, runs the body, and closes the context. A failure is recorded at the line that failed, after a screenshot, the page's text and its diagnostics are written to `$TMPDIR/web-tests-artifacts/<test>-<engine>-<time>/`, whose path is printed. A browser that cannot run here cancels the test with the reason rather than failing it.

Without swift-testing, use the core directly:

```swift
let browser = try await Browser.launch(.chrome)
let context = try await browser.newContext(baseURL: URL(string: "http://localhost:8080"))
try await context.addCookies([Cookie(name: "session", value: token, url: baseURL)])
let page = try await context.newPage()
try await page.setViewport(.desktop)
try await page.goto("/")
let title: String = try await page.evaluate("document.title", as: String.self)
try await page.screenshot(to: URL(fileURLWithPath: "/tmp/home.png"))
await context.close()
await browser.close()
```

### Locators

| Call | Matches |
|---|---|
| `page.locator("nav a")` | CSS |
| `page.getByRole(.button, name: "Save")` | explicit or implicit ARIA role; accessible name contains "Save" (case-insensitive), or equals it with `exact: true`; hidden elements left out |
| `page.getByText("Attributed")` | the smallest elements whose text contains it |
| `page.getByLabel("Email")` | controls labelled by `<label>`, `aria-labelledby` or `aria-label` |
| `.locator(…)`, `.getByRole(…)` on a locator | within its matches |
| `.nth(2)`, `.first`, `.last`, `.filter(hasText:)`, `.filter(visible:)` | narrowing |

A locator is a description, resolved afresh on every use; it never holds a stale element.

### Actions and when they run

An action waits, retrying every 100 ms up to the page's `defaultTimeout` (5 s), until its locator matches **exactly one** element (strict mode) and that element is:

1. **attached** to the document;
2. **visible**: a non-empty box, not `display: none` or `visibility: hidden`;
3. **stable**: the same bounding box across two animation frames (scrolled into view first if it was off screen);
4. **enabled**: not `disabled`, not inside `aria-disabled="true"` (`click`, `check`); **editable** as well for `fill`;
5. **the target**: `elementFromPoint` at the click point is the element or inside it, not an overlay.

Then it dispatches real input at the element's centre. A timeout names the check that never held:

```
click on getByRole(.button, name: "Done") timed out after 5s:
<div class="modal-backdrop"> would receive the pointer event at (412, 380) instead of <button class="date-picker-done">Done
```

Keys are DOM key names or chords: `"Enter"`, `"Escape"`, `"Tab"`, `"ArrowDown"`, `"PageUp"`, `"Shift+PageDown"`, `"Control+a"`.

### Assertions

`expect(locator)`: `toBeVisible`, `toBeHidden`, `toBeAttached`, `toBeEnabled`, `toBeDisabled`, `toBeChecked`, `toBeFocused`, `toHaveText`, `toContainText`, `toHaveTexts`, `toHaveAttribute`, `toHaveCount`, `toHaveCSS`, `toHaveValue`, `toHaveAccessibleName`, each negated by `.not`.

`expect(page)`: `toHaveURL` (exact, or a predicate), `toHaveTitle`.

Each reads the page again until it holds or the timeout passes (`expect(x, timeout: .seconds(10))`), and fails with what it last saw. For layout, `locator.boundingBox()` gives the box in CSS pixels, and `page.expectNoHorizontalOverflow()` fails with the deepest elements that stick out.

### Diagnostics

`page.diagnostics()` returns every console error, uncaught exception and failed request since the page opened; `page.expectNoErrors()` fails on any of them from the page's own origin (`sameOriginOnly: false` to include third parties, `ignoring:` for known noise).

## Running

```sh
swift test                                  # every engine
BROWSERS=chrome swift test                  # Chrome only
WEB_TESTS_HEADED=1 swift test               # watch Chrome work
```

| Variable | Meaning |
|---|---|
| `<PREFIX>_BASE_URL` | where relative URLs point (for Gnorium, `GNORIUM_BASE_URL`, default `http://localhost:8080`) |
| `BROWSERS` | `chrome`, `safari` or `chrome,safari` (the default) |
| `WEB_TESTS_CHROME` | another Chrome binary |
| `WEB_TESTS_HEADED` | `1` shows Chrome's window |
| `WEB_TESTS_ARTIFACTS` | where failure artifacts go |

### Safari setup (once)

Safari refuses automation until it is allowed, which needs an administrator:

1. `sudo safaridriver --enable`
2. Safari → Settings → Advanced → tick **Show features for web developers**.
3. Develop menu → tick **Allow Remote Automation**.
4. Quit Safari completely. A Safari that was already running when automation was enabled times out when asked for a session.

Until then, Safari tests are skipped with these steps as the reason.

## Gnorium's tests

`Tests/GnoriumWebTests` runs against the dev server (`make dev`, port 8080), on both engines:

- **Hydration smoke**: home, biblio-records, lexico-records, a biblio record and sign-in load, start the WebAssembly client, log no errors, have no same-origin request fail, and do not scroll sideways, at 375 wide (touch in Chrome) and at 1400.
- **Watchtower**: each permit link opens the records page whose Treatment filter (or Pipelines, as it may be named) shows the link's phrase.
- **Footer**: the links sit in one wrapping flex row, with no "|" separators in text or CSS.
- **Date picker**: on Mission Control's contributors page, "Active since date" opens Gnorium's popover (not a native picker, and by tap on a touch phone), as wide as its field; ArrowRight, Enter, Reset, Done and Esc work.
- **Field validation**: account forms carry `novalidate`, so an empty sign-in shows Gnorium's inline messages (with `aria-invalid` and `aria-describedby`) instead of the browser's bubbles and sends nothing; register names each broken rule.
- **Account core**: every centred-card page (sign in, register, choose your username, forgot and reset password, the admin console sign-in, verify email, and change password and delete account signed in) draws one card: centred both ways between the header and the footer, the same width, 40px padding and a 28px normal-weight centred title, never scrolling sideways; the admin console's refusal (`?error=invalid`) is drawn in it, and text that isn't an error code never is. Nothing is submitted; the tokens are fake.
- **Delete account**: a throwaway account reaches Delete Account from its menu; a wrong password and an unticked box delete nothing; then it deletes itself, and its row keeps only the username (email, password hash and names erased).
- **Sign out**: the account menu's Sign Out is a POST form (no sign-out link anywhere), drawn like Delete Account beside it; submitting it signs the browser out and deletes that session on the server.
- **Form item rows**: on the Submit Amendment form, removing a middle author renumbers the rows after it and the form serializes both remaining rows. Nothing is submitted.
- **Amendment attribution**: on the Submit Amendment form, every field, row, date part and field of a creation statement has its own attribution box, ticked by editing that field alone. Nothing is submitted.

The date picker, form item rows, amendment attribution and change password tests need an admin. Each registers a throwaway account over HTTP with a random password that never leaves memory, makes it an admin with one `UPDATE` in the dev database (`GNORIUM_DATABASE_URL`, psql from `GNORIUM_PSQL` or Homebrew), signs it in over HTTP, sets the session cookie in the browser context, and deletes that account's row afterwards. No one's password is typed anywhere.

## Design notes

**Why CDP for Chrome, WebDriver for Safari.** Playwright gets its reach from patched browsers; WebTests uses only what ships. Chrome's DevTools Protocol gives everything a test needs over one WebSocket (isolated contexts, real input, emulation, console and network events), spoken with Foundation's `URLSessionWebSocketTask` so there is no swift-nio. Safari offers W3C WebDriver through `safaridriver`; Safari 27 answers `webSocketUrl: true` but reports `safari:experimentalWebSocketUrl: false` and gives no BiDi endpoint, so the backend is WebDriver classic. When Safari ships BiDi, it is a new `BrowserDriver`, not a rewrite.

**One page-side script.** Resolving a locator, the actionability checks and the reads assertions make are one JavaScript function, evaluated with each call rather than installed, so no navigation can leave a stale copy and both engines share it exactly.

**Waiting, not sleeping.** Actions and assertions poll (at 0, 20, 50, 100 ms, then every 100 ms) and report the last state they saw. Transient errors while a page navigates are retried, not failed.

**What Safari cannot do, honestly:**

- No headless mode: each test opens an automation window (the striped address bar), separate from your own browsing.
- One session at a time: Safari tests run one after another even when the suite runs in parallel.
- Pointer input reaches only the key window. With another app in front, Safari silently drops simulated clicks (keys still arrive), and a page loaded in a window behind others gets no animation frames, so anything it defers to one (Gnorium's secondary hydration) never runs. The driver therefore brings Safari to the front (`open -b com.apple.Safari`) before each navigation and each pointer action, and sends an action again if focus was lost while it ran. Safari tests take the screen: leave the Mac alone while they run. Clicking in the automation window yourself ends the session.
- No touch or mobile emulation: a touch viewport throws `EngineLimitation`, which skips the test; `Viewport.narrow` (375×812 with a mouse) gives the phone layout. A real phone is the iOS Simulator's job (`safaridriver` has a `safari:useSimulator` capability), a possible later backend.
- No console or network events: a capture script is injected after each navigation. It hooks `console.error`, `error` and `unhandledrejection`, wraps `fetch` to see statuses, and catches failed subresources by their `error` events. Errors thrown before it is installed (while the document first loads) are missed, and only `fetch` responses carry a status (Safari has no `PerformanceResourceTiming.responseStatus`).
- Errors thrown by scripts that WebDriver itself injects are reported by Safari only as "Script error.".
- `safaridriver` sends Shift with a named key (`Shift+PageDown`) as a keydown whose `key` is empty.

**Out of scope, on purpose:** Firefox and other engines, tracing and trace viewers, test code generation, visual diffing of screenshots, network interception and mocking, iframes and shadow-DOM piercing in selectors, file uploads, downloads. The core is small so it can be trusted; each of these can grow on the driver protocols later.

## Requirements

- macOS 14 or later, Swift 6.2 tools (built and tested with Swift 6.4)
- Google Chrome in `/Applications` for the Chrome engine
- Safari with remote automation allowed for the Safari engine

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.

## Related Packages

- [admin-core](https://github.com/gnorium/admin-core) - Core admin functionalities for web applications
- [artifact-core](https://github.com/gnorium/artifact-core) - IIIF Presentation API v3 types + deep zoom viewer
- [design-tokens](https://github.com/gnorium/design-tokens) - Universal design tokens based on Apple HIG
- [diff-engine](https://github.com/gnorium/diff-engine) - Platform-agnostic character-level diff engine
- [embedded-swift-utilities](https://github.com/gnorium/embedded-swift-utilities) - Utility functions for Embedded Swift environments
- [markdown-utilities](https://github.com/gnorium/markdown-utilities) - Markdown rendering with extended syntax
- [tex-utilities](https://github.com/gnorium/tex-utilities) - TeX formula rendering with locally served KaTeX
- [web-apis](https://github.com/gnorium/web-apis) - Web API implementations for Swift WebAssembly
- [web-builders](https://github.com/gnorium/web-builders) - HTML, CSS, JS, and SVG DSL builders
- [web-components](https://github.com/gnorium/web-components) - Reusable UI components for web applications
- [web-formats](https://github.com/gnorium/web-formats) - Structured data format builders
- [web-security](https://github.com/gnorium/web-security) - Portable security utilities for web applications
- [web-types](https://github.com/gnorium/web-types) - Shared web types for web applications
- [xml-utilities](https://github.com/gnorium/xml-utilities) - XML and TEI rendering utilities
