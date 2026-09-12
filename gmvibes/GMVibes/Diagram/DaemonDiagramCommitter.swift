import Foundation
import GMCCDaemonKit

/// The db-backed `DiagramCommitting`: one DIAGRAM_BATCH_APPLY, then one
/// DIAGRAM_GET.
///
/// The re-GET is not a paranoia round trip. The batch response carries the
/// new revision and the minted uuids but NOT the resulting rows, and the
/// editor needs what only a read has: every element's post-mutation version
/// (each `elementUpdate` carries an `expectedVersion`, so a stale version
/// makes the NEXT drag a VERSION_CONFLICT), plus everything the store
/// normalized on the way in — minted codes, packed stroke vertices,
/// clientRef-resolved connector targets. Rebuilding that client-side would
/// be a third implementation of the reducer.
///
/// This is the "ONE swap" `LocalDiagramCommitter`'s contract promised: the
/// edit session, the staging discipline and every call site are untouched.
final class DaemonDiagramCommitter: DiagramCommitting {
    private let diagramUuid: String
    private let onCommit: @MainActor @Sendable (DiagramGetResponse) -> Void
    private let service = GMCCDaemonService.shared

    init(diagramUuid: String,
         onCommit: @escaping @MainActor @Sendable (DiagramGetResponse) -> Void) {
        self.diagramUuid = diagramUuid
        self.onCommit = onCommit
    }

    func commit(_ mutations: [DiagramMutation], expectedRevision: Int64?) async throws -> Int64 {
        try await commitReporting(mutations, expectedRevision: expectedRevision).revision
    }

    func commitReporting(_ mutations: [DiagramMutation],
                         expectedRevision: Int64?) async throws -> DiagramCommitOutcome {
        let applied = try await service.diagramBatchApply(
            diagramUuid: diagramUuid, expectedRevision: expectedRevision,
            mutations: mutations)
        // Index-aligned results: the clientRef the caller invented, paired
        // with the uuid the DB actually minted for it.
        var minted: [String: String] = [:]
        for result in applied.results {
            if let ref = result.clientRef, let uuid = result.uuid {
                minted[ref] = uuid
            }
        }
        let fresh = try await service.diagramGet(diagramUuid: diagramUuid)
        let notify = onCommit
        await MainActor.run { notify(fresh) }
        // Report the revision we just READ, not the one the batch returned:
        // another window may have committed in between, and the read tree is
        // what the workspace now displays and will CAS its next flush against.
        return DiagramCommitOutcome(revision: fresh.tree.revision, mintedUuids: minted)
    }
}
