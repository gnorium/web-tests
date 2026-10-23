import Foundation
import Testing
import WebTests
import WebTestsTesting

/// An explication is one process, the process's own (user, 2026-09-29): no
/// Sight, Proof or Vouch cards, and one session a chunk of pages—never a
/// row a page—whose trace shows the tool calls it read and saved with.
@Suite("Bibliographic explication sessions", .serialized)
struct BibliographicExplicationSessionsTests {
  /// The sessions' table, which owns their traces (`SessionTrace`).
  static let nocturnes = "bibliographic_explication_nocturne_instances"
  static let page = #"<TEI xmlns="http://www.tei-c.org/ns/1.0"><text><body><pb n="1"/><p><s><w lemma="sea" class="noun">sea</w></s><lb/></p></body></text></TEI>"#

  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aBibliographicExplicationShowsItsChunkSessionsAndNoProcesses(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphonID = UUID().uuidString.lowercased()
    let nocturneID = UUID().uuidString.lowercased()
    do {
      let user = try admin.column("id")
      let autoID = try TestAdmin.query("SELECT vignette_id FROM active_prompt_vignettes WHERE slot = 'bibliographic_explication'").trimmingCharacters(in: .whitespacesAndNewlines)
      let blocks: [[String: String]] = [
        ["type": "image_url", "content": "https://example.org/iiif/web-tests/full/1300,/0/default.jpg"],
        ["type": "thinking", "content": "Reading the first page of the `chunk`."],
        [
          "type": "tool", "name": "save_page", "arguments": "{}",
          "result": #"{"ok": true, "tool": "save_page", "saved": "1", "findings_count": 0}"#,
          "status": "ok", "call_id": "call_1",
        ],
        ["type": "image_xml", "label": "1", "content": Self.page],
        ["type": "image_xml", "label": "2", "content": Self.page],
        [
          "type": "compaction", "mode": "auto", "micro": "0", "tokens_before": "100", "tokens_after": "60",
          "template_id": autoID, "system_prompt": "Summarize this session.",
          "prompt": "Summarize.", "summary": "Kept **both** pages and `save_page`.",
        ],
        ["type": "text", "content": "Both pages of the chunk saved with `save_page`.\n\n## Saved\n\n```json\n{\"ok\": true}\n```"],
      ]
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, image_service_ids_json, processing_status)
          VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO bibliographic_explication_nocturnes (id, bibliographic_antiphon_id, submission_id, process, image, instance_count)
         VALUES (md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1–2')::text, ''))::uuid, '\(antiphonID)', (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'), 'explication', '1–2', 1)
         ON CONFLICT (id) DO UPDATE SET instance_count = bibliographic_explication_nocturnes.instance_count + 1;
        INSERT INTO bibliographic_explication_nocturne_instances (id, nocturne_id, submission_id, process, image, instance, provider, model, result, nocturne_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
        VALUES ('\(nocturneID)', md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1–2')::text, ''))::uuid, (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'), 'explication', '1–2', 1, 'DeepSeek', 'deepseek-flash', 'passed', gen_random_uuid(), '\(antiphonID)', 1200, now());
        \(try SessionTrace.append(blocks, table: Self.nocturnes, id: nocturneID))
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/antiphons/bibliographic/\(antiphonID)")
        try await ComputoriumMarks.check(page, process: "explication")
        try await ComputoriumMarks.checkThinking(page, process: "explication")
        // No process cards: the process is the process's name.
        try await expect(page.locator(".processes-view")).toHaveCount(0)
        try await expect(page.getByText("Processes", exact: true)).toHaveCount(0)
        try await expect(page.locator("a[href*='process=']")).toHaveCount(0)
        try await expect(page.locator(".process-container")).toHaveAttribute("data-active-process", "explication")
        // One session for the chunk, not a row for each of its pages (the
        // sidebar is drawn twice, for wide screens and the phone's menu).
        // The roster is Evidence, as the Disputorium's (user, 2026-10-09).
        try await expect(page.locator(".computorium-core-sidebar-processes-heading").first).toHaveText("Evidence")
        let rows = page.locator(".computorium-core-sessions-slot").first.locator(".roster-row")
        try await expect(rows).toHaveCount(1)
        try await expect(rows.first).toHaveAttribute("data-computorium-session-label", "1–2")
        // Its search is the site's search box, large as every field (user,
        // 2026-10-10: medium only in furniture): 48 tall (12 inside its
        // border on every side, a 22px line), its text 16px. Hidden on a
        // phone, so its inset is read, not its box.
        let roster = page.locator(".computorium-core-sessions-slot").first
        let search = roster.locator(".roster-search-input .search-input")
        let large = try await search.evaluate(
          """
          (el) => { const row = el.closest('.roster-view').querySelector('.roster-row');
            return !!row && el.closest('.search-input-view').dataset.size === 'large'
              && el.placeholder === 'Search evidence' && el.getAttribute('aria-label') === 'Search evidence'
              && getComputedStyle(el).fontSize === '16px'
              && getComputedStyle(el).paddingTop === '12px' && getComputedStyle(el).paddingBottom === '12px'
              && getComputedStyle(el).lineHeight === '22px'; }
          """).bool == true
        #expect(large, "The roster's search is a large search input, its text 16px")
        // It filters the items, the list drawing those it leaves (user,
        // 2026-10-11: a windowed roster).
        if layout == .desktop {
          try await search.fill("no such session")
          try await expect(rows).toHaveCount(0)
          try await search.fill("1–2")
          try await expect(rows.first).toHaveAttribute("data-hidden", "false")
        }
        // Its trace: the tool call it saved a page with, and its last word.
        try await expect(page.locator(".computorium-session-view").getByText("save_page").first).toBeAttached()
        try await expect(page.locator(".computorium-session-view .computorium-session-output-rendered")).toContainText("Both pages of the chunk saved")
        // Raw and code read at CodeEditorView's size, 16 on 22 (user,
        // 2026-10-08): the wire's dump, a tool's arguments and result, and
        // a page's code alike, shown or not.
        let offSize = try await page.evaluate(
          """
          [...document.querySelectorAll('.computorium-session-view :is(.computorium-session-output-raw, .computorium-session-prompt-body, .tool-field-block, .code-view)')]
            .map(e => { const s = getComputedStyle(e); return [e.className, s.fontSize, s.lineHeight]; })
            .filter(([, size, height]) => size !== '16px' || height !== '22px')
            .map(r => r.join(' ')).join('; ')
          """, as: String.self)
        #expect(offSize.isEmpty, "Raw and code at 16px on 22px: \(offSize)")
        // The formatted text beside them at 16 too, on the body's leading
        // (user, 2026-10-08), so switching Raw never changes the size: the
        // output, the thinking, the compaction summary and a prompt's
        // Markdown, inline code following the prose.
        let proseOff = try await page.evaluate(
          """
          (() => {
            const prose = [...document.querySelectorAll('.computorium-session-view :is(.computorium-session-output-rendered, .computorium-session-output-thinking-body .markdown-view, .computorium-session-compaction-summary, .computorium-session-prompt-rendered)')];
            const blocks = prose.flatMap(e => [e, ...e.querySelectorAll(':scope p, :scope li, :scope p > code')]);
            const off = blocks.map(e => { const s = getComputedStyle(e); return [e.tagName + '.' + e.className, s.fontSize, s.lineHeight]; })
              .filter(([, size, height]) => size !== '16px' || height !== '26px');
            const kinds = ['.computorium-session-output-rendered', '.markdown-view', '.computorium-session-compaction-summary', '.computorium-session-prompt-rendered']
              .filter(k => !prose.some(e => e.matches(k)));
            const codes = prose.flatMap(e => [...e.querySelectorAll(':scope p > code')]).length;
            // Headings on the scale's own pairs, never the prose's leading
            // multiplied up; a fence's language label at the 16px floor, on 22.
            const pairs = { H1: '24px/34px', H2: '20px/30px', H3: '18px/28px', H4: '16px/26px' };
            const heads = prose.flatMap(e => [...e.querySelectorAll(':scope h1, :scope h2, :scope h3, :scope h4')])
              .filter(h => !h.closest('.computorium-session-compaction-summary'));
            const headOff = heads.map(h => { const s = getComputedStyle(h); return [h.tagName, s.fontSize + '/' + s.lineHeight]; })
              .filter(([tag, pair]) => pairs[tag] !== pair).map(r => 'heading ' + r.join(' '));
            const labels = prose.flatMap(e => [...e.querySelectorAll('.code-block-lang')]);
            const labelOff = labels.map(l => { const s = getComputedStyle(l); return s.fontSize + '/' + s.lineHeight; })
              .filter(pair => pair !== '16px/22px').map(pair => 'label ' + pair);
            return [...off.map(r => r.join(' ')), ...headOff, ...labelOff, ...kinds.map(k => 'missing ' + k),
              codes < 3 ? 'inline code missing' : '', heads.length ? '' : 'heading missing', labels.length ? '' : 'label missing']
              .filter(Boolean).join('; ');
          })()
          """, as: String.self)
        #expect(proseOff.isEmpty, "Formatted text at 16px on 26px: \(proseOff)")
        // The legend's (i) names the template; its bubble, portaled to
        // <body> once hydrated (TooltipView, 2026-10-13), links its process's
        // prompts with the vignette's UUID.
        try await expect(page.locator(".computorium-session-compaction-prompt-fieldset .computorium-session-prompt-legend-vignette")).toHaveCount(1)
        let legend = page.locator(".tooltip-view[data-portal='true'] .tooltip-content a[href='/mission-control/prompts/bibliographic/explication']")
        try await expect(legend).toHaveCount(1)
        try await expect(legend).toHaveText(autoID)
        // Only the UUID, linked and whole (user, 2026-10-21): no words
        // around it.
        try await expect(page.locator(".tooltip-view[data-portal='true'] .tooltip-content:has(a[href='/mission-control/prompts/bibliographic/explication'])"))
          .toHaveText(autoID)
        // The autocompaction card is white; the prompt the summarizer was
        // given and the summary the main model is given from then on are
        // gray cards on it, each under its legend (user, 2026-10-10).
        try await expect(page.locator(".computorium-session-compaction-summary-fieldset legend")).toHaveText("Autocompaction Summary")
        #expect(try await page.evaluate("""
          (() => {
            const probe = document.createElement('span'); document.body.append(probe)
            const token = (name) => { probe.style.backgroundColor = 'var(--background-color-' + name + ')'; return getComputedStyle(probe).backgroundColor }
            const [white, seen] = [token('base'), token('neutral-subtle')]; probe.remove()
            const bg = (el) => getComputedStyle(el).backgroundColor
            const card = document.querySelector('.computorium-session-compaction-rendered')
            const prompt = document.querySelector('.computorium-session-compaction-prompt-fieldset')
            const summary = document.querySelector('.computorium-session-compaction-summary-fieldset')
            // Their legends are the boxes' last rows: 16 on every side
            // (user, 2026-10-12).
            const even = [prompt, summary].every(e => getComputedStyle(e).paddingBottom === '16px')
            return [bg(card) === white, bg(prompt) === seen, bg(summary) === seen, bg(summary.querySelector('legend')) === seen, even].join(' ')
          })()
          """, as: String.self) == "true true true true true", "Compaction card white, its prompt and summary gray, legends inside")
        // Raw is the chat template's text only: none recorded, none drawn.
        let rawCount = try await page.locator(".computorium-session-view .computorium-session-output-raw").count()
        #expect(rawCount == 0)
      }
    } catch {
      remove(nocturneID: nocturneID, antiphonID: antiphonID, work: work)
      try await admin.remove(after: error)
    }
    remove(nocturneID: nocturneID, antiphonID: antiphonID, work: work)
    try await admin.remove()
  }

  /// A zoom's card shows its datums, its source and sent pixels among them;
  /// its region shows once, where the model received it (user, 2026-10-16
  /// and 2026-10-17): in the round's image message after the call, under
  /// its caption, a full-width stage at the pixels it was sent, zoomed in
  /// place—never inside the tool card, no lightbox.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func aZoomCardShowsItsDetail(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphonID = UUID().uuidString.lowercased()
    let nocturneID = UUID().uuidString.lowercased()
    func image(_ width: Int, _ height: Int) -> String {
      let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='\(width)' height='\(height)'><rect width='100%' height='100%' fill='#ccc'/></svg>"
      return "data:image/svg+xml;base64," + Data(svg.utf8).base64EncodedString()
    }
    do {
      let user = try admin.column("id")
      // The region as sent, recorded after the call with its pixels as sent
      // (`image_sent_event`'s `width` and `height`): an image that loads, so
      // the stage keeps its address (one that fails is swapped for a blank).
      let region = image(600, 400)
      // Written in a fixed order: the card keeps the JSON's own.
      let result = """
        {"ok": true, "tool": "zoom_image", "page": "1", "region": [100, 250, 300, 200], "image": "attached below", \
        "source_width": 1200, "source_height": 800, "sent_width": 600, "sent_height": 400}
        """
      let blocks: [[String: String]] = [
        [
          "type": "tool", "name": "zoom_image", "arguments": #"{"x": 100, "y": 250, "width": 300, "height": 200}"#,
          "result": result,
          "status": "ok", "call_id": "call_zoom",
        ],
        [
          "type": "image_sent", "url": region, "source_sha256": "a", "sha256": "b", "caption": "Region",
          "width": "600", "height": "400",
        ],
        ["type": "text", "content": "Looked closer."],
      ]
      _ = try TestAdmin.query(
        """
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, image_service_ids_json, processing_status)
          VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO bibliographic_explication_nocturnes (id, bibliographic_antiphon_id, submission_id, process, image, instance_count)
         VALUES (md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid, '\(antiphonID)', (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'), 'explication', '1', 1)
         ON CONFLICT (id) DO UPDATE SET instance_count = bibliographic_explication_nocturnes.instance_count + 1;
        INSERT INTO bibliographic_explication_nocturne_instances (id, nocturne_id, submission_id, process, image, instance, provider, model, result, nocturne_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
        VALUES ('\(nocturneID)', md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid, (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'), 'explication', '1', 1, 'DeepSeek', 'deepseek-flash', 'passed', gen_random_uuid(), '\(antiphonID)', 1200, now());
        \(try SessionTrace.append(blocks, table: Self.nocturnes, id: nocturneID))
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/antiphons/bibliographic/\(antiphonID)")
        let card = page.locator("#computorium-session-tool-call_zoom")
        try await card.locator(".accordion-summary").first.click()
        // Its body, drawn when first opened: its datums, and no image.
        let box = card.locator(".computorium-session-tool-call-result-box")
        try await expect(box).toBeVisible()
        try await expect(card.locator(".detail-view, .expandable-attachment-view, img")).toHaveCount(0)
        // The region in the round's image message, under its caption: the
        // stage as wide as its box, the image at its sent pixels, zoomed in
        // place—no chip, no lightbox.
        let turn = page.locator(".computorium-session-view .computorium-session-image-turn")
        try await expect(turn).toHaveCount(1)
        try await expect(turn.locator(".message-blocks-text")).toHaveText("Region")
        let received = turn.locator(".expandable-attachment-view[data-presentation='received']")
        try await expect(received).toHaveCount(1)
        try await expect(received.locator(".expandable-attachment-image-frame")).toBeVisible()
        let sent = received.locator("img.expandable-attachment-image-received")
        try await expect(sent).toHaveAttribute("src", region)
        try await expect(sent).toHaveAttribute("width", "600")
        try await expect(sent).toHaveAttribute("height", "400")
        try await expect(turn.locator(".expandable-attachment-trigger, .expandable-attachment-dialog")).toHaveCount(0)
        let fullWidth = try await page.evaluate("""
          (() => {
            const turn = document.querySelector('.computorium-session-view .computorium-session-image-turn');
            const blocks = turn.querySelector('.message-blocks-view'), s = getComputedStyle(blocks);
            const inner = blocks.clientWidth - parseFloat(s.paddingLeft) - parseFloat(s.paddingRight);
            const frame = turn.querySelector('.expandable-attachment-image-frame').getBoundingClientRect();
            return Math.abs(frame.width - inner) <= 1;
          })()
          """, as: Bool.self)
        #expect(fullWidth, "The received stage spans its message's width")
        // The sizes the model received, under its own keys, in the result box.
        try await expect(box).toContainText("source_width")
        try await expect(box).toContainText("1200")
        try await expect(box).toContainText("sent_width")
        try await expect(box).toContainText("600")
        // Every other key too (user, 2026-10-07): the region as sent, and
        // `image` as the model read it.
        func labels(_ selector: String) async throws -> String {
          try await page.evaluate(
            "[...document.querySelectorAll('#computorium-session-tool-call_zoom \(selector) .datum-label')].map(l => l.textContent.trim()).join(' ')",
            as: String.self)
        }
        let resultLabels = try await labels(".computorium-session-tool-call-result-box")
        #expect(
          resultLabels == "ok tool page region image source_width source_height sent_width sent_height",
          "Every key the zoom returned, in the JSON's order: \(resultLabels)")
        try await expect(box).toContainText("[100, 250, 300, 200]")
        // The arguments as sent, each its own datum.
        let argumentLabels = try await labels(".computorium-session-tool-call-args")
        #expect(argumentLabels == "x y width height", "Every argument, in the JSON's order: \(argumentLabels)")
        // The card fits the phone: no sideways scroll.
        let overflow = try await page.evaluate("document.documentElement.scrollWidth > document.documentElement.clientWidth")
        #expect(overflow == .bool(false))
      }
    } catch {
      remove(nocturneID: nocturneID, antiphonID: antiphonID, work: work)
      try await admin.remove(after: error)
    }
    remove(nocturneID: nocturneID, antiphonID: antiphonID, work: work)
    try await admin.remove()
  }

  @Test(arguments: [BrowserEngine.chrome])
  func replayClearsEveryBlockAndRebuildsTheFinishedTraceTwice(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphonID = UUID().uuidString.lowercased()
    let nocturneID = UUID().uuidString.lowercased()
    let otherNocturneID = UUID().uuidString.lowercased()
    let failedNocturneID = UUID().uuidString.lowercased()
    do {
      let user = try admin.column("id")
      let blocks: [[String: String]] = [
        ["type": "thinking", "content": "Reading the first page before saving the recorded result."],
        ["type": "text", "content": "The first passage is ready."],
        ["type": "tool", "name": "save_page", "arguments": #"{"page":"1"}"#,
          "result": #"{"ok":true,"saved":"1"}"#, "status": "ok", "call_id": "replay_save"],
        ["type": "thinking", "content": "Checking the saved passage before finishing the session."],
        ["type": "compaction", "mode": "micro", "micro": "1", "tokens_before": "100", "tokens_after": "60",
          "summary": "Kept the saved passage."],
        ["type": "text", "content": "Replay finished with **every** recorded block."],
      ]
      // A replay plays a trace at the pace its events arrived: the blocks
      // 300ms apart, so the running card fills before it finishes.
      _ = try TestAdmin.query("""
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, image_service_ids_json, processing_status)
          VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO bibliographic_explication_nocturnes (id, bibliographic_antiphon_id, submission_id, process, image, instance_count)
         VALUES (md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid, '\(antiphonID)', (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'), 'explication', '1', 1)
         ON CONFLICT (id) DO UPDATE SET instance_count = bibliographic_explication_nocturnes.instance_count + 1;
        INSERT INTO bibliographic_explication_nocturne_instances (id, nocturne_id, submission_id, process, image, instance, provider, model, result, nocturne_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
        VALUES ('\(nocturneID)', md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid, (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'), 'explication', '1', 2, 'DeepSeek', 'deepseek-flash', 'passed', gen_random_uuid(), '\(antiphonID)', 3000, now());
        \(try SessionTrace.append(blocks, table: Self.nocturnes, id: nocturneID, stepMs: 300))
        INSERT INTO bibliographic_explication_nocturnes (id, bibliographic_antiphon_id, submission_id, process, image, instance_count)
         VALUES (md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid, '\(antiphonID)', (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'), 'explication', '1', 1)
         ON CONFLICT (id) DO UPDATE SET instance_count = bibliographic_explication_nocturnes.instance_count + 1;
        INSERT INTO bibliographic_explication_nocturne_instances (id, nocturne_id, submission_id, process, image, instance, provider, model, result, nocturne_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
        VALUES ('\(failedNocturneID)', md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid, (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'), 'explication', '1', 1, 'DeepSeek', 'deepseek-flash', 'failed', gen_random_uuid(), '\(antiphonID)', 500, now() - interval '1 second');
        \(try SessionTrace.append([["type": "thinking", "content": "Historical partial thought."]], table: Self.nocturnes, id: failedNocturneID))
        INSERT INTO bibliographic_explication_nocturnes (id, bibliographic_antiphon_id, submission_id, process, image, instance_count)
         VALUES (md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('2')::text, ''))::uuid, '\(antiphonID)', (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'), 'explication', '2', 1)
         ON CONFLICT (id) DO UPDATE SET instance_count = bibliographic_explication_nocturnes.instance_count + 1;
        INSERT INTO bibliographic_explication_nocturne_instances (id, nocturne_id, submission_id, process, image, instance, provider, model, result, nocturne_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
        VALUES ('\(otherNocturneID)', md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('2')::text, ''))::uuid, (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'), 'explication', '2', 1, 'DeepSeek', 'deepseek-flash', 'passed', gen_random_uuid(), '\(antiphonID)', 100, now());
        \(try SessionTrace.append([["type": "text", "content": "Another finished session."]], table: Self.nocturnes, id: otherNocturneID))
        COMMIT;
        """)
      try await withPage(engine, gnorium, cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/antiphons/bibliographic/\(antiphonID)?image=1")
        let session = page.locator(".computorium-session-view")
        let replay = page.locator(".replay-btn")
        let snapshot = """
          (() => {
            const root = document.querySelector('.computorium-session-output-content');
            const text = selector => [...root.querySelectorAll(selector)].map(e => e.textContent.trim().replace(/\\s+/g, ' '));
            return JSON.stringify({
              thinking: text('.computorium-session-output-thinking-body .markdown-view'),
              tools: text('.computorium-session-tool-call-name'),
              arguments: text('.computorium-session-tool-call-args'),
              results: text('.computorium-session-tool-call-result-box'),
              compactions: text('.computorium-session-compaction-summary'),
              output: text('.computorium-session-output-rendered').filter(Boolean)
            });
          })()
          """
        let finished = try await page.evaluate(snapshot, as: String.self)
        let otherRows = page.locator(".roster-row[data-computorium-session-label='2']")
        try await expect(otherRows.first).toHaveAttribute("data-computorium-session-status", "succeeded")
        try await expect(session.locator(".computorium-session-output-thinking")).toHaveCount(2)
        try await expect(session.locator(".computorium-session-tool-call")).toHaveCount(1)
        for attempt in 1...2 {
          // Observe the real click after hydration's handler, before any SSE
          // callback can run. This catches stale cards even on a busy machine.
          try await page.evaluate("""
            (() => {
              const root = document.querySelector('.computorium-session-output-content');
              const session = document.querySelector('.computorium-session-view');
              window.replayStart = null;
              window.replayFilledWhileRunning = false;
              document.querySelector('.replay-btn').addEventListener('click', () => {
                window.replayStart = { children: root.childElementCount, text: root.textContent,
                  status: session.dataset.computoriumSessionStatus };
                const observer = new MutationObserver(() => {
                  if (session.dataset.computoriumSessionStatus === 'running' && root.textContent.trim()
                      && !root.textContent.includes('Replay finished with')) window.replayFilledWhileRunning = true;
                  if (session.dataset.computoriumSessionStatus === 'succeeded') observer.disconnect();
                });
                observer.observe(session, { childList: true, subtree: true, characterData: true, attributes: true });
              }, { once: true });
            })()
            """)
          try await replay.click()
          let empty = try await page.evaluate("window.replayStart.children === 0 && window.replayStart.text === '' && window.replayStart.status === 'running'", as: Bool.self)
          #expect(empty, "Replay \(attempt) synchronously clears every finished block into an empty running shell")
          try await expect(replay, timeout: .seconds(20)).toBeEnabled()
          try await expect(session).toHaveAttribute("data-computorium-session-status", "succeeded")
          #expect(try await page.evaluate("window.replayFilledWhileRunning", as: Bool.self), "Stored trace fills the running card at replay pace")
          #expect(try await page.evaluate(snapshot, as: String.self) == finished, "Replay \(attempt) finishes with the original thinking, tools, compaction and output")
          // As live: the tool, Tools and compaction cards arrive closed and
          // stay closed; the thinking card streams open and stays open
          // (user, 2026-10-10).
          #expect(try await page.evaluate("""
            (() => {
              const closed = [...document.querySelectorAll(':is(.computorium-session-tool-call, .computorium-session-tools-rendered, .computorium-session-compaction) details, details:is(.computorium-session-tool-call, .computorium-session-tools-rendered, .computorium-session-compaction)')]
              const thinking = [...document.querySelectorAll('.computorium-session-output-thinking details, details.computorium-session-output-thinking')]
              return closed.length > 0 && closed.every(d => !d.open) && thinking.length > 0 && thinking.every(d => d.open)
            })()
            """, as: Bool.self), "Replay \(attempt) leaves cards as live leaves them: thinking open, the rest closed")
          try await expect(session.locator(".computorium-session-output-thinking-running")).toHaveCount(0)
          try await expect(otherRows.first).toHaveAttribute("data-computorium-session-status", "succeeded")
        }
        // An older failed instance remains failed in the card, while the list
        // continues to report the session's later successful result.
        try await page.openHydrated("/mission-control/antiphons/bibliographic/\(antiphonID)?image=1&instance=1")
        try await expect(session).toHaveAttribute("data-computorium-session-status", "failed")
        let currentRows = page.locator(".roster-row[data-computorium-session-label='1']")
        try await expect(currentRows.first).toHaveAttribute("data-computorium-session-status", "succeeded")
        let historical = try await page.evaluate(snapshot, as: String.self)
        try await replay.click()
        try await expect(currentRows.first).toHaveAttribute("data-computorium-session-status", "succeeded")
        try await expect(replay, timeout: .seconds(20)).toBeEnabled()
        try await expect(session).toHaveAttribute("data-computorium-session-status", "failed")
        try await expect(currentRows.first).toHaveAttribute("data-computorium-session-status", "succeeded")
        #expect(try await page.evaluate(snapshot, as: String.self) == historical)
        try await page.expectNoErrors()
      }
    } catch {
      remove(nocturneID: nocturneID, antiphonID: antiphonID, work: work)
      try await admin.remove(after: error)
    }
    remove(nocturneID: nocturneID, antiphonID: antiphonID, work: work)
    try await admin.remove()
  }

  /// The placement rule (user, 2026-10-17): the session's label at the top
  /// left of its card, the evidence pager right after it in the title
  /// block; at its foot one row of controls from the start edge—Raw, the
  /// info icon, and right after it the nocturne's instances' pager (two
  /// instances, the latest shown), next to it, not at the end edge.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func pagersSitBesideWhatTheyPage(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphonID = UUID().uuidString.lowercased()
    let nocturneIDs = (0..<3).map { _ in UUID().uuidString.lowercased() }
    func cleanup() {
      remove(nocturneID: nocturneIDs[0], antiphonID: antiphonID, work: work)
    }
    do {
      let user = try admin.column("id")
      let batch = "(SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())')"
      let columns = "(id, nocturne_id, submission_id, process, image, instance, provider, model, result, nocturne_batch_id, bibliographic_antiphon_id, duration_ms, created_at)"
      func text(_ content: String) -> [[String: String]] { [["type": "text", "content": content]] }
      _ = try TestAdmin.query("""
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, image_service_ids_json, processing_status)
          VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO bibliographic_explication_nocturnes (id, bibliographic_antiphon_id, submission_id, process, image, instance_count)
         VALUES (md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid, '\(antiphonID)', \(batch), 'explication', '1', 1)
         ON CONFLICT (id) DO UPDATE SET instance_count = bibliographic_explication_nocturnes.instance_count + 1;
        INSERT INTO bibliographic_explication_nocturne_instances \(columns)
        VALUES ('\(nocturneIDs[0])', md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid, \(batch), 'explication', '1', 2, 'DeepSeek', 'deepseek-flash', 'passed', gen_random_uuid(), '\(antiphonID)', 300, now());
        \(try SessionTrace.append(text("The second instance."), table: Self.nocturnes, id: nocturneIDs[0]))
        INSERT INTO bibliographic_explication_nocturnes (id, bibliographic_antiphon_id, submission_id, process, image, instance_count)
         VALUES (md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid, '\(antiphonID)', \(batch), 'explication', '1', 1)
         ON CONFLICT (id) DO UPDATE SET instance_count = bibliographic_explication_nocturnes.instance_count + 1;
        INSERT INTO bibliographic_explication_nocturne_instances \(columns)
        VALUES ('\(nocturneIDs[1])', md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid, \(batch), 'explication', '1', 1, 'DeepSeek', 'deepseek-flash', 'passed', gen_random_uuid(), '\(antiphonID)', 300, now() - interval '1 second');
        \(try SessionTrace.append(text("The first instance."), table: Self.nocturnes, id: nocturneIDs[1]))
        INSERT INTO bibliographic_explication_nocturnes (id, bibliographic_antiphon_id, submission_id, process, image, instance_count)
         VALUES (md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('2')::text, ''))::uuid, '\(antiphonID)', \(batch), 'explication', '2', 1)
         ON CONFLICT (id) DO UPDATE SET instance_count = bibliographic_explication_nocturnes.instance_count + 1;
        INSERT INTO bibliographic_explication_nocturne_instances \(columns)
        VALUES ('\(nocturneIDs[2])', md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('2')::text, ''))::uuid, \(batch), 'explication', '2', 1, 'DeepSeek', 'deepseek-flash', 'passed', gen_random_uuid(), '\(antiphonID)', 100, now());
        \(try SessionTrace.append(text("Another page."), table: Self.nocturnes, id: nocturneIDs[2]))
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/antiphons/bibliographic/\(antiphonID)?image=1")
        try await expect(page.locator(".computorium-session-title-block .computorium-session-page-nav")).toBeVisible()
        try await expect(page.locator(".computorium-session-controls .computorium-session-page-nav")).toHaveCount(0)
        let instances = page.locator(".computorium-session-controls-start .computorium-session-instance-nav")
        try await expect(instances).toBeVisible()
        try await expect(instances.locator(".page-box")).toHaveValue("2")
        try await expect(instances).toHaveAttribute("data-count", "2")
        try await expect(instances).toHaveAttribute("aria-label", "Instances")
        let report = try await page.evaluate(
          """
          (() => {
            const r = (s) => document.querySelector(s)?.getBoundingClientRect();
            const card = r('.computorium-session-view'), pager = r('.computorium-session-title-block .computorium-session-page-nav');
            const label = r('.computorium-session-header .computorium-session-title-image');
            const raw = r('.computorium-session-controls-start .computorium-session-markdown-toggle');
            const info = r('.computorium-session-controls-start .computorium-session-byline');
            const instances = r('.computorium-session-controls-start .computorium-session-instance-nav');
            const out = [];
            if (!card || !pager || !label || !raw || !info || !instances) return 'missing';
            // The evidence pager right after the label, in the title block.
            const labelEl = document.querySelector('.computorium-session-title-image');
            if (!labelEl.nextElementSibling?.classList.contains('computorium-session-page-nav')) out.push('evidence pager not after the label');
            if (pager.left < label.right) out.push('evidence pager overlaps the label');
            if (Math.abs((label.top + label.bottom) / 2 - (pager.top + pager.bottom) / 2) > 4) out.push('label and evidence pager not on one line');
            // The row is the session's last: under everything it controls.
            const session = document.querySelector('.computorium-session-view');
            if (!session.lastElementChild?.classList.contains('computorium-session-controls')) out.push('controls not at the foot');
            if (Math.abs(raw.left - card.left) > 1) out.push('raw not at the start: ' + (raw.left - card.left));
            // The instances' pager next to the info icon, a gap apart, not at the end edge.
            if (Math.abs(instances.left - info.right - 8) > 1) out.push('instance pager ' + (instances.left - info.right) + ' from the info icon');
            if (Math.abs((info.top + info.bottom) / 2 - (instances.top + instances.bottom) / 2) > 1) out.push('info and instance pager not on one line');
            if (instances.right > card.right - 16) out.push('instance pager at the end edge');
            // Raw, then the info icon, then the instances' pager.
            const start = document.querySelector('.computorium-session-controls-start');
            const kinds = [...start.children].map(e => e.classList.contains('computorium-session-markdown-toggle') ? 'raw'
              : e.classList.contains('computorium-session-byline') ? 'info'
              : e.classList.contains('computorium-session-instance-nav') ? 'instances' : 'other').join(' ');
            if (kinds !== 'raw info instances') out.push('controls ' + kinds);
            // A prompt's legend: its title, then its vignette's id, no Raw of
            // its own (the session's one is in the controls row).
            const inset = (e) => { const s = getComputedStyle(e); return s.paddingTop + ' ' + s.paddingBottom; };
            for (const field of document.querySelectorAll('.computorium-session-prompt-fieldset:has(> .prompt-legend-view)')) {
              const legend = field.querySelector(':scope > .prompt-legend-view');
              const order = [...legend.children].map(e => e.classList.contains('computorium-session-prompt-legend-title') ? 'title'
                : e.classList.contains('computorium-session-prompt-legend-vignette') ? 'id' : 'other').join(' ');
              if (order !== 'title' && order !== 'title id') out.push('prompt legend ' + order);
              const f = field.getBoundingClientRect(), l = legend.getBoundingClientRect();
              // Hung on its box's bottom border at the start, 16 in
              // (2026-10-13; spacing kept 2026-10-15).
              if (Math.abs(l.left - (f.left + 1 + 16)) > 1) out.push('prompt legend not at the start: ' + (l.left - f.left));
              if (Math.abs((l.top + l.bottom) / 2 - f.bottom) > 2) out.push('prompt legend off the border: ' + ((l.top + l.bottom) / 2 - f.bottom));
              // No control on it: 16 on every side.
              if (inset(field) !== '16px 16px') out.push('prompt inset ' + inset(field));
            }
            return out.join('; ');
          })()
          """, as: String.self)
        #expect(report.isEmpty, "\(layout): \(report)")
        try await page.expectNoHorizontalOverflow()
      }
    } catch {
      cleanup()
      try await admin.remove(after: error)
    }
    cleanup()
    try await admin.remove()
  }

  /// A session's task prompt is the one it sent, filled—its image, its
  /// neighbors, its conventions—as its trace recorded it (user,
  /// 2026-10-10), never the template's slots; a nocturne from before the trace
  /// recorded it shows its vignette's template, as it always has.
  @Test(arguments: [BrowserEngine.chrome])
  func aSessionShowsTheTaskPromptItSent(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphonID = UUID().uuidString.lowercased()
    let nocturneIDs = (0..<2).map { _ in UUID().uuidString.lowercased() }
    func cleanup() {
      remove(nocturneID: nocturneIDs[0], antiphonID: antiphonID, work: work)
    }
    do {
      let user = try admin.column("id")
      let vignette = try TestAdmin.query(
        "SELECT vignette_id FROM active_prompt_vignettes WHERE slot = 'bibliographic_explication'"
      ).trimmingCharacters(in: .whitespacesAndNewlines)
      let template = try TestAdmin.query("SELECT task_prompt FROM prompt_vignettes WHERE id = '\(vignette)'")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let sent = "Transcribe the image \"1\", shown above, exactly as it appears on its surface.\n\nThe last sentence of the image before: none (this is the witness's first canvas image)"
      let recorded: [[String: String]] = [
        ["type": "image_url", "content": "https://example.org/iiif/web-tests/full/1300,/0/default.jpg"],
        ["type": "task_prompt_instance", "content": sent, "system_prompt": "Read the image as sent.", "template_id": vignette.uppercased()],
        ["type": "text", "content": "Saved."],
      ]
      let old: [[String: String]] = [
        ["type": "image_url", "content": "https://example.org/iiif/web-tests/full/1300,/0/default.jpg"],
        ["type": "text", "content": "Saved."],
      ]
      let batch = "(SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())')"
      let columns = "(id, nocturne_id, submission_id, process, image, instance, provider, model, result, nocturne_batch_id, bibliographic_antiphon_id, duration_ms, prompt_vignette_id, created_at)"
      _ = try TestAdmin.query("""
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, image_service_ids_json, processing_status)
          VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO bibliographic_explication_nocturnes (id, bibliographic_antiphon_id, submission_id, process, image, instance_count)
         VALUES (md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid, '\(antiphonID)', \(batch), 'explication', '1', 1)
         ON CONFLICT (id) DO UPDATE SET instance_count = bibliographic_explication_nocturnes.instance_count + 1;
        INSERT INTO bibliographic_explication_nocturne_instances \(columns)
        VALUES ('\(nocturneIDs[0])', md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid, \(batch), 'explication', '1', 1, 'DeepSeek', 'deepseek-flash', 'passed', gen_random_uuid(), '\(antiphonID)', 300, '\(vignette)', now());
        \(try SessionTrace.append(recorded, table: Self.nocturnes, id: nocturneIDs[0]))
        INSERT INTO bibliographic_explication_nocturnes (id, bibliographic_antiphon_id, submission_id, process, image, instance_count)
         VALUES (md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('2')::text, ''))::uuid, '\(antiphonID)', \(batch), 'explication', '2', 1)
         ON CONFLICT (id) DO UPDATE SET instance_count = bibliographic_explication_nocturnes.instance_count + 1;
        INSERT INTO bibliographic_explication_nocturne_instances \(columns)
        VALUES ('\(nocturneIDs[1])', md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('2')::text, ''))::uuid, \(batch), 'explication', '2', 1, 'DeepSeek', 'deepseek-flash', 'passed', gen_random_uuid(), '\(antiphonID)', 300, '\(vignette)', now());
        \(try SessionTrace.append(old, table: Self.nocturnes, id: nocturneIDs[1]))
        COMMIT;
        """)
      let task = ".computorium-session-view .computorium-session-task-fieldset .computorium-session-prompt-body"
      let system = ".computorium-session-view .computorium-session-prompt-fieldset:not(.computorium-session-task-fieldset) .computorium-session-prompt-body"
      try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/antiphons/bibliographic/\(antiphonID)?image=1")
        let shown = try await page.evaluate("document.querySelector('\(task)')?.textContent ?? ''", as: String.self)
        #expect(shown == sent, "The task prompt as sent: \(shown)")
        #expect(!shown.contains("{"), "No slot is left in the task prompt: \(shown)")
        try await expect(page.locator(".computorium-session-view .computorium-session-task-fieldset .computorium-session-prompt-legend-title"))
          .toHaveText("Task prompt")
        let systemShown = try await page.evaluate("document.querySelector('\(system)')?.textContent ?? ''", as: String.self)
        #expect(systemShown == "Read the image as sent.", "The system prompt as sent: \(systemShown)")
        try await page.expectNoErrors()

        try await page.openHydrated("/mission-control/antiphons/bibliographic/\(antiphonID)?image=2")
        let before = try await page.evaluate("document.querySelector('\(task)')?.textContent ?? ''", as: String.self)
        #expect(before.trimmingCharacters(in: .whitespacesAndNewlines) == template && before.contains("{evidence}"),
          "A nocturne that did not record its task shows its vignette's template")
        try await page.expectNoErrors()
      }
    } catch {
      cleanup()
      try await admin.remove(after: error)
    }
    cleanup()
    try await admin.remove()
  }

  /// A resumed session's continuation turn is a sent prompt like its
  /// System and Task prompts (user, 2026-10-15): the gray box in the base
  /// text color, its legend "Continuation prompt" then its vignette's id,
  /// rendered as Markdown, the session's one Raw (its switch in the controls
  /// row, 2026-10-16 and 2026-10-17) exactly the text sent; drawn so by the
  /// server and by the live stream (a replay) alike.
  @Test(arguments: [BrowserEngine.chrome])
  func aContinuationPromptIsASentPromptWithItsLegendAndRaw(engine: BrowserEngine) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let work = try ScratchWork(owner: admin)
    let antiphonID = UUID().uuidString.lowercased()
    let nocturneID = UUID().uuidString.lowercased()
    do {
      let user = try admin.column("id")
      let vignette = try TestAdmin.query(
        "SELECT vignette_id FROM active_prompt_vignettes WHERE slot = 'bibliographic_explication'"
      ).trimmingCharacters(in: .whitespacesAndNewlines)
      let sent = "Continue from the **retained** conversation.\n\n- Do not repeat completed tool writes."
      let sentJSON = String(decoding: try JSONEncoder().encode(sent), as: UTF8.self)
      let blocks: [[String: String]] = [
        ["type": "thinking", "content": "Reading before the Stop."],
        ["type": "continuation_prompt", "content": sent, "template_id": vignette],
        ["type": "text", "content": "Carried on."],
      ]
      _ = try TestAdmin.query("""
        BEGIN;
        INSERT INTO bibliographic_antiphons (id, bibliographic_madrigal_id, requested_by_user_id, image_service_ids_json, processing_status)
          VALUES ('\(antiphonID)', '\(work.madrigalID.lowercased())', '\(user)', '[]', 'submitted');
        INSERT INTO bibliographic_explication_nocturnes (id, bibliographic_antiphon_id, submission_id, process, image, instance_count)
         VALUES (md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid, '\(antiphonID)', (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'), 'explication', '1', 1)
         ON CONFLICT (id) DO UPDATE SET instance_count = bibliographic_explication_nocturnes.instance_count + 1;
        INSERT INTO bibliographic_explication_nocturne_instances (id, nocturne_id, submission_id, process, image, instance, provider, model, result, nocturne_batch_id, bibliographic_antiphon_id, duration_ms, created_at)
        VALUES ('\(nocturneID)', md5('head:' || ('\(antiphonID)'):: text || ':' || coalesce(('1')::text, ''))::uuid, (SELECT batch_id FROM bibliographic_overtures WHERE id = '\(work.overtureID.lowercased())'), 'explication', '1', 1, 'DeepSeek', 'deepseek-flash', 'passed', gen_random_uuid(), '\(antiphonID)', 300, now());
        \(try SessionTrace.append(blocks, table: Self.nocturnes, id: nocturneID))
        COMMIT;
        """)
      try await withPage(engine, gnorium, viewport: Layout.desktop.viewport(for: engine), cookies: [admin.cookie]) { page in
        try await page.openHydrated("/mission-control/antiphons/bibliographic/\(antiphonID)?image=1")
        let check = """
          (() => {
            const out = [];
            const boxes = document.querySelectorAll('.computorium-session-output-content .computorium-session-continuation-prompt');
            if (boxes.length !== 1) return 'boxes ' + boxes.length;
            const box = boxes[0];
            if (box.tagName !== 'FIELDSET' || !box.classList.contains('computorium-session-prompt-fieldset')) out.push('not a prompt fieldset');
            const legend = box.querySelector(':scope > .prompt-legend-view');
            const order = [...legend.children].map(e => e.classList.contains('computorium-session-prompt-legend-title') ? 'title'
              : e.classList.contains('computorium-session-prompt-legend-vignette') ? 'id' : 'other').join(' ');
            if (order !== 'title id') out.push('legend ' + order);
            const title = legend.querySelector('.computorium-session-prompt-legend-title').textContent;
            if (title !== 'Continuation prompt') out.push('title ' + title);
            const rendered = box.querySelector('.computorium-session-prompt-rendered');
            if (!rendered.querySelector('strong') || !rendered.querySelector('li')) out.push('not Markdown');
            const probe = document.createElement('span'); probe.style.color = 'var(--color-base)'; document.body.append(probe);
            const base = getComputedStyle(probe).color; probe.remove();
            if (getComputedStyle(rendered.querySelector('p')).color !== base) out.push('not the base color');
            const ground = document.createElement('span'); ground.style.backgroundColor = 'var(--background-color-neutral-subtle)'; document.body.append(ground);
            const gray = getComputedStyle(ground).backgroundColor; ground.remove();
            if (getComputedStyle(box).backgroundColor !== gray) out.push('not the gray box');
            const raw = box.querySelector('pre.computorium-session-prompt-body');
            if (raw.textContent !== \(sentJSON)) out.push('raw is not the text sent: ' + JSON.stringify(raw.textContent));
            if (getComputedStyle(raw).display !== 'none') out.push('raw shown before the switch');
            return out.join('; ');
          })()
          """
        let served = try await page.evaluate(check, as: String.self)
        #expect(served.isEmpty, "server: \(served)")
        // The session's one Raw, in its controls row.
        let session = page.locator(".computorium-session-view")
        let toggle = page.locator(".computorium-session-controls .computorium-session-markdown-toggle button").first
        try await toggle.click()
        try await expect(session).toHaveAttribute("data-raw-view", "true")
        try await expect(page.locator(".computorium-session-continuation-prompt pre.computorium-session-prompt-body")).toBeVisible()
        // Rendered again before the replay, which keeps the session's Raw as
        // it is.
        try await toggle.click()
        try await expect(session).toHaveAttribute("data-raw-view", "false")

        // The live stream draws the same box.
        try await page.locator(".replay-btn").click()
        try await expect(page.locator(".replay-btn"), timeout: .seconds(20)).toBeEnabled()
        try await expect(session).toHaveAttribute("data-computorium-session-status", "succeeded")
        let streamed = try await page.evaluate(check, as: String.self)
        #expect(streamed.isEmpty, "live: \(streamed)")
        try await toggle.click()
        try await expect(session).toHaveAttribute("data-raw-view", "true")
        try await expect(page.locator(".computorium-session-continuation-prompt pre.computorium-session-prompt-body")).toBeVisible()
        try await page.expectNoErrors()
      }
    } catch {
      remove(nocturneID: nocturneID, antiphonID: antiphonID, work: work)
      try await admin.remove(after: error)
    }
    remove(nocturneID: nocturneID, antiphonID: antiphonID, work: work)
    try await admin.remove()
  }

  /// The antiphon's nocturnes, each with its trace, then the antiphon.
  private func remove(nocturneID: String, antiphonID: String, work: ScratchWork) {
    let nocturnes = "id = '\(nocturneID)' OR bibliographic_antiphon_id = '\(antiphonID)'"
    _ = try? TestAdmin.query(
      """
      BEGIN;
      \(SessionTrace.delete(table: Self.nocturnes, where: nocturnes))
      DELETE FROM bibliographic_explication_nocturnes WHERE id IN (SELECT nocturne_id FROM bibliographic_explication_nocturne_instances WHERE \(nocturnes));
      DELETE FROM bibliographic_antiphons WHERE id = '\(antiphonID)';
      COMMIT;
      """)
    work.remove()
  }
}
