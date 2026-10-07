import Foundation
import Testing
import WebTests
import WebTestsTesting

/// One field in place of "dropdown, Other, a second field to name it"
/// (user, 2026-09-29): a COMBOBOX (the WAI-ARIA combobox pattern, list
/// autocomplete). The reader types; the suggestions below narrow as they
/// type; choosing one takes it, and a value no suggestion names is kept as
/// typed. No "Other" option, no reveal field. On Submit Testament: a genre
/// row, the provider, the holding institution (its panel of facts for a
/// listed one only) and a citation's classification scheme. Keyboard: the
/// arrow keys move through the suggestions (aria-activedescendant), Enter
/// and Tab take the one the keys are on, Escape closes the list and a
/// second Escape clears the field. Screen readers: the field is a named
/// `combobox` controlling a `listbox` of `option`s, aria-expanded as the
/// list shows. Submitted, the typed values are stored as typed. Chrome, phone
/// and desktop; a throwaway admin owns every row submitted, removed after.
@Suite("Combobox", .serialized)
struct ComboboxTests {
  static let form = "/mission-control/submit/bibliographic/evidence-testament"

  @Test(arguments: gnorium.engines, Layout.allCases)
  func aComboboxSuggestsAndKeepsWhatIsTyped(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let suffix = String(UUID().uuidString.prefix(8)).lowercased()
    // A manifest the server can read: it reads the Source URL before it
    // takes the submission.
    let path = "/web-tests-combobox-\(suffix)/manifest.json"
    let fixtures = try await FixtureServer.manifest(at: path)
    defer { fixtures.stop() }
    let source = fixtures.baseURL + path
    func clean() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM bibliographic_overtures WHERE bibliographic_instance_id IN
          (SELECT id FROM bibliographic_instances WHERE source_url = '\(source)');
        UPDATE bibliographic_instances SET deleted_at = now(), deleted_by = '\(admin.username)'
          WHERE source_url = '\(source)' AND deleted_at IS NULL;
        COMMIT;
        """)
    }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await run(page, suffix: suffix, source: source)
        // The fixture manifest's page images are nowhere: the viewer's asks for them fail.
        try await page.expectNoErrors(ignoring: ["/web-tests-combobox-"])
      }
    } catch {
      clean()
      try await admin.remove(after: error)
    }
    clean()
    try await admin.remove()
  }

  private func run(_ page: Page, suffix: String, source: String) async throws {
    try await page.openHydrated(Self.form)
    let form = page.locator(".submit-testament-form")
    // The rows' hidden templates carry the same fields: the live ones only.
    let live = ":not([data-item-template] *)"

    // No "Other" anywhere, and no field to name one.
    try await expect(form.locator("input[name$='-other']")).toHaveCount(0)
    try await expect(form.locator("[data-value='other']")).toHaveCount(0)

    // MARK: A genre row, by the keyboard.
    let genre = form.locator("[data-item-list='work-genre'] .combobox-view\(live)").first
    let field = genre.getByRole(.combobox, name: "Genre")
    let value = genre.locator("input[type='hidden']")
    try await expect(field).toHaveCount(1)
    try await expect(field).toHaveAttribute("aria-autocomplete", "list")
    try await expect(field).toHaveAttribute("aria-expanded", "false")
    let listboxID = try await field.getAttribute("aria-controls") ?? ""
    #expect(!listboxID.isEmpty, "The field names the list it controls.")
    // Hidden from everyone while shut: found by its role once shown.
    let listbox = genre.locator("[role='listbox']")
    try await expect(listbox).toHaveAttribute("id", listboxID)
    try await expect(listbox).toBeHidden()

    // Typing narrows the list to what matches, and opens it.
    try await field.type("trag")
    try await expect(field).toHaveAttribute("aria-expanded", "true")
    try await expect(genre.getByRole(.listbox)).toBeVisible()
    let shown = listbox.getByRole(.option).filter(visible: true)
    try await expect(shown.first).toBeVisible()
    for text in try await shown.allInnerTexts() {
      #expect(text.lowercased().contains("trag"), "\(text) matches what is typed.")
    }
    // The arrow keys move through the suggestions, the field saying which.
    try await page.keyboard.press("ArrowDown")
    let first = shown.first
    let firstID = try await first.getAttribute("id") ?? ""
    try await expect(field).toHaveAttribute("aria-activedescendant", firstID)
    try await expect(first).toHaveAttribute("aria-selected", "true")
    // Enter takes it: its name in the field, its value posted, the list shut.
    let name = try await first.getAttribute("data-display") ?? ""
    let picked = try await first.getAttribute("data-value") ?? ""
    try await page.keyboard.press("Enter")
    try await expect(field).toHaveValue(name)
    try await expect(value).toHaveValue(picked)
    try await expect(field).toHaveAttribute("aria-expanded", "false")
    try await expect(field).not.toHaveAttribute("aria-activedescendant")

    // Escape closes the list and keeps the text; a second clears the field.
    try await field.fill("")
    try await field.type("com")
    try await expect(field).toHaveAttribute("aria-expanded", "true")
    try await page.keyboard.press("Escape")
    try await expect(field).toHaveAttribute("aria-expanded", "false")
    try await expect(field).toHaveValue("com")
    try await page.keyboard.press("Escape")
    try await expect(field).toHaveValue("")
    try await expect(value).toHaveValue("")

    // Tab takes the suggestion the keys are on, and the focus moves on.
    try await field.type("com")
    try await page.keyboard.press("ArrowDown")
    let tabbed = listbox.getByRole(.option).filter(visible: true).first
    let tabbedValue = try await tabbed.getAttribute("data-value") ?? ""
    try await page.keyboard.press("Tab")
    try await expect(value).toHaveValue(tabbedValue)
    try await expect(field).not.toBeFocused()

    // A genre the list does not have is kept as typed.
    let typedGenre = "Web tests genre \(suffix)"
    try await field.fill(typedGenre)
    try await expect(value).toHaveValue(typedGenre)
    try await expect(field).toHaveAttribute("aria-expanded", "false")

    // MARK: The provider, by the pointer: the toggle shows every suggestion.
    let carrier = form.locator(".dropdown-view:has(#testament-carrier)")
    try await carrier.locator(".dropdown-trigger").click()
    try await carrier.locator(".dropdown-option[data-value='printed']").click()
    let provider = form.locator(".combobox-view:has(input[name='provider-dropdown'])")
    let providerField = provider.getByRole(.combobox, name: "Provider")
    try await provider.locator(".combobox-toggle").click()
    try await expect(providerField).toHaveAttribute("aria-expanded", "true")
    let library = provider.locator(".combobox-option[data-value='british_library']")
    try await library.click()
    try await expect(providerField).toHaveValue("British Library")
    try await expect(provider.locator("input[name='provider-dropdown']")).toHaveValue("british_library")
    // A name typed as the list writes it, letter case aside, is that one.
    try await providerField.fill("internet archive")
    try await expect(provider.locator("input[name='provider-dropdown']")).toHaveValue("internet_archive")
    let typedProvider = "Web Tests Provider \(suffix)"
    try await providerField.fill(typedProvider)
    try await expect(provider.locator("input[name='provider-dropdown']")).toHaveValue(typedProvider)

    // MARK: The holding institution: a listed one shows its facts, a typed
    // one has none to show.
    let holding = form.locator(".form-info-view:has(input[name='holding-institution-dropdown'])")
    let holdingField = holding.getByRole(.combobox, name: "Holding institution")
    let panel = holding.locator(".form-info-panel")
    try await holdingField.fill("Folger Shakespeare Library")
    try await expect(holding.locator("input[name='holding-institution-dropdown']"))
      .toHaveValue("folger_shakespeare_library")
    try await expect(panel).toBeVisible()
    try await expect(panel.locator("input[id$='-info-institutionCity']")).toHaveValue("Washington")
    let typedHolding = "Web Tests Library \(suffix)"
    try await holdingField.fill(typedHolding)
    try await expect(holding.locator("input[name='holding-institution-dropdown']")).toHaveValue(typedHolding)
    try await expect(panel).toBeHidden()

    // MARK: A citation's scheme: a combobox of a row, its panel as a
    // listed scheme's.
    let citation = form.locator("[data-item-list='reference-citation'] .combobox-view\(live)").first
    try await expect(citation.getByRole(.combobox, name: "Classification scheme")).toHaveCount(1)

    // A long suggestion wraps on a phone as on a desktop: nothing runs past
    // the page.
    // An emptied field lists every suggestion; the toggle shuts and opens it.
    try await providerField.fill("")
    try await expect(providerField).toHaveAttribute("aria-expanded", "true")
    try await provider.locator(".combobox-toggle").click()
    try await expect(providerField).toHaveAttribute("aria-expanded", "false")
    try await provider.locator(".combobox-toggle").click()
    try await expect(provider.getByRole(.listbox)).toBeVisible()
    try await page.expectNoHorizontalOverflow()
    try await page.keyboard.press("Escape")

    // MARK: Submitted, the typed values are stored as typed.
    try await providerField.fill(typedProvider)
    _ = try await page.evaluate(
      """
      (() => {
        for (const [id, value] of [['work-language', 'eng'], ['work-type', 'report']]) {
          const input = document.getElementById(id);
          input.value = value;
          input.dispatchEvent(new Event('change'));
        }
      })()
      """)
    let apparatus = form.locator("#metadata")
    try await apparatus.locator("input[name='title']").fill("Web tests combobox \(suffix)")
    try await apparatus.locator(
      "[data-item-list='work-voice'] [data-item-section='true']\(live) .text-input-input"
    ).first.fill("Web Tests Author \(suffix)")
    try await form.locator("input[name='source-url']").fill(source)
    // Every level is shown in a new testament: the impression and the
    // issue left empty would be refused, so they are taken out.
    try await Self.removeLevels(form, ["impression", "issue"])
    try await form.locator(".record-actions button[type='submit']").click()
    try await expect(page, timeout: .seconds(15)).toHaveURL("the Mission Control page") {
      $0.path == "/mission-control"
    }
    let row = try TestAdmin.query(
      """
      SELECT coalesce(provider, '') || '|' || coalesce(holding_institution, '') || '|' || coalesce(genres_json, '')
        FROM bibliographic_instances WHERE source_url = '\(source)';
      """
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(row == "\(typedProvider)|\(typedHolding)|[\"\(typedGenre)\"]", "\(row)")
  }

  /// The new testament's `levels` taken out, each by its node's own −.
  static func removeLevels(_ form: Locator, _ levels: [String]) async throws {
    for level in levels {
      let node = form.locator(".outliner-item[data-outliner-id='\(level)-new']")
      try await node.locator(":scope > .outliner-footer .testament-draft-remove-level").click()
      try await expect(node).toHaveAttribute("data-outliner-removed", "true")
    }
  }

  /// A voice's name suggests, as it is typed, the names already on works'
  /// voices (the server's, fetched as typed): chosen, a suggestion is its
  /// name, plain text, never a link (user, 2026-10-03), and a name typed and
  /// not chosen is stored as typed. Chrome, phone and desktop; a scratch
  /// work voiced by a typed author, removed after.
  @Test(arguments: gnorium.engines, Layout.allCases)
  func aVoiceNameSuggestsTheNamesOnWorks(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let path = "/web-tests-combobox-voice-\(work.suffix)/manifest.json"
    let fixtures = try await FixtureServer.manifest(at: path)
    defer { fixtures.stop() }
    let source = fixtures.baseURL + path
    func clean() {
      _ = try? TestAdmin.query(
        """
        BEGIN;
        DELETE FROM bibliographic_overtures WHERE bibliographic_instance_id IN
          (SELECT id FROM bibliographic_instances WHERE source_url = '\(source)');
        UPDATE bibliographic_instances SET deleted_at = now(), deleted_by = '\(admin.username)'
          WHERE source_url = '\(source)' AND deleted_at IS NULL;
        COMMIT;
        """)
    }
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated(Self.form)
        let form = page.locator(".submit-testament-form")
        let rows = "[data-item-list='work-voice'] [data-item-section='true']:not([data-item-template] *)"
        let voice = form.locator("\(rows) .combobox-view").first
        let field = voice.getByRole(.combobox, name: "Voice name")
        let value = voice.locator("input[type='hidden']")
        try await expect(field).toHaveCount(1)

        // Typed, the server's suggestions: the scratch work's author among
        // them, by name alone (no count, gnorium-server 473d4e0).
        try await field.type(work.suffix)
        let option = voice.locator(".combobox-option[data-value='\(work.author)']")
        try await expect(option, timeout: .seconds(10)).toBeVisible()
        try await expect(option).toHaveAttribute("role", "option")
        try await expect(option).toHaveAttribute("data-display", work.author)
        try await expect(option).toHaveText(work.author)
        // Not chosen, the text is the name as typed.
        try await expect(value).toHaveValue(work.suffix)
        // Chosen by the keys: the name, and nothing else.
        while try await option.getAttribute("aria-selected") != "true" {
          try await page.keyboard.press("ArrowDown")
        }
        try await page.keyboard.press("Enter")
        try await expect(field).toHaveValue(work.author)
        try await expect(value).toHaveValue(work.author)
        try await page.expectNoHorizontalOverflow()

        // Submitted, the voice is its name and role: no record, no
        // sentiment.
        _ = try await page.evaluate(
          """
          (() => {
            for (const [id, value] of [['work-language', 'eng'], ['work-type', 'report']]) {
              const input = document.getElementById(id);
              input.value = value;
              input.dispatchEvent(new Event('change'));
            }
          })()
          """)
        let carrier = form.locator(".dropdown-view:has(#testament-carrier)")
        try await carrier.locator(".dropdown-trigger").click()
        try await carrier.locator(".dropdown-option[data-value='printed']").click()
        try await form.locator("#metadata input[name='title']").fill("Web tests voice \(work.suffix)")
        // No impression, issue or copy to say: their nodes removed, as an
        // empty one is refused.
        try await Self.removeLevels(form, ["impression", "issue", "copy"])
        try await form.locator(".combobox-view:has(input[name='provider-dropdown']) .text-input-input").fill("Gallica")
        try await form.locator("input[name='source-url']").fill(source)
        try await form.locator(".record-actions button[type='submit']").click()
        try await expect(page, timeout: .seconds(15)).toHaveURL("the Mission Control page") {
          $0.path == "/mission-control"
        }
        let stored = try TestAdmin.query(
          "SELECT voices_json FROM bibliographic_instances WHERE source_url = '\(source)';"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(stored.contains(work.author), "\(stored)")
        #expect(!stored.contains("lexicoRecord") && !stored.contains("sentiment"), "\(stored)")

        // Chosen, then edited: the edited text, as typed.
        try await page.openHydrated(Self.form)
        let again = page.locator(".submit-testament-form \(rows) .combobox-view").first
        let againField = again.getByRole(.combobox, name: "Voice name")
        try await againField.type(work.suffix)
        let againOption = again.locator(".combobox-option[data-value='\(work.author)']")
        try await againOption.click()
        try await expect(again.locator("input[type='hidden']")).toHaveValue(work.author)
        try await againField.type(" Jr.")
        try await expect(again.locator("input[type='hidden']")).toHaveValue("\(work.author) Jr.")
        // The fixture manifest's page images are nowhere: the viewer's asks for them fail.
        try await page.expectNoErrors(ignoring: ["/web-tests-combobox-"])
      }
    } catch {
      clean()
      work.remove()
      try await admin.remove(after: error)
    }
    clean()
    work.remove()
    try await admin.remove()
  }
}
