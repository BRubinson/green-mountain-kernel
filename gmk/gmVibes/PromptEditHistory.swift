import Foundation
import Observation

// In-memory undo/redo history for the prompt editor. One linear stack of full
// (backstory/goal/detail) snapshots PER PROMPT, capped at `cap`. A snapshot is
// recorded on each autosave commit; undo/redo walk the stack with a cursor and
// re-apply the stored state. Deliberately not persisted: the daemon versions
// every committed write, and local history dying with the process is the
// "daemon as source of truth" trade the overhaul chose.

/// View-local controller. Holds the snapshot list + cursor; confined to the
/// main actor by design.
@Observable
@MainActor
final class PromptEditHistory {
    struct EditState: Equatable {
        var backstory: String
        var goal: String
        var detail: String
    }

    static let cap = 100

    private(set) var promptKey: String = ""
    private var snapshots: [EditState] = []
    private var cursor: Int = -1

    var canUndo: Bool { cursor > 0 }
    var canRedo: Bool { cursor >= 0 && cursor < snapshots.count - 1 }

    /// Point the controller at a prompt. Seeds snapshot 0 from the loaded
    /// state so the very first edit is undoable. A same-key reload with
    /// UNCHANGED content keeps the existing stack; changed content (external
    /// edit accepted, conflict reload) records the new state so undo can never
    /// resurrect text the daemon has moved past unnoticed.
    func load(promptKey: String, current: EditState) {
        if promptKey == self.promptKey {
            if cursor >= 0, snapshots.indices.contains(cursor), snapshots[cursor] != current {
                record(current)
            }
            return
        }
        self.promptKey = promptKey
        snapshots = [current]
        cursor = 0
    }

    /// Record a new state if it differs from the cursor's. Truncates any redo
    /// branch (states after the cursor) before appending, then trims to `cap`.
    func record(_ s: EditState) {
        guard !promptKey.isEmpty else { return }
        if snapshots.isEmpty { snapshots = [s]; cursor = 0; return }
        if snapshots[cursor] == s { return }
        if cursor < snapshots.count - 1 {
            snapshots.removeSubrange((cursor + 1)...)
        }
        snapshots.append(s)
        while snapshots.count > Self.cap {
            snapshots.removeFirst()
        }
        cursor = snapshots.count - 1
    }

    func undo() -> EditState? {
        guard canUndo else { return nil }
        cursor -= 1
        return snapshots[cursor]
    }

    func redo() -> EditState? {
        guard canRedo else { return nil }
        cursor += 1
        return snapshots[cursor]
    }
}
