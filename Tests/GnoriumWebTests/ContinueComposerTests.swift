import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Continue composer", .serialized)
struct ContinueComposerTests {
  @Test(arguments: [BrowserEngine.chrome], Layout.allCases)
  func headerPursueSubmitsEditedInstruction(engine: BrowserEngine, layout: Layout) async throws {
    guard gnorium.engines.contains(engine) else { return }
    guard let path = ProcessInfo.processInfo.environment["GNORIUM_CONTINUE_FIXTURE_PATH"] else {
      try Test.cancel("Export the failed-admin saved-conversation fixture first.")
    }
    let file = URL(fileURLWithPath: "/Users/Madhavik/Downloads/Gnorium/gnorium-web/Public")
      .appendingPathComponent("continue-composer-\(UUID().uuidString).html")
    try Data(contentsOf: URL(fileURLWithPath: path)).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    try await withPage(engine, gnorium, viewport: layout.viewport(for: engine)) { page in
      try await page.openHydrated("/\(file.lastPathComponent)")
      let input = page.locator("#computorium-continuation-prompt")
      try await expect(input).toHaveValue("Continue.")
      #expect(try await page.evaluate("""
        (()=>{const e=document.querySelector('#computorium-continuation-prompt');const s=getComputedStyle(e);
          const f=e.form,b=document.querySelector('button[form=computorium-pursue]');
          const probe=document.createElement('span');probe.style.borderColor='var(--border-color-base)';document.body.append(probe);
          const neutral=getComputedStyle(probe).borderTopColor;probe.remove();
          return s.fontSize==='14px' && !s.fontFamily.includes('Mono') && parseFloat(s.paddingTop)===16
            && s.borderTopColor===neutral && e.getBoundingClientRect().width>250
            && f.id==='computorium-pursue' && b.form===f && !f.querySelector('legend') && !f.textContent.toLowerCase().includes('version');})()
        """, as: Bool.self), "Continue uses the plain full-width prompt box and header button targets its form")
      _ = try await page.evaluate("""
        (()=>{window.__continuationSubmission=null;const f=document.querySelector('#computorium-pursue');
          f.addEventListener('submit',e=>{e.preventDefault();window.__continuationSubmission={
            method:f.method,action:f.getAttribute('action'),body:new URLSearchParams(new FormData(f)).toString()};},true);
          return true;})()
        """, as: Bool.self)
      try await input.fill("Check the imprint again, then continue.")
      try await page.locator("button[form=computorium-pursue]").click()
      let submission = try await page.evaluate("JSON.stringify(window.__continuationSubmission)", as: String.self)
      #expect(submission.contains("\"method\":\"post\""))
      #expect(submission.contains("/pursue"))
      #expect(submission.contains("continuationPrompt=Check+the+imprint+again%2C+then+continue."))
      try await page.expectNoHorizontalOverflow()
      try await page.expectNoErrors()
    }
  }
}
