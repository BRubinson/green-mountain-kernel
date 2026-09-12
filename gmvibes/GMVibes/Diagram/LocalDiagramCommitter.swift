import Foundation
import GMCCDaemonKit

/// Real-uuid minting for the non-persisted tree. Uuids must be REAL (not a
/// "local-" scheme) so a later daemon replay of the same mutations is
/// accepted verbatim — the whole point of the one-committer-swap contract.
nonisolated struct LiveDiagramMinting: DiagramIdentityMinting {
    func mintUuid() -> String { UUID().uuidString.lowercased() }
    func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

/// Records what the reducer mints, in mint order.
///
/// `DiagramTreeReducer` calls `mintUuid()` exactly once per elementAdd, in
/// mutation order, and a failed batch throws the whole apply away — so on
/// success the nth recorded uuid belongs to the nth add. That ordering is how
/// the local path answers the clientRef → uuid question the daemon answers
/// from its per-mutation batch results: an in-memory committer may invent the
/// uuids, but it still has to report the ones it actually used.
private final class RecordingMinting: DiagramIdentityMinting {
    private let live = LiveDiagramMinting()
    private(set) var minted: [String] = []

    func mintUuid() -> String {
        let uuid = live.mintUuid()
        minted.append(uuid)
        return uuid
    }

    func now() -> String { live.now() }
}

/// The authoritative in-memory tree: a single-writer actor — the same shape
/// as the daemon it stands in for. All semantics live in the kit's
/// `DiagramTreeReducer` (the parity-tested second implementation of
/// `diagramBatchApply`); this box only serializes access.
actor DiagramTreeBox {
    private(set) var tree: DiagramTree

    init(tree: DiagramTree) {
        self.tree = tree
    }

    func apply(_ mutations: [DiagramMutation], expectedRevision: Int64?)
        throws -> (tree: DiagramTree, minted: [String: String])
    {
        let recorder = RecordingMinting()
        tree = try DiagramTreeReducer.apply(mutations, to: tree,
                                            expectedRevision: expectedRevision,
                                            minting: recorder)
        var minted: [String: String] = [:]
        var addIndex = 0
        for mutation in mutations {
            guard case .elementAdd(let add) = mutation else { continue }
            if let ref = add.clientRef, addIndex < recorder.minted.count {
                minted[ref] = recorder.minted[addIndex]
            }
            addIndex += 1
        }
        return (tree, minted)
    }

    /// Wholesale replacement (the preview scaffold / dope reload paths).
    func replace(_ newTree: DiagramTree) {
        tree = newTree
    }
}

/// The `DiagramCommitting` conformer behind a NON-PERSISTED workspace: the
/// dope preview canvases, which have no diagram row to write to. The
/// db-backed editor swaps in `DaemonDiagramCommitter` and nothing else
/// changes — the one-committer-swap contract, now with both halves built.
final class LocalDiagramCommitter: DiagramCommitting {
    let box: DiagramTreeBox
    private let onCommit: @MainActor @Sendable (DiagramTree) -> Void

    init(box: DiagramTreeBox, onCommit: @escaping @MainActor @Sendable (DiagramTree) -> Void) {
        self.box = box
        self.onCommit = onCommit
    }

    func commit(_ mutations: [DiagramMutation], expectedRevision: Int64?) async throws -> Int64 {
        try await commitReporting(mutations, expectedRevision: expectedRevision).revision
    }

    func commitReporting(_ mutations: [DiagramMutation],
                         expectedRevision: Int64?) async throws -> DiagramCommitOutcome {
        let applied = try await box.apply(mutations, expectedRevision: expectedRevision)
        let notify = onCommit
        let tree = applied.tree
        await MainActor.run { notify(tree) }
        return DiagramCommitOutcome(revision: tree.revision, mintedUuids: applied.minted)
    }
}
