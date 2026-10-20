import Foundation

/// A throwaway palinode of one process's prompt vignette in force (user,
/// 2026-10-20), opened by the test's account as an admin's Amend opens one.
/// Nothing here is ever committed or permitted: no review is called (no
/// model is ever asked) and no prompt is put in force, so no activation row
/// (append-only history) names it. `remove()` deletes its thread, its
/// revisions and its row; a killed run's palinode, opened by a web-tests
/// account an hour ago and never permitted, is swept on the next `init`.
/// One process holds one open palinode: where another is open (a real one),
/// `init` refuses rather than touch it.
struct ScratchPalinode {
  struct Occupied: Error, CustomStringConvertible {
    let slot: String
    var description: String { "\(slot) has an open palinode that is not a web test's" }
  }

  let id: String
  let kind: String
  let slot: String

  var path: String { "/mission-control/prompts/palinodes/\(kind)/\(id)" }

  init(slot: String, owner: TestAdmin) throws {
    let user = try owner.column("id")
    self.slot = slot
    kind = slot.hasPrefix("lexicographic_") ? "lexicographic" : "bibliographic"
    id = UUID().uuidString.lowercased()
    let stale = """
      SELECT p.id FROM vignette_palinodes p JOIN users u ON u.id = p.opened_by_user_id
      WHERE p.slot = '\(slot)' AND p.permitted_at IS NULL AND u.username LIKE 'web\\_tests\\_%'
        AND p.created_at < now() - interval '1 hour'
      """
    _ = try TestAdmin.query(
      """
      BEGIN;
      DELETE FROM locutions WHERE locutable_id IN (\(stale));
      DELETE FROM revisions WHERE revisable_id IN (\(stale));
      DELETE FROM vignette_palinodes WHERE id IN (\(stale));
      COMMIT;
      """)
    let open = try TestAdmin.query(
      "SELECT count(*) FROM vignette_palinodes WHERE slot = '\(slot)' AND permitted_at IS NULL")
    guard open.trimmingCharacters(in: .whitespacesAndNewlines) == "0" else { throw Occupied(slot: slot) }
    _ = try TestAdmin.query(
      """
      INSERT INTO vignette_palinodes (id, vignette_kind, slot, prompt_vignette_id, opened_by_user_id, created_at)
      SELECT '\(id)', 'prompt', '\(slot)', vignette_id, '\(user)', now() FROM active_prompt_vignettes WHERE slot = '\(slot)'
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
      VALUES ('\(revision)', '\(kind)PromptPalinode', '\(id)', json_build_array(json_build_object('slot', '\(slot)', 'prompt', 'main',
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
      DELETE FROM vignette_palinodes WHERE id = '\(id)';
      COMMIT;
      """)
  }
}
