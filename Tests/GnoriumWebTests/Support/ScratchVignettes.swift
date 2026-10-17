import Foundation

/// Two throwaway vignettes of one process (bibliographic explication), for
/// its Compare Prompt Vignettes page: the older one's system prompt spaces
/// its em dashes (" — ") on two lines, the newer one's closes them up ("—"),
/// with lines kept before, between and after; every other prompt the same,
/// so the page holds one diff.
///
/// Neither is committed and both are made after the slot's first, so no list
/// shows them and no vignette's standing changes; neither is activated, so
/// no activation rows (append-only history) name them. Nothing else names
/// them either, so `remove()` deletes their two rows; a killed run's pair
/// is swept on the next `init` (an hour old, unnamed by any slot's active
/// vignette). The event log is never read or written.
struct ScratchVignettes {
  /// The older's and the newer's ids, upper case as the server writes them.
  let from: String
  let to: String

  var path: String { "/mission-control/prompts/vignettes/compare?from=\(from)&to=\(to)" }

  static let marker = "Web tests spaced dashes:"

  init() throws {
    _ = try TestAdmin.query(
      "DELETE FROM prompt_vignettes WHERE slot = 'bibliographic_explication' AND system_prompt LIKE '\(Self.marker)%' AND committed_object_id IS NULL AND created_at < now() - interval '1 hour' AND id NOT IN (SELECT vignette_id FROM active_prompt_vignettes);"
    )
    let from = UUID().uuidString
    let to = UUID().uuidString
    let spaced = """
      \(Self.marker) this line is kept.
      Read the page — every line of it — before you answer.
      This line is kept too.
      Keep each mark — and each space — as the page has it.
      The last line is kept.
      """
    let closed = spaced.replacingOccurrences(of: " — ", with: "—")
    _ = try TestAdmin.query(
      """
      INSERT INTO prompt_vignettes(id, hash, slot, system_prompt, task_prompt,
        autocompaction_system_prompt, autocompaction_task_prompt, continuation_system_prompt, continuation_task_prompt,
        is_proprietary_content, created_at)
      VALUES ('\(from)', '\(from)', 'bibliographic_explication', '\(spaced)', 'Web tests task {page}',
          'Web tests summary.', 'Web tests {transcript}', '', 'Web tests carry on.', false, now() - interval '1 minute'),
        ('\(to)', '\(to)', 'bibliographic_explication', '\(closed)', 'Web tests task {page}',
          'Web tests summary.', 'Web tests {transcript}', '', 'Web tests carry on.', false, now());
      """)
    self.from = from
    self.to = to
  }

  /// Deletes the two rows.
  func remove() throws {
    _ = try TestAdmin.query("DELETE FROM prompt_vignettes WHERE id IN ('\(from)', '\(to)');")
  }
}
