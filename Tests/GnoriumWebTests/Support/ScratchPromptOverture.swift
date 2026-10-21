import Foundation

/// A throwaway overture of one process's prompt vignette in force (user,
/// 2026-10-21), opened as an admin's Amend opens one: the test's account
/// submits a palinode, frozen, which opens the overture. Nothing here is
/// ever committed or permitted: no review is called (no model is ever
/// asked) and no prompt is put in force, so no activation row (append-only
/// history) names it. `remove()` deletes its thread and its revisions and
/// deletes the overture as an admin does (its row stays, closed); the
/// palinode, a submission, is frozen and stays, under the throwaway
/// account. A killed run's overture, opened by a web-tests account an hour
/// ago and never permitted, is swept on the next `init`. One process holds
/// one open overture: where another is open (a real one), `init` refuses
/// rather than touch it.
struct ScratchPromptOverture {
  struct Occupied: Error, CustomStringConvertible {
    let slot: String
    var description: String { "\(slot) has an open overture that is not a web test's" }
  }

  /// The overture's id.
  let id: String
  /// The palinode that opened it.
  let palinodeID: String
  let kind: String
  let slot: String
  private let owner: String

  var path: String { "/mission-control/prompts/overtures/\(kind)/\(id)" }
  var palinodePath: String { "/mission-control/prompts/palinodes/\(kind)/\(palinodeID)" }

  init(slot: String, owner: TestAdmin) throws {
    let user = try owner.column("id")
    self.owner = owner.username
    self.slot = slot
    kind = slot.hasPrefix("lexicographic_") ? "lexicographic" : "bibliographic"
    id = UUID().uuidString.lowercased()
    palinodeID = UUID().uuidString.lowercased()
    let stale = """
      SELECT o.id FROM vignette_overtures o JOIN vignette_palinodes p ON p.id = o.vignette_palinode_id
        JOIN users u ON u.id = p.submitted_by_user_id
      WHERE o.slot = '\(slot)' AND o.vignette_kind = 'prompt' AND o.permitted_at IS NULL AND o.deleted_at IS NULL
        AND u.username LIKE 'web\\_tests\\_%' AND o.created_at < now() - interval '1 hour'
      """
    _ = try TestAdmin.query(
      """
      BEGIN;
      DELETE FROM locutions WHERE locutable_id IN (\(stale));
      DELETE FROM revisions WHERE revisable_id IN (\(stale));
      UPDATE vignette_overtures SET deleted_at = now(), deleted_by = 'web-tests' WHERE id IN (\(stale));
      COMMIT;
      """)
    let open = try TestAdmin.query(
      """
      SELECT count(*) FROM vignette_overtures
      WHERE slot = '\(slot)' AND vignette_kind = 'prompt' AND permitted_at IS NULL AND deleted_at IS NULL
      """)
    guard open.trimmingCharacters(in: .whitespacesAndNewlines) == "0" else { throw Occupied(slot: slot) }
    _ = try TestAdmin.query(
      """
      BEGIN;
      INSERT INTO vignette_palinodes (id, vignette_kind, slot, prompt_vignette_id, submitted_by_user_id, created_at)
      SELECT '\(palinodeID)', 'prompt', '\(slot)', vignette_id, '\(user)', now() FROM active_prompt_vignettes
      WHERE slot = '\(slot)';
      INSERT INTO vignette_overtures (id, vignette_kind, slot, vignette_palinode_id, prompt_vignette_id, created_at)
      SELECT '\(id)', 'prompt', '\(slot)', id, prompt_vignette_id, created_at FROM vignette_palinodes
      WHERE id = '\(palinodeID)';
      COMMIT;
      """)
  }

  /// One prompt's text in force: `system_prompt`, `task_prompt`,
  /// `autocompaction_system_prompt`, … of the process's vignette in force.
  static func inForce(_ slot: String, _ column: String) throws -> String {
    try TestAdmin.query(
      "SELECT \(column) FROM prompt_vignettes WHERE id = (SELECT vignette_id FROM active_prompt_vignettes WHERE slot = '\(slot)')")
  }

  /// A revision of its process's own prompts, `previous` to `proposed`
  /// system prompt, by `user`, with `status` (evaluated by `user` unless
  /// pending), made `minutes` ago.
  func insertRevision(
    id revision: String, user: String, previousSystem: String, proposedSystem: String, task: String,
    status: String = "pending", minutes: Int = 1
  ) throws {
    func sql(_ text: String) -> String { text.replacingOccurrences(of: "'", with: "''") }
    let evaluated = status == "pending" ? "NULL, NULL" : "'\(user)', now()"
    _ = try TestAdmin.query(
      """
      INSERT INTO revisions (id, revisable_type, revisable_id, prompt_changes_json, status, requested_by_user_id,
        evaluated_by_user_id, evaluated_at, created_at)
      VALUES ('\(revision)', '\(kind)PromptOverture', '\(id)', json_build_array(json_build_object('slot', '\(slot)', 'prompt', 'main',
          'previous', json_build_object('system', '\(sql(previousSystem))', 'task', '\(sql(task))'),
          'proposed', json_build_object('system', '\(sql(proposedSystem))', 'task', '\(sql(task))')))::text,
        '\(status)', '\(user)', \(evaluated), now() - interval '\(minutes) minute')
      """)
  }

  func remove() {
    _ = try? TestAdmin.query(
      """
      BEGIN;
      DELETE FROM locutions WHERE locutable_id = '\(id)';
      DELETE FROM revisions WHERE revisable_id = '\(id)';
      UPDATE vignette_overtures SET deleted_at = now(), deleted_by = '\(owner)' WHERE id = '\(id)' AND deleted_at IS NULL;
      COMMIT;
      """)
  }
}
