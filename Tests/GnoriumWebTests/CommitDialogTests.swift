import Foundation
import Testing
import WebTests
import WebTestsTesting

/// Committing a Disputorium object (user, 2026-10-03): no inline panel, no
/// levels, fields or argument. An overture's one way is a Commit button that
/// opens a confirmation dialog naming it; a notation's two ways are picked
/// in its prompt preview's toolbar (the menu went with the preview,
/// 2026-10-04), whose one Commit opens the picked way's dialog. Every dialog is cancelled: a commit is costly and never run
/// here. A throwaway admin owns the scratch objects (`ScratchCommit`).
@Suite("Commit dialog", .serialized)
struct CommitDialogTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func commitAsksFirst(engine: BrowserEngine, layout: Layout) async throws {
    if let reason = TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue: reason)) }
    guard gnorium.engines.contains(engine) else { return }
    let admin = try await TestAdmin.create(baseURL: gnorium.baseURL)
    let scratch = try ScratchCommit(owner: admin)
    do {
      try await withPage(engine, gnorium, viewport: layout.viewport(for: engine), cookies: [admin.cookie]) { page in
        // One way: a button, and its dialog.
        try await page.openHydrated(scratch.overturePath)
        // Hold substantial live Swift memory while callbacks open/close the
        // dialog. The JS bridge must never write into an arbitrary heap address.
        let allocationReady = try await page.evaluate(
          """
          (() => {
            const exports = window.wasmInstance.exports;
            const resolve = name => exports[name] ?? Object.entries(exports).find(([key, fn]) => typeof fn === 'function' && key.includes(name))?.[1];
            const length = 16 * 1024 * 1024;
            const pointer = resolve('allocateBridgeBuffer')(length);
            new Uint8Array(exports.memory.buffer, pointer, length).fill(90);
            window.__commitHeapProbe = { pointer, length };
            for (let i = 0; i < 32; i++) invokeWasmCallback(-1, 'bridge-probe-' + 'x'.repeat(4096));
            return true;
          })()
          """, as: Bool.self)
        #expect(allocationReady)
        try await expect(page.locator(".commit-view-menu")).toHaveCount(0)
        let dialog = page.locator(".commit-view-dialog")
        try await expect(dialog).toHaveCount(1)
        try await expect(dialog).toHaveAttribute("data-open", "false")
        for gone in ["Fields to fill", "Argument"] {
          try await expect(page.getByText(gone, exact: true)).toHaveCount(0)
        }
        try await page.locator(".commit-view-trigger").click()
        try await expect(dialog).toHaveAttribute("data-open", "true")
        try await expect(dialog.locator(".dialog-header-title")).toHaveText("Commit this overture for recognition?")
        try await expect(dialog.locator(".dialog-primary-button")).toContainText("Commit")
        try await dialog.locator(".dialog-default-button button").click()
        try await expect(dialog).toHaveAttribute("data-open", "false")
        let heapIntact = try await page.evaluate(
          """
          (() => {
            const exports = window.wasmInstance.exports;
            const { pointer, length } = window.__commitHeapProbe;
            const intact = new Uint8Array(exports.memory.buffer, pointer, length).every(byte => byte === 90);
            const release = exports.releaseBridgeBuffer ?? Object.entries(exports).find(([key, fn]) => typeof fn === 'function' && key.includes('releaseBridgeBuffer'))?.[1];
            release(pointer);
            delete window.__commitHeapProbe;
            return intact;
          })()
          """, as: Bool.self)
        #expect(heapIntact, "Callback marshalling must preserve live Swift allocations")
        try await page.expectNoErrors()

        // Two ways: the operation is picked in the prompt preview's toolbar
        // (recognition first), and its one Commit opens that way's dialog.
        try await page.openHydrated(scratch.notationPath)
        try await expect(page.locator(".commit-view-menu")).toHaveCount(0)
        let toolbar = page.locator(".disputorium-pipeline-toolbar")
        let dialogs = page.locator(".commit-view-dialog[data-open='true']")
        try await expect(toolbar).toBeVisible()
        try await expect(toolbar.locator(".pipeline-selection-toggle[data-pipeline='translation']")).toHaveCount(1)
        let recognition = toolbar.locator(".pipeline-selection-toggle[data-pipeline='recognition']")
        try await recognition.click()
        try await expect(toolbar).toHaveAttribute("data-selected-pipeline", "recognition")
        try await expect(dialogs).toHaveCount(0)
        try await expect(toolbar.locator(".commit-view-trigger:not([disabled])")).toHaveCount(1)
        try await toolbar.locator(".commit-view-trigger").click()
        try await expect(dialogs).toHaveCount(1)
        try await expect(dialogs.locator(".dialog-header-title")).toHaveText("Commit this notation for recognition?")
        try await dialogs.locator(".dialog-default-button button").click()
        try await expect(dialogs).toHaveCount(0)
        try await page.expectNoHorizontalOverflow()
        try await page.expectNoErrors()
      }
      #expect(try scratch.stillPending(), "a cancelled dialog committed nothing")
    } catch {
      scratch.remove()
      try await admin.remove(after: error)
    }
    scratch.remove()
    try await admin.remove()
  }
}
