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
        // Arbitration's calls awaiting Commit are its object figures' pending.
        let figures = box.first == "Arbitration"
          ? "running|finished (1w)|failed (1w)" : "pending|running|finished (1w)|failed (1w)"
        #expect(Array(box.dropFirst()) == ["Bibliographic|\(figures)", "Lexicographic|\(figures)"], "\(box)")
      }
      // A machine's object: pending, running, submitted (1w), failed (1w).
      for object in ["quatrain", "antiphon", "serenade"] {
        let figures = try await page.evaluate("""
          [...document.querySelectorAll('#live-region-watchtower-\(object)-figures .watchtower-figure-columns-column')]
            .map(column => [column.querySelector('.watchtower-figure-columns-tab').textContent.trim(),
              ...[...column.querySelectorAll('.live-figure-text')].map(f => f.textContent.trim().replace(/^\\S+ /, ''))]
              .join('|'))
          """, as: [String].self)
        #expect(figures == ["Bibliographic|pending|running|submitted (1w)|failed (1w)",
          "Lexicographic|pending|running|submitted (1w)|failed (1w)"], "\(object): \(figures)")
      }
      let promoted = try await page.evaluate(
        "document.querySelector('.watchtower-view').textContent.toLowerCase().includes('promot')", as: Bool.self)
      #expect(!promoted, "nothing on the Watchtower is promoted")
    }
  }

  /// The Watchtower reads alive (user, 2026-10-21): every Computorium
  /// figure—a process box's, a quatrain's, an antiphon's, a serenade's and
  /// a nested locution card's, on both sides—wears its status's mark in the
  /// process mark system: pending, the level its process starts from;
  /// running, the rotating sector of the level it goes to, turning only
  /// while its count is non-zero; finished or submitted, the level it goes
  /// to; failed, that mark in red. Arbitration's level is its object's: an
  /// overture postulated, a halftone calibrated, a madrigal explicated, an
  /// epilogue translated. A Disputorium object's figures wear none.
  @Test(arguments: gnorium.engines)
  func computoriumFiguresWearTheirStatusMarks(engine: BrowserEngine) async throws {
    try await withPage(engine, gnorium) { page in
      try await page.openHydrated("/")
      struct Marked: Decodable {
        let owner: String
        let text: String
        let mark: String
        let turning: Bool
        let animated: Bool
        let color: String
      }
      // Each figure: whose it is (a process box's process, or an object's
      // live region), its words, its mark's component, whether it turns.
      let figures = try await page.evaluate("""
        (() => {
          const kinds = ['rotating-dotted-ring-sector-view', 'rotating-ring-sector-with-disc-view',
            'rotating-ring-sector-view', 'rotating-sector-view', 'ringed-disc-icon-view', 'dotted-ring-view',
            'ring-icon-view', 'disc-icon-view']
          const owner = figure => {
            const box = figure.closest('.watchtower-processes-view')
            if (box) {
              const region = figure.closest('.live-region-view')?.id ?? ''
              return box.getAttribute('data-process') + (region.includes('arbitration') ? ':' + region : '')
            }
            return figure.closest('.live-region-view')?.id ?? ''
          }
          return [...document.querySelectorAll('.watchtower-view .live-figure-body')].map(body => {
            const mark = body.querySelector('.live-figure-mark')
            const shape = mark && mark.firstElementChild
            const kind = shape ? (kinds.find(k => shape.classList.contains(k)) ?? shape.getAttribute('class')) : ''
            const animated = !!mark && [...mark.querySelectorAll('*')].some(e => getComputedStyle(e).animationName !== 'none')
            return { owner: owner(body), text: body.querySelector('.live-figure-text').textContent.trim(),
              mark: kind, turning: mark?.getAttribute('data-turning') === 'true', animated,
              color: mark ? getComputedStyle(mark).color : '' }
          })
        })()
        """, as: [Marked].self)
      // Each process's marks, starting level → rotating sector → target level.
      let marks: [String: (pending: String, running: String, done: String)] = [
        "calibration": ("dotted-ring-view", "rotating-ring-sector-view", "ring-icon-view"),
        "explication": ("ring-icon-view", "rotating-sector-view", "disc-icon-view"),
        "translation": ("disc-icon-view", "rotating-ring-sector-with-disc-view", "ringed-disc-icon-view"),
      ]
      // Arbitration's, at its object's level.
      let levels: [String: (still: String, running: String)] = [
        "overture": ("dotted-ring-view", "rotating-dotted-ring-sector-view"),
        "halftone": ("ring-icon-view", "rotating-ring-sector-view"),
        "madrigal": ("disc-icon-view", "rotating-sector-view"),
        "epilogue": ("ringed-disc-icon-view", "rotating-ring-sector-with-disc-view"),
      ]
      let objects = ["quatrain": "calibration", "antiphon": "explication", "serenade": "translation"]
      var checked = 0
      var red = Set<String>()
      var blue = Set<String>()
      for figure in figures {
        let word = figure.text.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        let count = Int(figure.text.prefix { $0.isNumber }) ?? 0
        var expected: (pending: String, running: String, done: String)?
        if let process = marks[figure.owner.lowercased()] {
          expected = process
        } else if let object = objects.first(where: { figure.owner.hasSuffix("watchtower-\($0.key)-figures") }) {
          expected = marks[object.value]
        } else if let level = levels.first(where: { figure.owner.contains("arbitration-\($0.key)") }) {
          expected = (level.value.still, level.value.running, level.value.still)
        }
        guard let expected else {
          // A person's object, a fountain, a palinode: no mark.
          #expect(figure.mark.isEmpty, "\(figure.owner) \(figure.text) wears \(figure.mark)")
          continue
        }
        let wanted: String
        switch word {
        case "pending": wanted = expected.pending
        case "running": wanted = expected.running
        default: wanted = expected.done
        }
        #expect(figure.mark == wanted, "\(figure.owner) \(figure.text): \(figure.mark), not \(wanted)")
        if word == "running" {
          #expect(figure.turning == (count > 0), "\(figure.owner) \(figure.text): turning \(figure.turning)")
          if count == 0 { #expect(!figure.animated, "\(figure.owner) \(figure.text): the sector turns at zero") }
        } else {
          #expect(!figure.animated, "\(figure.owner) \(figure.text): a still mark turns")
        }
        if word == "failed" { red.insert(figure.color) } else if word != "running" { blue.insert(figure.color) }
        checked += 1
      }
      // Calibration, explication and translation of four figures and three
      // machines of four, on both sides: 48; the arbitrations' beside them.
      #expect(checked >= 48, "\(checked) Computorium figures checked")
      #expect(red.count == 1 && blue.count == 1 && red != blue, "failed \(red), others \(blue): a failure in red")
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
