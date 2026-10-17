import Foundation

/// A seeded session's trace as the server keeps it (server migration 0139,
/// `SessionTraces`): never a column of the session's row, but rows of
/// `session_trace_batches`—owned by the session's table and id, numbered
/// from 0 in the order written (`seq`), each a JSON array of the events
/// received, a block whole as `{"at": milliseconds since 1970, "block":
/// {…}}`—inserted, never updated. Nothing ties a batch to its session by
/// foreign key, so a test that deletes its sessions deletes their batches
/// first (`delete`), in the same transaction: the dev database's owner may,
/// as TestAdmin connects; the app's role may only read and insert them.
enum SessionTrace {
  /// SQL appending `blocks` to the session's trace as its next batch, one
  /// event a block: the first received at `start`, each next `stepMs` after
  /// (a replay plays them at that pace). Numbered after any batch it holds,
  /// as the server numbers its own, so a writer elsewhere never collides.
  static func append(
    _ blocks: [[String: String]], table: String, id: String, start: Date = Date(), stepMs: Int64 = 0
  ) throws -> String {
    let first = Int64((start.timeIntervalSince1970 * 1000).rounded())
    let events = try blocks.enumerated().map { index, block in
      let text = String(decoding: try JSONSerialization.data(withJSONObject: block), as: UTF8.self)
      return "{\"at\":\(first + Int64(index) * stepMs),\"block\":\(text)}"
    }
    let batch = ("[" + events.joined(separator: ",") + "]").replacingOccurrences(of: "'", with: "''")
    return """
      INSERT INTO session_trace_batches (owner_table, owner_id, seq, form, events)
        SELECT '\(table)', '\(id)'::uuid, coalesce(max(seq), -1) + 1, 'events', '\(batch)'
        FROM session_trace_batches WHERE owner_table = '\(table)' AND owner_id = '\(id)'::uuid;
      """
  }

  /// SQL deleting the batches of the sessions of `table` that `condition`
  /// (an SQL condition on that table's rows) selects: run before those
  /// sessions are deleted, so no trace is left without its session.
  static func delete(table: String, where condition: String) -> String {
    """
    DELETE FROM session_trace_batches WHERE owner_table = '\(table)'
      AND owner_id IN (SELECT id FROM \(table) WHERE \(condition));
    """
  }
}
