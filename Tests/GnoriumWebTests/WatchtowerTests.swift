import Foundation
import Testing
import WebTests
import WebTestsTesting

/// The Watchtower on the home page links each permitted status to the
/// records it shows, and that page's filter names the same status.
@Suite("Watchtower")
struct WatchtowerTests {
  /// The Watchtower's links into the public records.
  static let permitLinks = "a.watchtower-routes-name[href*='-records?']"

  @Test(arguments: gnorium.engines)
  func permitLinksOpenMatchingFilters(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated("/")
      let links = page.locator(Self.permitLinks)
      let count = try await links.count()
      try #require(count > 0, "the Watchtower shows no permit links")

      for index in 0..<count {
        if index > 0 { try await page.openHydrated("/") }
        let link = page.locator(Self.permitLinks).nth(index)
        let phrase = try await link.textContent()
        let href = try #require(try await link.getAttribute("href"))

        try await link.click()
        try await expect(page, timeout: .seconds(15)).toHaveURL(href)
        try await expect(page.locator("html"), timeout: .seconds(20)).toHaveAttribute("data-wasm-status", "started")

        // The filter row whose field is the status filter, however it is
        // labeled today.
        // The process the link filters by (its `status`), as the filter
        // names it: a permit link is named by what it lists ("biblio-record").
        let status = try #require(
          URLComponents(string: href)?.queryItems?.first { $0.name == "status" }?.value, "\(phrase) filters no status")
        let row = try await Self.statusRow(page)
        let selected = row.locator(".filter-bar-value-select .dropdown-selected-text")
        try await expect(selected).not.toHaveText("")
        let shown = try await selected.textContent()
        #expect(shown.lowercased().contains(status), "\(phrase): the filter reads \(shown), not \(status)")
      }
    }
  }

  /// Each process card carries its group's place in the flow (user,
  /// 2026-09-29): calibration 1, explication 2, translation 3; explication, of both kinds,
  /// and translation show one process and one card each.
  @Test(arguments: gnorium.engines)
  func processCardsCarryTheirGroupsNumber(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated("/")
      for (process, numbers) in [
        ("Calibration", ["1"]), ("Explication", ["2"]), ("Translation", ["3"]),
      ] {
        let card = page.locator(".watchtower-processes-view[data-process='\(process)']").first
        try await expect(card.locator(".watchtower-process-number")).toHaveTexts(numbers)
      }
      // No heading over a process's block: the block names its process.
      try await expect(page.locator(".watchtower-group-name")).toHaveCount(0)
      try await expect(page.locator(".watchtower-process-name")).toHaveTexts(
        ["ARBITRATION", "CALIBRATION", "ARBITRATION", "EXPLICATION", "ARBITRATION", "TRANSLATION"])
    }
  }

  /// The chain top to bottom (user, 2026-10-21): each Disputorium card
  /// over the machine its Commit moves forward to, the halftone between the
  /// overture and the madrigal; and every process box splits its figures
  /// into a Bibliographic and a Lexicographic column, one figure a row,
  /// pending first on calibration, explication and translation and on
  /// their objects (user, 2026-10-21).
  @Test(arguments: gnorium.engines)
  func theHalftoneStandsInTheChainAndProcessesSplitByKind(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated("/")
      let chain = ["Fountain", "Overture", "Quatrain", "Halftone", "Antiphon", "Madrigal", "Serenade", "Epilogue"]
      let names = try await page.locator(".watchtower-ladder .watchtower-object-name-link").allTextContents()
      #expect(names.filter { chain.contains($0) } == chain, "the chain reads \(names)")
      let description = try await page.evaluate("""
        [...document.querySelectorAll('.watchtower-object-name-link')]
          .find(e => e.textContent.trim() === 'Halftone')
          ?.closest('.watchtower-object-view').querySelector('.watchtower-object-description')?.textContent.trim() ?? ''
        """, as: String.self)
      #expect(description == "The calibrated document people settle, then commit or permit.", "\(description)")
      // Each box's process, then its columns' headings and figures' words.
      let columns = try await page.evaluate("""
        [...document.querySelectorAll('.watchtower-process-figures')].map(box =>
          [box.closest('.watchtower-processes-view').getAttribute('data-process'),
           ...[...box.querySelectorAll('.watchtower-figure-columns-column')].map(column =>
            [column.querySelector('.watchtower-figure-columns-tab').textContent.trim(),
             ...[...column.querySelectorAll('.live-figure-text')].map(f => f.textContent.trim().replace(/^\\S+ /, ''))]
              .join('|'))])
        """, as: [[String]].self)
      #expect(columns.count == 6, "calibration, explication, translation and three arbitrations: \(columns.count)")
      for box in columns {
        // Every status a nocturne can be in, as its lifecycle runs;
        // arbitration's sessions alike (user, 2026-10-21).
        let figures = "pending|running|passed (1w)|failed (1w)"
        #expect(Array(box.dropFirst()) == ["Bibliographic|\(figures)", "Lexicographic|\(figures)"], "\(box)")
      }
      // A call's every status, in order (user, 2026-10-21): pending
      // (awaiting Commit or queued: one figure), running, submitted (1w),
      // failed (1w), nullified; hidden is no figure (the Locutions filter).
      let calls = try await page.evaluate("""
        [...document.querySelectorAll('[id^="live-region-watchtower-arbitration-"][id$="-figures"] .watchtower-figure-columns-column')]
          .map(column => [column.querySelector('.watchtower-figure-columns-tab').textContent.trim(),
            ...[...column.querySelectorAll('.live-figure-text')].map(f => f.textContent.trim().replace(/^\\S+ /, ''))]
            .join('|'))
        """, as: [String].self)
      #expect(!calls.isEmpty)
      for column in calls {
        #expect(column.hasSuffix("|pending|running|submitted (1w)|failed (1w)|nullified"), "\(column)")
      }
      // A machine's object: every status its enum has, in order—pending,
      // its process's in-flight status, submitted (1w), failed (1w).
      for (object, inFlight) in [("quatrain", "calibrating"), ("antiphon", "explicating"), ("serenade", "translating")] {
        let figures = try await page.evaluate("""
          [...document.querySelectorAll('#live-region-watchtower-\(object)-figures .watchtower-figure-columns-column')]
            .map(column => [column.querySelector('.watchtower-figure-columns-tab').textContent.trim(),
              ...[...column.querySelectorAll('.live-figure-text')].map(f => f.textContent.trim().replace(/^\\S+ /, ''))]
              .join('|'))
          """, as: [String].self)
        #expect(figures == ["Bibliographic|pending|\(inFlight)|submitted (1w)|failed (1w)",
          "Lexicographic|pending|\(inFlight)|submitted (1w)|failed (1w)"], "\(object): \(figures)")
      }
      let promoted = try await page.evaluate(
        "document.querySelector('.watchtower-view').textContent.toLowerCase().includes('promot')", as: Bool.self)
      #expect(!promoted, "nothing on the Watchtower is promoted")
    }
  }

  /// The Watchtower reads alive (user, 2026-10-21): every figure, on both
  /// sides, always shown with its count (0 included), wears its status's
  /// mark BEFORE its words ("◌ 0 pending"), in two vocabularies (as headers
  /// and rosters keep theirs):
  /// - a PROCESS box's figures (its evidence items' sessions) the level
  ///   marks: pending, the level its process starts from; running, the
  ///   rotating sector of the level it goes to; passed, the level it goes
  ///   to; failed, that mark in red. Arbitration's at its object's level:
  ///   an overture postulated, a halftone calibrated, a madrigal
  ///   explicated, an epilogue translated.
  /// - a machine's OBJECT figures (a quatrain, an antiphon, a serenade as a
  ///   whole) its header chip's marks: pending its pending ring (a
  ///   quatrain's dotted, an antiphon's plain, a serenade's disc), in
  ///   flight its turning mark, submitted the green check, failed the red
  ///   cross (a failure the machine retries counts as pending: failed
  ///   always needs a person). A call's too, at its object's level: pending
  ///   that level still, running it turning, submitted the check, failed
  ///   and nullified the red cross.
  /// - a Disputorium object's figures its chip's: pending its level's
  ///   pending mark (an overture's and a halftone's the dotted ring, a
  ///   madrigal's the ring, an epilogue's the disc), committed and
  ///   permitted the green check (a lexicographic epilogue's committed, on
  ///   its verdict, the disc); a fountain's and a palinode's submitted the
  ///   check; a stale count the orange alert icon. Hidden is no figure.
  /// A turning mark always turns, at zero too (its computed animation is
  /// never none, outside reduced motion); a still one never does.
  @Test(arguments: gnorium.engines)
  func computoriumFiguresWearTheirStatusMarks(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated("/")
      struct Marked: Decodable {
        let owner: String
        let text: String
        let mark: String
        let color: String
        let column: String
        let leads: Bool
        let animated: Bool
      }
      let figures = try await page.evaluate("""
        (() => {
          const kinds = ['rotating-dotted-ring-sector-view', 'rotating-ring-sector-with-disc-view',
            'rotating-ring-sector-view', 'rotating-sector-view', 'ringed-disc-icon-view', 'dotted-ring-view',
            'ring-icon-view', 'disc-icon-view', 'check-icon-view', 'x-icon-view', 'triangle-alert-icon-view']
          const owner = figure => {
            const box = figure.closest('.watchtower-processes-view')
            const region = figure.closest('.live-region-view')?.id ?? ''
            if (box) return box.getAttribute('data-process') + (region.includes('arbitration') ? ':' + region : '')
            return region
          }
          return [...document.querySelectorAll('.watchtower-view .live-figure-body')].map(body => {
            const mark = body.querySelector('.live-figure-mark')
            const shape = mark && mark.firstElementChild
            const kind = shape ? (kinds.find(k => shape.classList.contains(k)) ?? shape.getAttribute('class')) : ''
            const animated = !!mark && [...mark.querySelectorAll('*')].some(e => getComputedStyle(e).animationName !== 'none')
            return { owner: owner(body), text: body.querySelector('.live-figure-text').textContent.trim(),
              mark: kind, color: mark?.getAttribute('data-color') ?? '',
              column: body.closest('.watchtower-figure-columns-column')?.getAttribute('data-tab') ?? '',
              leads: !!mark && body.firstElementChild === mark, animated }
          })
        })()
        """, as: [Marked].self)
      // A process's level marks: starting level, rotating sector, target level.
      let levels: [String: (pending: String, running: String, done: String)] = [
        "calibration": ("dotted-ring-view", "rotating-ring-sector-view", "ring-icon-view"),
        "explication": ("ring-icon-view", "rotating-sector-view", "disc-icon-view"),
        "translation": ("disc-icon-view", "rotating-ring-sector-with-disc-view", "ringed-disc-icon-view"),
      ]
      // Arbitration's, at its object's level.
      let arbitrations: [String: (still: String, running: String)] = [
        "overture": ("dotted-ring-view", "rotating-dotted-ring-sector-view"),
        "halftone": ("ring-icon-view", "rotating-ring-sector-view"),
        "madrigal": ("disc-icon-view", "rotating-sector-view"),
        "epilogue": ("ringed-disc-icon-view", "rotating-ring-sector-with-disc-view"),
      ]
      // A machine's object's chip marks: its pending ring, its turning mark.
      let objects: [String: (pending: String, inFlight: String, word: String)] = [
        "quatrain": ("dotted-ring-view", "rotating-ring-sector-view", "calibrating"),
        "antiphon": ("ring-icon-view", "rotating-sector-view", "explicating"),
        "serenade": ("disc-icon-view", "rotating-ring-sector-with-disc-view", "translating"),
      ]
      // A Disputorium object's chip marks: pending, then committed.
      let disputorium: [String: (pending: String, committed: [String: String])] = [
        "overture": ("dotted-ring-view", [:]),
        "halftone": ("dotted-ring-view", [:]),
        "madrigal": ("ring-icon-view", [:]),
        "epilogue": ("disc-icon-view", ["lexicographic": "disc-icon-view"]),
      ]
      var processes = 0
      var machines = 0
      var calls = 0
      var people = 0
      for figure in figures {
        let word = figure.text.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        let count = Int(figure.text.prefix { $0.isNumber }) ?? 0
        let turns = ["running", "calibrating", "explicating", "translating"].contains(word)
        let wanted: String
        var color = "blue"
        if let process = levels[figure.owner.lowercased()] {
          wanted = word == "pending" ? process.pending : word == "running" ? process.running : process.done
          if word == "failed" { color = "red" }
          processes += 1
        } else if let level = arbitrations.first(where: { figure.owner.contains("arbitration-\($0.key)") })?.value {
          if figure.owner.lowercased().hasPrefix("arbitration:") {
            // Its process box's level marks.
            wanted = word == "running" ? level.running : level.still
            if word == "failed" { color = "red" }
          } else {
            // Its call's chip marks.
            switch word {
            case "pending": wanted = level.still
            case "running": wanted = level.running
            case "submitted": wanted = "check-icon-view"; color = "green"
            default: wanted = "x-icon-view"; color = "red"
            }
            calls += 1
          }
        } else if let object = objects.first(where: { figure.owner.hasSuffix("watchtower-\($0.key)-figures") })?.value {
          switch word {
          case "pending": wanted = object.pending
          case object.word: wanted = object.inFlight
          case "submitted": wanted = "check-icon-view"; color = "green"
          default: wanted = "x-icon-view"; color = "red"
          }
          machines += 1
        } else if let entry = disputorium.first(where: { figure.owner.hasSuffix("watchtower-\($0.key)-figures") }) {
          let tab = figure.column
          switch word {
          // Stale work owed again: the orange alert icon (user, 2026-10-21).
          case "stale": wanted = "triangle-alert-icon-view"; color = "orange"; people -= 1
          case "pending": wanted = entry.value.pending
          case "committed":
            wanted = entry.value.committed[tab] ?? "check-icon-view"
            if wanted == "check-icon-view" { color = "green" }
          default: wanted = "check-icon-view"; color = "green"
          }
          people += 1
        } else {
          // A register's row (a fountain, a palinode): submitted, the check.
          wanted = "check-icon-view"
          color = "green"
          people += 1
        }
        #expect(figure.leads, "\(figure.owner) \(figure.text): its mark leads its words")
        #expect(figure.mark == wanted, "\(figure.owner) \(figure.text): \(figure.mark), not \(wanted)")
        #expect(figure.color == color, "\(figure.owner) \(figure.text): \(figure.color), not \(color)")
        // A running mark always turns: its computed animation is never
        // none, at zero too (user, 2026-10-21).
        #expect(figure.animated == turns, "\(figure.owner) \(figure.text) (\(count)): animated \(figure.animated)")
      }
      // Three processes and three machines, four statuses on both sides.
      #expect(processes == 24 && machines == 24, "\(processes) process figures, \(machines) object figures")
      // Four Disputorium objects of three figures and the fountain's and
      // four palinodes' one, both sides.
      #expect(people == 4 * 3 * 2 + 5 * 2, "\(people) Disputorium and register figures")
      // Each nested Locution card's call: five statuses on both sides.
      #expect(calls > 0 && calls % 10 == 0, "\(calls) call figures")
    }
  }

  @Test(arguments: gnorium.engines)
  func nestedLocutionsAreCommittedOnce(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated("/")
      let cards = page.locator(".watchtower-object-view:has(> .watchtower-object-header .watchtower-object-name-link)")
      let routes = try await page.evaluate("""
        [...document.querySelectorAll('.watchtower-object-name-link')]
          .filter(e => e.textContent === 'Locution')
          .map(e => [...e.closest('.watchtower-object-view').querySelectorAll(':scope > .watchtower-routes-view')]
            .map(r => [...r.querySelectorAll('.watchtower-routes-row > span')].map(s => s.textContent.trim()).join(' ')).join('|')).join('\\n')
        """, as: String.self)
      #expect(routes.split(separator: "\n").map(String.init) == Array(repeating: "commit ← locution|submit → locution", count: 3))
      #expect(try await cards.count() > 0)
    }
  }

  /// A status mark sits in its permit row's line (user, 2026-10-10): the
  /// words of the row's first line—mono verb, sans arrow, status word and
  /// names—share one baseline, and the 26px mark centers on the capitals
  /// of the word beside it, by the font's cap height, within half a pixel.
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func statusMarksCenterOnTheirRowsCapitals(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/")
      let rows = try await page.evaluate("""
        (() => {
          const ctx = document.createElement('canvas').getContext('2d');
          // A text run's baseline (a zero box on it) and cap height (its font's H).
          const measure = node => {
            const probe = document.createElement('span');
            probe.style.cssText = 'display:inline-block;width:0;height:0';
            node.parentNode.insertBefore(probe, node.nextSibling);
            const baseline = probe.getBoundingClientRect().bottom;
            probe.remove();
            const style = getComputedStyle(node.parentElement);
            ctx.font = `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
            return { text: node.textContent.trim(), baseline, cap: ctx.measureText('H').actualBoundingBoxAscent };
          };
          return [...document.querySelectorAll('.watchtower-routes-row:has(.watchtower-routes-mark)')].map(row => {
            const walker = document.createTreeWalker(row, NodeFilter.SHOW_TEXT);
            const runs = [];
            for (let node; (node = walker.nextNode());) if (node.textContent.trim()) runs.push(measure(node));
            const word = measure(row.querySelector('.watchtower-routes-mark-text').firstChild);
            const icon = row.querySelector('.watchtower-routes-mark .icon-view').getBoundingClientRect();
            const line = runs.filter(r => Math.abs(r.baseline - word.baseline) < 8);
            return {
              row: runs.map(r => r.text).join(' '),
              baselines: Math.max(...line.map(r => r.baseline)) - Math.min(...line.map(r => r.baseline)),
              tops: Math.max(...line.map(r => r.baseline - r.cap)) - Math.min(...line.map(r => r.baseline - r.cap)),
              offset: (icon.top + icon.bottom) / 2 - (word.baseline - word.cap / 2),
            };
          });
        })()
        """, as: [Row].self)
      try #require(!rows.isEmpty, "the Watchtower shows no status mark")
      for row in rows {
        #expect(row.baselines < 0.5, "\(row.row): its first line's words are \(row.baselines)px off one baseline")
        #expect(row.tops < 0.5, "\(row.row): its first line's capitals are \(row.tops)px apart at the top")
        #expect(abs(row.offset) < 0.5, "\(row.row): the mark is \(row.offset)px off its word's capitals")
      }
    }
  }

  struct Row: Decodable {
    let row: String
    let baselines: Double
    let tops: Double
    let offset: Double
  }

  static let statusLabels = ["Status"]

  static func statusRow(_ page: Page) async throws -> Locator {
    let rows = page.locator(".filter-bar-row")
    try await expect(rows.first).toBeVisible()
    var labels: [String] = []
    for row in try await rows.all() {
      let label = try await row.locator(".filter-bar-field-picker .dropdown-selected-text").textContent()
      if statusLabels.contains(label) { return row }
      labels.append(label)
    }
    throw WebTestError("No filter row is labeled \(statusLabels.joined(separator: " or ")); the rows are \(labels).")
  }
}
