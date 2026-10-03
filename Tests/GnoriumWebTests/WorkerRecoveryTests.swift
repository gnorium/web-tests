import Foundation
import Testing
import WebTests
import WebTestsTesting

@Suite("Local worker recovery", .serialized)
struct WorkerRecoveryTests {
  @Test func disabledLocalPoolConfirmsStopWithoutStarting() async throws {
    guard ProcessInfo.processInfo.environment["GNORIUM_VERIFY_LOCAL_WORKER_STOP"] == "1",
      ["localhost","127.0.0.1"].contains(gnorium.baseURL.host ?? "") else {
      try Test.cancel("Explicit local disabled-pool recovery verification only.")
    }
    if let reason=TestAdmin.unavailableReason() { try Test.cancel(Comment(rawValue:reason)) }
    guard try TestAdmin.query("SELECT enabled::text FROM computorium_worker_pool WHERE singleton").trimmingCharacters(in:.whitespacesAndNewlines)=="false",
      try TestAdmin.query("SELECT COUNT(*) FROM computorium_task_leases WHERE status='running'").trimmingCharacters(in:.whitespacesAndNewlines)=="0" else {
      try Test.cancel("Only an already disabled, empty local pool may be verified.")
    }
    let admin=try await TestAdmin.create(baseURL:gnorium.baseURL)
    func removeTemporaryControlActor() {
      _ = try? TestAdmin.query("UPDATE computorium_worker_pool SET changed_by=NULL WHERE changed_by=(SELECT id FROM users WHERE username='\(admin.username)'); UPDATE computorium_worker_controls SET changed_by=NULL WHERE changed_by=(SELECT id FROM users WHERE username='\(admin.username)');")
    }
    do {
      try await withPage(.chrome,gnorium,cookies:[admin.cookie]) { page in
        try await page.openHydrated("/mission-control/workers")
        let code=try await page.evaluate("fetch('/mission-control/workers',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'enabled=false'}).then(r=>r.status)",as:Int.self)
        #expect(code==200)
        try await page.openHydrated("/mission-control/workers")
        try await expect(page.locator(".workers-content")).toContainText("Confirmed")
        try await expect(page.locator(".workers-content")).toContainText("Disabled")
        try await expect(page.locator(".mission-control-worker-control-actions button").filter(hasText:"Start")).toBeAttached()
      }
    } catch { removeTemporaryControlActor(); try await admin.remove(after:error) }
    removeTemporaryControlActor()
    try await admin.remove()
    #expect(try TestAdmin.query("SELECT enabled::text FROM computorium_worker_pool WHERE singleton").trimmingCharacters(in:.whitespacesAndNewlines)=="false")
  }
}
